"""Shared pieces of the Waitlist's Mac-side tooling (US-WL06 to US-WL10).

Python 3 standard library only, so it runs under the system `/usr/bin/python3` a `launchd` job uses.
Nothing here holds a credential or an address: it names where the founder's files live, takes the one
run lock, bounds a run, writes a private file atomically, mints entry identifiers, and does the date
arithmetic the removal and retention rules need (always against an injected clock).

The state directory holds four things, all owner-only and address-free, beside each other:

    waitlist-view.json   the anonymous view gr0wthlab reads (US-WL07)
    ledger.json          the producer's own record of which entry identifier it gave each Kit subscriber (D1)
    launch-email.json    the launch-email date the founder recorded once (US-WL10, OQ13)
    .run.lock            the one lock every run takes, so no two runs overlap
"""
import contextlib
import fcntl
import json
import os
import secrets
import signal
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / 'contract.json'

DEFAULT_STATE_DIR = Path('~/Library/Application Support/RepToday/waitlist')
VIEW_NAME = 'waitlist-view.json'
LEDGER_NAME = 'ledger.json'
LAUNCH_NAME = 'launch-email.json'
LOCK_NAME = '.run.lock'
TEMP_PREFIX = '.waitlist-'
TEMP_SUFFIX = '.tmp'

# Every run, of any command, ends within this many seconds: a run past it is cut off (it never writes
# the view after the limit) and the lock it held is released with the process. A run that waits for
# the lock waits a little longer than that, so a hung run can never stall another one indefinitely.
RUN_LIMIT_ENV = 'WAITLIST_RUN_LIMIT_SECONDS'
DEFAULT_RUN_LIMIT_SECONDS = 600
LOCK_MARGIN_SECONDS = 60
# A run stops starting new deletions, and new entry write-backs to Kit, this long before its limit, so
# the view that follows still has time to be written inside the run.
SWEEP_RESERVE_SECONDS = 120
# One run of the retention sweep erases what fits before that point: Kit lets an API key make about 2
# requests a second and an erasure takes 3, so roughly 300 sign-ups. The daily job repeats the sweep, each
# pass a separate run under the lock and its own limit, while the previous pass left sign-ups and erased at
# least one, up to this many passes: about 6,000 sign-ups in one daily run.
RETENTION_PASS_CAP = 20
# Every network call carries its own timeout.
NETWORK_TIMEOUT_SECONDS = 20

# Removal and retention (OQ13, FR-43, FR-44).
RETENTION_DAYS = 30
# The launch-email date the founder records must be today or a few days before it. A date further back
# would put the retention deletion in the past or a day or two away, and the sweep deletes every
# sign-up the morning after, so a mistyped date is refused rather than recorded.
LAUNCH_WINDOW_DAYS = 7

ENTRY_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
ENTRY_LENGTH = 16  # 62^16 is about 2^95, above the PRD's 80-bit floor.


class WaitlistError(Exception):
    """A failure whose message is safe to print: it names a step and never repeats a value."""


class RunLimitExceeded(BaseException):
    """The run's time limit passed. A BaseException so no `except Exception` on the way up swallows it."""


class LockTimeout(WaitlistError):
    pass


def load_contract(path=CONTRACT_PATH):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def field_key(contract, name):
    """The Kit custom-field key a posted field name (`fields[fit]`) is stored under (`fit`)."""
    posted = contract['posted_fields'][name]
    if posted.startswith('fields[') and posted.endswith(']'):
        return posted[len('fields['):-1]
    return posted


# Where the files live.


def state_dir(explicit=None):
    return Path(os.path.expanduser(str(explicit))) if explicit else DEFAULT_STATE_DIR.expanduser()


def run_limit_seconds():
    try:
        return max(1.0, float(os.environ[RUN_LIMIT_ENV]))
    except (KeyError, ValueError):
        return float(DEFAULT_RUN_LIMIT_SECONDS)


def nearest_existing(path):
    """The longest prefix of `path` that exists, and the parts below it."""
    path = Path(os.path.abspath(str(path)))
    rest = []
    while not os.path.lexists(str(path)) and path.parent != path:
        rest.append(path.name)
        path = path.parent
    return path, list(reversed(rest))


def resolved(path):
    """`path` with every symbolic link resolved, also for the part that does not exist yet."""
    base, rest = nearest_existing(path)
    return Path(os.path.realpath(str(base))).joinpath(*rest)


def work_tree_ancestor(path):
    """The nearest directory, `path` itself or one above it, that holds a `.git` entry (a directory, or the file a
    linked worktree has), or None. `path` is resolved first, so a symbolic link into a checkout is seen."""
    current = resolved(path)
    for candidate in [current] + list(current.parents):
        if os.path.lexists(str(candidate / '.git')):
            return candidate
    return None


def require_directory_outside_work_trees(directory):
    """The directory, as given and as its symbolic links resolve, and every ancestor of it, must hold no `.git`
    entry (FR-33): the view and its neighbours live outside every checkout and git work tree."""
    for candidate in (Path(os.path.abspath(str(directory))), resolved(directory)):
        if work_tree_ancestor(candidate) is not None:
            raise WaitlistError('refusing to write in or under a git work tree; choose a directory outside every checkout')


def require_file_outside_work_trees(path):
    """Likewise for a file: the directory it would be written in, and the directory its final symbolic link
    resolves to."""
    require_directory_outside_work_trees(Path(os.path.abspath(str(path))).parent)
    require_directory_outside_work_trees(Path(os.path.dirname(str(resolved(path)))))


def ensure_private_dir(directory):
    """The tool's own state directory: created if missing, and owner-only either way."""
    directory = Path(str(directory))
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(str(directory), 0o700)


def create_missing_dir(directory):
    """Create `directory` owner-only when it is missing. An existing one, such as the folder an `--output` path
    names, is the founder's and keeps its mode."""
    if not Path(str(directory)).is_dir():
        ensure_private_dir(directory)


# Faults a test injects at named points of a run: `WAITLIST_TEST_FAULT=<point>:exit` ends the process there, as a
# crash would, `<point>:hang` stops there until the run's time limit cuts it off, and `<point>:pause` waits
# FAULT_PAUSE_SECONDS each time the point is reached, as a slow Kit call would. They are honored only when
# the CLI switched them on, which it does only in the synthetic store mode, so a real run cannot be made to fail
# this way.
FAULT_ENV = 'WAITLIST_TEST_FAULT'
FAULT_PAUSE_SECONDS = 0.3
_faults_enabled = False


def enable_test_faults():
    global _faults_enabled
    _faults_enabled = True


def fault(point):
    if not _faults_enabled:
        return
    chosen = os.environ.get(FAULT_ENV, '')
    name, _, action = chosen.partition(':')
    if name != point:
        return
    if action == 'hang':
        time.sleep(3600)
    elif action == 'pause':
        time.sleep(FAULT_PAUSE_SECONDS)
    else:
        os._exit(137)


def write_private_atomic(path, data):
    """Write `data` to `path`: a mode-600 temporary file in the same directory, flushed to disk, then a rename."""
    path = Path(str(path))
    create_missing_dir(path.parent)
    temporary = path.parent / '{}{}.{}{}'.format(TEMP_PREFIX, path.name, os.getpid(), TEMP_SUFFIX)
    descriptor = os.open(str(temporary), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, 'wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        fault('after-temp-write')
        os.replace(str(temporary), str(path))
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(str(temporary))
        raise
    with contextlib.suppress(OSError):
        directory_fd = os.open(str(path.parent), os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)


def remove_stale_temporaries(directory):
    """Delete the temporary files an interrupted run left behind. Only called while holding the run lock."""
    removed = 0
    for child in Path(str(directory)).glob('{}*{}'.format(TEMP_PREFIX, TEMP_SUFFIX)):
        with contextlib.suppress(OSError):
            child.unlink()
            removed += 1
    return removed


# The one lock, and the run's time limit.


class RunLock(object):
    """An exclusive `flock` on `.run.lock` in the state directory, waited for no longer than the run limit plus a
    margin. The kernel drops it when the process ends, however it ends, so an interrupted run blocks nothing."""

    def __init__(self, directory, wait_seconds=None):
        self.path = Path(str(directory)) / LOCK_NAME
        self.wait_seconds = wait_seconds if wait_seconds is not None else run_limit_seconds() + LOCK_MARGIN_SECONDS
        self.handle = None

    def __enter__(self):
        ensure_private_dir(self.path.parent)
        descriptor = os.open(str(self.path), os.O_RDWR | os.O_CREAT, 0o600)
        deadline = time.monotonic() + self.wait_seconds
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    os.close(descriptor)
                    raise LockTimeout('another Waitlist run holds the lock past its limit')
                time.sleep(0.05)
        self.handle = descriptor
        return self

    def __exit__(self, *exc):
        if self.handle is not None:
            with contextlib.suppress(OSError):
                fcntl.flock(self.handle, fcntl.LOCK_UN)
            os.close(self.handle)
            self.handle = None
        return False


@contextlib.contextmanager
def run_limit(seconds=None):
    """Raise `RunLimitExceeded` in the main thread once `seconds` have passed. Yields the monotonic deadline."""
    seconds = seconds if seconds is not None else run_limit_seconds()

    def expire(signum, frame):
        raise RunLimitExceeded()

    previous = signal.signal(signal.SIGALRM, expire)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield time.monotonic() + seconds
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


# Entry identifiers (FR-23).


def new_entry(taken=()):
    """A fresh entry identifier from the system's secure random source, never in `taken`. It is never a function
    of anything about the sign-up."""
    taken = set(taken)
    while True:
        candidate = ''.join(secrets.choice(ENTRY_ALPHABET) for _ in range(ENTRY_LENGTH))
        if candidate not in taken:
            return candidate


# Dates. Everything that depends on today takes `as_of` (a `date`); the CLI is the one place that reads the clock.


def today_local():
    return datetime.now().astimezone().date()


def parse_day(text):
    """A strict `YYYY-MM-DD` date, or None."""
    if not isinstance(text, str):
        return None
    try:
        parsed = date.fromisoformat(text)
    except ValueError:
        return None
    return parsed if parsed.isoformat() == text else None


def utc_day_of(timestamp):
    """The UTC date of an ISO 8601 time that states its offset, or None."""
    if not isinstance(timestamp, str):
        return None
    try:
        moment = datetime.fromisoformat(timestamp.strip().replace('Z', '+00:00'))
    except ValueError:
        return None
    if moment.tzinfo is None:
        return None
    return moment.astimezone(timezone.utc).date()


def deletion_date(sent_on):
    return sent_on + timedelta(days=RETENTION_DAYS)


def validate_launch_date(text, today):
    """The launch-email date as a `date`, or raises `WaitlistError` naming the reason and nothing about the file.

    The date must be a real `YYYY-MM-DD`, not after `today`, and no more than `LAUNCH_WINDOW_DAYS` before it."""
    sent_on = parse_day(text)
    if sent_on is None:
        raise WaitlistError('the date must be a real calendar date written YYYY-MM-DD')
    if sent_on > today:
        raise WaitlistError('the launch email cannot have been sent in the future (today is {})'.format(today.isoformat()))
    if (today - sent_on).days > LAUNCH_WINDOW_DAYS:
        raise WaitlistError(
            'that date is more than {} days ago; recording it would delete every sign-up on {} (retention is {} days '
            'after the launch email), so it is refused'.format(LAUNCH_WINDOW_DAYS, deletion_date(sent_on).isoformat(), RETENTION_DAYS))
    return sent_on


def retention_due(sent_on, as_of):
    """Whether the retention sweep deletes on `as_of`: on or after the launch-email date plus 30 days."""
    return as_of >= deletion_date(sent_on)

"""The Waitlist's Mac-side logic: the ledger, identifier assignment, the anonymous view producer, the removal and
retention sweeps, `remove`, the launch-email record, and the send-time lookup (US-WL06 to US-WL10).

The command line (`waitlist.py`) is a thin shell over this module. Every function that depends on today takes an
injected `as_of`; every message it raises or returns names a step, a count or an entry identifier and never an
address, an answer or a credential. Importers must have `tools/waitlist/` on `sys.path`.

How the pieces fit (the PRD's OQ1 Option A with the captain's Kit decisions D1 to D4):

  * Kit stores each sign-up. A public post can set Kit's `entry` field, so the producer trusts only its own
    ledger (`ledger.json`, Kit subscriber id -> entry identifier plus the Source first seen) and resets Kit's
    `entry` to the ledger's value (D1).
  * The view is projected from the store and the ledger, checked by `check-view.py`'s own code, and written
    atomically only if it passes.
  * Kit cannot delete a subscriber, so removal and retention erase one (unsubscribe, placeholder address, blank
    fields) and the next view leaves it out (D2).
"""
import importlib.util
import json
import time
from datetime import datetime, timezone
from pathlib import Path

from wl_common import (
    HERE, LAUNCH_NAME, LAUNCH_WINDOW_DAYS, LEDGER_NAME, VIEW_NAME, WaitlistError, deletion_date, ensure_private_dir,
    fault, load_contract, new_entry, parse_day, remove_stale_temporaries, require_directory_outside_work_trees,
    require_file_outside_work_trees, retention_due, utc_day_of, validate_launch_date, write_private_atomic)
from wl_store import ACTIVE, CANCELLED, INACTIVE


def _load_checker():
    spec = importlib.util.spec_from_file_location('waitlist_check_view', str(HERE / 'check-view.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check_view = _load_checker()
CONTRACT = load_contract()
RULES = check_view.load_rules()
FIT_TAGS = tuple(answer['tag'] for answer in CONTRACT['fit_answers'])
SOURCES = tuple(CONTRACT['source_tags']) + (CONTRACT['unknown_source'],)
UNKNOWN_SOURCE = CONTRACT['unknown_source']
ENTRY_PATTERN = RULES.entry_pattern
VIEW_VERSION = CONTRACT['view']['version']
LEDGER_VERSION = 1
LAUNCH_VERSION = 1


class CheckRefused(WaitlistError):
    """The candidate view failed the checker. The previous file is untouched."""

    def __init__(self, message, verdict):
        WaitlistError.__init__(self, message)
        self.verdict = verdict


# Normalizing what Kit stores (US-WL06: a value outside the allowed sets never reaches the view as stored).


def normal_source(value):
    return value if value in CONTRACT['source_tags'] else UNKNOWN_SOURCE


def normal_fit(value):
    return value if value in FIT_TAGS else None


def normal_beta(value):
    """Kit stores the box as the string `true` or `false`; anything else, including no value, is not opted in."""
    if value is True:
        return True
    return isinstance(value, str) and value.strip().lower() == 'true'


# The ledger (D1).


class Ledger(object):
    """Kit subscriber id -> the entry identifier this producer gave it and the Source first seen for it (OQ11).
    It holds no address. It is the only place an entry identifier is trusted."""

    def __init__(self, directory):
        self.path = Path(str(directory)) / LEDGER_NAME
        self.entries = {}
        # Ids of subscribers this producer erased. Kit's listing trails a write by up to a couple of minutes, so a
        # listing made just after an erasure can still show the old record; a tombstone keeps such a stale record
        # from being given a new identifier, written to, listed in the view or erased a second time. An id is
        # never reused by Kit, and a tombstone holds nothing but that id.
        self.erased = set()

    def load(self):
        try:
            raw = self.path.read_bytes()
        except FileNotFoundError:
            self.entries = {}
            self.erased = set()
            return self
        except OSError:
            raise WaitlistError('the ledger could not be read')
        try:
            data = json.loads(raw.decode('utf-8'))
            subscribers = data['subscribers']
            erased = data.get('erased', [])
            if data.get('ledger') != LEDGER_VERSION or not isinstance(subscribers, dict) or not isinstance(erased, list):
                raise ValueError
            if not all(isinstance(item, str) and item.isdigit() for item in erased):
                raise ValueError
            seen = set()
            for subscriber_id, record in subscribers.items():
                entry, source = record['entry'], record['source']
                if (not isinstance(entry, str) or not ENTRY_PATTERN.fullmatch(entry) or entry in seen
                        or source not in SOURCES or not subscriber_id.isdigit()):
                    raise ValueError
                seen.add(entry)
        except (ValueError, KeyError, TypeError, AttributeError):
            # A damaged ledger is never replaced by guessing: that would hand every sign-up a new identifier.
            raise WaitlistError('the ledger is damaged; restore it or move it aside (moving it aside gives every sign-up a new entry identifier)')
        self.entries = {str(key): {'entry': value['entry'], 'source': value['source']} for key, value in subscribers.items()}
        self.erased = set(erased)
        return self

    def save(self):
        payload = {'ledger': LEDGER_VERSION, 'subscribers': self.entries, 'erased': sorted(self.erased, key=int)}
        write_private_atomic(self.path, (json.dumps(payload, indent=2, sort_keys=True) + '\n').encode('utf-8'))

    def mark_erased(self, subscriber_id):
        """Forget a subscriber's identifier and remember that it was erased. The caller saves."""
        self.entries.pop(str(subscriber_id), None)
        self.erased.add(str(subscriber_id))

    def entry_of(self, subscriber_id):
        record = self.entries.get(str(subscriber_id))
        return record['entry'] if record else None

    def id_of(self, entry):
        for subscriber_id, record in self.entries.items():
            if record['entry'] == entry:
                return subscriber_id
        return None

    def taken(self):
        return [record['entry'] for record in self.entries.values()]


# Identifier assignment (US-WL06).


def assign_entries(store, ledger, subscribers):
    """Give every stored sign-up that lacks an identifier one, remember the Source first seen, and reset Kit's
    `entry` field wherever it differs from the ledger. The ledger is saved before any write to Kit, so an
    interruption leaves either nothing or an identifier the next run writes back. Returns counts."""
    counts = {'assigned': 0, 'reset': 0, 'pruned': 0, 'writeback_failed': 0}
    eligible = [item for item in subscribers
                if item.state in (ACTIVE, INACTIVE) and not item.scrubbed and item.id not in ledger.erased]
    taken = set(ledger.taken())
    changed = False
    for item in eligible:
        if ledger.entry_of(item.id) is None:
            entry = new_entry(taken)
            taken.add(entry)
            ledger.entries[item.id] = {'entry': entry, 'source': normal_source(item.source)}
            counts['assigned'] += 1
            changed = True
    for item in subscribers:
        if item.scrubbed and (item.id in ledger.entries or item.id not in ledger.erased):
            if item.id in ledger.entries:
                counts['pruned'] += 1
            ledger.mark_erased(item.id)
            changed = True
    if changed:
        ledger.save()
    for item in eligible:
        wanted = ledger.entry_of(item.id)
        if item.entry == wanted:
            continue
        try:
            store.set_entry(item.id, wanted)
        except WaitlistError:
            counts['writeback_failed'] += 1
            continue
        if item.entry is not None:
            counts['reset'] += 1
    return counts


# The view (US-WL07).


def build_view(subscribers, ledger, generated_at):
    """The view as a dict, projected from the five fields only. Nothing about an address or any other stored field
    is read into it. An unconfirmed (inactive) or unsubscribed sign-up is never projected."""
    entries = []
    for item in subscribers:
        if item.state != ACTIVE or item.scrubbed or item.id in ledger.erased:
            continue
        entry = ledger.entry_of(item.id)
        if entry is None:
            raise WaitlistError('a confirmed sign-up has no entry identifier')
        day = utc_day_of(item.created_at)
        if day is None:
            raise WaitlistError('a confirmed sign-up has no readable creation time')
        entries.append({
            'entry': entry,
            'source': ledger.entries[item.id]['source'],
            'fit': normal_fit(item.fit),
            'beta_opt_in': normal_beta(item.beta),
            'signed_up_on': day.isoformat(),
        })
    entries.sort(key=lambda row: (row['signed_up_on'], row['entry']))
    return {'view': VIEW_VERSION, 'generated_at': generated_at.replace(microsecond=0).isoformat(), 'entries': entries}


def render_view(view):
    return (json.dumps(view, indent=2, ensure_ascii=True) + '\n').encode('utf-8')


def view_path(directory, output=None):
    return Path(str(output)) if output else Path(str(directory)) / VIEW_NAME


def produce_view(store, directory, output=None, now=None, mutate_candidate=None):
    """Read the store, assign identifiers, project the view, check it, and replace the file only if the check
    passes. Must be called while holding the run lock. Returns counts."""
    directory = Path(str(directory))
    target = view_path(directory, output)
    require_directory_outside_work_trees(directory)
    require_file_outside_work_trees(target)
    ensure_private_dir(directory)
    ensure_private_dir(target.parent)
    remove_stale_temporaries(directory)
    remove_stale_temporaries(target.parent)

    ledger = Ledger(directory).load()
    subscribers = store.list_subscribers()
    fault('after-read')
    generated_at = (now or (lambda: datetime.now(timezone.utc)))()  # stamped after the store was read
    counts = assign_entries(store, ledger, subscribers)
    counts['unconfirmed'] = sum(1 for item in subscribers
                                if item.state == INACTIVE and not item.scrubbed and item.id not in ledger.erased)
    view = build_view(subscribers, ledger, generated_at)
    candidate = render_view(view)
    if mutate_candidate is not None:
        candidate = mutate_candidate(candidate)
    if len(candidate) > RULES.max_bytes:
        raise WaitlistError('the view would exceed {} bytes; the previous file is untouched'.format(RULES.max_bytes))
    result = check_view.evaluate(candidate, RULES)
    if result.verdict != check_view.ACCEPTED:
        rules = ', '.join(sorted(set(finding.rule for finding in result.findings)))
        raise CheckRefused('the candidate view failed the checker ({}: rule {}); the previous file is untouched'.format(
            result.verdict, rules), result.verdict)
    write_private_atomic(target, candidate)
    counts['entries'] = len(view['entries'])
    return counts


# Removal and retention (US-WL10).


def read_launch_record(directory, today=None):
    """The recorded launch-email date as a `date`, or None when no date has been recorded. A record that is damaged,
    states a date in the future of when it was recorded, or was recorded with a date the validator would have
    refused raises, so the retention sweep deletes nothing on a record it cannot trust."""
    path = Path(str(directory)) / LAUNCH_NAME
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        return None
    except OSError:
        raise WaitlistError('the launch-email record could not be read; nothing was deleted')
    try:
        data = json.loads(raw.decode('utf-8'))
        sent_on, recorded_on = parse_day(data['sent_on']), parse_day(data['recorded_on'])
        if data.get('launch_email') != LAUNCH_VERSION or sent_on is None or recorded_on is None:
            raise ValueError
        if sent_on > recorded_on or (recorded_on - sent_on).days > LAUNCH_WINDOW_DAYS:
            raise ValueError
    except (ValueError, KeyError, TypeError, AttributeError):
        raise WaitlistError('the launch-email record is not one record-launch-email would have written; nothing was deleted')
    if today is not None and recorded_on > today:
        raise WaitlistError('the launch-email record is dated in the future; nothing was deleted')
    return sent_on


def record_launch_email(directory, sent_on_text, today, replace=False):
    """Record the launch-email date once. Returns `(sent_on, deletion_day)`. A future date, a date more than
    `LAUNCH_WINDOW_DAYS` before `today`, or a second record without `replace` is refused."""
    directory = Path(str(directory))
    require_directory_outside_work_trees(directory)
    sent_on = validate_launch_date(sent_on_text, today)
    existing = None
    try:
        existing = read_launch_record(directory)
    except WaitlistError:
        existing = False  # a damaged record: only `replace` may overwrite it
    if existing is not None and not replace:
        raise WaitlistError('a launch-email date is already recorded; it is recorded once (use --replace to change it deliberately)')
    payload = {'launch_email': LAUNCH_VERSION, 'sent_on': sent_on.isoformat(), 'recorded_on': today.isoformat()}
    write_private_atomic(directory / LAUNCH_NAME, (json.dumps(payload, indent=2, sort_keys=True) + '\n').encode('utf-8'))
    return sent_on, deletion_date(sent_on)


def _erase_all(store, ledger, targets, soft_deadline):
    """Erase each target, forgetting its ledger entry as it goes. Stops starting new ones past the soft deadline.
    Returns (erased, failed, remaining)."""
    erased = failed = 0
    remaining = len(targets)
    for item in targets:
        if soft_deadline is not None and time.monotonic() > soft_deadline:
            break
        remaining -= 1
        try:
            store.erase(item.id)
        except WaitlistError:
            failed += 1
            continue
        erased += 1
        ledger.mark_erased(item.id)
        ledger.save()
    return erased, failed, remaining


def sweep_unsubscribed(store, directory, live=False, soft_deadline=None):
    """Erase every sign-up Kit reports as unsubscribed. A dry run counts them and changes nothing. Returns counts."""
    ledger = Ledger(directory).load()
    targets = [item for item in store.list_subscribers()
               if item.state == CANCELLED and not item.scrubbed and item.id not in ledger.erased]
    fault('sweep-unsubscribed')
    counts = {'due': len(targets), 'erased': 0, 'failed': 0, 'remaining': 0, 'live': live}
    if live and targets:
        counts['erased'], counts['failed'], counts['remaining'] = _erase_all(store, ledger, targets, soft_deadline)
    return counts


def sweep_retention(store, directory, as_of, live=False, soft_deadline=None):
    """Erase every remaining sign-up on or after the launch-email date plus 30 days. With no date recorded it deletes
    nothing. A dry run counts them and changes nothing. Returns counts."""
    sent_on = read_launch_record(directory, today=as_of)
    counts = {'due': 0, 'erased': 0, 'failed': 0, 'remaining': 0, 'live': live, 'recorded': sent_on is not None,
              'not_due': False, 'deletion_date': deletion_date(sent_on).isoformat() if sent_on else None}
    if sent_on is None:
        return counts
    if not retention_due(sent_on, as_of):
        counts['not_due'] = True
        return counts
    ledger = Ledger(directory).load()
    targets = [item for item in store.list_subscribers() if not item.scrubbed and item.id not in ledger.erased]
    counts['due'] = len(targets)
    if live and targets:
        counts['erased'], counts['failed'], counts['remaining'] = _erase_all(store, ledger, targets, soft_deadline)
    return counts


def remove_signup(store, directory, entry=None, address=None, live=True):
    """Erase one sign-up, found by entry identifier or by an exact address. Returns the Kit id it erased, or None for
    a dry run that found it. Raises when nothing matches exactly."""
    ledger = Ledger(directory).load()
    if entry is not None:
        if not ENTRY_PATTERN.fullmatch(entry) or check_view.looks_like_address(entry):
            raise WaitlistError('that is not an entry identifier')
        subscriber_id = ledger.id_of(entry)
        if subscriber_id is None:
            raise WaitlistError('no sign-up has entry identifier {}'.format(entry))
    else:
        subscriber_id = store.find_id_by_email(address)
        if subscriber_id is None:
            raise WaitlistError('no sign-up has that address')
    if not live:
        return subscriber_id
    store.erase(subscriber_id)
    ledger.mark_erased(subscriber_id)
    ledger.save()
    return subscriber_id


# Send-time lookup (US-WL09).

TAG_LABEL_ALLOWED = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _.-')


def valid_tag_label(label):
    return 1 <= len(label) <= 64 and all(char in TAG_LABEL_ALLOWED for char in label) and label == label.strip()


def _name(entry, position):
    """How an error names an identifier: by its text, unless it looks like an address, which is never repeated."""
    if check_view.looks_like_address(entry):
        return 'argument {}'.format(position)
    return repr(entry)


def resolve_entries(store, directory, entries, need_confirmed=True):
    """Map entry identifiers to Kit ids, all or nothing. Every malformed, unknown or unconfirmed identifier is
    reported by name in one error. Returns the ids in the order given, without repeats."""
    ledger = Ledger(directory).load()
    states = {item.id: item for item in store.list_subscribers()} if need_confirmed else {}
    problems, ids, seen = [], [], set()
    for position, entry in enumerate(entries, 1):
        if not ENTRY_PATTERN.fullmatch(entry) or check_view.looks_like_address(entry):
            problems.append('{} is not an entry identifier'.format(_name(entry, position)))
            continue
        subscriber_id = ledger.id_of(entry)
        if subscriber_id is None:
            problems.append('{} is not a known entry identifier'.format(_name(entry, position)))
            continue
        if need_confirmed:
            item = states.get(subscriber_id)
            if item is None or item.state != ACTIVE or item.scrubbed:
                problems.append('{} is not a confirmed sign-up'.format(_name(entry, position)))
                continue
        if subscriber_id not in seen:
            seen.add(subscriber_id)
            ids.append(subscriber_id)
    if problems:
        raise WaitlistError('; '.join(problems))
    return ids


def tag_entries(store, directory, label, entries):
    """Tag the named confirmed sign-ups inside Kit so a broadcast to that label needs no address to leave Kit."""
    if not valid_tag_label(label):
        raise WaitlistError('the label must be 1 to 64 letters, digits, spaces, dots, dashes or underscores')
    if not entries:
        raise WaitlistError('name at least one entry identifier')
    ids = resolve_entries(store, directory, entries)
    store.tag_subscribers(label, ids)
    return len(ids)


def address_for_entry(store, directory, entry):
    (subscriber_id,) = resolve_entries(store, directory, [entry])
    return store.email_of(subscriber_id)

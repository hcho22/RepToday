#!/usr/bin/env python3
"""The Waitlist's operator command, run on the founder's Mac (US-WL06 to US-WL10).

    waitlist.py produce                      assign identifiers and write the anonymous view
    waitlist.py assign                       assign identifiers only
    waitlist.py sweep-unsubscribed [--live]  erase every sign-up Kit reports as unsubscribed or complained
    waitlist.py sweep-retention [--live]     erase every sign-up past the launch-email date plus 25 days
    waitlist.py remove [--entry ID]          erase one sign-up, by entry identifier or an address typed at a prompt
    waitlist.py record-launch-email --sent-on YYYY-MM-DD
    waitlist.py tag LABEL ENTRY...           tag the named sign-ups inside Kit for a broadcast
    waitlist.py show ENTRY                   print one address, to an interactive terminal only
    waitlist.py kit-deletes                  list the erased sign-ups to delete in Kit's web app, and confirm
                                             the ones Kit no longer answers for
    waitlist.py daily [--live]               the scheduled job: both sweeps, then the producer, then the Kit
                                             delete check, each step run whatever an earlier step did, every
                                             failed step reported; the retention sweep repeats in separate
                                             passes until it is done

Python 3 standard library only (the system `/usr/bin/python3` is enough). The Kit API key is read from the
macOS Keychain at run time (service `com.reptoday.waitlist.kit`, account `api-key`; the service name can be
overridden with `WAITLIST_KIT_KEYCHAIN_SERVICE`), never from a file, argument or environment value.
Output is counts, rule names, entry identifiers and Kit subscriber ids: never an address, an answer or the key.
Kit's API cannot delete a subscriber, so every erasure is followed by the founder's delete in Kit's web app: the
command that erased names the Kit subscriber ids and the day to delete each by, and `kit-deletes` lists every one
still waiting until Kit no longer answers for it.

Options every command takes:
    --state-dir DIR          where the view, ledger, launch-email record and lock live
                             (default: ~/Library/Application Support/RepToday/waitlist)
    --synthetic FILE         use a synthetic store held in a JSON file instead of Kit (tests)
    --restrict-to-ids A,B    act only on those Kit subscriber ids, so a shared test account's other
                             subscribers are never read or touched

Both sweeps are dry runs unless `--live` is given. `--as-of YYYY-MM-DD` (retention only) moves the sweep's clock
and is accepted only in a dry run or against a synthetic store.

Exit status: 0 done, 1 a step failed (for `kit-deletes`: an id is past its delete-by day), 2 the candidate view failed the checker (the old file is untouched),
3 a run passed its time limit, 64 usage, 70 internal error, 130 interrupted (Ctrl-C stops the whole command).
"""
import argparse
import getpass
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import wl_core  # noqa: E402
from wl_common import (  # noqa: E402
    RETENTION_PASS_CAP, SWEEP_RESERVE_SECONDS, WaitlistError, RunLimitExceeded, RunLock, enable_test_faults,
    ensure_private_dir, parse_day, require_directory_outside_work_trees, run_limit, state_dir, today_local)
from wl_store import KIT_SUBSCRIBER_PAGE, KitStore, RestrictedStore, SyntheticStore  # noqa: E402

EXIT_OK, EXIT_FAILED, EXIT_REFUSED, EXIT_LIMIT, EXIT_USAGE, EXIT_INTERNAL, EXIT_INTERRUPTED = 0, 1, 2, 3, 64, 70, 130


def say(message):
    print(message, flush=True)


def complain(message):
    print(message, file=sys.stderr, flush=True)


def make_store(args):
    if args.synthetic:
        enable_test_faults()
        store = SyntheticStore(args.synthetic)
    else:
        store = KitStore.from_keychain()
    if args.restrict_to_ids:
        store = RestrictedStore(store, [item for item in args.restrict_to_ids.split(',') if item])
    return store


def locked_run(args, body):
    """Take the run lock, start the run's clock, and call `body(store, directory, soft_deadline)`. The state
    directory is checked to be outside every work tree before anything is created in it."""
    directory = state_dir(args.state_dir)
    require_directory_outside_work_trees(directory)
    ensure_private_dir(directory)
    store = make_store(args)
    with RunLock(directory):
        with run_limit() as deadline:
            return body(store, directory, deadline - SWEEP_RESERVE_SECONDS)


# Commands. Each returns an exit status.


def regenerate(store, directory, soft_deadline, output=None):
    counts = wl_core.produce_view(store, directory, output=output, soft_deadline=soft_deadline)
    say('waitlist-view: wrote the view (entries {}, assigned {}, entry resets {}, unconfirmed left out {}, pruned {})'.format(
        counts['entries'], counts['assigned'], counts['reset'], counts['unconfirmed'], counts['pruned']))
    if counts['writeback_deferred']:
        say('waitlist-view: {} entry write-backs to Kit were left for the next run (time limit)'.format(counts['writeback_deferred']))
    if counts['writeback_failed']:
        say('waitlist-view: {} entry write-backs to Kit failed; the next run retries them'.format(counts['writeback_failed']))
        return EXIT_FAILED
    return EXIT_OK


def command_produce(args):
    return locked_run(args, lambda store, directory, soft_deadline: regenerate(store, directory, soft_deadline, output=args.output))


def command_assign(args):
    def body(store, directory, soft_deadline):
        ledger = wl_core.Ledger(directory).load()
        counts = wl_core.assign_entries(store, ledger, store.list_subscribers(), soft_deadline)
        say('waitlist-assign: assigned {}, entry resets {}, pruned {}, write-backs failed {}, left for the next run {}'.format(
            counts['assigned'], counts['reset'], counts['pruned'], counts['writeback_failed'], counts['writeback_deferred']))
        return EXIT_FAILED if counts['writeback_failed'] else EXIT_OK
    return locked_run(args, body)


def sweep_status(name, counts, directory, extra=''):
    mode = 'live' if counts['live'] else 'dry run, nothing deleted'
    say('{}: {} ({}) - due {}, erased {}, failed {}, left for the next run {}{}'.format(
        name, 'done' if not counts['failed'] and not counts['remaining'] else 'incomplete', mode,
        counts['due'], counts['erased'], counts['failed'], counts['remaining'], extra))
    tell_kit_deletes(directory, counts['erased_ids'])
    return EXIT_FAILED if counts['failed'] or counts['remaining'] else EXIT_OK


def tell_kit_deletes(directory, ids):
    """Name the Kit subscriber ids the founder now deletes in Kit's web app, each with the day the ledger lists it to
    be deleted by and its page there (ids only, never an address)."""
    if ids:
        delete_by = wl_core.Ledger(directory).load().awaiting_kit_delete
        say('kit-delete: delete {} erased sign-up{} in Kit\'s web app (README, "Delete in Kit"): Kit subscriber id{} {}'.format(
            len(ids), '' if len(ids) == 1 else 's', '' if len(ids) == 1 else 's', ', '.join(ids)))
        for subscriber_id in ids:
            say('kit-delete: Kit subscriber id {} - delete by {} - {}'.format(
                subscriber_id, delete_by[subscriber_id], KIT_SUBSCRIBER_PAGE.format(subscriber_id)))


def after_erasure(store, directory, counts, soft_deadline):
    """A deletion is followed by a view generated from a store read made after it. A view that cannot be written is
    a failed status, never an exception, so the erasure's counts still reach the caller."""
    if counts['erased']:
        return guarded(lambda: regenerate(store, directory, soft_deadline))
    return EXIT_OK


def command_sweep_unsubscribed(args):
    def body(store, directory, soft_deadline):
        counts = wl_core.sweep_unsubscribed(store, directory, live=args.live, soft_deadline=soft_deadline)
        status = sweep_status('sweep-unsubscribed', counts, directory, ' (unsubscribed {}, spam complaints {})'.format(
            counts['unsubscribed'], counts['complained']))
        return max(status, after_erasure(store, directory, counts, soft_deadline))
    return locked_run(args, body)


def retention_pass(args, as_of):
    """One run of the retention sweep, under the lock and its own time limit. Returns (exit status, counts)."""
    def body(store, directory, soft_deadline):
        counts = wl_core.sweep_retention(store, directory, as_of, live=args.live, soft_deadline=soft_deadline)
        if not counts['recorded']:
            say('sweep-retention: no launch-email date is recorded, so nothing is due and nothing was deleted')
            return EXIT_OK, counts
        if counts['not_due']:
            say('sweep-retention: not due until {} - nothing deleted ({})'.format(
                counts['erase_date'], 'live' if counts['live'] else 'dry run'))
            return EXIT_OK, counts
        status = sweep_status('sweep-retention', counts, directory)
        return max(status, after_erasure(store, directory, counts, soft_deadline)), counts
    return locked_run(args, body)


def command_sweep_retention(args):
    as_of = today_local()
    if args.as_of:
        if args.live and not args.synthetic:
            raise WaitlistError('--as-of moves the clock and is accepted only in a dry run or against a synthetic store')
        as_of = parse_day(args.as_of)
        if as_of is None:
            raise WaitlistError('--as-of must be a real date written YYYY-MM-DD')
    return retention_pass(args, as_of)[0]


def daily_retention(args):
    """The daily job's retention step: one pass erases what fits in one run, so the pass is repeated, each a separate
    run, while the previous one left sign-ups and erased at least one, up to RETENTION_PASS_CAP passes. The step
    fails only when sign-ups remain after the last pass or a pass erased none."""
    as_of = today_local()
    for number in range(1, RETENTION_PASS_CAP + 1):
        status, counts = retention_pass(args, as_of)
        left = counts['due'] - counts['erased']
        if not left or not counts['erased']:
            return status
        if number < RETENTION_PASS_CAP:
            say('sweep-retention: {} left after pass {}; starting pass {}'.format(left, number, number + 1))
    say('sweep-retention: {} left after {} passes, the most one daily run makes'.format(left, RETENTION_PASS_CAP))
    return status


def prompt_address():
    if not sys.stdin.isatty():
        raise WaitlistError('removing by address needs an interactive terminal, so the address is typed and never passed as an argument or piped')
    return getpass.getpass('Address to remove (not shown): ').strip()


def command_remove(args):
    address = None
    if args.entry is None:
        address = prompt_address()  # before the lock: a prompt must never hold it
        if not address:
            raise WaitlistError('no address was typed')

    def body(store, directory, soft_deadline):
        subscriber_id = wl_core.remove_signup(store, directory, entry=args.entry, address=address,
                                              live=not args.dry_run, today=today_local())
        if args.dry_run:
            say('remove: dry run - one sign-up matches exactly; nothing deleted')
            return EXIT_OK
        say('remove: erased one sign-up')
        tell_kit_deletes(directory, [subscriber_id])
        return regenerate(store, directory, soft_deadline)
    return locked_run(args, body)


def command_record_launch_email(args):
    directory = state_dir(args.state_dir)
    require_directory_outside_work_trees(directory)
    ensure_private_dir(directory)
    sent_on, erases_on, delete_by = wl_core.record_launch_email(directory, args.sent_on, today_local(), replace=args.replace)
    say('record-launch-email: recorded {}; the retention sweep will erase every remaining sign-up on or after {}, '
        'each to be deleted in Kit\'s web app by {}'.format(sent_on.isoformat(), erases_on.isoformat(), delete_by.isoformat()))
    return EXIT_OK


def command_tag(args):
    def body(store, directory, soft_deadline):
        count = wl_core.tag_entries(store, directory, args.label, args.entries)
        say('tag: tagged {} confirmed sign-ups with the label {!r}'.format(count, args.label))
        return EXIT_OK
    return locked_run(args, body)


def command_show(args):
    if not sys.stdout.isatty():
        raise WaitlistError('show prints an address only to an interactive terminal, never to a pipe or a file')

    def body(store, directory, soft_deadline):
        sys.stdout.write(wl_core.address_for_entry(store, directory, args.entry) + '\n')
        sys.stdout.flush()
        return EXIT_OK
    return locked_run(args, body)


def command_kit_deletes(args):
    def body(store, directory, soft_deadline):
        today = today_local()
        counts = wl_core.check_kit_deletes(store, directory, today, soft_deadline=soft_deadline)
        waiting = counts['waiting']
        overdue = [item for item in waiting if item['overdue']]
        say('kit-deletes: {} confirmed deleted in Kit, {} still to delete in Kit\'s web app ({} past the day to delete by), '
            'check failed {}, left unchecked {}'.format(counts['confirmed'], len(waiting), len(overdue), counts['failed'],
                                                        counts['unchecked']))
        for item in waiting:
            say('kit-deletes: Kit subscriber id {} - delete by {}{} - {}'.format(
                item['id'], item['delete_by'], ' - OVERDUE' if item['overdue'] else '', KIT_SUBSCRIBER_PAGE.format(item['id'])))
        return EXIT_FAILED if overdue or counts['failed'] else EXIT_OK
    return locked_run(args, body)


def command_daily(args):
    """Both sweeps, the producer, then the Kit delete check. A step that fails, raises or runs out of time does not stop the next one, and
    the job's own exit status is non-zero when any step did not finish; an interrupt stops the job."""
    steps = [
        ('sweep-unsubscribed', lambda: command_sweep_unsubscribed(args)),
        ('sweep-retention', lambda: daily_retention(args)),
        ('produce', lambda: command_produce(argparse.Namespace(**dict(vars(args), output=None)))),
        ('kit-deletes', lambda: command_kit_deletes(args)),
    ]
    failed = []
    started = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    say('daily: started {} ({})'.format(started, 'live sweeps' if args.live else 'dry-run sweeps'))
    for name, step in steps:
        status = guarded(step)
        say('daily: step {} {}'.format(name, 'ok' if status == EXIT_OK else 'FAILED (exit {})'.format(status)))
        if status != EXIT_OK:
            failed.append(name)
    if failed:
        say('daily: {} of {} steps failed: {}'.format(len(failed), len(steps), ', '.join(failed)))
        return EXIT_FAILED
    say('daily: all {} steps ok'.format(len(steps)))
    return EXIT_OK


def guarded(step):
    """Run a command and turn every way it can fail into an exit status and a message that holds no value. An
    interrupt is not a failure: it goes on up, so it stops the whole command."""
    try:
        return step()
    except wl_core.CheckRefused as error:
        complain('waitlist: {}'.format(error))
        return EXIT_REFUSED
    except WaitlistError as error:
        complain('waitlist: {}'.format(error))
        return EXIT_FAILED
    except RunLimitExceeded:
        complain('waitlist: the run passed its time limit; nothing was replaced')
        return EXIT_LIMIT
    except Exception as error:  # never let a traceback carry a value out
        complain('waitlist: internal error ({})'.format(type(error).__name__))
        return EXIT_INTERNAL


def build_parser():
    parser = argparse.ArgumentParser(prog='waitlist.py', description=__doc__.split('\n')[0])
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument('--state-dir')
    common.add_argument('--synthetic')
    common.add_argument('--restrict-to-ids')
    commands = parser.add_subparsers(dest='command', required=True)

    produce = commands.add_parser('produce', parents=[common])
    produce.add_argument('--output')
    produce.set_defaults(run=command_produce)
    commands.add_parser('assign', parents=[common]).set_defaults(run=command_assign)

    unsubscribed = commands.add_parser('sweep-unsubscribed', parents=[common])
    unsubscribed.add_argument('--live', action='store_true')
    unsubscribed.set_defaults(run=command_sweep_unsubscribed)

    retention = commands.add_parser('sweep-retention', parents=[common])
    retention.add_argument('--live', action='store_true')
    retention.add_argument('--as-of')
    retention.set_defaults(run=command_sweep_retention)

    remove = commands.add_parser('remove', parents=[common])
    remove.add_argument('--entry')
    remove.add_argument('--dry-run', action='store_true')
    remove.set_defaults(run=command_remove)

    record = commands.add_parser('record-launch-email', parents=[common])
    record.add_argument('--sent-on', required=True)
    record.add_argument('--replace', action='store_true')
    record.set_defaults(run=command_record_launch_email)

    tag = commands.add_parser('tag', parents=[common])
    tag.add_argument('label')
    tag.add_argument('entries', nargs='+')
    tag.set_defaults(run=command_tag)

    show = commands.add_parser('show', parents=[common])
    show.add_argument('entry')
    show.set_defaults(run=command_show)
    commands.add_parser('kit-deletes', parents=[common]).set_defaults(run=command_kit_deletes)

    daily = commands.add_parser('daily', parents=[common])
    daily.add_argument('--live', action='store_true')
    daily.set_defaults(run=command_daily)
    return parser


def main(argv):
    try:
        args = build_parser().parse_args(argv)
    except SystemExit as error:
        return EXIT_USAGE if error.code else EXIT_OK
    try:
        return guarded(lambda: args.run(args))
    except KeyboardInterrupt:
        return EXIT_INTERRUPTED


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

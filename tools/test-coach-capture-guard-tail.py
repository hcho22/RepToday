#!/usr/bin/env python3
"""Synthetic streamed events only. No credentials, tail sessions or network."""
import contextlib
import io
import sys
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('capture', Path(__file__).with_name('coach-capture-guard-tail.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
VERSION = '11111111-1111-4111-8111-111111111111'
PRIVATE = 'PRIVATE-SENTINEL-DO-NOT-OUTPUT'


def row(stage='do_assertion', reason='assertion_signature'):
    return {'event': 'coach_final_auth_guard', 'stage': stage, 'reason': reason}


def event(rows=(), entry='default', **changes):
    return dict({'scriptName': module.WORKER, 'scriptVersion': {'id': VERSION}, 'entrypoint': entry,
                 'executionModel': 'stateless', 'truncated': False,
                 'event': {'request': {'url': PRIVATE, 'headers': {'Authorization': PRIVATE}, 'body': PRIVATE}},
                 'exceptions': [{'message': PRIVATE}], 'eventTimestamp': PRIVATE,
                 'logs': [{'message': [json.dumps(value) for value in rows]}]}, **changes)


class FilterTests(unittest.TestCase):
    def test_every_exact_pair_survives_with_only_three_fields(self):
        for stage, reasons in module.FINAL.items():
            for reason in reasons:
                expected = row(stage, reason)
                self.assertEqual(list(module.guard_rows(event([expected]))), [expected])

    def test_negative_confidentiality_and_unknown_shape(self):
        good = row()
        for bad in [dict(good, keyId=PRIVATE), dict(good, deltaMs=1), dict(good, reason=PRIVATE),
                    dict(good, stage=PRIVATE), dict(good, stage='__proto__'), dict(good, reason=[]),
                    dict(good, stage={}), dict(good, event='coach_auth_guard'),
                    row('worker_envelope', 'assertion_signature'), None, [], PRIVATE]:
            self.assertEqual(list(module.guard_rows(event([bad]))), [])
        for bad in [None, [], {}, {'logs': {}}, {'logs': [None, {}, {'message': PRIVATE}]}]:
            self.assertEqual(list(module.guard_rows(bad)), [])
        self.assertEqual(list(module.guard_rows({'logs': [{'message': ['not-json', '"' + 'x' * 513 + '"']}]})), [])


class StreamTests(unittest.TestCase):
    def setUp(self):
        self.output = []
        self.clock = 0
        self.capture = module.Capture(VERSION, self.output.append, now=lambda: self.clock)

    def feed(self, value):
        encoded = (json.dumps(value, indent=2) + '\n').encode()
        for start in range(0, len(encoded), 7):  # actual incremental, pretty-JSON framing
            self.capture.feed(encoded[start:start + 7])

    def attach(self):
        self.capture.feed((module.ATTACHED + '\n').encode())

    def ready(self):
        self.attach()
        self.feed(event())
        self.assertFalse(self.capture.ready)
        self.feed(event(entry='CoachAuthenticationState'))
        self.assertTrue(self.capture.ready)

    def test_no_circular_wait_coverage_events_need_no_diagnostic_or_device_send(self):
        self.ready()
        self.assertEqual(self.output, [{'capture': 'attached', 'ready': False},
                                      {'capture': 'ready', 'ready': True, 'coverage': 'worker_and_do'}])
        self.feed(event([row()], entry='CoachAuthenticationState'))
        self.assertEqual(self.output[-1], row())
        self.assertNotIn(PRIVATE, json.dumps(self.output))
        self.assertNotIn(VERSION, json.dumps(self.output))

    def test_output_before_attachment_is_not_evidence(self):
        self.feed(event([row()]))
        self.assertEqual(self.output, [])

    def test_worker_only_transport_attachment_never_becomes_ready(self):
        self.attach()
        self.feed(event([row('worker_state', 'denied')]))
        self.clock = 120
        self.assertEqual(self.capture.poll(), 'coverage_missing')
        self.assertFalse(self.capture.ready)
        self.assertEqual(self.capture.rows, 0)

    def test_do_only_never_becomes_ready(self):
        self.attach()
        self.feed(event(entry='CoachAuthenticationState'))
        self.assertFalse(self.capture.ready)

    def test_wrong_or_missing_version_stops_without_output(self):
        self.attach()
        self.feed(event([row()], scriptVersion={'id': 'foreign'}))
        self.assertEqual(self.capture.stop, 'version_mismatch')
        self.assertFalse(self.capture.ready)
        self.assertEqual(self.capture.rows, 0)

    def test_unknown_or_missing_entrypoint_cannot_prove_do(self):
        self.attach()
        self.feed(event(entry='Unknown'))
        self.feed(event(entry=None))
        self.assertFalse(self.capture.ready)

    def test_truncated_sample_is_inconclusive(self):
        self.ready()
        self.feed(event([row()], truncated=True))
        self.assertEqual(self.capture.stop, 'truncated')
        self.assertEqual(self.capture.rows, 0)

    def test_sample_bound_applies_even_to_empty_logs(self):
        self.ready()
        for _ in range(210):
            self.capture.event(event())
        self.assertEqual(self.capture.stop, 'sample_limit')

    def test_maximum_twenty_rows_and_bounded_output(self):
        self.ready()
        self.feed(event([row()] * 30, entry='CoachAuthenticationState'))
        self.assertEqual(self.capture.rows, 20)
        self.assertEqual(self.capture.stop, 'row_limit')
        self.assertLess(len(json.dumps(self.output)), 4096)

    def test_first_row_shortens_window_without_extending_original_deadline(self):
        self.ready()
        self.clock = 119
        self.feed(event([row()]))
        self.assertEqual(self.capture.deadline, 120)
        self.clock = 120
        self.assertEqual(self.capture.poll(), 'deadline')

    def test_silence_is_not_a_successful_coach_result(self):
        self.ready()
        self.clock = 120
        self.assertEqual(self.capture.poll(), 'deadline')
        self.assertEqual(self.capture.rows, 0)
        self.assertFalse(any('success' in item for item in self.output))

    def test_cancel_and_duplicate_attachment_stop(self):
        self.ready()
        self.capture.stop = 'cancelled'
        self.feed(event([row()]))
        self.assertEqual(self.capture.rows, 0)
        other = module.Capture(VERSION, self.output.append)
        other.feed((module.ATTACHED + '\n' + module.ATTACHED + '\n').encode())
        self.assertEqual(other.stop, 'attachment_changed')

    def test_partial_or_oversized_json_never_leaks(self):
        self.attach()
        self.capture.feed(b'{"private":"' + PRIVATE.encode())
        self.clock = 120
        self.assertEqual(self.capture.poll(), 'coverage_missing')
        self.assertNotIn(PRIVATE, json.dumps(self.output))
        other = module.Capture(VERSION, self.output.append)
        other.feed(b'{' + b'x' * 262144)
        self.assertEqual(other.stop, 'input_limit')

    def test_invalid_bounds_and_versions(self):
        for version, seconds in [('latest', 120), (VERSION, 0), (VERSION, 121), (VERSION, True)]:
            with self.assertRaises(ValueError):
                module.Capture(version, self.output.append, seconds=seconds)


class CleanupTests(unittest.TestCase):
    def test_timeout_escalates_once_each_without_restarting_or_claiming_remote_close(self):
        class Stuck:
            pid = 999999
            def poll(self):
                return None
            def wait(self, timeout):
                raise subprocess.TimeoutExpired('synthetic', timeout)
        with patch.object(module.os, 'killpg') as kill:
            module.close_child(Stuck())
        self.assertEqual([args[0][1] for args in kill.call_args_list],
                         [module.signal.SIGINT, module.signal.SIGTERM, module.signal.SIGKILL])


class ProcessTests(unittest.TestCase):
    def run_capture(self, payload, end='time.sleep(10)'):
        original = subprocess.Popen
        script = 'import time,sys,os\n' + 'sys.stdout.write(' + repr(payload) + '); sys.stdout.flush()\n' + end
        def spawn(args, **options):
            self.assertEqual(Path(args[1]).name, 'coach-tail-ready.cjs')
            self.assertEqual(args[2], VERSION)
            self.assertEqual(Path(options['env']['WRANGLER_LOG_PATH']).resolve(), Path('/dev/null'))
            self.assertEqual(options['stderr'], subprocess.DEVNULL)
            return original([sys.executable, '-c', script], **options)
        output = io.StringIO()
        with tempfile.TemporaryDirectory(prefix='capture-test-', dir=Path(__file__).resolve().parents[1]) as directory:
            root = Path(directory)
            self.assertFalse((root / 'build').exists())
            with patch.object(module, '__file__', str(root / 'tools/coach-capture-guard-tail.py')), \
                    patch.object(module.subprocess, 'Popen', spawn), contextlib.redirect_stdout(output):
                status = module.capture(VERSION, seconds=1)
            self.assertTrue((root / 'build').is_dir())
            self.assertEqual(list((root / 'build').iterdir()), [])
        self.assertNotIn(PRIVATE, output.getvalue())
        return status, [json.loads(line) for line in output.getvalue().splitlines()]

    def test_real_pipe_ready_rows_deadline_and_process_cleanup(self):
        payload = module.ATTACHED + '\n' + '\n'.join(json.dumps(e) for e in [
            event(), event(entry='CoachAuthenticationState'), event([row()], entry='CoachAuthenticationState')]) + '\n'
        status, output = self.run_capture(payload)
        self.assertEqual(status, 0)
        self.assertIn(row(), output)
        self.assertEqual(output[-1], {'capture': 'ended', 'ready': True, 'reason': 'deadline',
                                    'fixed_rows': 1, 'remote_closure': 'unverified'})

    def test_real_pipe_timeout_does_not_invite_a_send(self):
        status, output = self.run_capture(module.ATTACHED + '\n' + json.dumps(event()) + '\n')
        self.assertEqual(status, 78)
        self.assertFalse(any(e.get('ready') for e in output))
        self.assertEqual(output[-1]['reason'], 'coverage_missing')

    def test_child_failure_and_arbitrary_output_are_not_success(self):
        status, output = self.run_capture(PRIVATE + '\n', 'sys.stderr.write(' + repr(PRIVATE) + ');sys.exit(3)')
        self.assertEqual(status, 78)
        self.assertFalse(output[-1]['ready'])
        self.assertEqual(output[-1]['reason'], 'child_exit')

    def test_cancel_signal_has_bounded_cleanup_and_no_retry(self):
        status, output = self.run_capture(module.ATTACHED + '\n',
            'time.sleep(0.1);os.kill(os.getppid(),15);time.sleep(10)')
        self.assertEqual(status, 78)
        self.assertEqual(output[-1]['reason'], 'cancelled')


if __name__ == '__main__':
    unittest.main()

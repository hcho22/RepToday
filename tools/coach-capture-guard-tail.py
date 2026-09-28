#!/usr/bin/env python3
"""Bounded transient filter, ported from the investigation helper. Capture needs separate authority.
Raw events/metadata stay in memory. No deploy, credential reader, reconnect or retry.
"""
import argparse
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import subprocess
import tempfile
import time

WORKER = 'reptoday-variety-language-proxy'
ATTACHED = '__COACH_TAIL_ATTACHED__'
TOKEN = {'token_syntax', 'token_mac', 'token_claims', 'token_future', 'token_expired'}
FINAL = {
    'worker_envelope': {'missing_proof', 'proof_envelope', 'assertion_encoding'},
    'worker_token': TOKEN, 'worker_state': {'denied', 'not_authorized'},
    'worker_premium': {'denied', 'presented_environment', 'presented_chain', 'status_identity',
                       'status_count', 'status_match', 'premium_policy'},
    'do_preflight': {'key_format', 'prefix_format', 'request_shape', 'assertion_encoding'},
    'do_token_entry': TOKEN, 'do_token_transaction': TOKEN,
    'do_state': {'denied', 'pending_challenge'},
    'do_assertion': {'assertion_cbor', 'assertion_shape', 'assertion_counter', 'assertion_signature', 'assertion_result'},
}


def guard_rows(event):
    logs = event.get('logs') if isinstance(event, dict) else None
    if not isinstance(logs, list):
        return
    for log in logs:
        messages = log.get('message') if isinstance(log, dict) else None
        if not isinstance(messages, list):
            continue
        for message in messages:
            if not isinstance(message, str) or len(message) > 512:
                continue
            try:
                row = json.loads(message)
            except (ValueError, TypeError):
                continue
            if not isinstance(row, dict) or set(row) != {'event', 'stage', 'reason'}:
                continue
            stage, reason = row.get('stage'), row.get('reason')
            if (row.get('event') == 'coach_final_auth_guard' and isinstance(stage, str)
                    and isinstance(reason, str) and reason in FINAL.get(stage, set())):
                yield {key: row[key] for key in ('event', 'stage', 'reason')}


class Capture:
    """Streaming parser/state machine; injected clock/output make all stops locally testable."""
    def __init__(self, version, emit, now=time.monotonic, seconds=120):
        if not isinstance(version, str) or not re.fullmatch(r'[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}', version):
            raise ValueError('version')
        if type(seconds) is not int or not 1 <= seconds <= 120:
            raise ValueError('duration')
        self.version, self.emit, self.now = version, emit, now
        self.deadline = now() + seconds
        self.attached = self.ready = False
        self.coverage = set()
        self.rows = self.samples = self.bytes = 0
        self.pending = b''
        self.document = ''
        self.stop = None

    def poll(self):
        if not self.stop and self.now() >= self.deadline:
            self.stop = 'deadline' if self.ready else 'coverage_missing'
        return self.stop

    def feed(self, chunk):
        if self.poll():
            return
        self.bytes += len(chunk)
        if self.bytes > 4 * 1024 * 1024 or len(self.pending) + len(chunk) > 262144:
            self.stop = 'input_limit'
            return
        self.pending += chunk
        while b'\n' in self.pending and not self.stop:
            raw, self.pending = self.pending.split(b'\n', 1)
            line = raw.decode('utf-8', errors='replace')
            if line == ATTACHED and not self.document:
                if self.attached:
                    self.stop = 'attachment_changed'
                    return
                self.attached = True
                self.emit({'capture': 'attached', 'ready': False})
                continue
            if not self.document and not line.lstrip().startswith('{'):
                continue
            self.document += line + '\n'
            if len(self.document) > 262144:
                self.stop = 'input_limit'
                return
            try:
                event = json.loads(self.document)
            except ValueError:
                continue
            self.document = ''
            self.event(event)

    def event(self, event):
        if self.poll() or not self.attached or not isinstance(event, dict):
            return
        self.samples += 1
        if self.samples > 200:
            self.stop = 'sample_limit'
            return
        if event.get('scriptName') != WORKER or not isinstance(event.get('scriptVersion'), dict) or event['scriptVersion'].get('id') != self.version:
            self.stop = 'version_mismatch'
            return
        if event.get('truncated') is True:
            self.stop = 'truncated'
            return
        entry = event.get('entrypoint')
        if entry == 'CoachAuthenticationState':
            self.coverage.add('do')
        elif entry == 'default' or entry is None and event.get('executionModel') == 'stateless':
            self.coverage.add('worker')
        if not self.ready:
            if self.coverage == {'worker', 'do'}:
                self.ready = True
                self.emit({'capture': 'ready', 'ready': True, 'coverage': 'worker_and_do'})
            # Readiness probes/events never become diagnostic evidence for the device send.
            return
        for row in guard_rows(event):
            self.emit(row)
            self.rows += 1
            self.deadline = min(self.deadline, self.now() + 5)
            if self.rows >= 20:
                self.stop = 'row_limit'
                return


def close_child(proc):
    """Bounded process-group cleanup. Remote closure ALWAYS needs a separate zero-tail read."""
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGKILL):
        if proc.poll() is not None:
            return
        try:
            os.killpg(proc.pid, sig)
            proc.wait(timeout=2)
        except ProcessLookupError:
            return
        except subprocess.TimeoutExpired:
            pass


def capture(version, seconds=120):
    emit = lambda row: print(json.dumps(row, separators=(',', ':')), flush=True)
    state = Capture(version, emit, seconds=seconds)
    node = shutil.which('node')
    if not node:
        return 78
    root = Path(__file__).resolve().parents[1]
    (root / 'build').mkdir(exist_ok=True)
    # Dedicated empty cwd prevents inherited Wrangler config. Logger disk sink is /dev/null.
    with tempfile.TemporaryDirectory(prefix='coach-tail-', dir=root / 'build') as directory:
        sink = Path(directory) / 'discard.log'
        sink.symlink_to('/dev/null')
        env = os.environ.copy()
        for name in ('NODE_OPTIONS', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE'):
            env.pop(name, None)
        env.update(CI='true', WRANGLER_LOG_PATH=str(sink), WRANGLER_SEND_METRICS='false', WRANGLER_LOG='log')
        proc = subprocess.Popen([node, str(root / 'tools/coach-tail-ready.cjs'), version], cwd=directory,
                                env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
        selector = selectors.DefaultSelector()
        selector.register(proc.stdout, selectors.EVENT_READ)
        def cancel(_sig, _frame):
            state.stop = 'cancelled'
        previous = {sig: signal.signal(sig, cancel) for sig in (signal.SIGINT, signal.SIGTERM)}
        emit({'capture': 'starting', 'ready': False})
        try:
            while not state.poll():
                for key, _ in selector.select(min(0.5, max(0, state.deadline - time.monotonic()))):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        state.stop = 'child_exit'
                        break
                    state.feed(chunk)
                if proc.poll() is not None and not state.stop:
                    state.stop = 'child_exit'
        finally:
            selector.close()
            close_child(proc)
            proc.stdout.close()
            for sig, handler in previous.items():
                signal.signal(sig, handler)
            emit({'capture': 'ended', 'ready': state.ready, 'reason': state.stop,
                  'fixed_rows': state.rows, 'remote_closure': 'unverified'})
    return 0 if state.ready and state.stop in ('deadline', 'row_limit') else 78


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture-version', required=True)
    parser.add_argument('--seconds', type=int, default=120)
    args = parser.parse_args()
    try:
        raise SystemExit(capture(args.capture_version, args.seconds))
    except (ValueError, OSError):
        print('{"capture":"failed","ready":false,"remote_closure":"unverified"}')
        raise SystemExit(78)

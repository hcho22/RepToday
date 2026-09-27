#!/usr/bin/env python3
"""Bound and filter only the native --keychain-preflight entry. No operational mode."""
import os
import re
import selectors
import signal
import subprocess
import sys
import time

# Output protocol labels only; credential selection/order belongs solely to the Swift enum.
LINE = re.compile(
    rb"preflight category=(all|openAI|clientGate|wafToken|appPrefix|appID|keyID|issuerID|privateKey) "
    rb"event=(start|pending|completed|success|failure|timed_out|cancelled) "
    rb"elapsed_ms=([0-9]{1,9}) read_elapsed_ms=([0-9]{1,9}) osstatus=(unavailable|-?[0-9]{1,10})"
)
READ_LIMIT = 118
OVERALL_LIMIT = 595
CLEANUP_GRACE = 1


def stop_owned(child):
    """Only the session created for this invocation; never signal system UI or other helpers."""
    # Kill the owned group even when its leader just exited. Native preflight has no children;
    # this also contains unexpected children in the synthetic containment test.
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        child.wait(timeout=CLEANUP_GRACE)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    child.wait(timeout=CLEANUP_GRACE)


def supervise(binary, *, read_limit=READ_LIMIT, overall_limit=OVERALL_LIMIT):
    started = time.monotonic()
    pending_at = None
    category = b"all"
    cancelled = False
    old_handlers = {}

    def cancel(_number, _frame):
        nonlocal cancelled
        cancelled = True

    def fixed(event):
        elapsed = int((time.monotonic() - started) * 1000)
        read_elapsed = 0 if pending_at is None else int((time.monotonic() - pending_at) * 1000)
        print(f"preflight category={category.decode('ascii')} event={event} elapsed_ms={elapsed} "
              f"read_elapsed_ms={read_elapsed} osstatus=unavailable", flush=True)

    child = None
    selector = selectors.DefaultSelector()
    try:
        for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            old_handlers[number] = signal.signal(number, cancel)
        # No argument/environment credential transport; no child diagnostic forwarding.
        child = subprocess.Popen([binary, "--keychain-preflight"], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 start_new_session=True)
        os.set_blocking(child.stdout.fileno(), False)
        selector.register(child.stdout, selectors.EVENT_READ)
        buffer = b""
        terminal = None
        completed = set()
        while True:
            now = time.monotonic()
            if cancelled:
                fixed("cancelled")
                return 130
            if now - started >= overall_limit or (pending_at is not None and now - pending_at >= read_limit):
                fixed("timed_out")
                return 124
            for key, _ in selector.select(timeout=0.05):
                data = os.read(key.fd, 4096)
                if not data:
                    selector.unregister(key.fileobj)
                    continue
                buffer += data
                if len(buffer) > 8192:
                    fixed("failure")
                    return 78
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    match = LINE.fullmatch(line)
                    if not match or terminal is not None:
                        fixed("failure")
                        return 78
                    label, event = match.group(1, 2)
                    if event == b"start":
                        if pending_at is not None or label == b"all" or label in completed:
                            fixed("failure")
                            return 78
                        category, pending_at = label, time.monotonic()
                    elif event == b"completed":
                        if pending_at is None or label != category or match.group(5) != b"0":
                            fixed("failure")
                            return 78
                        completed.add(label)
                        pending_at = None
                    elif event == b"success":
                        if pending_at is not None or len(completed) != 8 or label != b"all" or match.group(5) != b"0":
                            fixed("failure")
                            return 78
                        terminal = 0
                    elif event == b"pending":
                        if pending_at is None or label != category:
                            fixed("failure")
                            return 78
                    else:
                        if label != category and label != b"all":
                            fixed("failure")
                            return 78
                        terminal = {b"failure": 78, b"timed_out": 124, b"cancelled": 130}[event]
                    # The whole line passed the closed schema; no arbitrary child output.
                    print(line.decode("ascii"), flush=True)
            if child.poll() is not None and not selector.get_map():
                if buffer or terminal is None or child.returncode != terminal:
                    fixed("failure")
                    return 78
                return terminal
    except (OSError, ValueError, subprocess.SubprocessError):
        fixed("failure")
        return 78
    finally:
        if child is not None:
            stop_owned(child)
            child.stdout.close()
        selector.close()
        for number, handler in old_handlers.items():
            signal.signal(number, handler)


if __name__ == "__main__":
    if len(sys.argv) != 2 or not os.path.isabs(sys.argv[1]):
        print("usage: coach-keychain-preflight.py /absolute/path/to/coach-runtime-migrate")
        sys.exit(64)
    sys.exit(supervise(sys.argv[1]))

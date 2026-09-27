#!/usr/bin/env python3
"""Synthetic processes/UI only. Never execute the native credential reader."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build/coach-runtime-migration"
spec = importlib.util.spec_from_file_location("preflight", ROOT / "tools/coach-keychain-preflight.py")
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=BUILD)
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def executable(self, name, source):
        file = self.root / name
        file.write_text(f"#!{sys.executable}\n" + source)
        file.chmod(0o700)
        return file

    def supervise(self, source, **limits):
        binary = self.executable("synthetic-native", source)
        output = io.StringIO()
        start = time.monotonic()
        with contextlib.redirect_stdout(output):
            status = preflight.supervise(str(binary), **limits)
        for line in output.getvalue().splitlines():
            self.assertIsNotNone(preflight.LINE.fullmatch(line.encode()))
        self.assertNotIn("SENTINEL", output.getvalue())
        return status, output.getvalue(), time.monotonic() - start

    def test_outer_protocol_and_pending_deadline(self):
        source = """
import time
print('preflight category=issuerID event=start elapsed_ms=0 read_elapsed_ms=0 osstatus=unavailable', flush=True)
time.sleep(20)
"""
        status, output, elapsed = self.supervise(source, read_limit=0.15, overall_limit=3)
        self.assertEqual(status, 124)
        self.assertIn("category=issuerID event=timed_out", output)
        self.assertLess(elapsed, 2.5)

    def test_outer_overall_silent_deadline_and_kill(self):
        status, output, elapsed = self.supervise(
            "import time, signal\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\ntime.sleep(20)\n",
            overall_limit=0.15)
        self.assertEqual(status, 124)
        self.assertIn("category=all event=timed_out", output)
        self.assertLess(elapsed, 2.5)

    def test_outer_rejects_arbitrary_output_and_incomplete_success(self):
        for payload in ["NONSECRET_VALUE_SENTINEL", "x" * 9000,
                        "preflight category=all event=success elapsed_ms=0 read_elapsed_ms=0 osstatus=0"]:
            status, _, _ = self.supervise(f"print({payload!r}, flush=True)\n")
            self.assertEqual(status, 78)

    def test_outer_cancel_reaps_owned_child(self):
        pidfile = self.root / "pid"
        binary = self.executable("pending", f"""
import os, time
open({str(pidfile)!r}, 'w').write(str(os.getpid()))
print('preflight category=openAI event=start elapsed_ms=0 read_elapsed_ms=0 osstatus=unavailable', flush=True)
time.sleep(20)
""")
        supervisor = subprocess.Popen([sys.executable, str(ROOT / "tools/coach-keychain-preflight.py"), str(binary)],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertIn("event=start", supervisor.stdout.readline())
            supervisor.send_signal(signal.SIGTERM)
            output, error = supervisor.communicate(timeout=4)
            self.assertEqual(supervisor.returncode, 130)
            self.assertEqual(error, "")
            self.assertIn("event=cancelled", output)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pidfile.read_text()), 0)
        finally:
            if supervisor.poll() is None:
                supervisor.kill(); supervisor.wait()

    def test_native_presenter_success_failure_cancel_and_deadlines(self):
        binary = BUILD / "presentation-tests"
        for scenario, status, count in [("success", 0, 8), ("failure", 78, 6),
                                         ("cancel", 130, 1), ("pending", 124, 1), ("blocked-main", 124, 1)]:
            with self.subTest(scenario=scenario):
                run = subprocess.run([str(binary), scenario], capture_output=True, timeout=12)
                self.assertEqual(run.returncode, status)
                lines = run.stdout.splitlines()
                self.assertEqual(sum(b"event=start " in line for line in lines), count)
                self.assertTrue(all(preflight.LINE.fullmatch(line) for line in lines))
                self.assertNotIn(b"SENTINEL", run.stdout)
                if scenario == "failure":
                    self.assertIn(b"category=keyID event=failure", lines[-1])
                    self.assertTrue(lines[-1].endswith(b"osstatus=-25293"))

    def test_native_signal_cancels_pending_modal(self):
        child = subprocess.Popen([str(BUILD / "presentation-tests"), "signal"],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        try:
            self.assertIn(b"event=start", child.stdout.readline())
            # Wait briefly for the synthetic modal/read to enter; no actual Keychain query.
            time.sleep(0.3)
            child.send_signal(signal.SIGTERM)
            output, _ = child.communicate(timeout=3)
            self.assertEqual(child.returncode, 130)
            self.assertIn(b"event=cancelled", output)
        finally:
            if child.poll() is None:
                child.kill(); child.wait()

    def test_wrapper_routes_before_all_production_prerequisites(self):
        tools = self.root / "tools"
        tools.mkdir()
        (self.root / "proxy").mkdir()
        for name in ["migrate-coach-runtime.sh", "coach-keychain-preflight.py"]:
            shutil.copy(ROOT / "tools" / name, tools / name)
        calls = self.root / "calls"
        fixture = """
import sys
assert sys.argv[1:] == ['--keychain-preflight']
for category in ['openAI','clientGate','wafToken','appPrefix','appID','keyID','issuerID','privateKey']:
    print(f'preflight category={category} event=start elapsed_ms=0 read_elapsed_ms=0 osstatus=unavailable', flush=True)
    print(f'preflight category={category} event=completed elapsed_ms=0 read_elapsed_ms=0 osstatus=0', flush=True)
print('preflight category=all event=success elapsed_ms=0 read_elapsed_ms=0 osstatus=0', flush=True)
"""
        self.executable("xcrun", f"""
import pathlib, sys
with open({str(calls)!r}, 'a') as f: f.write('compile\\n')
target = pathlib.Path(sys.argv[sys.argv.index('-o') + 1])
target.write_text({('#!' + sys.executable + chr(10) + fixture)!r})
target.chmod(0o700)
""")
        for name in ["git", "node"]:
            self.executable(name, f"open({str(calls)!r}, 'a').write({name!r} + '\\n')\nraise SystemExit(99)\n")
        environment = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ["PATH"])
        wrapper = ["/bin/bash", str(tools / "migrate-coach-runtime.sh")]
        invalid = [[], ["--inspect"], ["--keychain-preflight", "--keychain-preflight"],
                   ["--keychain-preflight", "--auth-guard-diagnostics"], ["--keychain-preflight=1"],
                   ["--stage", "--auth-guard-diagnostics", "--keychain-preflight"]]
        for flag in ["--stage", "--release", "--hold", "--inspect", "--deploy"]:
            invalid += [[flag, "--keychain-preflight"], ["--keychain-preflight", flag]]
        for args in invalid:
            result = subprocess.run(wrapper + args, capture_output=True, env=environment, timeout=5)
            self.assertEqual(result.returncode, 64)
        self.assertFalse(calls.exists())
        help_result = subprocess.run(wrapper + ["--help"], capture_output=True, env=environment, timeout=5)
        self.assertEqual(help_result.returncode, 0)
        self.assertFalse(calls.exists())
        result = subprocess.run(wrapper + ["--keychain-preflight"], capture_output=True, env=environment, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls.read_text(), "compile\n")
        # Normal modes still enter the existing production prerequisite gate.
        for flag in ["--stage", "--release", "--hold"]:
            result = subprocess.run(wrapper + [flag], capture_output=True, env=environment, timeout=5)
            self.assertEqual(result.returncode, 78)
        self.assertEqual(calls.read_text(), "compile\ngit\ngit\ngit\n")

    def test_no_downstream_capability_in_preflight_body(self):
        source = (ROOT / "tools/coach-keychain-preflight.swift").read_text()
        body = source[source.index("func runKeychainPreflight"):]
        for forbidden in ["RuntimeNodeCoordinator", "runRuntimeMigration(", "Process(", "URLSession",
                          "SecItemAdd", "SecItemUpdate", "SecItemDelete", "JSONSerialization"]:
            self.assertNotIn(forbidden, body)
        self.assertIn("RuntimeMigrationCredential.allCases", body)

    def test_real_entry_rejects_ambiguous_cli_before_reads(self):
        for args in [["--keychain-preflight", "--stage"], ["--stage", "--keychain-preflight"],
                     ["--keychain-preflight", "/repo", "/node"],
                     ["--stage", "/repo", "/node", "--keychain-preflight"],
                     ["--keychain-preflight", "--auth-guard-diagnostics"], ["--keychain-preflight=1"]]:
            result = subprocess.run([str(BUILD / "coach-runtime-migrate"), *args],
                                    capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 64)
            self.assertTrue(result.stdout.startswith(b"usage:"))
            self.assertNotIn(b"event=start", result.stdout)


if __name__ == "__main__":
    unittest.main()

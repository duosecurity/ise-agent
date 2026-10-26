"""Exercise the real host scripts with a controlled container-runtime boundary."""

import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
RUNTIME = r"""
import json, os, pathlib, sys, time
args = sys.argv[1:]
root = pathlib.Path(os.environ['RESUME_TEST_ROOT'])
if pathlib.Path(sys.argv[0]).name == 'docker' and os.environ.get('RESUME_TEST_PODMAN'):
    sys.exit(1)
with (root / 'commands.jsonl').open('a') as log:
    log.write(json.dumps(args) + '\n')
if args[:2] == ['compose', 'version']:
    sys.exit(0)
if args[:1] == ['info']:
    print(('true' if os.environ.get('RESUME_TEST_ROOTLESS') else 'false')
          if 'Host.Security.Rootless' in ' '.join(args) else '[]')
    sys.exit(0)
stage = ''
if '/app/bootstrap_iot.py' in args:
    stage = 'bootstrap'
elif '/app/setup_credentials.py' in args:
    stage = 'credentials'
elif '/app/setup_pxgrid.py' in args:
    stage = 'pxgrid'
elif args[:3] == ['compose', 'up', '-d']:
    stage = 'start'
if stage and os.environ.get('RESUME_TEST_HOLD') == stage:
    (root / 'holding').touch()
    time.sleep(30)
if stage and os.environ.get('RESUME_TEST_FAILURE') == stage:
    sys.exit(21)
if stage in ('credentials', 'pxgrid') and not os.environ.get('RESUME_TEST_NO_STORE'):
    name = '.credentials.enc' if stage == 'credentials' else '.pxgrid.enc'
    (root / 'certs' / name).write_text('fixture encrypted store')
"""


class ResumeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ise-agent-resume-")
        self.root = Path(self.temporary.name)
        (self.root / ".launcher").mkdir()
        (self.root / "certs").mkdir()
        (self.root / "bin").mkdir()
        for source, target in [
            ("start.sh", "start.sh"),
            ("agentctl", ".launcher/agentctl"),
            ("docker-compose.yml", "docker-compose.yml"),
        ]:
            shutil.copy2(REPOSITORY / source, self.root / target)
        (self.root / ".env").write_text("AGENT_ID=test__ISE__12345678\n")
        (self.root / "certs/certificate.pem.crt").write_text(
            "-----BEGIN CERTIFICATE-----\nfixture\n"
        )
        (self.root / "certs/private.pem.key").write_text("fixture private key")
        runtime = self.root / "bin/docker"
        runtime.write_text("#!" + sys.executable + "\n" + RUNTIME)
        runtime.chmod(0o755)
        shutil.copy2(runtime, self.root / "bin/podman")
        self.environment = dict(
            os.environ,
            PATH=str(runtime.parent) + os.pathsep + os.environ["PATH"],
            RESUME_TEST_ROOT=str(self.root),
        )
        self.before = self.identity()

    def tearDown(self):
        self.temporary.cleanup()

    def identity(self):
        return {
            name: hashlib.sha256((self.root / name).read_bytes()).hexdigest()
            for name in (".env", "certs/certificate.pem.crt", "certs/private.pem.key")
        }

    def run_host(self, *arguments, **environment):
        return subprocess.run(
            ["/bin/bash", str(self.root / "start.sh"), *arguments, "--no-pull"],
            cwd=self.root,
            env=dict(self.environment, **environment),
            text=True,
            capture_output=True,
            timeout=15,
            check=False,
        )

    def commands(self):
        log = self.root / "commands.jsonl"
        return (
            [json.loads(line) for line in log.read_text().splitlines()]
            if log.exists()
            else []
        )

    def pending(self, phase="credentials"):
        (self.root / ".launcher/setup.pending").write_text(phase + "\n")

    def test_credential_failure_preserves_identity_and_requires_explicit_resume(self):
        failed = self.run_host(RESUME_TEST_FAILURE="credentials")
        self.assertNotEqual(failed.returncode, 0, failed.stdout + failed.stderr)
        marker = self.root / ".launcher/setup.pending"
        self.assertEqual(marker.read_text().strip(), "credentials")
        self.assertEqual(marker.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.identity(), self.before)
        self.assertFalse((self.root / ".launcher/setup.lock").exists())
        self.assertIn("--resume", failed.stderr)
        self.assertNotEqual(self.run_host().returncode, 0)
        self.assertNotEqual(self.run_host("--update").returncode, 0)
        resumed = self.run_host("--resume")
        self.assertEqual(resumed.returncode, 0, resumed.stdout + resumed.stderr)
        self.assertFalse(marker.exists())
        self.assertEqual(self.identity(), self.before)
        self.assertTrue((self.root / "certs/.pxgrid.enc").is_file())
        self.assertFalse(any("--bundle" in args for args in self.commands()))

    def test_missing_pxgrid_is_configured_with_existing_ise_store(self):
        (self.root / "certs/.credentials.enc").write_text("existing ISE store")
        result = self.run_host()
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        self.assertFalse(any("/app/setup_credentials.py" in args for args in commands))
        self.assertTrue(any("/app/setup_pxgrid.py" in args for args in commands))

    def test_pxgrid_failure_retains_ise_store_and_resumes(self):
        failed = self.run_host(RESUME_TEST_FAILURE="pxgrid")
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(
            (self.root / ".launcher/setup.pending").read_text().strip(), "pxgrid"
        )
        self.assertTrue((self.root / "certs/.credentials.enc").is_file())
        self.assertEqual(self.run_host("--resume").returncode, 0)

    def test_start_failure_retains_stores_and_resumes(self):
        failed = self.run_host(RESUME_TEST_FAILURE="start")
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(
            (self.root / ".launcher/setup.pending").read_text().strip(), "start"
        )
        self.assertTrue((self.root / "certs/.pxgrid.enc").is_file())
        self.assertEqual(self.run_host("--resume").returncode, 0)

    def test_stop_is_available_during_partial_setup(self):
        self.pending()
        self.assertEqual(self.run_host("--stop").returncode, 0)
        self.assertTrue((self.root / ".launcher/setup.pending").exists())

    def test_log_collection_is_available_during_partial_setup(self):
        self.pending()
        result = self.run_host("--collect-logs")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any("collect-logs" in args for args in self.commands()))
        self.assertTrue((self.root / ".launcher/setup.pending").exists())

    def test_installer_refuses_to_overwrite_saved_identity(self):
        result = subprocess.run(
            ["/bin/bash", str(REPOSITORY / "install.sh"), "fixture-only-bundle"],
            cwd=self.root,
            env=self.environment,
            text=True,
            capture_output=True,
            timeout=15,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--resume", result.stderr)
        self.assertEqual(self.identity(), self.before)
        self.assertFalse(any("--bundle" in args for args in self.commands()))

    def test_concurrent_setup_refused(self):
        (self.root / ".launcher/setup.lock").mkdir()
        result = self.run_host("--resume")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("another setup", result.stderr)
        self.assertFalse(
            any("/app/setup_credentials.py" in args for args in self.commands())
        )

    def test_placeholder_token_cannot_be_used_as_resumed_identity(self):
        (self.root / "certs/certificate.pem.crt").write_text(
            "https://bootstrap.example.invalid"
        )
        result = self.run_host("--resume")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(
            any("/app/bootstrap_iot.py" in args for args in self.commands())
        )

    def test_success_without_store_is_not_accepted(self):
        result = self.run_host(RESUME_TEST_NO_STORE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / ".launcher/setup.pending").exists())
        self.assertFalse(
            any(args[:3] == ["compose", "up", "-d"] for args in self.commands())
        )

    def test_resume_stops_service_before_authentication(self):
        self.pending()
        self.assertEqual(self.run_host("--resume").returncode, 0)
        commands = self.commands()
        stop = commands.index(["compose", "stop", "ise-agent"])
        setup = next(
            i for i, args in enumerate(commands) if "/app/setup_credentials.py" in args
        )
        self.assertLess(stop, setup)

    def test_interruption_preserves_progress_and_releases_lock(self):
        child = subprocess.Popen(
            ["/bin/bash", str(self.root / "start.sh"), "--no-pull"],
            cwd=self.root,
            env=dict(self.environment, RESUME_TEST_HOLD="credentials"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            deadline = time.monotonic() + 8
            while not (self.root / "holding").exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue((self.root / "holding").exists())
            os.killpg(child.pid, signal.SIGTERM)
            child.communicate(timeout=5)
            self.assertNotEqual(child.returncode, 0)
            self.assertTrue((self.root / ".launcher/setup.pending").exists())
            self.assertFalse((self.root / ".launcher/setup.lock").exists())
            self.assertEqual(self.identity(), self.before)
        finally:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGKILL)
                child.communicate()


class PodmanResumeTests(ResumeTests):
    def setUp(self):
        super().setUp()
        self.environment["RESUME_TEST_PODMAN"] = "1"


class RootlessPodmanResumeTests(PodmanResumeTests):
    def setUp(self):
        super().setUp()
        self.environment["RESUME_TEST_ROOTLESS"] = "1"


if __name__ == "__main__":
    unittest.main(verbosity=2)

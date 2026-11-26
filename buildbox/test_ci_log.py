import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class CILogTests(unittest.TestCase):
    def test_output_and_exit_status(self):
        script = Path(__file__).with_name("ci-log.sh")
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, CI_PROJECT_DIR=directory, CI_JOB_ID="123")
            for status in (0, 23):
                with self.subTest(status=status):
                    result = subprocess.run(["bash", str(script), "bash", "-c", f"echo stdout-{status}; echo stderr-{status} >&2; exit {status}"], env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, status)
                    self.assertIn(f"stdout-{status}", result.stdout)
                    self.assertIn(f"stderr-{status}", result.stdout)
            log = (Path(directory) / ".ci-build-logs/123/job.log").read_text()
            for output in ("stdout-0", "stderr-0", "stdout-23", "stderr-23"):
                self.assertIn(output, log)

    def test_missing_command(self):
        result = subprocess.run(["bash", str(Path(__file__).with_name("ci-log.sh"))], capture_output=True)
        self.assertEqual(result.returncode, 64)


if __name__ == "__main__":
    unittest.main()

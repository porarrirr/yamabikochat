import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

from ios.YamabikoChat.Python.Resources import yamabiko_runtime


class YamabikoRuntimeTests(unittest.TestCase):
    def run_cell(self, session: str, code: str, *, reset: bool = False):
        root = Path(tempfile.mkdtemp(prefix="yamabiko-python-test-"))
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        workspace = root / "workspace"
        outputs = workspace / "outputs"
        options = json.dumps({
            "workspace": str(workspace),
            "outputs": str(outputs),
            "read_roots": [
                str(Path(__file__).resolve().parents[2]),
                str(Path(os.__file__).resolve().parent),
            ],
            "reset": reset,
        })
        return json.loads(yamabiko_runtime.run_cell(session, code, options)), root

    def test_final_expression_and_stateful_namespace(self):
        first, _ = self.run_cell("state", "value = 40\nvalue + 2")
        self.assertEqual(first["status"], "ok")
        self.assertEqual(first["result_repr"], "42")

        second, _ = self.run_cell("state", "value + 3")
        self.assertEqual(second["result_repr"], "43")

    def test_reset_discards_namespace(self):
        self.run_cell("reset", "secret = 7")
        result, _ = self.run_cell("reset", "secret", reset=True)
        self.assertEqual(result["status"], "error")
        self.assertEqual(result["error"]["type"], "NameError")

    def test_stdout_is_bounded(self):
        result, _ = self.run_cell("stdout", "print('x' * 100000)")
        self.assertLessEqual(len(result["stdout"]), 64 * 1024)
        self.assertIn("...truncated...", result["stdout"])

    def test_file_access_outside_workspace_is_rejected(self):
        result, _ = self.run_cell("audit", "open('/etc/passwd').read()")
        self.assertEqual(result["status"], "error")
        self.assertEqual(result["error"]["type"], "PermissionError")

    def test_network_and_subprocess_are_rejected(self):
        network, _ = self.run_cell("network", "import socket\nsocket.socket()")
        process, _ = self.run_cell(
            "process",
            "import subprocess\nsubprocess.run(['/usr/bin/true'])",
        )
        self.assertEqual(network["error"]["type"], "PermissionError")
        self.assertEqual(process["error"]["type"], "PermissionError")

    def test_user_ctypes_dlopen_is_rejected(self):
        result, _ = self.run_cell("ctypes", "import ctypes\nctypes.CDLL(None)")
        self.assertEqual(result["status"], "error")
        self.assertEqual(result["error"]["type"], "PermissionError")

    def test_outputs_are_reported_as_artifacts(self):
        result, root = self.run_cell(
            "artifact",
            "from pathlib import Path\nPath('outputs/chart.txt').write_text('ok')",
        )
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["artifacts"][0]["root"], "outputs")
        self.assertEqual(result["artifacts"][0]["relpath"], "chart.txt")
        self.assertEqual((root / "workspace" / "outputs" / "chart.txt").read_text(), "ok")

    def test_workspace_files_are_reported_without_model_path_compliance(self):
        result, root = self.run_cell(
            "workspace-artifact",
            "from pathlib import Path\nPath('chart.svg').write_text('<svg/>')",
        )
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["artifacts"][0]["root"], "workspace")
        self.assertEqual(result["artifacts"][0]["relpath"], "chart.svg")
        self.assertEqual((root / "workspace" / "chart.svg").read_text(), "<svg/>")


if __name__ == "__main__":
    unittest.main()

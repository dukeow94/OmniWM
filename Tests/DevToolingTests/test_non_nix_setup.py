import hashlib
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class NonNixSetupTests(unittest.TestCase):
    def fixture(self, root):
        scripts = root / "Scripts"
        scripts.mkdir()
        shutil.copy2(ROOT / "Scripts/dev-tools.sh", scripts / "dev-tools.sh")
        tools = root / ".cache/flake-tools/bin"
        tools.mkdir(parents=True)
        for name, output in {
            "swiftformat": "0.64.4",
            "swiftlint": "0.65.1",
            "fish": "fish, version 4.9.3",
            "nu": "0.116.1",
        }.items():
            tool = tools / name
            tool.write_text(f"#!/bin/sh\nprintf '%s\\n' {shlex.quote(output)}\n")
            tool.chmod(0o755)
        system = root / "test-bin"
        system.mkdir()
        for name, body in {
            "nix": "echo unexpected-nix >&2; exit 99",
            "uname": 'case "$1" in -s) echo Darwin ;; -m) echo arm64 ;; esac',
        }.items():
            tool = system / name
            tool.write_text(f"#!/bin/sh\n{body}\n")
            tool.chmod(0o755)
        archive = root / "invalid-download"
        archive.write_bytes(b"not a valid archive")
        pins = {
            "SWIFTFORMAT_VERSION": "0.64.4",
            "SWIFTLINT_VERSION": "0.65.1",
            "FISH_VERSION": "4.9.3",
            "NUSHELL_VERSION": "0.116.1",
        }
        for name, digest_name in [
            ("SWIFTFORMAT", "ZIP"), ("SWIFTLINT", "ZIP"),
            ("FISH", "ZIP"), ("NUSHELL", "TAR"), ("GHOSTTY", "ZIP"),
        ]:
            pins[f"OMNIWM_{name}_DOWNLOAD_URL"] = archive.as_uri()
            pins[f"OMNIWM_{name}_{digest_name}_SHA256"] = "0" * 64
        (scripts / "dev-tools.env").write_text(
            "".join(f"{key}={shlex.quote(value)}\n" for key, value in pins.items())
        )
        return {**os.environ, "PATH": f"{system}:{os.environ['PATH']}"}

    def run_setup(self, root, environment, *arguments):
        return subprocess.run(
            ["/bin/bash", str(root / "Scripts/dev-tools.sh"), *arguments],
            cwd=root, env=environment, capture_output=True, text=True, check=False,
        )

    def test_pinned_tools_are_reused_without_nix_or_downloads(self):
        with tempfile.TemporaryDirectory(prefix="omniwm setup ") as temporary:
            root = Path(temporary)
            environment = self.fixture(root)
            for _ in range(2):
                result = self.run_setup(root, environment, "setup-tools")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(result.stdout.count("(reused)"), 4)
                self.assertNotIn("Downloading", result.stderr)
                self.assertNotIn("unexpected-nix", result.stderr)
            self.assertFalse((root / "Frameworks").exists())

    def test_invalid_existing_framework_is_preserved(self):
        with tempfile.TemporaryDirectory(prefix="omniwm setup ") as temporary:
            root = Path(temporary)
            environment = self.fixture(root)
            framework = root / "Frameworks/GhosttyKit.xcframework"
            framework.mkdir(parents=True)
            sentinel = framework / "local-changes"
            sentinel.write_bytes(b"preserve this framework")
            result = self.run_setup(root, environment)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("it was preserved", result.stderr)
            self.assertEqual(sentinel.read_bytes(), b"preserve this framework")
            self.assertNotIn("Downloading", result.stderr)

    def test_checksum_failure_preserves_existing_tool(self):
        with tempfile.TemporaryDirectory(prefix="omniwm setup ") as temporary:
            root = Path(temporary)
            environment = self.fixture(root)
            tool = root / ".cache/flake-tools/bin/swiftformat"
            tool.write_text("#!/bin/sh\necho wrong-version\n")
            before = tool.read_bytes()
            result = self.run_setup(root, environment, "setup-tools")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("checksum mismatch", result.stderr)
            self.assertEqual(tool.read_bytes(), before)
            self.assertFalse(any((root / ".cache/flake-tools").glob("setup.*")))

    def test_setup_has_no_nix_execution_or_flake_dependency(self):
        source = (ROOT / "Scripts/dev-tools.sh").read_text()
        self.assertNotIn("nix build", source)
        self.assertNotIn("nix develop", source)
        self.assertNotIn("flake.lock", source)
        pins = dict(
            line.split("=", 1) for line in (ROOT / "Scripts/dev-tools.env").read_text().splitlines()
            if line and not line.startswith("#")
        )
        for name, suffix in [("FISH", "ZIP"), ("NUSHELL", "TAR")]:
            digest = pins[f"OMNIWM_{name}_{suffix}_SHA256"]
            self.assertEqual(len(digest), hashlib.sha256().digest_size * 2)
            self.assertEqual(len(bytes.fromhex(digest)), 32)

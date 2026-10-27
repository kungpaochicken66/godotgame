"""Negative handoff checks; these do not stand in for real Godot validation."""
import contextlib
import io
from pathlib import Path
import tempfile
import unittest

import model_handoff as handoff


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "repo"
        (self.source / "game").mkdir(parents=True)
        (self.source / "game/item.glb").write_bytes(b"test bytes, not a real GLB")
        self.files = self.root / "files.txt"
        self.files.write_text("game/item.glb\n")
        self.candidate = self.root / "candidate"

    def seal(self):
        with contextlib.redirect_stdout(io.StringIO()):
            handoff.seal(self.source, self.candidate, self.files, "test-base")
        return handoff.digest(self.candidate / "manifest.json")

    def test_copy_is_independent_and_source_changes_do_not_change_candidate(self):
        identity = self.seal()
        (self.source / "game/item.glb").write_bytes(b"new producer revision")
        self.assertEqual(handoff.verify(self.candidate, identity)[1], identity)

    def test_corrupted_content_is_rejected(self):
        identity = self.seal()
        (self.candidate / "source/game/item.glb").write_bytes(b"corrupt")
        with self.assertRaises(ValueError):
            handoff.verify(self.candidate, identity)

    def test_wrong_manifest_id_is_rejected(self):
        self.seal()
        with self.assertRaises(ValueError):
            handoff.verify(self.candidate, "0" * 64)

    def test_extra_and_missing_files_are_rejected(self):
        identity = self.seal()
        extra = self.candidate / "source/extra.txt"
        extra.write_text("extra")
        with self.assertRaises(ValueError):
            handoff.verify(self.candidate, identity)
        extra.unlink()
        (self.candidate / "source/game/item.glb").unlink()
        with self.assertRaises(ValueError):
            handoff.verify(self.candidate, identity)

    def test_symlink_input_is_rejected(self):
        path = self.source / "game/item.glb"
        path.unlink()
        path.symlink_to(self.files)
        with self.assertRaises(ValueError):
            self.seal()

    def test_traversal_private_paths_and_absolute_paths_are_rejected(self):
        for name in ("../outside", "/tmp/outside", ".git/config", ".env", "keys/private.pem", "a/.aws/config"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                handoff.relative(name)

    def test_existing_candidate_is_not_overwritten(self):
        self.seal()
        with self.assertRaises(FileExistsError):
            self.seal()

    def test_permission_changes_are_rejected(self):
        identity = self.seal()
        path = self.candidate / "source/game/item.glb"
        path.chmod(path.stat().st_mode ^ 0o100)
        with self.assertRaises(ValueError):
            handoff.verify(self.candidate, identity)

    def test_success_text_cannot_hide_engine_errors(self):
        self.assertFalse(handoff.stage_passed(0, "TOUR PASS: 0 failures\nERROR: resource leak", "TOUR PASS: 0 failures"))
        self.assertFalse(handoff.stage_passed(0, "SCRIPT ERROR: broken script", None))

    def test_success_marker_and_exit_code_are_both_required(self):
        self.assertFalse(handoff.stage_passed(0, "started", "TOUR PASS: 0 failures"))
        self.assertFalse(handoff.stage_passed(1, "TOUR PASS: 0 failures", "TOUR PASS: 0 failures"))


if __name__ == "__main__":
    unittest.main()

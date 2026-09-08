import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import sync_catalog as sync


def fixture():
    return {"extension": True, "models": [
        {"slug": "gpt-5.6-sol", "priority": 2, "visibility": "list", "custom": "keep"},
        {"slug": "CPA/old", "priority": 1000, "base_instructions": "old identity",
         "model_messages": {"instructions_template": "old identity"}, "visibility": "list"}]}


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.old = fixture()
        self.bundled = {"models": [{"slug": "gpt-6-astra", "priority": 1,
                                   "base_instructions": "native Astra", "visibility": "list"}]}

    def test_new_native_metadata_and_priority(self):
        result = sync.merge_catalog(self.old, self.bundled, ["gpt-6-astra", "CPA/new"])
        self.assertEqual(result["models"][0]["slug"], "gpt-6-astra")
        self.assertEqual(result["models"][0]["base_instructions"], "native Astra")

    def test_preserve_missing_and_unknown_fields(self):
        result = sync.merge_catalog(self.old, self.bundled, ["gpt-6-astra"])
        self.assertIn("CPA/old", sync.model_map(result))
        self.assertEqual(sync.model_map(result)["gpt-5.6-sol"]["custom"], "keep")
        self.assertTrue(result["extension"])
        self.assertEqual(self.old, fixture())

    def test_policy_and_generic_metadata(self):
        result = sync.merge_catalog(self.old, self.bundled, ["CPA/new", "gpt-reserve"])
        for row in result["models"]:
            self.assertEqual(row["context_window"], 526316)
            self.assertEqual(row["effective_context_window_percent"], 95)
            self.assertEqual(row["auto_compact_token_limit"], 450000)
        new = sync.model_map(result)["CPA/new"]
        self.assertNotIn("old identity", new["base_instructions"])
        self.assertNotIn("model_messages", new)
        self.assertEqual(sync.model_map(result)["gpt-reserve"]["visibility"], "hide")

    def test_idempotent(self):
        first = sync.merge_catalog(self.old, self.bundled, ["gpt-6-astra", "CPA/new"])
        self.assertEqual(first, sync.merge_catalog(first, self.bundled, ["gpt-6-astra", "CPA/new"]))

    def test_bad_upstream_rejected(self):
        for document in [{}, {"data": []}, {"data": [{"id": "gpt-6-astra"}]},
                         {"data": [{"id": "CPA/x"}]}, {"data": [{"id": "bad\n"}]}]:
            with self.assertRaises(ValueError):
                sync.advertised_ids(document)

    def test_duplicate_ids_deduplicated(self):
        ids = sync.advertised_ids({"data": [{"id": i} for i in ["gpt-x", "CPA/y", "gpt-x"]]})
        self.assertEqual(ids, ["gpt-x", "CPA/y"])

    def test_invalid_catalog_rejected(self):
        for document in [{}, {"models": []}, {"models": [{"slug": "a"}, {"slug": "a"}]}]:
            with self.assertRaises(ValueError):
                sync.model_map(document)

    def test_publish_backup_atomic_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "catalog.json"
            original = json.dumps(self.old).encode()
            target.write_bytes(original)
            candidate = sync.merge_catalog(self.old, self.bundled, ["gpt-6-astra"])
            with patch.object(sync, "run_json", return_value=candidate):
                self.assertEqual(sync.publish(target, original, candidate, "codex"), "updated")
            backups = list((Path(directory) / "backups/auto-model-catalog").glob("*.json"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), original)
            self.assertEqual(sync.publish(target, target.read_bytes(), candidate, "codex"), "unchanged")

    def test_failed_validation_keeps_original(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "catalog.json"
            original = json.dumps(self.old).encode()
            target.write_bytes(original)
            candidate = sync.merge_catalog(self.old, self.bundled, ["gpt-6-astra"])
            with patch.object(sync, "run_json", side_effect=ValueError("bad schema")):
                with self.assertRaises(ValueError):
                    sync.publish(target, original, candidate, "codex")
            self.assertEqual(target.read_bytes(), original)
            self.assertEqual(list(Path(directory).glob(".catalog-candidate-*")), [])

    def test_concurrent_edit_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "catalog.json"
            original = json.dumps(self.old).encode()
            target.write_bytes(original)
            candidate = sync.merge_catalog(self.old, self.bundled, ["gpt-6-astra"])
            def change(_):
                target.write_bytes(b"external edit")
                return candidate
            with patch.object(sync, "run_json", side_effect=change):
                with self.assertRaises(ValueError):
                    sync.publish(target, original, candidate, "codex")
            self.assertEqual(target.read_bytes(), b"external edit")

    def test_dry_run_does_not_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "catalog.json"
            original = json.dumps(self.old).encode()
            target.write_bytes(original)
            candidate = sync.merge_catalog(self.old, self.bundled, ["gpt-6-astra"])
            with patch.object(sync, "run_json", return_value=candidate):
                self.assertEqual(sync.publish(target, original, candidate, "codex", True), "update-available")
            self.assertEqual(target.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()

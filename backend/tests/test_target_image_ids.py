import json
import tempfile
import unittest
from pathlib import Path

import yaml

import content_db
import admin_panel
from package_builder import build_tour_json, copy_referenced_targets, target_image_ids


class TargetImageIdsTests(unittest.TestCase):
    def test_builder_keeps_primary_and_adds_ordered_unique_targets(self):
        nugget = {
            "targetImageId": "primary",
            "targetImageIds": ["left", "primary", "right", "left"],
        }
        self.assertEqual(target_image_ids(nugget), ["primary", "left", "right"])

        doc = {
            "monument": {"id": "test", "name": {"en": "Test"}, "languages": ["en"]},
            "checkpoints": [{
                "id": "cp", "name": {"en": "CP"}, "nuggets": [{
                    "id": "n", "title": {"en": "N"}, "text": {"en": "Text"}, **nugget,
                }],
            }],
        }
        output = build_tour_json(doc)["checkpoints"][0]["nuggets"][0]
        self.assertEqual(output["targetImageId"], "primary")
        self.assertEqual(output["targetImageIds"], ["primary", "left", "right"])
        with self.assertRaises(ValueError):
            target_image_ids({"id": "unsafe", "targetImageId": "../escape"})

    def test_database_round_trip_preserves_alternate_targets(self):
        original_db_path = content_db.DB_PATH
        with tempfile.TemporaryDirectory() as temporary:
            content_db.DB_PATH = str(Path(temporary) / "tour.db")
            source = Path(temporary) / "source.yaml"
            exported = Path(temporary) / "exported.yaml"
            source.write_text(yaml.safe_dump({
                "monument": {
                    "id": "test", "name": {"en": "Test", "hi": ""},
                    "languages": ["en", "hi"], "overview": {"en": "", "hi": ""},
                },
                "checkpoints": [{
                    "id": "cp", "name": {"en": "CP", "hi": ""},
                    "intro": {"en": "", "hi": ""},
                    "nuggets": [{
                        "id": "n", "title": {"en": "N", "hi": ""},
                        "text": {"en": "Text", "hi": ""},
                        "targetImageId": "primary", "targetImageIds": ["left", "right"],
                    }],
                }],
            }, sort_keys=False), encoding="utf-8")

            content_db.import_yaml(str(source)).close()
            content_db.export_yaml(str(exported), "test")
            nugget = yaml.safe_load(exported.read_text(encoding="utf-8"))["checkpoints"][0]["nuggets"][0]
            self.assertEqual(nugget["targetImageId"], "primary")
            self.assertEqual(nugget["targetImageIds"], ["left", "right"])
        content_db.DB_PATH = original_db_path

    def test_missing_referenced_target_fails_the_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "targets"
            destination = root / "package" / "targets"
            source.mkdir()
            destination.mkdir(parents=True)
            (source / "present.jpg").write_bytes(b"jpeg")
            with self.assertRaisesRegex(FileNotFoundError, "missing.jpg"):
                copy_referenced_targets({"present.jpg", "missing.jpg"}, source, destination)

    def test_legacy_admin_update_preserves_alternate_targets(self):
        original_db_path = content_db.DB_PATH
        with tempfile.TemporaryDirectory() as temporary:
            content_db.DB_PATH = str(Path(temporary) / "tour.db")
            con = content_db.connect()
            with con:
                con.execute("INSERT INTO monuments(id,name_en) VALUES('m','M')")
                con.execute("INSERT INTO checkpoints(id,monument_id,name_en) VALUES('cp','m','CP')")
                con.execute(
                    "INSERT INTO nuggets(id,checkpoint_id,title_en,text_en,target_image_id,"
                    "target_image_ids_json) VALUES(?,?,?,?,?,?)",
                    ("n", "cp", "Old", "Text", "primary", '["left", "right"]'),
                )
            admin_panel.upsert_nugget(admin_panel.NuggetIn(
                id="n", checkpoint_id="cp", title_en="New", text_en="Text",
                target_image_id="primary",
            ))
            row = content_db.connect().execute(
                "SELECT title_en,target_image_ids_json FROM nuggets WHERE id='n'"
            ).fetchone()
            self.assertEqual(row["title_en"], "New")
            self.assertEqual(json.loads(row["target_image_ids_json"]), ["left", "right"])
        content_db.DB_PATH = original_db_path


if __name__ == "__main__":
    unittest.main()

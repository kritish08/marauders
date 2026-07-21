#!/usr/bin/env python3
"""SQLite content store — the authoritative DB behind the admin panel.

Design contract (do not violate):
- The DB is authoritative for EDITS. The YAML remains the interchange format:
  DB --export--> content/<monument>.yaml --package_builder--> tour.json/zip.
  Every already-verified component (builder, /ask grounding, /admin/rebuild)
  keeps reading YAML and stays UNTOUCHED.
- Schema evolution rule: ADD columns, never rename/remove. schema_version row
  tracks the current shape (v1 mirrors the frozen tour.json document shape).
- All writes are idempotent upserts keyed on stable ids.
- Every localized field is stored as one column per language (name_en,
  name_hi, name_fr, name_es, ...). Adding a language = append it to DB_LANGS,
  add its per-field ALTERs to MIGRATIONS. en/hi are the originals and are
  always emitted; other languages are emitted only when non-empty.

CLI:
  python content_db.py --import content/taj_mahal.yaml   # one-time seed
  python content_db.py --export content/taj_mahal.yaml   # DB -> YAML
DB path: $CONTENT_DB (default content/tour.db; on App Service use
/home/site/wwwroot/content/tour.db — /home is persistent storage).
"""
import argparse
import json
import os
import sqlite3
from pathlib import Path

import yaml

DB_PATH = os.getenv("CONTENT_DB", str(Path(__file__).parent / "content" / "tour.db"))

# Languages carried as first-class per-field columns. en/hi are the originals;
# fr/es were added in S6 Phase B (additive columns + MIGRATIONS below).
DB_LANGS = ["en", "hi", "fr", "es"]

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT OR IGNORE INTO meta VALUES ('schema_version', '1');

CREATE TABLE IF NOT EXISTS monuments (
  id TEXT PRIMARY KEY, name_en TEXT NOT NULL, name_hi TEXT NOT NULL DEFAULT '',
  name_fr TEXT NOT NULL DEFAULT '', name_es TEXT NOT NULL DEFAULT '',
  overview_en TEXT NOT NULL DEFAULT '', overview_hi TEXT NOT NULL DEFAULT '',
  overview_fr TEXT NOT NULL DEFAULT '', overview_es TEXT NOT NULL DEFAULT '',
  languages TEXT NOT NULL DEFAULT 'en,hi', ambient_track TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS checkpoints (
  id TEXT PRIMARY KEY, monument_id TEXT NOT NULL REFERENCES monuments(id),
  name_en TEXT NOT NULL, name_hi TEXT NOT NULL DEFAULT '',
  name_fr TEXT NOT NULL DEFAULT '', name_es TEXT NOT NULL DEFAULT '',
  intro_en TEXT NOT NULL DEFAULT '', intro_hi TEXT NOT NULL DEFAULT '',
  intro_fr TEXT NOT NULL DEFAULT '', intro_es TEXT NOT NULL DEFAULT '',
  map_x REAL NOT NULL DEFAULT 0.5, map_y REAL NOT NULL DEFAULT 0.5,
  venue INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0,
  aicontext_json TEXT NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS nuggets (
  id TEXT PRIMARY KEY, checkpoint_id TEXT NOT NULL REFERENCES checkpoints(id),
  title_en TEXT NOT NULL, title_hi TEXT NOT NULL DEFAULT '',
  title_fr TEXT NOT NULL DEFAULT '', title_es TEXT NOT NULL DEFAULT '',
  text_en TEXT NOT NULL, text_hi TEXT NOT NULL DEFAULT '',
  text_fr TEXT NOT NULL DEFAULT '', text_es TEXT NOT NULL DEFAULT '',
  target_image_id TEXT NOT NULL DEFAULT '', exclusive INTEGER NOT NULL DEFAULT 0,
  position INTEGER NOT NULL DEFAULT 0, images_json TEXT NOT NULL DEFAULT '[]',
  target_width_m REAL, target_image_ids_json TEXT NOT NULL DEFAULT '[]'
);
"""


# Additive migrations only (schema rule: add, never rename/remove). Each runs
# once against an existing DB; the ALTER throws "duplicate column" on DBs that
# already have it, which is caught below.
MIGRATIONS = [
    "ALTER TABLE checkpoints ADD COLUMN lat REAL",        # real-world GPS (optional)
    "ALTER TABLE checkpoints ADD COLUMN lng REAL",
    "ALTER TABLE checkpoints ADD COLUMN radius_m INTEGER NOT NULL DEFAULT 40",
    "ALTER TABLE monuments ADD COLUMN ambient_track TEXT NOT NULL DEFAULT ''",  # admin-settable bg music
    # S6 Phase B: French + Spanish per-field columns (additive).
    "ALTER TABLE monuments ADD COLUMN name_fr TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE monuments ADD COLUMN name_es TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE monuments ADD COLUMN overview_fr TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE monuments ADD COLUMN overview_es TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE checkpoints ADD COLUMN name_fr TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE checkpoints ADD COLUMN name_es TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE checkpoints ADD COLUMN intro_fr TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE checkpoints ADD COLUMN intro_es TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE nuggets ADD COLUMN title_fr TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE nuggets ADD COLUMN title_es TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE nuggets ADD COLUMN text_fr TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE nuggets ADD COLUMN text_es TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE nuggets ADD COLUMN images_json TEXT NOT NULL DEFAULT '[]'",
    "ALTER TABLE checkpoints ADD COLUMN aicontext_json TEXT NOT NULL DEFAULT '{}'",
    "ALTER TABLE nuggets ADD COLUMN target_width_m REAL",  # optional AR-target physical width (m)
    "ALTER TABLE nuggets ADD COLUMN target_image_ids_json TEXT NOT NULL DEFAULT '[]'",
]


def connect() -> sqlite3.Connection:
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    con.executescript(SCHEMA)
    for mig in MIGRATIONS:
        try:
            con.execute(mig)
        except sqlite3.OperationalError:
            pass  # column already exists
    return con


def _loc(d, lang):
    return (d or {}).get(lang, "") if isinstance(d, dict) else (d or "")


def _langmap(row, field, langs):
    """Rebuild a {lang: value} map from per-lang columns. en/hi are always
    emitted (originals — the YAML has always carried both). Other languages in
    `langs` are emitted only when their column is non-empty, so [FILL]/
    untranslated fields do not sprout empty fr/es keys."""
    out = {"en": row[f"{field}_en"], "hi": row[f"{field}_hi"]}
    keys = set(row.keys())
    for lg in langs:
        if lg in ("en", "hi"):
            continue
        col = f"{field}_{lg}"
        val = row[col] if col in keys else ""
        if val:
            out[lg] = val
    return out


def import_yaml(path: str):
    """Idempotent seed: upserts everything from a content YAML, all languages."""
    doc = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    m = doc["monument"]
    con = connect()
    with con:
        con.execute(
            "INSERT INTO monuments(id,name_en,name_hi,name_fr,name_es,"
            "overview_en,overview_hi,overview_fr,overview_es,languages,ambient_track) "
            "VALUES(?,?,?,?,?,?,?,?,?,?,?) "
            "ON CONFLICT(id) DO UPDATE SET name_en=excluded.name_en,"
            "name_hi=excluded.name_hi,name_fr=excluded.name_fr,name_es=excluded.name_es,"
            "overview_en=excluded.overview_en,overview_hi=excluded.overview_hi,"
            "overview_fr=excluded.overview_fr,overview_es=excluded.overview_es,"
            "languages=excluded.languages,ambient_track=excluded.ambient_track",
            (m["id"], _loc(m["name"], "en"), _loc(m["name"], "hi"),
             _loc(m["name"], "fr"), _loc(m["name"], "es"),
             _loc(m.get("overview"), "en"), _loc(m.get("overview"), "hi"),
             _loc(m.get("overview"), "fr"), _loc(m.get("overview"), "es"),
             ",".join(m.get("languages", ["en", "hi"])), m.get("ambientTrack", "")),
        )
        pos = 0
        for venue, key in ((0, "checkpoints"), (1, "venue_checkpoints")):
            for c in doc.get(key) or []:
                gps = c.get("gps") or {}
                con.execute(
                    "INSERT INTO checkpoints(id,monument_id,name_en,name_hi,name_fr,name_es,"
                    "intro_en,intro_hi,intro_fr,intro_es,map_x,map_y,venue,position,"
                    "lat,lng,radius_m,aicontext_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
                    "ON CONFLICT(id) DO UPDATE SET name_en=excluded.name_en,"
                    "name_hi=excluded.name_hi,name_fr=excluded.name_fr,name_es=excluded.name_es,"
                    "intro_en=excluded.intro_en,intro_hi=excluded.intro_hi,"
                    "intro_fr=excluded.intro_fr,intro_es=excluded.intro_es,"
                    "map_x=excluded.map_x,map_y=excluded.map_y,venue=excluded.venue,"
                    "position=excluded.position,lat=excluded.lat,lng=excluded.lng,"
                    "radius_m=excluded.radius_m,aicontext_json=excluded.aicontext_json",
                    (c["id"], m["id"], _loc(c["name"], "en"), _loc(c["name"], "hi"),
                     _loc(c["name"], "fr"), _loc(c["name"], "es"),
                     _loc(c.get("intro"), "en"), _loc(c.get("intro"), "hi"),
                     _loc(c.get("intro"), "fr"), _loc(c.get("intro"), "es"),
                     c.get("mapPosition", {}).get("x", 0.5),
                     c.get("mapPosition", {}).get("y", 0.5), venue, pos,
                     gps.get("lat"), gps.get("lng"), gps.get("radius", 40),
                     json.dumps(c.get("aiContext") or {})),
                )
                pos += 1
                for i, n in enumerate(c.get("nuggets") or []):
                    con.execute(
                        "INSERT INTO nuggets(id,checkpoint_id,title_en,title_hi,title_fr,"
                        "title_es,text_en,text_hi,text_fr,text_es,target_image_id,exclusive,"
                        "position,images_json,target_width_m,target_image_ids_json) "
                        "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
                        "ON CONFLICT(id) DO UPDATE SET checkpoint_id=excluded.checkpoint_id,"
                        "title_en=excluded.title_en,title_hi=excluded.title_hi,"
                        "title_fr=excluded.title_fr,title_es=excluded.title_es,"
                        "text_en=excluded.text_en,text_hi=excluded.text_hi,"
                        "text_fr=excluded.text_fr,text_es=excluded.text_es,"
                        "target_image_id=excluded.target_image_id,"
                        "exclusive=excluded.exclusive,position=excluded.position,"
                        "images_json=excluded.images_json,target_width_m=excluded.target_width_m,"
                        "target_image_ids_json=excluded.target_image_ids_json",
                        (n["id"], c["id"], _loc(n["title"], "en"), _loc(n["title"], "hi"),
                         _loc(n["title"], "fr"), _loc(n["title"], "es"),
                         _loc(n["text"], "en"), _loc(n["text"], "hi"),
                         _loc(n["text"], "fr"), _loc(n["text"], "es"),
                         n.get("targetImageId", ""), int(bool(n.get("exclusive"))), i,
                         json.dumps(n.get("images") or []), n.get("target_width_m"),
                         json.dumps(n.get("targetImageIds") or [])),
                    )
    return con


def export_yaml(path: str, monument_id: str | None = None):
    """DB -> YAML in the exact shape package_builder.py consumes.

    Scoped to ONE monument: checkpoints are filtered by monument_id so multiple
    properties in the DB never bleed into one YAML. monument_id defaults to the
    first monument row (preserves the original single-property behavior)."""
    con = connect()
    if monument_id:
        m = con.execute(
            "SELECT * FROM monuments WHERE id=?", (monument_id,)
        ).fetchone()
    else:
        m = con.execute("SELECT * FROM monuments ORDER BY rowid LIMIT 1").fetchone()
    if not m:
        raise SystemExit("DB is empty — run --import first")
    langs = [l for l in m["languages"].split(",") if l]
    mon = {
        "id": m["id"],
        "name": _langmap(m, "name", langs),
        "languages": langs,
        "overview": _langmap(m, "overview", langs),
    }
    if m["ambient_track"]:
        mon["ambientTrack"] = m["ambient_track"]
    doc = {"monument": mon, "checkpoints": [], "venue_checkpoints": []}
    for c in con.execute(
        "SELECT * FROM checkpoints WHERE monument_id=? ORDER BY position", (m["id"],)
    ):
        cp = {
            "id": c["id"],
            "name": _langmap(c, "name", langs),
            "mapPosition": {"x": c["map_x"], "y": c["map_y"]},
            "intro": _langmap(c, "intro", langs),
        }
        if c["lat"] is not None and c["lng"] is not None:
            cp["gps"] = {"lat": c["lat"], "lng": c["lng"], "radius": c["radius_m"]}
        if "aicontext_json" in c.keys():
            ai = json.loads(c["aicontext_json"] or "{}")
            if ai:
                cp["aiContext"] = ai
        cp["nuggets"] = []
        for n in con.execute(
            "SELECT * FROM nuggets WHERE checkpoint_id=? ORDER BY position",
            (c["id"],),
        ):
            nug = {
                "id": n["id"],
                "title": _langmap(n, "title", langs),
                "targetImageId": n["target_image_id"],
                "targetImageIds": json.loads(n["target_image_ids_json"] or "[]")
                if "target_image_ids_json" in n.keys()
                else [],
                "exclusive": bool(n["exclusive"]),
                "images": json.loads(n["images_json"] or "[]")
                if ("images_json" in n.keys())
                else [],
                "text": _langmap(n, "text", langs),
            }
            tw = n["target_width_m"] if "target_width_m" in n.keys() else None
            if tw is not None:
                nug["target_width_m"] = tw
            cp["nuggets"].append(nug)
        doc["venue_checkpoints" if c["venue"] else "checkpoints"].append(cp)
    Path(path).write_text(
        yaml.safe_dump(doc, allow_unicode=True, sort_keys=False), encoding="utf-8"
    )
    return path


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--import", dest="imp", metavar="YAML")
    g.add_argument("--export", dest="exp", metavar="YAML")
    ap.add_argument("--monument", default=None, help="monument id for --export scoping")
    a = ap.parse_args()
    if a.imp:
        import_yaml(a.imp)
        print(f"[ok] imported {a.imp} -> {DB_PATH}")
    else:
        export_yaml(a.exp, a.monument)
        print(f"[ok] exported {DB_PATH} -> {a.exp}")

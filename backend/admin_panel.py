"""Admin panel router — SQLite-backed CRUD for nuggets & checkpoints.

Integration (ONE line in ask_service.py, do not modify anything else):
    from admin_panel import admin_router
    app.include_router(admin_router)

Flow per edit session: CRUD via this panel (writes SQLite, transactional,
idempotent) -> POST /admin/export (DB -> content YAML) -> existing
POST /admin/rebuild (YAML -> tour.json + audio + zip). The verified builder
chain is untouched.
"""
import io
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile
from fastapi.responses import HTMLResponse
from PIL import Image
from pydantic import BaseModel

import content_db

ROOT = Path(__file__).parent
CONTENT_YAML = os.getenv("CONTENT_YAML", str(ROOT / "content" / "taj_mahal.yaml"))

admin_router = APIRouter(prefix="/admin")


def _auth(x_app_key: str | None = Header(default=None, alias="X-App-Key")):
    key = os.getenv("APP_KEY", "")
    if key and x_app_key != key:
        raise HTTPException(401, "missing or invalid X-App-Key")


def _valid_id(v: str) -> bool:
    """Guard ids used to build filesystem paths (monument/nugget) — blocks path
    traversal. Ids in this project are lowercase-alnum + underscore."""
    return bool(re.fullmatch(r"[a-z0-9_]+", v or ""))


class NuggetIn(BaseModel):
    id: str
    checkpoint_id: str
    title_en: str
    title_hi: str = ""
    title_fr: str = ""
    title_es: str = ""
    text_en: str
    text_hi: str = ""
    text_fr: str = ""
    text_es: str = ""
    target_image_id: str = ""
    target_image_ids: list[str] | None = None
    exclusive: bool = False
    position: int = 0


class CheckpointIn(BaseModel):
    id: str
    name_en: str
    name_hi: str = ""
    name_fr: str = ""
    name_es: str = ""
    intro_en: str = ""
    intro_hi: str = ""
    intro_fr: str = ""
    intro_es: str = ""
    map_x: float = 0.5
    map_y: float = 0.5
    venue: bool = False
    position: int = 0
    lat: float | None = None       # real-world GPS, optional (outdoor monuments)
    lng: float | None = None
    radius_m: int = 40             # geofence radius, metres
    monument_id: str | None = None  # optional: place checkpoint under a chosen property


class MonumentIn(BaseModel):
    id: str
    name_en: str
    name_hi: str = ""
    name_fr: str = ""
    name_es: str = ""
    overview_en: str = ""
    overview_hi: str = ""
    overview_fr: str = ""
    overview_es: str = ""
    languages: str = "en,hi,fr,es"


@admin_router.get("", response_class=HTMLResponse)
def admin_page():
    return (ROOT / "admin.html").read_text(encoding="utf-8")


@admin_router.get("/verify", dependencies=[Depends(_auth)])
def verify_key():
    """Login gate: the panel calls this to validate the key before entering."""
    return {"ok": True}


@admin_router.get("/monuments", dependencies=[Depends(_auth)])
def list_monuments():
    con = content_db.connect()
    out = []
    for r in con.execute(
        "SELECT id,name_en,name_hi,name_fr,name_es,languages FROM monuments ORDER BY rowid"
    ):
        m = dict(r)
        m["checkpoint_count"] = con.execute(
            "SELECT COUNT(*) FROM checkpoints WHERE monument_id=?", (m["id"],)
        ).fetchone()[0]
        out.append(m)
    return out


@admin_router.post("/monuments", dependencies=[Depends(_auth)])
def upsert_monument(m: MonumentIn):
    con = content_db.connect()
    with con:
        con.execute(
            "INSERT INTO monuments(id,name_en,name_hi,name_fr,name_es,"
            "overview_en,overview_hi,overview_fr,overview_es,languages) "
            "VALUES(?,?,?,?,?,?,?,?,?,?) "
            "ON CONFLICT(id) DO UPDATE SET name_en=excluded.name_en,"
            "name_hi=excluded.name_hi,name_fr=excluded.name_fr,name_es=excluded.name_es,"
            "overview_en=excluded.overview_en,overview_hi=excluded.overview_hi,"
            "overview_fr=excluded.overview_fr,overview_es=excluded.overview_es,"
            "languages=excluded.languages",
            (m.id, m.name_en, m.name_hi, m.name_fr, m.name_es,
             m.overview_en, m.overview_hi, m.overview_fr, m.overview_es, m.languages),
        )
    return {"ok": True, "id": m.id, "op": "upsert"}


@admin_router.get("/content", dependencies=[Depends(_auth)])
def get_content(monument: str | None = None):
    con = content_db.connect()
    schema_version = con.execute(
        "SELECT value FROM meta WHERE key='schema_version'"
    ).fetchone()[0]
    if monument is not None:
        checkpoints = [dict(r) for r in con.execute(
            "SELECT * FROM checkpoints WHERE monument_id=? ORDER BY venue, position",
            (monument,))]
        nuggets = [dict(r) for r in con.execute(
            "SELECT * FROM nuggets WHERE checkpoint_id IN "
            "(SELECT id FROM checkpoints WHERE monument_id=?) "
            "ORDER BY checkpoint_id, position",
            (monument,))]
    else:
        checkpoints = [dict(r) for r in con.execute(
            "SELECT * FROM checkpoints ORDER BY venue, position")]
        nuggets = [dict(r) for r in con.execute(
            "SELECT * FROM nuggets ORDER BY checkpoint_id, position")]
    return {
        "schema_version": schema_version,
        "monument": monument,
        "checkpoints": checkpoints,
        "nuggets": nuggets,
    }


@admin_router.post("/checkpoints", dependencies=[Depends(_auth)])
def upsert_checkpoint(c: CheckpointIn):
    con = content_db.connect()
    if c.monument_id:
        mid = c.monument_id
    else:
        mid_row = con.execute("SELECT id FROM monuments").fetchone()
        if not mid_row:
            raise HTTPException(409, "DB empty — run: python content_db.py --import <yaml>")
        mid = mid_row[0]
    with con:
        con.execute(
            "INSERT INTO checkpoints(id,monument_id,name_en,name_hi,name_fr,name_es,"
            "intro_en,intro_hi,intro_fr,intro_es,"
            "map_x,map_y,venue,position,lat,lng,radius_m) "
            "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
            "ON CONFLICT(id) DO UPDATE SET name_en=excluded.name_en,name_hi=excluded.name_hi,"
            "name_fr=excluded.name_fr,name_es=excluded.name_es,"
            "intro_en=excluded.intro_en,intro_hi=excluded.intro_hi,"
            "intro_fr=excluded.intro_fr,intro_es=excluded.intro_es,map_x=excluded.map_x,"
            "map_y=excluded.map_y,venue=excluded.venue,position=excluded.position,"
            "lat=excluded.lat,lng=excluded.lng,radius_m=excluded.radius_m",
            (c.id, mid, c.name_en, c.name_hi, c.name_fr, c.name_es,
             c.intro_en, c.intro_hi, c.intro_fr, c.intro_es,
             c.map_x, c.map_y, int(c.venue), c.position, c.lat, c.lng, c.radius_m),
        )
    return {"ok": True, "id": c.id, "op": "upsert"}


@admin_router.post("/nuggets", dependencies=[Depends(_auth)])
def upsert_nugget(n: NuggetIn):
    con = content_db.connect()
    if not con.execute("SELECT 1 FROM checkpoints WHERE id=?", (n.checkpoint_id,)).fetchone():
        raise HTTPException(404, f"unknown checkpoint {n.checkpoint_id}")
    if n.target_image_id and not _valid_id(n.target_image_id):
        raise HTTPException(400, "bad target image id")
    if n.target_image_ids is not None and any(not _valid_id(value) for value in n.target_image_ids):
        raise HTTPException(400, "bad alternate target image id")
    existing = con.execute(
        "SELECT target_image_ids_json FROM nuggets WHERE id=?", (n.id,)
    ).fetchone()
    target_image_ids = (
        n.target_image_ids
        if n.target_image_ids is not None
        else json.loads(existing["target_image_ids_json"] or "[]") if existing else []
    )
    with con:
        con.execute(
            "INSERT INTO nuggets(id,checkpoint_id,title_en,title_hi,title_fr,title_es,"
            "text_en,text_hi,text_fr,text_es,"
            "target_image_id,target_image_ids_json,exclusive,position) "
            "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
            "ON CONFLICT(id) DO UPDATE SET checkpoint_id=excluded.checkpoint_id,"
            "title_en=excluded.title_en,title_hi=excluded.title_hi,"
            "title_fr=excluded.title_fr,title_es=excluded.title_es,text_en=excluded.text_en,"
            "text_hi=excluded.text_hi,text_fr=excluded.text_fr,text_es=excluded.text_es,"
            "target_image_id=excluded.target_image_id,"
            "target_image_ids_json=excluded.target_image_ids_json,"
            "exclusive=excluded.exclusive,position=excluded.position",
            (n.id, n.checkpoint_id, n.title_en, n.title_hi, n.title_fr, n.title_es,
             n.text_en, n.text_hi, n.text_fr, n.text_es,
             n.target_image_id, json.dumps(target_image_ids), int(n.exclusive), n.position),
        )
    return {"ok": True, "id": n.id, "op": "upsert"}


@admin_router.delete("/nuggets/{nugget_id}", dependencies=[Depends(_auth)])
def delete_nugget(nugget_id: str):
    con = content_db.connect()
    with con:
        cur = con.execute("DELETE FROM nuggets WHERE id=?", (nugget_id,))
    if cur.rowcount == 0:
        raise HTTPException(404, f"unknown nugget {nugget_id}")
    return {"ok": True, "id": nugget_id, "op": "delete"}


@admin_router.delete("/checkpoints/{checkpoint_id}", dependencies=[Depends(_auth)])
def delete_checkpoint(checkpoint_id: str):
    con = content_db.connect()
    with con:
        con.execute("DELETE FROM nuggets WHERE checkpoint_id=?", (checkpoint_id,))
        cur = con.execute("DELETE FROM checkpoints WHERE id=?", (checkpoint_id,))
    if cur.rowcount == 0:
        raise HTTPException(404, f"unknown checkpoint {checkpoint_id}")
    return {"ok": True, "id": checkpoint_id, "op": "delete (with nuggets)"}


@admin_router.post("/export", dependencies=[Depends(_auth)])
def export_to_yaml(monument: str | None = None):
    """DB -> content YAML, scoped to one monument. Then call POST /admin/rebuild.

    monument omitted = the primary property (content/taj_mahal.yaml, byte-identical
    to before). A non-primary property (e.g. red_fort) exports to
    content/<id>.yaml so it can be published on its own."""
    if monument:
        if not _valid_id(monument):
            raise HTTPException(400, "bad monument id")
        path = str(ROOT / "content" / f"{monument}.yaml")
        content_db.export_yaml(path, monument)
    else:
        path = content_db.export_yaml(CONTENT_YAML)
    return {"ok": True, "yaml": path, "next": "POST /admin/rebuild to regenerate package"}


@admin_router.post("/nuggets/{nugget_id}/images", dependencies=[Depends(_auth)])
def upload_nugget_image(nugget_id: str, file: UploadFile = File(...)):
    """Accept an image, convert to WebP, store on disk, and record its
    in-package path (images/<nugget_id>_<n>.webp) on the nugget. Max 3."""
    if not _valid_id(nugget_id):
        raise HTTPException(400, "bad nugget id")
    con = content_db.connect()
    row = con.execute("SELECT images_json FROM nuggets WHERE id=?", (nugget_id,)).fetchone()
    if not row:
        raise HTTPException(404, f"unknown nugget {nugget_id}")
    imgs = json.loads(row["images_json"] or "[]")
    if len(imgs) >= 3:
        raise HTTPException(400, "max 3 images")
    data = file.file.read()
    if len(data) > 20 * 1024 * 1024:  # cap raw upload before Pillow decodes it
        raise HTTPException(400, "image too large (max 20MB)")
    try:
        im = Image.open(io.BytesIO(data))
        im = im.convert("RGB")
        im.thumbnail((1600, 1600))
    except Exception:
        raise HTTPException(400, "not a valid image")
    # Suffix from the max existing index + 1, NOT len(imgs): after a delete
    # (which does not renumber) len() could collide with a surviving file.
    used = [int(m.group(1)) for p in imgs
            if (m := re.search(rf"{re.escape(nugget_id)}_(\d+)\.webp$", p))]
    n = (max(used) + 1) if used else 0
    out = ROOT / "nugget_images" / f"{nugget_id}_{n}.webp"
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out, "WEBP", quality=82)
    imgs.append(f"images/{nugget_id}_{n}.webp")
    with con:
        con.execute("UPDATE nuggets SET images_json=? WHERE id=?", (json.dumps(imgs), nugget_id))
    return {"ok": True, "id": nugget_id, "images": imgs}


@admin_router.delete("/nuggets/{nugget_id}/images/{idx}", dependencies=[Depends(_auth)])
def delete_nugget_image(nugget_id: str, idx: int):
    """Remove the image at index idx from the nugget. Best-effort unlink of the
    on-disk WebP; remaining paths are left as-is (not renumbered)."""
    if not _valid_id(nugget_id):
        raise HTTPException(400, "bad nugget id")
    con = content_db.connect()
    row = con.execute("SELECT images_json FROM nuggets WHERE id=?", (nugget_id,)).fetchone()
    if not row:
        raise HTTPException(404, f"unknown nugget {nugget_id}")
    imgs = json.loads(row["images_json"] or "[]")
    if idx < 0 or idx >= len(imgs):
        raise HTTPException(404, "image index out of range")
    on_disk = ROOT / "nugget_images" / Path(imgs[idx]).name
    try:
        on_disk.unlink()
    except OSError:
        pass
    imgs.pop(idx)
    with con:
        con.execute("UPDATE nuggets SET images_json=? WHERE id=?", (json.dumps(imgs), nugget_id))
    return {"ok": True, "images": imgs}


@admin_router.post("/translate", dependencies=[Depends(_auth)])
def translate_missing(monument: str | None = None, force: bool = False):
    """Idempotent en -> fr/es backfill for monument/checkpoint/nugget copy.

    Scope: a single monument (with its checkpoints + nuggets) when `monument`
    is given, else every row. Never touches hi (human-authored) or en (source);
    skips en that is empty or a [FILL placeholder. force=False fills only EMPTY
    fr/es targets (safe to re-run); force=True re-translates fr/es from the
    current en. Per-field failures are counted, not fatal."""
    # Lazy import: translate_content builds its Azure client at module import,
    # so importing at top would break the whole admin module without keys.
    from translate_content import translate

    if monument is not None and not _valid_id(monument):
        raise HTTPException(400, "bad monument id")

    con = content_db.connect()
    if monument is not None:
        monuments = con.execute(
            "SELECT * FROM monuments WHERE id=?", (monument,)
        ).fetchall()
        checkpoints = con.execute(
            "SELECT * FROM checkpoints WHERE monument_id=?", (monument,)
        ).fetchall()
        nuggets = con.execute(
            "SELECT * FROM nuggets WHERE checkpoint_id IN "
            "(SELECT id FROM checkpoints WHERE monument_id=?)",
            (monument,),
        ).fetchall()
    else:
        monuments = con.execute("SELECT * FROM monuments").fetchall()
        checkpoints = con.execute("SELECT * FROM checkpoints").fetchall()
        nuggets = con.execute("SELECT * FROM nuggets").fetchall()

    # (table, rows, [(en_col, fr_col, es_col), ...]) — column names are fixed
    # literals here, never user input, so f-string interpolation is safe.
    groups = [
        ("monuments", monuments,
         [("name_en", "name_fr", "name_es"),
          ("overview_en", "overview_fr", "overview_es")]),
        ("checkpoints", checkpoints,
         [("name_en", "name_fr", "name_es"),
          ("intro_en", "intro_fr", "intro_es")]),
        ("nuggets", nuggets,
         [("title_en", "title_fr", "title_es"),
          ("text_en", "text_fr", "text_es")]),
    ]

    translated = skipped = failed = 0
    with con:
        for table, rows, fields in groups:
            for row in rows:
                for en_col, fr_col, es_col in fields:
                    en = (row[en_col] or "").strip()
                    if not en or en.startswith("[FILL"):
                        continue
                    for lang, target_col in (("fr", fr_col), ("es", es_col)):
                        current = (row[target_col] or "").strip()
                        if not force and current:
                            skipped += 1
                            continue
                        try:
                            out = translate(row[en_col], lang)
                        except Exception:
                            failed += 1
                            continue
                        con.execute(
                            f"UPDATE {table} SET {target_col}=? WHERE id=?",
                            (out, row["id"]),
                        )
                        translated += 1
    return {"ok": True, "translated": translated, "skipped": skipped, "failed": failed}

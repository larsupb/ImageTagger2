# Image Attributes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-image categorical attributes (shot_type, framing, camera_angle, ...) stored in the dataset SQLite DB, VLM-classified with manual override, exposed via schema/footprint/query/classify endpoints plus UI filtering.

**Architecture:** Attributes reuse the existing dormant `metadata` KV table (`(image_id, key, value)` rows) — zero DB migration. A Python vocabulary module is the single source of truth for values/validation/UI/classifier prompt. Classification reuses `lib.captioning.generate_caption` with a custom prompt through the existing task-service job queue. Spec: `docs/superpowers/specs/2026-10-10-image-attributes-design.md`.

**Tech Stack:** FastAPI + sqlite3 (stdlib), pytest; Next.js 15 / React 19 / TypeScript.

**Repo workflow:** `backend/` and `frontend/` are git submodules. Commit inside the submodule in every task, then bump pointers from the root repo in the final task. Backend tests: `cd backend && source .venv/bin/activate && pytest tests/<file> -v`.

---

## File Structure

Backend submodule (`backend/`):

| File | Action | Responsibility |
|---|---|---|
| `app/attributes.py` | create | Vocabulary dict, validation, classifier prompt, lenient JSON parse — pure functions, no I/O |
| `app/db/repository.py` | modify | Add `AttributeRepository` (set/get/unset/footprint-rows) |
| `app/services/attribute_service.py` | create | put/get, footprint, query, classify job runner |
| `app/routers/attributes.py` | create | `GET /schema`, `GET /footprint`, `GET /query`, `PUT ""`, `POST /classify` |
| `app/main.py` | modify | Mount attributes router (line ~87, after `dedup`) |
| `app/routers/media.py` | modify | `GET /by-id/{id}`, `GET /thumbnail-by-id/{id}` |
| `app/models/schemas.py` | modify | `GalleryItem.attributes`, filter param model untouched (query params on router) |
| `app/routers/dataset.py` | modify | gallery returns per-item attributes, accepts `attributes` filter |
| `tests/test_attributes.py` | create | vocabulary/parse unit tests |
| `tests/test_attribute_db.py` | create | repository + footprint + query tests |
| `tests/test_attributes_api.py` | create | endpoint tests incl. classify with stubbed tagger |

Frontend submodule (`frontend/`):

| File | Action | Responsibility |
|---|---|---|
| `src/lib/types.ts` | modify | Attribute types |
| `src/lib/api.ts` | modify | 5 API calls |
| `src/components/edit/AttributePanel.tsx` | create | Attribute selects in edit view |
| `src/app/edit/page.tsx` | modify | Mount panel |
| `src/components/browse/GalleryGrid.tsx` | modify | Filter dropdowns + badges |

---

### Task 1: Vocabulary module

**Files:**
- Create: `backend/app/attributes.py`
- Test: `backend/tests/test_attributes.py`

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_attributes.py`:

```python
from app.attributes import (
    ATTRIBUTES,
    coerce_value,
    parse_attributes_response,
    validate_attributes,
)


def test_vocabularies_match_spec():
    assert ATTRIBUTES["shot_type"]["applies_to"] == "all"
    assert "selfie" in ATTRIBUTES["shot_type"]["values"]
    assert ATTRIBUTES["camera_angle"]["applies_to"] == "person"
    assert ATTRIBUTES["expression"]["values"] == [
        "neutral", "smile", "laugh", "serious", "surprised", "sad", "angry",
    ]
    assert len(ATTRIBUTES) == 10


def test_coerce_value_normalizes():
    assert coerce_value("shot_type", "Selfie") == "selfie"
    assert coerce_value("framing", "Medium Wide") == "medium_wide"
    assert coerce_value("pose", " Running  Jumping ") == "running_jumping"
    assert coerce_value("shot_type", "cats_and_dogs") is None


def test_validate_attributes():
    valid, errors = validate_attributes(
        {"shot_type": "selfie", "framing": "blurry", "unknown_attr": "x"}
    )
    assert valid == {"shot_type": "selfie"}
    assert errors["framing"] == "blurry"
    assert "unknown_attr" in errors


def test_parse_plain_json():
    parsed, has_person = parse_attributes_response(
        '{"has_person": true, "shot_type": "headshot", "pose": "standing",'
        ' "camera_angle": "low angle"}'
    )
    assert parsed == {
        "shot_type": "headshot", "pose": "standing", "camera_angle": "low_angle",
    }
    assert has_person is True


def test_parse_prose_wrapped_and_junk():
    parsed, has_person = parse_attributes_response(
        'Sure! {"has_person": false, "shot_type": "landscape",'
        ' "pose": "dancing", "medium": "photo"} hope that helps'
    )
    # pose ignored: has_person false -> person-only attributes dropped
    assert parsed == {"shot_type": "landscape", "medium": "photo"}
    assert has_person is False


def test_parse_out_of_vocab_and_no_json():
    parsed, _ = parse_attributes_response(
        '{"has_person": true, "shot_type": "vibes", "framing": "close-up"}'
    )
    assert parsed == {"framing": "close_up"}
    parsed, _ = parse_attributes_response("the image shows a cat")
    assert parsed == {}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && source .venv/bin/activate && pytest tests/test_attributes.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.attributes'`

- [ ] **Step 3: Write the implementation**

Create `backend/app/attributes.py`:

```python
import json
import re

ATTRIBUTES: dict[str, dict] = {
    "shot_type": {
        "applies_to": "all",
        "values": [
            "selfie", "headshot", "upper_body_portrait", "full_body_portrait",
            "environmental_portrait", "lifestyle", "candid_street", "group_shot",
            "couple_shot", "landscape", "aerial", "macro", "architecture",
            "interior", "product", "still_life", "food", "animal",
            "sports_action", "event",
        ],
    },
    "framing": {
        "applies_to": "all",
        "values": [
            "extreme_close_up", "close_up", "medium_close_up", "medium_shot",
            "cowboy_shot", "medium_wide", "full_shot", "wide_shot", "extreme_wide",
        ],
    },
    "camera_angle": {
        "applies_to": "person",
        "values": [
            "eye_level", "low_angle", "high_angle", "birds_eye", "worms_eye",
            "dutch_angle", "pov", "over_the_shoulder",
        ],
    },
    "subject_orientation": {
        "applies_to": "person",
        "values": [
            "frontal_looking_at_camera", "frontal_looking_away", "three_quarter",
            "profile", "back_view",
        ],
    },
    "pose": {
        "applies_to": "person",
        "values": [
            "standing", "walking", "running_jumping", "sitting", "sitting_on_floor",
            "kneeling", "crouching", "lying_reclining", "leaning", "dancing",
        ],
    },
    "medium": {
        "applies_to": "all",
        "values": ["photo", "illustration_anime", "3d_render", "screenshot"],
    },
    "setting": {
        "applies_to": "all",
        "values": [
            "studio_plain", "indoor_home", "indoor_public", "urban_outdoor",
            "nature_outdoor", "beach_water", "snow",
        ],
    },
    "lighting": {
        "applies_to": "all",
        "values": [
            "natural_soft", "direct_sunlight", "golden_hour", "blue_hour",
            "overcast", "window_light", "studio_strobe", "flash", "backlit_rim",
            "night_low_light", "neon",
        ],
    },
    "expression": {
        "applies_to": "person",
        "values": ["neutral", "smile", "laugh", "serious", "surprised", "sad", "angry"],
    },
    "quality_flags": {
        "applies_to": "all",
        "values": ["sharp", "blurry", "watermarked", "text_overlay", "very_low_res"],
    },
}

_ALIASES = {
    ("medium", "close_up"): ["closeup", "close up"],
    ("framing", "close_up"): ["closeup", "close up"],
    ("framing", "extreme_close_up"): ["ecu", "extreme close up"],
    ("framing", "medium_close_up"): ["mcu", "medium close up"],
    ("framing", "medium_shot"): ["ms", "medium shot"],
    ("framing", "medium_wide"): ["medium wide shot", "three quarter shot", "knees up"],
    ("framing", "wide_shot"): ["long shot", "ws"],
    ("framing", "extreme_wide"): ["extreme long shot", "ews"],
    ("camera_angle", "pov"): ["point of view"],
    ("camera_angle", "over_the_shoulder"): ["ots"],
    ("shot_type", "candid_street"): ["candid", "street", "street photography"],
}


def coerce_value(attribute: str, raw: str) -> str | None:
    spec = ATTRIBUTES.get(attribute)
    if spec is None or not isinstance(raw, str):
        return None
    candidate = re.sub(r"[\s\-]+", "_", raw.strip().lower())
    if candidate in spec["values"]:
        return candidate
    for (attr, value), aliases in _ALIASES.items():
        if attr == attribute and candidate in [a.replace(" ", "_") for a in aliases]:
            return value
    return None


def validate_attributes(attributes: dict) -> tuple[dict, dict[str, str]]:
    valid: dict[str, str] = {}
    errors: dict[str, str] = {}
    for key, value in attributes.items():
        if key not in ATTRIBUTES:
            errors[key] = "unknown attribute"
        elif value is None:
            continue
        else:
            coerced = coerce_value(key, value)
            if coerced is None:
                errors[key] = str(value)
            else:
                valid[key] = coerced
    return valid, errors


def build_classify_prompt() -> str:
    all_attrs = [k for k, s in ATTRIBUTES.items() if s["applies_to"] == "all"]
    person_attrs = [k for k, s in ATTRIBUTES.items() if s["applies_to"] == "person"]

    def lines(keys: list[str]) -> str:
        return "\n".join(f"- {k}: one of {', '.join(ATTRIBUTES[k]['values'])}" for k in keys)

    return (
        "You are an image classifier for a photography dataset. Respond with ONLY a"
        " flat JSON object, no markdown, no prose. Keys and allowed values:\n"
        + lines(all_attrs)
        + "\nAlso answer \"has_person\": true if one or more people are visible,"
        " else false. When has_person is false, omit these keys:"
        " " + ", ".join(person_attrs)
        + "\n"
        + lines(person_attrs)
        + "\nOmit any key you cannot determine confidently. Example:"
        ' {"has_person": true, "shot_type": "selfie", "framing": "close_up",'
        ' "camera_angle": "eye_level", "pose": "standing"}'
    )


def parse_attributes_response(raw: str) -> tuple[dict, bool]:
    if not raw:
        return {}, False
    match = re.search(r"\{.*\}", raw, re.DOTALL)
    if not match:
        return {}, False
    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError:
        return {}, False
    if not isinstance(data, dict):
        return {}, False
    has_person = bool(data.get("has_person", False))
    parsed, _ = validate_attributes(
        {
            k: v
            for k, v in data.items()
            if k != "has_person" and (has_person or ATTRIBUTES.get(k, {}).get("applies_to") != "person")
        }
    )
    return parsed, has_person
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && source .venv/bin/activate && pytest tests/test_attributes.py -v`
Expected: 6 PASS

- [ ] **Step 5: Commit (backend submodule)**

```bash
cd backend && git add app/attributes.py tests/test_attributes.py && git commit -m "Add attribute vocabulary, validation and classifier parsing"
```

---

### Task 2: AttributeRepository

**Files:**
- Modify: `backend/app/db/repository.py` (append class at end)
- Test: `backend/tests/test_attribute_db.py` (create)

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_attribute_db.py`:

```python
import pytest

from app.db.connection import create_schema
from app.db.repository import AttributeRepository, ImageRepository
from app.attributes import ATTRIBUTES


@pytest.fixture()
def db(tmp_path):
    import sqlite3

    conn = sqlite3.connect(tmp_path / "test.db")
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    create_schema(conn)
    yield conn
    conn.close()


def _image(db, filename="a.png"):
    return ImageRepository.ensure_image(db, filename)


def test_set_get_unset_roundtrip(db):
    image_id = _image(db)
    AttributeRepository.set(db, image_id, "shot_type", "selfie")
    AttributeRepository.set(db, image_id, "pose", "standing")
    assert AttributeRepository.get_for_image(db, image_id) == {
        "shot_type": "selfie", "pose": "standing",
    }
    AttributeRepository.set(db, image_id, "shot_type", "headshot")
    assert AttributeRepository.get_for_image(db, image_id)["shot_type"] == "headshot"
    AttributeRepository.unset(db, image_id, "shot_type")
    assert AttributeRepository.get_for_image(db, image_id) == {"pose": "standing"}


def test_set_many_replaces_dict(db):
    image_id = _image(db)
    AttributeRepository.set_many(db, image_id, {"shot_type": "selfie", "pose": "standing"})
    AttributeRepository.set_many(db, image_id, {"pose": "sitting"})
    assert AttributeRepository.get_for_image(db, image_id) == {
        "shot_type": "selfie", "pose": "sitting",
    }


def test_attributes_cascade_on_image_delete(db):
    image_id = _image(db)
    AttributeRepository.set(db, image_id, "shot_type", "selfie")
    ImageRepository.delete_by_filename(db, "a.png")
    assert AttributeRepository.get_for_image(db, image_id) == {}


def test_get_all_rows_for_footprint(db):
    a, b = _image(db, "a.png"), _image(db, "b.png")
    AttributeRepository.set(db, a, "shot_type", "selfie")
    AttributeRepository.set(db, b, "shot_type", "selfie")
    rows = AttributeRepository.get_all_rows(db)
    assert rows == [("shot_type", "selfie", 2)]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && pytest tests/test_attribute_db.py -v`
Expected: FAIL — `ImportError: cannot import name 'AttributeRepository'`

- [ ] **Step 3: Implement**

Append to `backend/app/db/repository.py`:

```python
class AttributeRepository:
    """Per-image categorical attributes stored in the metadata KV table."""

    @staticmethod
    def set(db: sqlite3.Connection, image_id: int, key: str, value: str) -> None:
        db.execute(
            "INSERT INTO metadata (image_id, key, value) VALUES (?, ?, ?)"
            " ON CONFLICT(image_id, key) DO UPDATE SET value = excluded.value",
            (image_id, key, value),
        )
        db.commit()

    @staticmethod
    def unset(db: sqlite3.Connection, image_id: int, key: str) -> None:
        db.execute(
            "DELETE FROM metadata WHERE image_id = ? AND key = ?", (image_id, key)
        )
        db.commit()

    @staticmethod
    def set_many(db: sqlite3.Connection, image_id: int, attributes: dict) -> None:
        for key, value in attributes.items():
            if value is None:
                db.execute(
                    "DELETE FROM metadata WHERE image_id = ? AND key = ?",
                    (image_id, key),
                )
            else:
                db.execute(
                    "INSERT INTO metadata (image_id, key, value) VALUES (?, ?, ?)"
                    " ON CONFLICT(image_id, key) DO UPDATE SET value = excluded.value",
                    (image_id, key, value),
                )
        db.commit()

    @staticmethod
    def get_for_image(db: sqlite3.Connection, image_id: int) -> dict:
        rows = db.execute(
            "SELECT key, value FROM metadata WHERE image_id = ?", (image_id,)
        ).fetchall()
        return {row["key"]: row["value"] for row in rows}

    @staticmethod
    def get_for_image_ids(db: sqlite3.Connection, image_ids: list[int]) -> dict[int, dict]:
        if not image_ids:
            return {}
        placeholders = ", ".join("?" * len(image_ids))
        rows = db.execute(
            f"SELECT image_id, key, value FROM metadata WHERE image_id IN ({placeholders})",
            image_ids,
        ).fetchall()
        result: dict[int, dict] = {}
        for row in rows:
            result.setdefault(row["image_id"], {})[row["key"]] = row["value"]
        return result

    @staticmethod
    def get_all_rows(db: sqlite3.Connection) -> list[tuple]:
        rows = db.execute(
            "SELECT key, value, COUNT(*) AS n FROM metadata"
            " GROUP BY key, value ORDER BY key, value"
        ).fetchall()
        return [(row["key"], row["value"], row["n"]) for row in rows]

    @staticmethod
    def get_filenames_with_attributes(db: sqlite3.Connection) -> dict[str, dict]:
        rows = db.execute(
            "SELECT i.filename, m.key, m.value FROM metadata m JOIN images i ON m.image_id = i.id"
        ).fetchall()
        result: dict[str, dict] = {}
        for row in rows:
            result.setdefault(row["filename"], {})[row["key"]] = row["value"]
        return result
```

Note: `create_schema` and `get_all_rows` return tuples as lists of 3-tuples — the footprint test compares against the list, and sqlite3 `Row` supports `row["n"]` access (that is why `COUNT(*) AS n`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && pytest tests/test_attribute_db.py -v`
Expected: 4 PASS

- [ ] **Step 5: Commit**

```bash
cd backend && git add app/db/repository.py tests/test_attribute_db.py && git commit -m "Add AttributeRepository on the metadata KV table"
```

---

### Task 3: Service — put, footprint, query

**Files:**
- Create: `backend/app/services/attribute_service.py`
- Test: extend `backend/tests/test_attribute_db.py`

- [ ] **Step 1: Write the failing tests**

Append to `backend/tests/test_attribute_db.py`:

```python
from app.db.repository import CaptionRepository
from app.services.attribute_service import (
    compute_footprint,
    query_images,
    set_attributes,
)


def test_set_attributes_validates(db):
    image_id = _image(db)
    valid, errors = set_attributes(db, image_id, {"shot_type": "Selfie", "framing": "nope"})
    assert valid == {"shot_type": "selfie"}
    assert errors == {"framing": "nope"}
    assert AttributeRepository.get_for_image(db, image_id) == {"shot_type": "selfie"}


def test_footprint_counts_and_unset(db):
    a, b, c = _image(db, "a.png"), _image(db, "b.png"), _image(db, "c.png")
    AttributeRepository.set(db, a, "shot_type", "selfie")
    AttributeRepository.set(db, b, "shot_type", "selfie")
    AttributeRepository.set(db, c, "shot_type", "landscape")
    fp = compute_footprint(db)
    assert fp["_total"] == 3
    assert fp["shot_type"] == {"selfie": 2, "landscape": 1, "_unset": 0}
    assert fp["pose"]["_unset"] == 3
    assert set(fp) == {"_total", *ATTRIBUTES}


def test_query_and_or_unset(db):
    a = _image(db, "a.png")
    b = _image(db, "b.png")
    c = _image(db, "c.png")
    AttributeRepository.set_many(db, a, {"shot_type": "selfie", "pose": "walking"})
    AttributeRepository.set_many(db, b, {"shot_type": "selfie", "pose": "standing"})
    CaptionRepository.upsert(db, a, "tags", "1girl, selfie")

    result = query_images(db, {"shot_type": ["selfie"], "pose": ["walking"]})
    assert [i["filename"] for i in result["items"]] == ["a.png"]
    assert result["items"][0]["captions"] == {"tags": "1girl, selfie"}
    assert result["total"] == 1

    result = query_images(db, {"shot_type": ["selfie"], "pose": ["walking", "standing"]})
    assert result["total"] == 2

    result = query_images(db, {"shot_type": ["selfie"], "pose": ["unset"]})
    assert [i["filename"] for i in result["items"]] == ["c.png"]
    assert result["total"] == 1

    result = query_images(db, {}, limit=1, offset=1)
    assert result["total"] == 3
    assert len(result["items"]) == 1


def test_query_unknown_attribute_raises(db):
    import pytest as _pytest
    from app.services.attribute_service import UnknownAttributeError

    with _pytest.raises(UnknownAttributeError):
        query_images(db, {"shot_typ": ["selfie"]})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && pytest tests/test_attribute_db.py -v`
Expected: last 4 tests FAIL — `ModuleNotFoundError: No module named 'app.services.attribute_service'`

- [ ] **Step 3: Implement**

Create `backend/app/services/attribute_service.py`:

```python
import os
import sqlite3

from app.attributes import ATTRIBUTES, validate_attributes
from app.db.repository import AttributeRepository, CaptionRepository, ImageRepository


class UnknownAttributeError(ValueError):
    pass


def set_attributes(db: sqlite3.Connection, image_id: int, attributes: dict) -> tuple[dict, dict]:
    valid, errors = validate_attributes(attributes)
    if valid:
        AttributeRepository.set_many(db, image_id, valid)
    for key, value in attributes.items():
        if value is None and key in ATTRIBUTES:
            AttributeRepository.unset(db, image_id, key)
    return valid, errors


def compute_footprint(db: sqlite3.Connection) -> dict:
    total = db.execute("SELECT COUNT(*) AS n FROM images").fetchone()["n"]
    footprint: dict = {
        name: {value: 0 for value in spec["values"]} for name, spec in ATTRIBUTES.items()
    }
    for key, value, count in AttributeRepository.get_all_rows(db):
        if key in footprint and value in footprint[key]:
            footprint[key][value] = count
    for key in footprint:
        footprint[key]["_unset"] = total - sum(footprint[key].values())
    footprint["_total"] = total
    return footprint


def query_images(
    db: sqlite3.Connection,
    filters: dict[str, list[str]],
    limit: int = 100,
    offset: int = 0,
) -> dict:
    for key in filters:
        if key not in ATTRIBUTES:
            raise UnknownAttributeError(key)

    where: list[str] = []
    params: list = []
    joins: list[str] = []
    for n, (key, values) in enumerate(filters.items()):
        alias = f"m{n}"
        if values == ["unset"]:
            joins.append(
                f"LEFT JOIN metadata {alias} ON {alias}.image_id = i.id AND {alias}.key = ?"
            )
            params.append(key)
            where.append(f"{alias}.key IS NULL")
        else:
            joins.append(
                f"JOIN metadata {alias} ON {alias}.image_id = i.id AND {alias}.key = ?"
                f" AND {alias}.value IN ({', '.join('?' * len(values))})"
            )
            params.append(key)
            params.extend(values)

    where_sql = (" WHERE " + " AND ".join(where)) if where else ""
    joins_sql = " ".join(joins)
    total = db.execute(
        f"SELECT COUNT(*) AS n FROM images i {joins_sql}{where_sql}", params
    ).fetchone()["n"]
    rows = db.execute(
        f"SELECT i.* FROM images i {joins_sql}{where_sql}"
        " GROUP BY i.id ORDER BY i.id LIMIT ? OFFSET ?",
        params + [limit, offset],
    ).fetchall()

    items = []
    for row in rows:
        row = dict(row)
        captions = {
            c["caption_type"]: c["content"]
            for c in CaptionRepository.get_all_for_image(db, row["id"])
        }
        items.append(
            {
                "id": row["id"],
                "filename": row["filename"],
                "width": row["width"],
                "height": row["height"],
                "file_size": row["file_size"],
                "is_bookmarked": bool(row["is_bookmarked"]),
                "attributes": AttributeRepository.get_for_image(db, row["id"]),
                "captions": captions,
            }
        )
    return {"total": total, "items": items}


def index_for_filename(session, filename: str) -> int | None:
    ds = session.dataset
    if ds is None:
        return None
    try:
        return ds.find_index(os.path.join(ds.base_dir, filename))
    except Exception:
        return None
```

Note: `find_index` (backend/lib/image_dataset.py:201) expects the full path; `index_for_filename` returns `None` when the file is not in the current session dataset (renamed/filtered datasets).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && pytest tests/test_attribute_db.py -v`
Expected: 8 PASS

- [ ] **Step 5: Commit**

```bash
cd backend && git add app/services/attribute_service.py tests/test_attribute_db.py && git commit -m "Add attribute service: validation, footprint, query"
```

---

### Task 4: Router + endpoints + media by-id

**Files:**
- Create: `backend/app/routers/attributes.py`
- Modify: `backend/app/main.py` (after line 87 `app.include_router(dedup.router)`)
- Modify: `backend/app/routers/media.py` (append two routes)
- Test: `backend/tests/test_attributes_api.py` (create)

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_attributes_api.py` (client fixture copies the proven pattern from `backend/tests/test_dataset_delete.py`). The dataset fixture RE-OLPENS the project after upload: `sync_db_with_filesystem` only runs when a dataset is opened (backend/app/services/dataset_service.py:36), so freshly uploaded files have no DB rows until reopen.

```python
import io
import os
import tempfile
import time

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.main import app


@pytest.fixture()
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture()
def dataset(client):
    with tempfile.TemporaryDirectory() as parent:
        path = os.path.join(parent, "dataset")
        response = client.post("/api/projects/create", json={"path": path})
        session_id = response.json()["session_id"]
        files = []
        for i, color in enumerate([(255, 0, 0), (0, 255, 0), (0, 0, 255)]):
            buf = io.BytesIO()
            Image.new("RGB", (8, 8), color).save(buf, format="PNG")
            files.append(("files", (f"img{i}.png", buf.getvalue(), "image/png")))
        client.post("/api/dataset/upload", files=files, headers={"X-Session-ID": session_id})
        client.delete(f"/api/projects/{session_id}")
        response = client.post("/api/projects/open", json={"path": path})
        session_id = response.json()["session_id"]
        yield {"session_id": session_id, "path": path, "headers": {"X-Session-ID": session_id}}


def test_schema_lists_vocabularies(client, dataset):
    response = client.get("/api/attributes/schema", headers=dataset["headers"])
    assert response.status_code == 200
    schema = response.json()
    assert schema["shot_type"]["applies_to"] == "all"
    assert "selfie" in schema["shot_type"]["values"]


def test_put_and_footprint(client, dataset):
    headers = dataset["headers"]
    response = client.put(
        "/api/attributes",
        json={"filename": "img0.png", "attributes": {"shot_type": "Selfie", "pose": "walking"}},
        headers=headers,
    )
    assert response.status_code == 200
    assert response.json()["attributes"] == {"shot_type": "selfie", "pose": "walking"}

    response = client.put(
        "/api/attributes",
        json={"filename": "img1.png", "attributes": {"framing": "blurry"}},
        headers=headers,
    )
    assert response.status_code == 422
    assert "blurry" in response.json()["detail"]

    response = client.put(
        "/api/attributes",
        json={"filename": "img1.png", "attributes": {"nope": "selfie"}},
        headers=headers,
    )
    assert response.status_code == 422

    footprint = client.get("/api/attributes/footprint", headers=headers).json()
    assert footprint["_total"] == 3
    assert footprint["shot_type"]["selfie"] == 1
    assert footprint["shot_type"]["_unset"] == 2

    response = client.get("/api/attributes?filename=img0.png", headers=headers)
    assert response.status_code == 200
    assert response.json() == {"filename": "img0.png", "attributes": {"shot_type": "selfie", "pose": "walking"}}


def test_query_and_media_by_id(client, dataset):
    headers = dataset["headers"]
    client.put(
        "/api/attributes",
        json={"filename": "img0.png", "attributes": {"shot_type": "selfie", "pose": "walking"}},
        headers=headers,
    )
    put = client.put(
        "/api/attributes",
        json={"filename": "img1.png", "attributes": {"shot_type": "selfie"}},
        headers=headers,
    )
    img1_id = put.json()["id"]

    response = client.get(
        "/api/attributes/query?shot_type=selfie&pose=walking", headers=headers
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    item = body["items"][0]
    assert item["filename"] == "img0.png"
    assert item["index"] == 0
    assert item["attributes"] == {"shot_type": "selfie", "pose": "walking"}

    response = client.get("/api/attributes/query?shot_typ=selfie", headers=headers)
    assert response.status_code == 422

    response = client.get("/api/attributes/query?shot_type=selfie|headshot", headers=headers)
    assert response.json()["total"] == 2

    response = client.get(f"/api/media/by-id/{img1_id}", headers=headers)
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"

    response = client.get(f"/api/media/thumbnail-by-id/{img1_id}", headers=headers)
    assert response.status_code == 200

    assert client.get("/api/media/by-id/99999", headers=headers).status_code == 404
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && pytest tests/test_attributes_api.py -v`
Expected: FAIL — 404s (routes not mounted)

- [ ] **Step 3: Implement**

Create `backend/app/routers/attributes.py`:

```python
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel

from app.attributes import ATTRIBUTES
from app.db.repository import AttributeRepository, ImageRepository
from app.sessions import Session, get_session
from app.services import task_service
from app.services.attribute_service import (
    UnknownAttributeError,
    compute_footprint,
    index_for_filename,
    query_images,
    set_attributes,
)

router = APIRouter(prefix="/api/attributes", tags=["attributes"])


class AttributeUpdate(BaseModel):
    filename: str
    attributes: dict


def _require_db(session: Session):
    if session.db is None:
        raise HTTPException(400, "No project database open")


@router.get("/schema")
def schema(session: Session = Depends(get_session)):
    return ATTRIBUTES


@router.get("/footprint")
def footprint(session: Session = Depends(get_session)):
    _require_db(session)
    return compute_footprint(session.db)


@router.get("")
def get_attributes(
    filename: str, session: Session = Depends(get_session)
):
    """Current attributes of one image — feeds the edit-view panel."""
    _require_db(session)
    row = ImageRepository.get_by_filename(session.db, filename)
    return {
        "filename": filename,
        "attributes": AttributeRepository.get_for_image(session.db, row["id"]) if row else {},
    }


@router.get("/query")
def query(
    request: Request,
    limit: int = Query(default=100, le=500),
    offset: int = 0,
    session: Session = Depends(get_session),
):
    _require_db(session)
    filters = {
        key: values.split("|")
        for key, values in request.query_params.items()
        if key not in ("limit", "offset")
    }
    try:
        result = query_images(session.db, filters, limit=limit, offset=offset)
    except UnknownAttributeError as exc:
        raise HTTPException(422, f"Unknown attribute: {exc}")
    for item in result["items"]:
        item["index"] = index_for_filename(session, item["filename"])
    return result


@router.put("")
def put(update: AttributeUpdate, session: Session = Depends(get_session)):
    _require_db(session)
    # ensure_image (not get_by_filename): files uploaded after the project was
    # opened have no DB row until the next sync; the row must be creatable now.
    image_id = ImageRepository.ensure_image(session.db, update.filename)
    valid, errors = set_attributes(session.db, image_id, update.attributes)
    if errors:
        rendered = ", ".join(f"{k}={v}" for k, v in errors.items())
        raise HTTPException(422, f"Invalid attribute values: {rendered}")
    return {"id": image_id, "filename": update.filename, "attributes": valid}


@router.post("/classify")
def classify(
    tagger: str = Query(default="vlm-tagger"),
    only_missing: bool = False,
    session: Session = Depends(get_session),
):
    _require_db(session)
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    from app.services.attribute_service import run_classification

    task_id = task_service.create_task(
        len(session.dataset),
        name="Attribute classification",
        operation="attribute_classification",
        project_name=os.path.basename(session.dataset.base_dir)
        if session.dataset.base_dir
        else None,
    )

    async def run():
        await run_classification(session, task_id, tagger, only_missing)

    task_service.submit(task_id, run)
    return {"task_id": task_id}
```

Add `import os` at the top of the router file. `run_classification` does not exist yet — create it as a stub at the end of `app/services/attribute_service.py` so imports resolve (real body lands in Task 5):

```python
async def run_classification(session, task_id: str, tagger: str, only_missing: bool) -> None:
    from app.services import task_service

    task_service.complete_task(task_id)
```

Mount: add to `backend/app/main.py` — import line next to the other routers (`from app.routers import ... attributes ...`, follow existing import style at the top of the file) and `app.include_router(attributes.router)` after line 87.

Media by-id, append to `backend/app/routers/media.py`:

```python
@router.get("/by-id/{image_id}")
def serve_media_by_id(image_id: int, session: Session = Depends(get_session_flexible)):
    from app.db.repository import ImageRepository

    if session.db is None:
        raise HTTPException(400, "No project database open")
    row = ImageRepository.get_by_id(session.db, image_id)
    if row is None:
        raise HTTPException(404, "Image not found")
    try:
        index = session.dataset.find_index(
            os.path.join(session.dataset.base_dir, row["filename"])
        )
    except Exception:
        raise HTTPException(404, "Image not in current dataset")
    return serve_media(index, session)


@router.get("/thumbnail-by-id/{image_id}")
def serve_thumbnail_by_id(image_id: int, session: Session = Depends(get_session_flexible)):
    from app.db.repository import ImageRepository

    if session.db is None:
        raise HTTPException(400, "No project database open")
    row = ImageRepository.get_by_id(session.db, image_id)
    if row is None:
        raise HTTPException(404, "Image not found")
    try:
        index = session.dataset.find_index(
            os.path.join(session.dataset.base_dir, row["filename"])
        )
    except Exception:
        raise HTTPException(404, "Image not in current dataset")
    return serve_thumbnail(index, session)
```

(`find_index` behavior: check `backend/lib/image_dataset.py:201` — if it returns `-1`/`None` instead of raising, replace the `try/except` with `if index is None or index < 0: raise HTTPException(404, ...)` in both routes and mirror this in `attribute_service.index_for_filename`.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && pytest tests/test_attributes_api.py -v`
Expected: 3 PASS

- [ ] **Step 5: Run the full backend suite, then commit**

Run: `cd backend && pytest -q` → Expected: all pass (was 82 + 20 new).
```bash
cd backend && git add app/routers/attributes.py app/main.py app/routers/media.py app/services/attribute_service.py tests/test_attributes_api.py && git commit -m "Add attribute schema/footprint/query/put endpoints and media by-id routes"
```

---

### Task 5: Classification job

**Files:**
- Modify: `backend/app/services/attribute_service.py` (replace `run_classification` stub)
- Test: `backend/tests/test_attributes_api.py` (append)

- [ ] **Step 1: Write the failing tests**

Append to `backend/tests/test_attributes_api.py`:

```python
import json as _json


def _start_classify(client, dataset, monkeypatch, responses, only_missing=False):
    calls = []

    def fake_generate_caption(index, tagger, state_dict, prompt=None):
        calls.append({"index": index, "tagger": tagger, "prompt": prompt})
        return responses[index]

    monkeypatch.setattr("lib.captioning.generate_caption", fake_generate_caption)
    response = client.post(
        f"/api/attributes/classify?tagger=vlm-tagger&only_missing={str(only_missing).lower()}",
        headers=dataset["headers"],
    )
    assert response.status_code == 200
    return response.json()["task_id"], calls


def _wait_task(client, task_id, headers):
    for _ in range(200):
        status = client.get(f"/api/tasks/{task_id}", headers=headers).json()
        if status["status"] in ("completed", "failed", "cancelled"):
            return status
        time.sleep(0.05)
    raise AssertionError("task did not finish")


def test_classify_writes_valid_values(client, dataset, monkeypatch):
    good = _json.dumps({"has_person": True, "shot_type": "Selfie", "pose": "walking"})
    junk = "I cannot answer"
    task_id, calls = _start_classify(client, dataset, monkeypatch, {0: good, 1: junk, 2: ""})
    status = _wait_task(client, task_id, dataset["headers"])
    assert status["status"] == "completed"
    assert all(c["tagger"] == "vlm-tagger" for c in calls)
    assert "has_person" in calls[0]["prompt"]

    query = client.get("/api/attributes/query?shot_type=selfie", headers=dataset["headers"]).json()
    assert [i["filename"] for i in query["items"]] == ["img0.png"]
    assert query["items"][0]["attributes"]["pose"] == "walking"


def test_classify_only_missing_skips_classified_images(client, dataset, monkeypatch):
    client.put(
        "/api/attributes",
        json={"filename": "img0.png", "attributes": {"shot_type": "headshot"}},
        headers=dataset["headers"],
    )
    good = _json.dumps({"has_person": False, "shot_type": "aerial"})
    task_id, calls = _start_classify(
        client, dataset, monkeypatch, {0: good, 1: good, 2: good}, only_missing=True
    )
    _wait_task(client, task_id, dataset["headers"])
    # img0 already had a value -> the VLM is never called for it (skipped cheaply)
    assert 0 not in [c["index"] for c in calls]
    query = client.get("/api/attributes/query?shot_type=headshot", headers=dataset["headers"]).json()
    assert [i["filename"] for i in query["items"]] == ["img0.png"]
    query = client.get("/api/attributes/query?shot_type=aerial", headers=dataset["headers"]).json()
    assert sorted(i["filename"] for i in query["items"]) == ["img1.png", "img2.png"]
```

(`only_missing` semantics: any image that already carries at least one attribute is skipped entirely — no VLM call, manual corrections and GPU budget both survive reruns.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && pytest tests/test_attributes_api.py -k classify -v`
Expected: FAIL — img0 keeps getting overwritten / attributes empty (stub completes without work).

- [ ] **Step 3: Implement**

Replace the `run_classification` stub in `backend/app/services/attribute_service.py` with:

```python
async def run_classification(session, task_id: str, tagger: str, only_missing: bool) -> None:
    import asyncio

    from app.attributes import build_classify_prompt
    from app.services import task_service

    ds = session.dataset
    db = session.db
    prompt = build_classify_prompt()
    failures = 0
    task_service.start_task(task_id)

    for index in range(len(ds)):
        if task_service.is_cancelled(task_id):
            break
        await task_service.wait_if_paused(task_id)

        item = ds.get_item(index)
        rel_path = os.path.relpath(item.media_path, ds.base_dir)
        row = ImageRepository.get_by_filename(db, rel_path)
        if row is None:
            continue
        existing = AttributeRepository.get_for_image(db, row["id"])
        if only_missing and existing:
            task_service.update_progress(
                task_id, index, len(ds), index, rel_path, "skipped (already set)"
            )
            continue

        try:
            from lib.captioning import generate_caption

            raw = await asyncio.to_thread(
                generate_caption, index, tagger, {"dataset": ds}, prompt=prompt
            )
            parsed, _has_person = parse_attributes_response(raw or "")
        except Exception:
            parsed, failures = {}, failures + 1

        if parsed:
            AttributeRepository.set_many(db, row["id"], parsed)
        task_service.update_progress(task_id, index + 1)

    session.touch()
    task_service.complete_task(
        task_id, error=f"{failures} images failed to classify" if failures else None
    )
```

Add to the imports at the top of `attribute_service.py`:

```python
from app.attributes import parse_attributes_response
from app.db.repository import AttributeRepository, CaptionRepository, ImageRepository
```

(The `ImageRepository`/`AttributeRepository` import line added in Task 3 already covers these; extend it.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && pytest tests/test_attributes_api.py -v`
Expected: 5 PASS. Then `pytest -q` full suite still green.

- [ ] **Step 5: Commit**

```bash
cd backend && git add app/services/attribute_service.py tests/test_attributes_api.py && git commit -m "Add VLM attribute classification job"
```

---

### Task 6: Gallery integration (attributes + filter)

**Files:**
- Modify: `backend/app/models/schemas.py:262` (`GalleryItem`)
- Modify: `backend/app/routers/dataset.py` (`gallery`, ~line 99)
- Test: `backend/tests/test_attributes_api.py` (append)

- [ ] **Step 1: Write the failing test**

```python
def test_gallery_returns_attributes(client, dataset):
    headers = dataset["headers"]
    client.put(
        "/api/attributes",
        json={"filename": "img0.png", "attributes": {"shot_type": "selfie"}},
        headers=headers,
    )
    gallery = client.get("/api/dataset/gallery?page=0&page_size=10", headers=headers).json()
    by_name = {i["filename"]: i for i in gallery["items"]}
    assert by_name["img0.png"]["attributes"] == {"shot_type": "selfie"}
    assert by_name["img1.png"]["attributes"] == {}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && pytest tests/test_attributes_api.py::test_gallery_returns_attributes -v`
Expected: FAIL — `KeyError`/missing `attributes` field.

- [ ] **Step 3: Implement**

In `backend/app/models/schemas.py`, add to `GalleryItem` (after `category: str | None = None`, line ~271):

```python
    attributes: dict[str, str] = {}
```

In `backend/app/routers/dataset.py` `gallery()` (starts line ~99): the loop already resolves `img_row = ImageRepository.get_by_filename(...)` per item. Three surgical changes, no other behavior touched:

1. Before the loop (right after `items = []`): `row_ids: dict[int, int] = {}`
2. Inside the loop, immediately after the existing `img_row = ...` assignment: `if img_row: row_ids[i] = img_row["id"]`
3. After the loop, before `return GalleryResponse(...)`:

```python
    if session.db and row_ids:
        attrs_map = AttributeRepository.get_for_image_ids(session.db, list(row_ids.values()))
        for gallery_index, row_id in row_ids.items():
            items[gallery_index - start].attributes = attrs_map.get(row_id, {})
```

Add `AttributeRepository` to the existing `from app.db.repository import ...` line in `dataset.py`.

Browse-side filtering stays client-side for v1: the frontend filters loaded gallery pages by `item.attributes` — no server filter parameter in this task (pages are already the browse unit; a server-side filter would fight pagination). The agent-facing filter is `/api/attributes/query`.

- [ ] **Step 4: Run tests**

Run: `cd backend && pytest tests/test_attributes_api.py -v && pytest -q`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd backend && git add app/models/schemas.py app/routers/dataset.py tests/test_attributes_api.py && git commit -m "Expose image attributes on gallery items"
```

---

### Task 7: Frontend — types + API client

**Files:**
- Modify: `frontend/src/lib/types.ts` (append)
- Modify: `frontend/src/lib/api.ts` (inside the `api` object, after the category calls)

- [ ] **Step 1: Add types** to `frontend/src/lib/types.ts`:

```typescript
export interface AttributeSpec {
  applies_to: "all" | "person";
  values: string[];
}

export type AttributeSchema = Record<string, AttributeSpec>;

export type AttributeMap = Record<string, string>;

export type AttributeFootprint = Record<string, Record<string, number>>;

export interface AttributeQueryItem {
  id: number;
  index: number | null;
  filename: string;
  width: number | null;
  height: number | null;
  file_size: number | null;
  is_bookmarked: boolean;
  attributes: AttributeMap;
  captions: Record<string, string>;
}

export interface AttributeQueryResponse {
  total: number;
  items: AttributeQueryItem[];
}
```

- [ ] **Step 2: Add API calls** inside `export const api = { ... }` in `frontend/src/lib/api.ts` (uses `apiFetch`, which injects session + Content-Type):

```typescript
  getAttributeSchema: () => apiFetch<AttributeSchema>("/api/attributes/schema"),

  getAttributeFootprint: () => apiFetch<AttributeFootprint>("/api/attributes/footprint"),

  getAttributes: (filename: string) =>
    apiFetch<{ filename: string; attributes: AttributeMap }>(
      `/api/attributes?filename=${encodeURIComponent(filename)}`
    ),

  queryAttributes: (filters: AttributeMap, limit = 100, offset = 0) => {
    const params = new URLSearchParams({ ...filters, limit: String(limit), offset: String(offset) });
    return apiFetch<AttributeQueryResponse>(`/api/attributes/query?${params.toString()}`);
  },

  setAttributes: (filename: string, attributes: Record<string, string | null>) =>
    apiFetch<{ id: number; filename: string; attributes: AttributeMap }>("/api/attributes", {
      method: "PUT",
      body: JSON.stringify({ filename, attributes }),
    }),

  classifyAttributes: (tagger: string, onlyMissing: boolean) =>
    apiFetch<{ task_id: string }>(
      `/api/attributes/classify?tagger=${encodeURIComponent(tagger)}&only_missing=${onlyMissing}`,
      { method: "POST" }
    ),
```

Add the imported types to the existing `import type { ... } from "./types"` statement at the top of `api.ts`.

- [ ] **Step 3: Typecheck**

Run: `cd frontend && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 4: Commit (frontend submodule)**

```bash
cd frontend && git add src/lib/types.ts src/lib/api.ts && git commit -m "Add attribute API client and types"
```

---

### Task 8: Frontend — AttributePanel in edit view

**Files:**
- Create: `frontend/src/components/edit/AttributePanel.tsx`
- Modify: `frontend/src/app/edit/page.tsx`

- [ ] **Step 1: Create the panel.** Read `frontend/src/components/edit/CategorySelector.tsx` first and match its select-primitive choice (shadcn `Select` vs native) and props style. The panel fetches schema and current values itself (via `GET /api/attributes?filename=`) — the edit page only passes `filename` and a remount `key`; no state plumbing.

```tsx
"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { AttributeMap, AttributeSchema } from "@/lib/types";

export function AttributePanel({ filename }: { filename: string }) {
  const [schema, setSchema] = useState<AttributeSchema | null>(null);
  const [attributes, setAttributes] = useState<AttributeMap>({});

  useEffect(() => {
    api.getAttributeSchema().then(setSchema).catch(() => setSchema(null));
  }, []);

  useEffect(() => {
    setAttributes({});
    api
      .getAttributes(filename)
      .then((r) => setAttributes(r.attributes))
      .catch(() => setAttributes({}));
  }, [filename]);

  if (!schema) return null;

  const visible = Object.entries(schema).filter(
    ([name, spec]) => spec.applies_to === "all" || name in attributes
  );

  async function handleChange(attribute: string, value: string) {
    try {
      await api.setAttributes(filename, { [attribute]: value === "unset" ? null : value });
      setAttributes((prev) => {
        const next = { ...prev };
        if (value === "unset") delete next[attribute];
        else next[attribute] = value;
        return next;
      });
    } catch (err) {
      console.error(err);
    }
  }

  return (
    <div className="space-y-2 p-2">
      <h3 className="text-sm font-medium">Attributes</h3>
      {visible.map(([name, spec]) => (
        <label key={name} className="block text-xs">
          <span className="text-muted-foreground">{name.split("_").join(" ")}</span>
          <select
            className="w-full rounded border bg-background p-1 text-xs"
            value={attributes[name] ?? "unset"}
            onChange={(e) => handleChange(name, e.target.value)}
          >
            <option value="unset">-- unset --</option>
            {spec.values.map((v) => (
              <option key={v} value={v}>{v.split("_").join(" ")}</option>
            ))}
          </select>
        </label>
      ))}
    </div>
  );
}
```

Person-only attributes appear once the VLM (or a manual pick) set one — `applies_to: "person"` entries show only when already present. (Chicken-and-egg for first manual person-attribute: it is set via `shot_type`-adjacent values or a classify run first; acceptable for v1.)

- [ ] **Step 2: Mount it** in `frontend/src/app/edit/page.tsx` beside `CategorySelector` in the same sidebar/panel area: `<AttributePanel key={currentFilename} filename={currentFilename} />` — `key` forces a value refetch when the user navigates images. Locate the current filename variable by reading how `CategorySelector` receives its image identity and mirror it.

- [ ] **Step 3: Verify**

Run: `cd frontend && npm run lint && npx tsc --noEmit && npm run build`
Expected: clean. Manual check with `./run.sh`: open a project, edit view shows Attributes panel, picking a value persists across navigation.

- [ ] **Step 4: Commit**

```bash
cd frontend && git add src/components/edit/AttributePanel.tsx src/app/edit/page.tsx && git commit -m "Add attribute editing panel to edit view"
```

---

### Task 9: Frontend — browse badges + client-side filter

**Files:**
- Modify: `frontend/src/components/browse/GalleryGrid.tsx` (and its page `frontend/src/app/browse/page.tsx` if state lives there)

- [ ] **Step 1: Extend the client GalleryItem type** in `types.ts` where `GalleryItem` (frontend) is defined: add `attributes?: Record<string, string>;`.

- [ ] **Step 2: Badges** — on each card render at most 2 attribute badges (`shot_type`, `framing` if present) as small `<span>` chips, matching the existing bookmark-badge styling in `GalleryGrid.tsx`.

- [ ] **Step 3: Filter row** — above the grid, one `<select>` per attribute from the schema (fetched once via `api.getAttributeSchema()`), options: `all` (default), `unset`, then values; multiple simultaneous selections AND together against the already-loaded items' `attributes`. Keep the filter state next to the existing browse filter state (categories/bookmark filter) and reuse its dropdown UI pattern.

- [ ] **Step 4: Verify**

Run: `cd frontend && npm run lint && npm run build`
Expected: clean. Manual: classify-free badges empty; after setting a few attributes in edit view, filtering shows matching cards only.

- [ ] **Step 5: Commit**

```bash
cd frontend && git add -A src/ && git commit -m "Add attribute badges and browse filtering"
```

---

### Task 10: Full verification + root bump

- [ ] **Step 1:** `cd backend && pytest -q` — all green (82 existing + ~20 new).
- [ ] **Step 2:** `cd frontend && npm run lint && npm run build` — clean.
- [ ] **Step 3:** Manual smoke: `./run.sh`, open project, browse → attributes visible, edit → set one value, `curl -s "localhost:8000/api/attributes/footprint" -H "X-Session-ID: <sid>"` shows the value.
- [ ] **Step 4:** Root bump:

```bash
git add backend frontend docs/superpowers/plans/2026-10-10-image-attributes.md
git commit -m "Bump submodules: image attributes (vocabulary, classify, footprint/query API, UI)"
```

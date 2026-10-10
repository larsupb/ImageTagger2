# Semantic Search (Caption Embeddings) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-dataset vector store over caption text (all types combined) with cosine search, exposed via HTTP API, browse-grid search box, and a batch-captioning hook.

**Architecture:** Embeddings computed by a remote OpenAI-compatible `/v1/embeddings` endpoint; float32 vectors stored as BLOBs in a new `caption_vectors` table inside each dataset's `metadata.db`; search = one remote embed of the query + cosine over an in-memory numpy matrix cached per session. Indexing is an on-demand task-service job plus an opt-in hook in the batch captioning loop.

**Tech Stack:** FastAPI, sqlite3, numpy, `openai` python client (already a dependency), Next.js 15 / React 19 / TanStack Query, shadcn UI.

**Spec:** `docs/superpowers/specs/2026-10-11-semantic-search-design.md`

**Repos:** `backend/` and `frontend/` are git submodules — commit inside the submodule, bump pointers from the root repo at the end. Backend tests: `cd backend && .venv/bin/python -m pytest` (venv required; the full suite must keep passing except the 2 known `test_white_balance.py` failures). Frontend gates: `cd frontend && npx tsc --noEmit && npm run lint` (lint may show the 12 pre-existing errors on untouched files — no NEW errors allowed).

---

### Task 1: `caption_vectors` table + VectorRepository

**Files:**
- Modify: `backend/app/db/schema.py`
- Modify: `backend/app/db/repository.py` (append class at end)
- Test: `backend/tests/test_vector_db.py` (create)

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_vector_db.py`:

```python
import sqlite3

from app.db.schema import create_schema
from app.db.repository import VectorRepository


def _db():
    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row
    create_schema(db)
    db.execute("INSERT INTO images (id, filename) VALUES (1, 'a.png'), (2, 'b.png')")
    return db


def test_caption_vectors_table_exists():
    db = _db()
    cols = [r[1] for r in db.execute("PRAGMA table_info(caption_vectors)")]
    assert cols == ["image_id", "model", "dim", "embedding", "text_hash", "updated_at"]


def test_upsert_and_load_roundtrip():
    db = _db()
    blob = (b"\x00" * 16)
    VectorRepository.upsert(db, 1, "m1", 4, blob, "hash-a")
    db.commit()
    rows = VectorRepository.load_all(db)
    assert len(rows) == 1
    assert bytes(rows[0]["embedding"]) == blob
    VectorRepository.upsert(db, 1, "m1", 4, b"\x01" * 16, "hash-b")
    db.commit()
    assert VectorRepository.hashes(db) == {1: ("m1", "hash-b")}
    assert len(VectorRepository.load_all(db)) == 1


def test_orphans_deleted_and_revision_changes():
    db = _db()
    VectorRepository.upsert(db, 1, "m1", 4, b"\x00" * 16, "h1")
    VectorRepository.upsert(db, 2, "m1", 4, b"\x00" * 16, "h2")
    db.commit()
    before = VectorRepository.revision(db)
    removed = VectorRepository.delete_missing(db, {1})
    db.commit()
    assert removed == 1
    assert VectorRepository.hashes(db) == {1: ("m1", "h1")}
    assert VectorRepository.revision(db) != before


def test_image_delete_cascades():
    db = _db()
    VectorRepository.upsert(db, 1, "m1", 4, b"\x00" * 16, "h1")
    db.commit()
    db.execute("DELETE FROM images WHERE id = 1")
    assert VectorRepository.hashes(db) == {}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && .venv/bin/python -m pytest tests/test_vector_db.py -q`
Expected: FAIL — `ImportError: cannot import name 'VectorRepository'` / no such table.

- [ ] **Step 3: Add the table**

In `backend/app/db/schema.py`: bump `SCHEMA_VERSION = 3`, and inside `SCHEMA_SQL` (after the `metadata` table block, before the closing `"""`) append:

```sql
CREATE TABLE IF NOT EXISTS caption_vectors (
    image_id INTEGER PRIMARY KEY REFERENCES images(id) ON DELETE CASCADE,
    model TEXT NOT NULL,
    dim INTEGER NOT NULL,
    embedding BLOB NOT NULL,
    text_hash TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

- [ ] **Step 4: Add the repository**

In `backend/app/db/repository.py`, append at end of file:

```python
class VectorRepository:
    """Caption embedding vectors (one L2-normalized float32 blob per image)."""

    @staticmethod
    def upsert(db: sqlite3.Connection, image_id: int, model: str, dim: int,
               embedding: bytes, text_hash: str) -> None:
        db.execute(
            "INSERT INTO caption_vectors (image_id, model, dim, embedding, text_hash)"
            " VALUES (?, ?, ?, ?, ?)"
            " ON CONFLICT(image_id) DO UPDATE SET model = excluded.model,"
            " dim = excluded.dim, embedding = excluded.embedding,"
            " text_hash = excluded.text_hash, updated_at = datetime('now')",
            (image_id, model, dim, embedding, text_hash),
        )

    @staticmethod
    def load_all(db: sqlite3.Connection) -> list[sqlite3.Row]:
        return db.execute(
            "SELECT image_id, model, dim, embedding, updated_at FROM caption_vectors"
        ).fetchall()

    @staticmethod
    def hashes(db: sqlite3.Connection) -> dict[int, tuple[str, str]]:
        return {
            r["image_id"]: (r["model"], r["text_hash"])
            for r in db.execute("SELECT image_id, model, text_hash FROM caption_vectors")
        }

    @staticmethod
    def delete_missing(db: sqlite3.Connection, keep_ids: set[int]) -> int:
        removed = 0
        for r in db.execute("SELECT image_id FROM caption_vectors").fetchall():
            if r["image_id"] not in keep_ids:
                db.execute("DELETE FROM caption_vectors WHERE image_id = ?", (r["image_id"],))
                removed += 1
        return removed

    @staticmethod
    def revision(db: sqlite3.Connection) -> tuple[int, str]:
        r = db.execute(
            "SELECT COUNT(*) c, COALESCE(MAX(updated_at), '') m FROM caption_vectors"
        ).fetchone()
        return r["c"], r["m"]
```

(`import sqlite3` is already at the top of repository.py.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && .venv/bin/python -m pytest tests/test_vector_db.py -q` → PASS.

- [ ] **Step 6: Commit (backend submodule)**

```bash
cd backend && git add app/db/schema.py app/db/repository.py tests/test_vector_db.py
git commit -m "Add caption_vectors table and VectorRepository for search embeddings"
```

---

### Task 2: `embedding_endpoint` settings

**Files:**
- Modify: `backend/app/config.py` (DEFAULTS dict + accessor)
- Test: `backend/tests/test_embeddings.py` (create)

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_embeddings.py`:

```python
import app.config as config


def test_embedding_endpoint_defaults_present():
    assert "embedding_endpoint" in config.DEFAULTS
    d = config.DEFAULTS["embedding_endpoint"]
    assert set(d) >= {"api_key", "base_url", "model", "timeout"}


def test_embedding_endpoint_settings_reads_settings_file(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "SETTINGS_FILE", str(tmp_path / "settings.json"))
    config.update_setting("embedding_endpoint", {"api_key": "k", "base_url": "http://x/v1",
                                                 "model": "embed-m", "timeout": 30})
    s = config.embedding_endpoint_settings()
    assert s["model"] == "embed-m" and s["base_url"] == "http://x/v1"
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && .venv/bin/python -m pytest tests/test_embeddings.py -q`
Expected: FAIL — `AttributeError: ... 'embedding_endpoint_settings'`.

- [ ] **Step 3: Implement**

In `backend/app/config.py`, inside `DEFAULTS` (next to the `llm_endpoint` entry) add:

```python
    "embedding_endpoint": {
        "api_key": "",
        "base_url": "http://localhost:11434/v1",
        "model": "qwen3-embedding-8b",
        "timeout": 120,
    },
```

and after the existing `llm_endpoint_settings()` function add:

```python
def embedding_endpoint_settings() -> dict:
    """Get OpenAI-compatible embedding endpoint settings."""
    return read_settings().get("embedding_endpoint", DEFAULTS["embedding_endpoint"])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && .venv/bin/python -m pytest tests/test_embeddings.py -q` → PASS.

- [ ] **Step 5: Commit**

```bash
cd backend && git add app/config.py tests/test_embeddings.py
git commit -m "Add embedding_endpoint settings for semantic search"
```

---

### Task 3: `embed_texts` — batched remote embedding with retry

**Files:**
- Create: `backend/app/services/embedding_service.py`
- Test: `backend/tests/test_embeddings.py` (append)

- [ ] **Step 1: Write the failing test**

Append to `backend/tests/test_embeddings.py`:

```python
import numpy as np
import pytest

from app.services import embedding_service


SETTINGS = {"api_key": "k", "base_url": "http://x/v1", "model": "m", "timeout": 5}


def test_embed_texts_batches_and_normalizes(monkeypatch):
    calls = []

    def fake(texts, settings):
        calls.append(list(texts))
        return [[1.0, 0.0] for _ in texts]

    monkeypatch.setattr(embedding_service, "_create_embeddings", fake)
    out = embedding_service.embed_texts(["a", "b", "c"], SETTINGS)
    assert out.shape == (3, 2)
    assert np.allclose(np.linalg.norm(out, axis=1), 1.0)


def test_embed_texts_retries_empty_response_once(monkeypatch):
    responses = [[], [[1.0, 1.0]]]
    monkeypatch.setattr(embedding_service, "_create_embeddings",
                        lambda texts, settings: responses.pop(0))
    out = embedding_service.embed_texts(["a"], SETTINGS)
    assert np.allclose(out[0], [1 / np.sqrt(2), 1 / np.sqrt(2)])


def test_embed_texts_raises_after_second_empty(monkeypatch):
    monkeypatch.setattr(embedding_service, "_create_embeddings",
                        lambda texts, settings: [])
    with pytest.raises(RuntimeError):
        embedding_service.embed_texts(["a"], SETTINGS)


def test_embed_texts_chunks_at_batch_size(monkeypatch):
    calls = []

    def fake(texts, settings):
        calls.append(len(texts))
        return [[1.0] for _ in texts]

    monkeypatch.setattr(embedding_service, "_create_embeddings", fake)
    embedding_service.embed_texts([f"t{i}" for i in range(70)], SETTINGS)
    assert calls == [32, 32, 6]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && .venv/bin/python -m pytest tests/test_embeddings.py -q`
Expected: FAIL — `ImportError: cannot import name 'embedding_service'`.

- [ ] **Step 3: Implement**

Create `backend/app/services/embedding_service.py`:

```python
"""Caption embedding + semantic search over the caption_vectors table."""

import hashlib
import os

import numpy as np

from app.db.repository import ImageRepository, VectorRepository

BATCH_SIZE = 32


def _create_embeddings(texts: list[str], settings: dict) -> list[list[float]]:
    """Raw call to the OpenAI-compatible embeddings endpoint (test seam)."""
    from openai import OpenAI

    client = OpenAI(
        base_url=settings["base_url"],
        api_key=settings.get("api_key") or "none",
        timeout=settings.get("timeout", 120),
    )
    resp = client.embeddings.create(model=settings["model"], input=texts)
    return [d.embedding for d in resp.data]


def embed_texts(texts: list[str], settings: dict) -> np.ndarray:
    """Embed texts in batches, one retry per batch, L2-normalized float32 rows."""
    out: list[list[float]] = []
    for start in range(0, len(texts), BATCH_SIZE):
        chunk = texts[start:start + BATCH_SIZE]
        vecs = _create_embeddings(chunk, settings)
        if len(vecs) != len(chunk):
            vecs = _create_embeddings(chunk, settings)
        if len(vecs) != len(chunk):
            raise RuntimeError(
                f"embedding endpoint returned {len(vecs)}/{len(chunk)} vectors"
            )
        out.extend(vecs)
    arr = np.asarray(out, dtype=np.float32)
    norms = np.linalg.norm(arr, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    return arr / norms
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && .venv/bin/python -m pytest tests/test_embeddings.py -q` → PASS.

- [ ] **Step 5: Commit**

```bash
cd backend && git add app/services/embedding_service.py tests/test_embeddings.py
git commit -m "Add embed_texts with batching and retry"
```

---

### Task 4: Combined caption text + staleness plan

**Files:**
- Modify: `backend/app/services/embedding_service.py`
- Test: `backend/tests/test_search_api.py` (create — pure-service tests use the shared fixture from Task 5's file; keep them here with a small local db helper)

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_caption_text_and_plan.py`:

```python
import hashlib
import sqlite3

from app.db.schema import create_schema
from app.db.repository import VectorRepository
from app.services.embedding_service import caption_text, compute_index_plan


def _db():
    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row
    create_schema(db)
    db.execute("INSERT INTO images (id, filename) VALUES (1, 'a.png'), (2, 'b.png'), (3, 'c.png')")
    return db


def _caption(db, image_id, ctype, content):
    db.execute(
        "INSERT INTO captions (image_id, caption_type, content, is_active)"
        " VALUES (?, ?, ?, 1)", (image_id, ctype, content))


def test_caption_text_combines_all_types_sorted_ignores_empty():
    db = _db()
    _caption(db, 1, "tags", "1girl, waving")
    _caption(db, 1, "qwen3.8", "a person waving")
    _caption(db, 1, "empty_type", "")
    assert caption_text(db, 1) == "1girl, waving\n\na person waving"


def test_plan_detects_new_changed_and_model_change():
    db = _db()
    _caption(db, 1, "tags", "hello")
    _caption(db, 2, "tags", "world")
    digest2 = hashlib.sha256(b"world").hexdigest()
    VectorRepository.upsert(db, 2, "m1", 2, b"\x00\x00", digest2)
    db.commit()

    todo, fresh = compute_index_plan(db, "m1")
    assert [i for i, _ in todo] == [1]           # image 1 new, image 2 fresh
    assert fresh == 1

    _caption(db, 2, "tags", "world changed")
    todo, fresh = compute_index_plan(db, "m1")
    assert sorted(i for i, _ in todo) == [1, 2]  # stale by hash

    todo, fresh = compute_index_plan(db, "other-model")
    assert len(todo) == 2                        # stale by model
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && .venv/bin/python -m pytest tests/test_caption_text_and_plan.py -q`
Expected: FAIL — `ImportError: cannot import name 'caption_text'`.

- [ ] **Step 3: Implement**

Append to `backend/app/services/embedding_service.py`:

```python
def caption_text(db, image_id: int) -> str:
    """All non-empty captions of an image, tags and descriptions alike, in
    stable order so the hash does not depend on insertion order."""
    rows = db.execute(
        "SELECT content FROM captions WHERE image_id = ? AND content != ''"
        " ORDER BY caption_type",
        (image_id,),
    ).fetchall()
    return "\n\n".join(r["content"] for r in rows)


def compute_index_plan(db, model: str) -> tuple[list[tuple[int, str]], int]:
    """Images needing (re-)embedding + count already fresh for `model`.

    Staleness is derived, never stored: hash or model mismatch."""
    stored = VectorRepository.hashes(db)
    todo: list[tuple[int, str]] = []
    fresh = 0
    rows = db.execute(
        "SELECT DISTINCT image_id FROM captions WHERE content != ''"
    ).fetchall()
    for r in rows:
        text = caption_text(db, r["image_id"])
        digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
        if stored.get(r["image_id"]) == (model, digest):
            fresh += 1
        else:
            todo.append((r["image_id"], text))
    return todo, fresh


def indexed_count(db, model: str) -> int:
    return sum(1 for m, _ in VectorRepository.hashes(db).values() if m == model)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && .venv/bin/python -m pytest tests/test_caption_text_and_plan.py -q` → PASS.

- [ ] **Step 5: Commit**

```bash
cd backend && git add app/services/embedding_service.py tests/test_caption_text_and_plan.py
git commit -m "Add combined caption text and derived staleness for search index"
```

---

### Task 5: Search service + `/api/search` router + index job

**Files:**
- Modify: `backend/app/services/embedding_service.py` (index/search functions)
- Create: `backend/app/routers/search.py`
- Modify: `backend/app/main.py` (register router)
- Test: `backend/tests/test_search_api.py` (create)

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_search_api.py`. It reuses the same fixture style as `tests/test_attributes_api.py` (3 tiny PNGs, renamed `img0.png`–`img2.png`; copy the `dataset` and `_wait_task` fixtures/helpers from that file — the dataset fixture there is self-contained per file).

```python
import json as _json
import time  # noqa: F401  (used by _wait_task copy)

# copy verbatim from tests/test_attributes_api.py: the `dataset` fixture and
# `_wait_task`. They only depend on `client` (from conftest), PIL, io, os, tempfile.

def _set_caption(client, headers, filename, content, caption_type="tags"):
    r = client.put(
        "/api/captions",
        json={"filename": filename, "content": content, "caption_type": caption_type},
        headers=headers,
    )
    assert r.status_code == 200, r.text


def _fake_embed(responses_by_text):
    """Fake _create_embeddings: deterministic 2-d vectors from a lookup."""
    table = {
        "a person by the sea": [1.0, 0.0],
        "a car on the road": [0.0, 1.0],
        "sea": [0.9, 0.1],
        "car": [0.1, 0.9],
    }
    def fake(texts, settings):
        out = []
        for t in texts:
            if t not in table:
                return []          # unknown text -> empty response (exercises retry/error)
            out.append(table[t])
        return out
    return fake


def test_index_job_and_search_ranking(client, dataset, monkeypatch):
    headers = dataset["headers"]
    _set_caption(client, headers, "img0.png", "a person by the sea")
    _set_caption(client, headers, "img1.png", "a car on the road")
    monkeypatch.setattr("app.services.embedding_service._create_embeddings", _fake_embed(None))

    empty = client.get("/api/search?q=sea", headers=headers)
    assert empty.status_code == 400        # index empty -> 400 pointing at index job

    stats = client.get("/api/search", headers=headers)   # no q: stats only
    assert stats.json()["indexed"] == 0 and stats.json()["pending"] == 2

    task_id = client.post("/api/search/index", headers=headers).json()["task_id"]
    status = _wait_task(client, task_id, headers)
    assert status["status"] == "completed"

    body = client.get("/api/search?q=sea", headers=headers).json()
    assert [r["filename"] for r in body["results"]] == ["img0.png", "img1.png"]
    assert body["results"][0]["score"] > body["results"][1]["score"]
    assert body["indexed"] == 2 and body["pending"] == 0

    limited = client.get("/api/search?q=sea&min_score=0.5", headers=headers).json()
    assert [r["filename"] for r in limited["results"]] == ["img0.png"]


def test_reindex_after_caption_edit(client, dataset, monkeypatch):
    headers = dataset["headers"]
    _set_caption(client, headers, "img0.png", "a person by the sea")
    monkeypatch.setattr("app.services.embedding_service._create_embeddings", _fake_embed(None))
    _wait_task(client, client.post("/api/search/index", headers=headers).json()["task_id"], headers)
    assert client.get("/api/search", headers=headers).json()["pending"] == 0

    _set_caption(client, headers, "img0.png", "a car on the road")
    assert client.get("/api/search", headers=headers).json()["pending"] == 1
    _wait_task(client, client.post("/api/search/index", headers=headers).json()["task_id"], headers)

    body = client.get("/api/search?q=car", headers=headers).json()
    assert body["results"][0]["filename"] == "img0.png"
    assert body["pending"] == 0
```

The caption PUT endpoint (`/api/captions`) takes `{filename, content, caption_type}` — confirm against `app/routers/captions.py` before relying on it; if the payload differs, use the same shape its tests use.

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && .venv/bin/python -m pytest tests/test_search_api.py -q`
Expected: FAIL — `POST /api/search/index` → 404.

- [ ] **Step 3: Add index/search to the service**

Append to `backend/app/services/embedding_service.py`:

```python
import asyncio

from app.config import embedding_endpoint_settings
from app.services import task_service

# keyed by sqlite file path: {"rev", "model", "ids", "mat"}
# ponytail: brute-force cosine, fine to ~50k images/dataset; upgrade = sqlite-vec/ANN
_matrix_cache: dict[str, dict] = {}


async def index_dataset(session, task_id: str) -> None:
    db = session.db
    settings = embedding_endpoint_settings()
    model = settings["model"]
    task_service.start_task(task_id)
    todo, _fresh = compute_index_plan(db, model)
    total = len(todo)
    failures = 0
    done = 0
    for start in range(0, total, BATCH_SIZE):
        if task_service.is_cancelled(task_id):
            break
        await task_service.wait_if_paused(task_id)
        chunk = todo[start:start + BATCH_SIZE]
        try:
            vecs = await asyncio.to_thread(embed_texts, [t for _, t in chunk], settings)
        except Exception:
            failures += len(chunk)
            done += len(chunk)
            continue
        for (image_id, text), vec in zip(chunk, vecs):
            row = ImageRepository.get_by_id(db, image_id)
            VectorRepository.upsert(
                db, image_id, model, len(vec),
                np.asarray(vec, dtype=np.float32).tobytes(),
                hashlib.sha256(text.encode("utf-8")).hexdigest(),
            )
            if row:
                task_service.update_progress(
                    task_id, done + 1, total, done, row["filename"], "ok")
        db.commit()
        done += len(chunk)
    keep = {
        r["image_id"]
        for r in db.execute("SELECT DISTINCT image_id FROM captions WHERE content != ''")
    }
    VectorRepository.delete_missing(db, keep)
    db.commit()
    task_service.complete_task(
        task_id, error=f"{failures} images failed to embed" if failures else None
    )


async def embed_one(session, image_id: int) -> None:
    """Embed (or refresh) a single image's combined caption — batch-hook entry."""
    settings = embedding_endpoint_settings()
    text = caption_text(session.db, image_id)
    if not text:
        return
    vec = await asyncio.to_thread(embed_texts, [text], settings)
    VectorRepository.upsert(
        session.db, image_id, settings["model"], len(vec[0]),
        np.asarray(vec[0], dtype=np.float32).tobytes(),
        hashlib.sha256(text.encode("utf-8")).hexdigest(),
    )
    session.db.commit()


def _matrix(db, model: str) -> tuple[list[int], np.ndarray]:
    path = db.execute("PRAGMA database_list").fetchone()[2]
    rev = VectorRepository.revision(db)
    entry = _matrix_cache.get(path)
    if entry and entry["rev"] == rev and entry["model"] == model:
        return entry["ids"], entry["mat"]
    ids: list[int] = []
    vecs: list[np.ndarray] = []
    for r in VectorRepository.load_all(db):
        if r["model"] != model:
            continue
        ids.append(r["image_id"])
        vecs.append(np.frombuffer(r["embedding"], dtype=np.float32))
    mat = np.vstack(vecs) if vecs else np.zeros((0, 0), dtype=np.float32)
    _matrix_cache[path] = {"rev": rev, "model": model, "ids": ids, "mat": mat}
    return ids, mat


def search(session, query: str, limit: int = 200, min_score: float = 0.0):
    """Ranked hits or None when the index is empty."""
    from app.services.attribute_service import index_for_filename

    db = session.db
    settings = embedding_endpoint_settings()
    ids, mat = _matrix(db, settings["model"])
    if mat.shape[0] == 0:
        return None
    q = embed_texts([query], settings)
    sims = mat @ q[0]
    results = []
    for i in np.argsort(-sims):
        if len(results) >= limit or sims[i] < min_score:
            break
        row = ImageRepository.get_by_id(db, ids[int(i)])
        if row is None:
            continue
        idx = index_for_filename(session, row["filename"])
        if idx is None:
            continue
        results.append({"index": idx, "filename": row["filename"], "score": float(sims[i])})
    return results
```

Note: `index_for_filename(session, filename)` takes a base-dir-relative filename — same call the attributes router uses.

- [ ] **Step 4: Add the router**

Create `backend/app/routers/search.py`:

```python
from fastapi import APIRouter, Depends, HTTPException

from app.models.session import Session
from app.routers.attributes import _require_db
from app.services import task_service
from app.services.embedding_service import (
    compute_index_plan,
    embedding_endpoint_settings,
    indexed_count,
    index_dataset,
    search,
)
from app.sessions import get_session

router = APIRouter(prefix="/api/search", tags=["search"])


@router.get("")
def search_images(
    q: str = "",
    limit: int = 200,
    min_score: float = 0.0,
    session: Session = Depends(get_session),
):
    _require_db(session)
    settings = embedding_endpoint_settings()
    model = settings["model"]
    pending = len(compute_index_plan(session.db, model)[0])
    indexed = indexed_count(session.db, model)
    if not q.strip():
        return {"results": [], "indexed": indexed, "pending": pending, "model": model}
    try:
        results = search(session, q.strip(), min(limit, 500), min_score)
    except Exception as e:
        raise HTTPException(502, f"embedding endpoint error: {e}")
    if results is None:
        raise HTTPException(400, "search index is empty, index captions first")
    return {"results": results, "indexed": indexed, "pending": pending, "model": model}


@router.post("/index")
async def start_index(session: Session = Depends(get_session)):
    _require_db(session)
    model = embedding_endpoint_settings()["model"]
    total = len(compute_index_plan(session.db, model)[0])
    task_id = task_service.create_task(
        max(total, 1),
        name="Caption embedding index",
        operation="caption_embedding_index",
    )

    async def run():
        await index_dataset(session, task_id)

    task_service.submit(task_id, run)
    return {"task_id": task_id}
```

(`_require_db` — if it is defined in `app/routers/attributes.py` as a module-level private helper, import it as shown; otherwise use the same pattern attributes.py uses to guard `session.db`. `create_task` signature: check `task_service.create_task` — match how `routers/attributes.py` calls it, including `project_name` if present.)

- [ ] **Step 5: Register the router**

In `backend/app/main.py`, add `search` to the existing `from app.routers import ...` line and add `app.include_router(search.router)` beside the others.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && .venv/bin/python -m pytest tests/test_search_api.py -q` → PASS.

- [ ] **Step 7: Run the full backend suite**

Run: `cd backend && .venv/bin/python -m pytest -q --ignore=tests/test_openai_tagger.py --ignore=tests/test_ideogram_tagger.py`
Expected: all pass except the 2 pre-existing `test_white_balance.py` failures.

- [ ] **Step 8: Commit**

```bash
cd backend && git add app/services/embedding_service.py app/routers/search.py app/main.py tests/test_search_api.py
git commit -m "Add semantic search API and caption embedding index job"
```

---

### Task 6: Batch captioning hook (`embed_captions`)

**Files:**
- Modify: `backend/app/models/schemas.py` (`BatchProcessRequest`)
- Modify: `backend/app/routers/batch.py` (caption loop)
- Test: `backend/tests/test_batch_embed.py` (create)

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_batch_embed.py` (copy the `dataset` fixture + `_wait_task` from `tests/test_attributes_api.py` as in Task 5):

```python
def test_batch_embed_captions(client, dataset, monkeypatch):
    headers = dataset["headers"]
    embedded = []

    def fake(texts, settings):
        embedded.extend(texts)
        return [[1.0, 0.0] for _ in texts]

    def fake_caption(index, tagger, state_dict, prompt=None):
        return f"a description {index}"

    monkeypatch.setattr("app.services.embedding_service._create_embeddings", fake)
    monkeypatch.setattr("lib.captioning.generate_caption", fake_caption)
    r = client.post(
        "/api/batch/captions",
        json={"caption_type": "tags", "skip_existing_captions": False,
              "classify_attributes": False, "embed_captions": True},
        headers=headers,
    )
    assert r.status_code == 200
    _wait_task(client, r.json()["task_id"], headers)
    assert embedded == ["a description 0", "a description 1", "a description 2"]
    stats = client.get("/api/search", headers=headers).json()
    assert stats["indexed"] == 3 and stats["pending"] == 0


def test_batch_embed_failure_does_not_abort(client, dataset, monkeypatch):
    headers = dataset["headers"]

    def fake_caption(index, tagger, state_dict, prompt=None):
        return f"a description {index}"

    def boom(texts, settings):
        raise RuntimeError("endpoint down")

    monkeypatch.setattr("app.services.embedding_service._create_embeddings", boom)
    monkeypatch.setattr("lib.captioning.generate_caption", fake_caption)
    r = client.post(
        "/api/batch/captions",
        json={"caption_type": "tags", "skip_existing_captions": False,
              "classify_attributes": False, "embed_captions": True},
        headers=headers,
    )
    status = _wait_task(client, r.json()["task_id"], headers)
    assert status["status"] in ("completed", "failed")
    # captions still saved
    cap = client.get("/api/captions?filename=img1.png", headers=headers).json()
    assert cap["content"] == "a description 1"
```

Adjust the batch endpoint path/payload (`/api/batch/captions`) to what `routers/batch.py` actually exposes for caption runs — mirror `tests/test_batch_attributes.py`.

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && .venv/bin/python -m pytest tests/test_batch_embed.py -q`
Expected: FAIL (unknown field `embed_captions` ignored and no embeddings called).

- [ ] **Step 3: Add the flag**

In `backend/app/models/schemas.py`, in `BatchProcessRequest` beside `classify_attributes`:

```python
    embed_captions: bool = False
```

- [ ] **Step 4: Wire the hook**

In `backend/app/routers/batch.py` caption loop, inside the branch that GENERATED a caption (the `else` of the skip path, right after `db_save_caption(...)` / the `attributes:` block — search for `attributes: none`), append:

```python
                if req.embed_captions and not caption_skipped:
                    from app.services.embedding_service import embed_one

                    row = ImageRepository.get_by_filename(
                        session.db,
                        os.path.relpath(item.media_path, ds.base_dir),
                    )
                    if row is not None:
                        try:
                            await embed_one(session, row["id"])
                            log_line.append("embedding: ok")
                        except Exception:
                            log_line.append("embedding: error")
```

(`caption_skipped` is the existing flag set by the skip-existing-captions logic; reuse it — only freshly generated captions get embedded, stale ones are the index job's job.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && .venv/bin/python -m pytest tests/test_batch_embed.py -q` → PASS. Then full suite as in Task 5 Step 7.

- [ ] **Step 6: Commit**

```bash
cd backend && git add app/models/schemas.py app/routers/batch.py tests/test_batch_embed.py
git commit -m "Embed captions during batch captioning when embed_captions is set"
```

---

### Task 7: Frontend types + API client

**Files:**
- Modify: `frontend/src/lib/types.ts`
- Modify: `frontend/src/lib/api.ts`

- [ ] **Step 1: Add types**

In `frontend/src/lib/types.ts` append:

```ts
export interface SearchResult {
  index: number;
  filename: string;
  score: number;
}

export interface SearchResponse {
  results: SearchResult[];
  indexed: number;
  pending: number;
  model: string;
}
```

and inside the existing `Settings` interface add:

```ts
  embedding_endpoint: { base_url: string; api_key: string; model: string; timeout?: number };
```

- [ ] **Step 2: Add api methods**

In `frontend/src/lib/api.ts`, beside the attribute methods (they use the shared `apiFetch` which already injects the session header):

```ts
  searchImages: (q: string, minScore = 0, limit = 200) => {
    const params = new URLSearchParams({ q, min_score: String(minScore), limit: String(limit) });
    return apiFetch<SearchResponse>(`/api/search?${params.toString()}`);
  },

  startIndexJob: () =>
    apiFetch<{ task_id: string }>("/api/search/index", { method: "POST" }),
```

Update the `import type { ... } from "./types"` line to include `SearchResponse`. Note: `searchImages` with empty `q` returns stats, but a 400 is thrown when the index is empty AND `q` is set — callers must handle `Response` errors; `apiFetch` already throws `Error(body.detail)` so the 400 detail string surfaces in catch blocks.

- [ ] **Step 3: Verify**

Run: `cd frontend && npx tsc --noEmit` → no NEW errors.

- [ ] **Step 4: Commit**

```bash
cd frontend && git add src/lib/types.ts src/lib/api.ts
git commit -m "Add search API client and types"
```

---

### Task 8: Settings page — embedding endpoint section

**Files:**
- Modify: `frontend/src/app/settings/page.tsx`

- [ ] **Step 1: Add the section**

Copy the pattern of the existing VLM endpoint block (base_url / model / api_key inputs that mutate `localSettings` on change and call `save("vlm_endpoint", ...)` on blur). Add a section titled "Semantic search (embeddings)" after it:

```tsx
        <div className="space-y-4">
          <h3 className="text-sm font-semibold text-text">Semantic search (embeddings)</h3>
          <div className="space-y-1">
            <label className="text-xs text-text-secondary">Base URL</label>
            <Input
              value={localSettings.embedding_endpoint?.base_url ?? ""}
              onChange={(e) => {
                const ee = { ...(localSettings.embedding_endpoint ?? { base_url: "", api_key: "", model: "" }), base_url: e.target.value };
                setLocalSettings({ ...localSettings, embedding_endpoint: ee });
              }}
              onBlur={() => save("embedding_endpoint", localSettings.embedding_endpoint)}
            />
          </div>
          <div className="space-y-1">
            <label className="text-xs text-text-secondary">Model</label>
            <Input
              value={localSettings.embedding_endpoint?.model ?? ""}
              onChange={(e) => {
                const ee = { ...(localSettings.embedding_endpoint ?? { base_url: "", api_key: "", model: "" }), model: e.target.value };
                setLocalSettings({ ...localSettings, embedding_endpoint: ee });
              }}
              onBlur={() => save("embedding_endpoint", localSettings.embedding_endpoint)}
            />
          </div>
          <div className="space-y-1">
            <label className="text-xs text-text-secondary">API key</label>
            <Input
              type="password"
              value={localSettings.embedding_endpoint?.api_key ?? ""}
              onChange={(e) => {
                const ee = { ...(localSettings.embedding_endpoint ?? { base_url: "", api_key: "", model: "" }), api_key: e.target.value };
                setLocalSettings({ ...localSettings, embedding_endpoint: ee });
              }}
              onBlur={() => save("embedding_endpoint", localSettings.embedding_endpoint)}
            />
          </div>
        </div>
```

(If `localSettings.embedding_endpoint` can be `undefined` before first save, the `??` fallbacks above cover it; if `Settings` type requires it non-optional and the backend always merges DEFAULTS, simplify.)

- [ ] **Step 2: Verify**

Run: `cd frontend && npx tsc --noEmit && npm run lint` → no NEW errors.

- [ ] **Step 3: Commit**

```bash
cd frontend && git add src/app/settings/page.tsx
git commit -m "Add embedding endpoint settings section"
```

---

### Task 9: Browse grid search UI

**Files:**
- Modify: `frontend/src/components/browse/GalleryGrid.tsx`

- [ ] **Step 1: Search state + query**

In the `GalleryGrid` component (where `attrFilters` state lives, ~line 743), add:

```tsx
  const [searchQuery, setSearchQuery] = useState("");
  const [submittedSearch, setSubmittedSearch] = useState("");

  const { data: searchStats } = useQuery({
    queryKey: ["search-stats", total],
    queryFn: () => api.searchImages(""),
  });

  const searchQuery_ = useQuery({
    queryKey: ["search", submittedSearch],
    queryFn: () => api.searchImages(submittedSearch),
    enabled: submittedSearch.trim().length > 0,
  });
```

(Names: whatever fits — `searchQuery`/`submittedSearch` just distinguish the input value from the debounced-submitted one. The `["gallery", "all", total]` query already loads every item for client-side filtering; results map through it.)

- [ ] **Step 2: Debounce submit + result-mode items**

```tsx
  useEffect(() => {
    const t = setTimeout(() => setSubmittedSearch(searchQuery), 500);
    return () => clearTimeout(t);
  }, [searchQuery]);

  const allItems = data?.items ?? [];   // the existing ["gallery","all"] query result

  const searchScores = useMemo(
    () => new Map((searchQuery_.data?.results ?? []).map((r) => [r.index, r.score])),
    [searchQuery_.data],
  );

  const searchItems: GalleryItem[] | null = useMemo(() => {
    if (!submittedSearch.trim()) return null;
    const res = searchQuery_.data?.results;
    if (!res) return [];
    const byIndex = new Map(allItems.map((it) => [it.index, it]));
    return res.map((r) => byIndex.get(r.index)).filter((it): it is GalleryItem => !!it);
  }, [submittedSearch, searchQuery_.data, allItems]);
```

Where the component currently renders `items` (the attr-filtered list): when `searchItems !== null`, use the attr-filters intersected with `searchItems` instead of the full gallery list (one-line change at the existing `filtered` memo's source list). Pass `searchScores` down so each tile renders a badge when a score exists:

```tsx
  {searchScores.size > 0 && (
    <span className="absolute left-1 top-1 rounded bg-black/60 px-1 text-[10px] text-white">
      {searchScores.get(item.index)!.toFixed(2)}
    </span>
  )}
```

- [ ] **Step 3: Search box + index button in the toolbar**

Beside the `Filters` chip in the toolbar row:

```tsx
        <div className="flex items-center gap-2">
          <Input
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Semantic search..."
            className="h-7 w-48 text-xs"
          />
          {searchQuery && (
            <button type="button" className="text-xs text-text-secondary" onClick={() => setSearchQuery("")}>
              clear
            </button>
          )}
          {(searchStats?.pending ?? 0) > 0 && (
            <button
              type="button"
              className="h-7 rounded-lg border border-input px-2 text-xs text-text-secondary"
              onClick={async () => {
                try {
                  await api.startIndexJob();
                  toast(`Indexing ${searchStats?.pending} captions`);
                } catch (e) {
                  toast.error(e instanceof Error ? e.message : "Index failed");
                }
              }}
            >
              Index {searchStats?.pending} captions
            </button>
          )}
        </div>
```

On search error (e.g. 400 empty index): show `searchQuery_.error` via the same toast pattern. After the index job finishes, invalidate `["search-stats"]` and `["search"]` (the Jobs drawer's completion already invalidates queries — add these two keys where it invalidates `["gallery"]`).

- [ ] **Step 4: Verify**

Run: `cd frontend && npx tsc --noEmit && npm run lint` → no NEW errors.

- [ ] **Step 5: Commit**

```bash
cd frontend && git add src/components/browse/GalleryGrid.tsx
git commit -m "Add semantic search box with scores and index button to browse"
```

---

### Task 10: Live verification, config, push

- [ ] **Step 1: Seed the embedding endpoint for this machine**

```bash
cd backend && .venv/bin/python - <<'EOF'
from app.config import get_setting, update_setting
s = get_setting("embedding_endpoint") or {}
llm = get_setting("llm_endpoint")
s.setdefault("base_url", llm["base_url"]); s.setdefault("api_key", llm.get("api_key", ""))
s.setdefault("model", "qwen3-embedding-8b"); s.setdefault("timeout", 120)
update_setting("embedding_endpoint", s); print(s["base_url"], s["model"])
EOF
```

- [ ] **Step 2: End-to-end against the real dataset** (backend has `--reload`, so it is live once committed; use a fresh session each curl since reloads kill sessions)

```bash
SID=$(curl -s -X POST http://localhost:8000/api/projects/open -H 'Content-Type: application/json' -d '{"path":"/mnt/sd_encrypted/datasets/characters/ashleyt/ashleyt_it2"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["session_id"])')
curl -s -X POST -H "X-Session-ID: $SID" http://localhost:8000/api/search/index   # job over ~699 captions
# poll: curl -s -H "X-Session-ID: $SID" http://localhost:8000/api/tasks/<task_id>
curl -s -H "X-Session-ID: $SID" "http://localhost:8000/api/search?q=looking%20over%20shoulder" | python3 -m json.tool | head -30
```

Expected: sensible ranked results (top hits are captions mentioning shoulders/turning), `pending: 0` after the job.

- [ ] **Step 3: Push submodules and bump root**

```bash
cd backend && git push
cd ../frontend && git push
cd .. && git add backend frontend && git commit -m "Bump submodules: semantic search (caption embeddings)" && git push
```

(The PRs from the attributes branch auto-update only if this work goes on `feature/image-attributes`; if starting a fresh branch, name it `feature/semantic-search` in both submodules + root and open new PRs.)

---

## Self-review notes

- Spec coverage: data model (T1), settings (T2), embed/retry (T3), combined text/staleness/orphans (T4/T5), API incl. stats+400 (T5), batch hook incl. error policy (T6), UI incl. scores/clear/intersection/debounce/index-button (T7-T9), error handling (T3/T5/T6 tests), out-of-scope honored.
- `caption_skipped` variable name in batch.py must be confirmed by the implementer against the actual loop (introduced by the attributes work — if it was named differently, match reality).
- Cache key is the sqlite file path via `PRAGMA database_list` — safe because one process per backend and revisions checked per call.

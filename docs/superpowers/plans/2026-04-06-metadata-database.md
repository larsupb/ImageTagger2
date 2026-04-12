# Metadata Database Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local SQLite metadata database (`.imagetagger/metadata.db`) that becomes the source of truth for captions (multiple types), image versioning, and bookmarks.

**Architecture:** New `backend/app/db/` package with schema, connection management, and repository layer. Services switch from filesystem-based caption/bookmark I/O to repository queries. The `Session` dataclass gains a `db` connection field. Image versions are backed up to `.imagetagger/versions/` before destructive operations.

**Tech Stack:** Python stdlib `sqlite3`, existing FastAPI/Pydantic stack. No new dependencies.

**Design spec:** `docs/superpowers/specs/2026-04-06-metadata-database-design.md`

---

### Task 1: Create DB Schema and Connection Module

**Files:**
- Create: `backend/app/db/__init__.py`
- Create: `backend/app/db/schema.py`
- Create: `backend/app/db/connection.py`

- [ ] **Step 1: Create the schema module**

Create `backend/app/db/schema.py`:

```python
SCHEMA_VERSION = 1

SCHEMA_SQL = """
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS schema_info (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS images (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    filename TEXT NOT NULL UNIQUE,
    width INTEGER,
    height INTEGER,
    file_size INTEGER,
    file_hash TEXT,
    is_bookmarked INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS captions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    caption_type TEXT NOT NULL,
    content TEXT NOT NULL DEFAULT '',
    is_active INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(image_id, caption_type)
);

CREATE INDEX IF NOT EXISTS idx_captions_type_active ON captions(caption_type, is_active);

CREATE TABLE IF NOT EXISTS image_versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    version_path TEXT NOT NULL,
    operation TEXT NOT NULL,
    original_width INTEGER,
    original_height INTEGER,
    original_size INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_versions_image ON image_versions(image_id);

CREATE TABLE IF NOT EXISTS metadata (
    image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    value TEXT,
    PRIMARY KEY(image_id, key)
);
"""


def create_schema(db) -> None:
    db.executescript(SCHEMA_SQL)
    db.execute(
        "INSERT OR IGNORE INTO schema_info (key, value) VALUES (?, ?)",
        ("schema_version", str(SCHEMA_VERSION)),
    )
    db.commit()
```

- [ ] **Step 2: Create the connection module**

Create `backend/app/db/connection.py`:

```python
import os
import sqlite3

from app.db.schema import create_schema, SCHEMA_VERSION

PROJECT_CONFIG_DIR = ".imagetagger"
DB_FILENAME = "metadata.db"


def open_db(dataset_path: str) -> sqlite3.Connection:
    db_dir = os.path.join(dataset_path, PROJECT_CONFIG_DIR)
    os.makedirs(db_dir, exist_ok=True)
    db_path = os.path.join(db_dir, DB_FILENAME)

    is_new = not os.path.exists(db_path)
    db = sqlite3.connect(db_path, check_same_thread=False)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA foreign_keys=ON")

    if is_new:
        create_schema(db)
    else:
        _check_and_migrate(db)

    return db


def close_db(db: sqlite3.Connection) -> None:
    if db:
        db.close()


def _check_and_migrate(db) -> None:
    try:
        row = db.execute(
            "SELECT value FROM schema_info WHERE key = 'schema_version'"
        ).fetchone()
        if row is None:
            create_schema(db)
            return
        version = int(row["value"])
    except sqlite3.OperationalError:
        create_schema(db)
        return

    if version < SCHEMA_VERSION:
        _run_migrations(db, version)


def _run_migrations(db, from_version: int) -> None:
    migrations = {
        # 1: _migrate_v1_to_v2,
    }
    for v in range(from_version, SCHEMA_VERSION):
        if v in migrations:
            migrations[v](db)
    db.execute(
        "UPDATE schema_info SET value = ? WHERE key = 'schema_version'",
        (str(SCHEMA_VERSION),),
    )
    db.commit()
```

- [ ] **Step 3: Create the package init**

Create `backend/app/db/__init__.py`:

```python
from app.db.connection import open_db, close_db
```

- [ ] **Step 4: Verify manually**

Run from `backend/`:
```bash
source .venv/bin/activate
python -c "
from app.db import open_db, close_db
import tempfile, os
d = tempfile.mkdtemp()
db = open_db(d)
tables = [r[0] for r in db.execute(\"SELECT name FROM sqlite_master WHERE type='table'\").fetchall()]
print('Tables:', tables)
assert 'images' in tables
assert 'captions' in tables
assert 'image_versions' in tables
assert 'metadata' in tables
assert 'schema_info' in tables
close_db(db)
import shutil; shutil.rmtree(d)
print('OK')
"
```

- [ ] **Step 5: Commit**

```bash
git add backend/app/db/
git commit -m "feat: add SQLite metadata database schema and connection module"
```

---

### Task 2: Create Repository Layer

**Files:**
- Create: `backend/app/db/repository.py`

- [ ] **Step 1: Create ImageRepository**

Create `backend/app/db/repository.py`:

```python
import sqlite3
from typing import Optional


class ImageRepository:
    @staticmethod
    def ensure_image(db: sqlite3.Connection, filename: str, **attrs) -> int:
        row = db.execute(
            "SELECT id FROM images WHERE filename = ?", (filename,)
        ).fetchone()
        if row:
            return row["id"]
        cols = ["filename"] + list(attrs.keys())
        placeholders = ", ".join(["?"] * len(cols))
        col_names = ", ".join(cols)
        values = [filename] + list(attrs.values())
        cursor = db.execute(
            f"INSERT INTO images ({col_names}) VALUES ({placeholders})", values
        )
        db.commit()
        return cursor.lastrowid

    @staticmethod
    def get_by_filename(db: sqlite3.Connection, filename: str) -> Optional[dict]:
        row = db.execute(
            "SELECT * FROM images WHERE filename = ?", (filename,)
        ).fetchone()
        return dict(row) if row else None

    @staticmethod
    def get_by_id(db: sqlite3.Connection, image_id: int) -> Optional[dict]:
        row = db.execute(
            "SELECT * FROM images WHERE id = ?", (image_id,)
        ).fetchone()
        return dict(row) if row else None

    @staticmethod
    def update_metadata(
        db: sqlite3.Connection,
        image_id: int,
        width: int = None,
        height: int = None,
        file_size: int = None,
        file_hash: str = None,
    ) -> None:
        updates = []
        values = []
        if width is not None:
            updates.append("width = ?")
            values.append(width)
        if height is not None:
            updates.append("height = ?")
            values.append(height)
        if file_size is not None:
            updates.append("file_size = ?")
            values.append(file_size)
        if file_hash is not None:
            updates.append("file_hash = ?")
            values.append(file_hash)
        if not updates:
            return
        updates.append("updated_at = datetime('now')")
        values.append(image_id)
        db.execute(
            f"UPDATE images SET {', '.join(updates)} WHERE id = ?", values
        )
        db.commit()

    @staticmethod
    def set_bookmarked(db: sqlite3.Connection, image_id: int, value: bool) -> None:
        db.execute(
            "UPDATE images SET is_bookmarked = ?, updated_at = datetime('now') WHERE id = ?",
            (1 if value else 0, image_id),
        )
        db.commit()

    @staticmethod
    def is_bookmarked(db: sqlite3.Connection, filename: str) -> bool:
        row = db.execute(
            "SELECT is_bookmarked FROM images WHERE filename = ?", (filename,)
        ).fetchone()
        return bool(row["is_bookmarked"]) if row else False

    @staticmethod
    def get_all_filenames(db: sqlite3.Connection) -> set[str]:
        rows = db.execute("SELECT filename FROM images").fetchall()
        return {row["filename"] for row in rows}

    @staticmethod
    def delete_by_filename(db: sqlite3.Connection, filename: str) -> None:
        db.execute("DELETE FROM images WHERE filename = ?", (filename,))
        db.commit()

    @staticmethod
    def rename(db: sqlite3.Connection, old_filename: str, new_filename: str) -> None:
        db.execute(
            "UPDATE images SET filename = ?, updated_at = datetime('now') WHERE filename = ?",
            (new_filename, old_filename),
        )
        db.commit()


class CaptionRepository:
    @staticmethod
    def get(db: sqlite3.Connection, image_id: int, caption_type: str) -> Optional[str]:
        row = db.execute(
            "SELECT content FROM captions WHERE image_id = ? AND caption_type = ?",
            (image_id, caption_type),
        ).fetchone()
        return row["content"] if row else None

    @staticmethod
    def get_active(db: sqlite3.Connection, image_id: int) -> Optional[tuple]:
        row = db.execute(
            "SELECT caption_type, content FROM captions WHERE image_id = ? AND is_active = 1",
            (image_id,),
        ).fetchone()
        return (row["caption_type"], row["content"]) if row else None

    @staticmethod
    def get_all_for_image(db: sqlite3.Connection, image_id: int) -> list[dict]:
        rows = db.execute(
            "SELECT caption_type, content, is_active FROM captions WHERE image_id = ? ORDER BY caption_type",
            (image_id,),
        ).fetchall()
        return [dict(r) for r in rows]

    @staticmethod
    def upsert(
        db: sqlite3.Connection,
        image_id: int,
        caption_type: str,
        content: str,
        is_active: Optional[bool] = None,
    ) -> None:
        existing = db.execute(
            "SELECT id, is_active FROM captions WHERE image_id = ? AND caption_type = ?",
            (image_id, caption_type),
        ).fetchone()

        if existing:
            if is_active is not None:
                db.execute(
                    "UPDATE captions SET content = ?, is_active = ?, updated_at = datetime('now') WHERE id = ?",
                    (content, 1 if is_active else 0, existing["id"]),
                )
            else:
                db.execute(
                    "UPDATE captions SET content = ?, updated_at = datetime('now') WHERE id = ?",
                    (content, existing["id"]),
                )
        else:
            active = 1 if is_active else 0
            db.execute(
                "INSERT INTO captions (image_id, caption_type, content, is_active) VALUES (?, ?, ?, ?)",
                (image_id, caption_type, content, active),
            )
        db.commit()

    @staticmethod
    def set_active(db: sqlite3.Connection, image_id: int, caption_type: str) -> None:
        db.execute(
            "UPDATE captions SET is_active = 0 WHERE image_id = ?", (image_id,)
        )
        db.execute(
            "UPDATE captions SET is_active = 1 WHERE image_id = ? AND caption_type = ?",
            (image_id, caption_type),
        )
        db.commit()

    @staticmethod
    def get_all_by_type(db: sqlite3.Connection, caption_type: str) -> list[dict]:
        rows = db.execute(
            "SELECT i.filename, c.content FROM captions c JOIN images i ON c.image_id = i.id WHERE c.caption_type = ?",
            (caption_type,),
        ).fetchall()
        return [dict(r) for r in rows]

    @staticmethod
    def get_all_active(db: sqlite3.Connection) -> list[dict]:
        rows = db.execute(
            "SELECT i.filename, c.caption_type, c.content FROM captions c JOIN images i ON c.image_id = i.id WHERE c.is_active = 1",
        ).fetchall()
        return [dict(r) for r in rows]


class VersionRepository:
    @staticmethod
    def create(
        db: sqlite3.Connection,
        image_id: int,
        version_path: str,
        operation: str,
        original_width: int = None,
        original_height: int = None,
        original_size: int = None,
    ) -> int:
        cursor = db.execute(
            "INSERT INTO image_versions (image_id, version_path, operation, original_width, original_height, original_size) VALUES (?, ?, ?, ?, ?, ?)",
            (image_id, version_path, operation, original_width, original_height, original_size),
        )
        db.commit()
        return cursor.lastrowid

    @staticmethod
    def get_for_image(db: sqlite3.Connection, image_id: int) -> list[dict]:
        rows = db.execute(
            "SELECT * FROM image_versions WHERE image_id = ? ORDER BY created_at DESC",
            (image_id,),
        ).fetchall()
        return [dict(r) for r in rows]

    @staticmethod
    def get_by_id(db: sqlite3.Connection, version_id: int) -> Optional[dict]:
        row = db.execute(
            "SELECT * FROM image_versions WHERE id = ?", (version_id,)
        ).fetchone()
        return dict(row) if row else None

    @staticmethod
    def delete(db: sqlite3.Connection, version_id: int) -> None:
        db.execute("DELETE FROM image_versions WHERE id = ?", (version_id,))
        db.commit()
```

- [ ] **Step 2: Verify manually**

```bash
source .venv/bin/activate
python -c "
from app.db import open_db, close_db
from app.db.repository import ImageRepository, CaptionRepository
import tempfile, shutil
d = tempfile.mkdtemp()
db = open_db(d)
img_id = ImageRepository.ensure_image(db, 'test.jpg', width=800, height=600)
print('Image ID:', img_id)
CaptionRepository.upsert(db, img_id, 'tags', '1girl, solo, blue hair', is_active=True)
CaptionRepository.upsert(db, img_id, 'natural_language', 'A girl with blue hair')
captions = CaptionRepository.get_all_for_image(db, img_id)
print('Captions:', captions)
active = CaptionRepository.get_active(db, img_id)
print('Active:', active)
close_db(db)
shutil.rmtree(d)
print('OK')
"
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/db/repository.py
git commit -m "feat: add repository layer for images, captions, and versions"
```

---

### Task 3: Create Filesystem Sync (Auto-Import)

**Files:**
- Create: `backend/app/db/sync.py`
- Modify: `backend/app/db/__init__.py`

- [ ] **Step 1: Create the sync module**

Create `backend/app/db/sync.py`:

```python
import json
import logging
import os
from typing import Optional

from app.db.repository import ImageRepository, CaptionRepository

logger = logging.getLogger(__name__)


def sync_db_with_filesystem(db, dataset) -> dict:
    existing_filenames = ImageRepository.get_all_filenames(db)
    dataset_filenames = set()
    added = 0
    removed = 0

    for i in range(len(dataset)):
        item = dataset.get_item(i)
        if not item:
            continue
        rel_path = os.path.relpath(item.media_path, dataset.base_dir)
        dataset_filenames.add(rel_path)

        if rel_path not in existing_filenames:
            image_id = ImageRepository.ensure_image(db, rel_path)
            _import_caption_file(db, image_id, item)
            added += 1

    stale = existing_filenames - dataset_filenames
    for filename in stale:
        ImageRepository.delete_by_filename(db, filename)
        removed += 1

    _import_bookmarks(db, dataset)

    logger.info(
        f"DB sync: {added} added, {removed} removed, {len(dataset_filenames)} total"
    )
    return {"added": added, "removed": removed, "total": len(dataset_filenames)}


def _import_caption_file(db, image_id: int, item) -> None:
    if not os.path.exists(item.caption_path):
        return
    try:
        with open(item.caption_path, "r", encoding="utf-8") as f:
            content = f.read().strip()
        if content:
            CaptionRepository.upsert(db, image_id, "tags", content, is_active=True)
    except Exception as e:
        logger.warning(f"Failed to import caption for {item.filename}: {e}")


def _import_bookmarks(db, dataset) -> None:
    bookmarks_path = os.path.join(dataset.base_dir, "bookmarks.json")
    if not os.path.exists(bookmarks_path):
        return
    try:
        with open(bookmarks_path, "r", encoding="utf-8") as f:
            bookmarks = json.load(f)
        for filename, is_bm in bookmarks.items():
            if not is_bm:
                continue
            row = db.execute(
                "SELECT id FROM images WHERE filename = ?", (filename,)
            ).fetchone()
            if row:
                ImageRepository.set_bookmarked(db, row["id"], True)
    except Exception as e:
        logger.warning(f"Failed to import bookmarks: {e}")
```

- [ ] **Step 2: Update the package init**

Update `backend/app/db/__init__.py`:

```python
from app.db.connection import open_db, close_db
from app.db.sync import sync_db_with_filesystem
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/db/sync.py backend/app/db/__init__.py
git commit -m "feat: add filesystem sync to auto-import captions and bookmarks into DB"
```

---

### Task 4: Integrate DB into Session Lifecycle

**Files:**
- Modify: `backend/app/sessions.py`
- Modify: `backend/app/services/dataset_service.py`
- Modify: `backend/app/routers/projects.py`

- [ ] **Step 1: Add db field to Session dataclass**

In `backend/app/sessions.py`, add the import and field:

```python
# Add to imports at top
import sqlite3
```

Add field to the `Session` dataclass (after the `upscaled_index` field, line 25):

```python
    upscaled_index: Optional[int] = None
    db: Optional[sqlite3.Connection] = None
```

In the `delete` method of `SessionManager` (line 58-60), close the DB connection before removing:

```python
    def delete(self, session_id: str):
        with self._lock:
            session = self._sessions.pop(session_id, None)
            if session and session.db:
                try:
                    session.db.close()
                except Exception:
                    pass
```

In `cleanup_all` (line 62-64), close all DB connections:

```python
    def cleanup_all(self):
        with self._lock:
            for s in self._sessions.values():
                if s.db:
                    try:
                        s.db.close()
                    except Exception:
                        pass
            self._sessions.clear()
```

In `cleanup_expired` (line 66-70), close DB connections of expired sessions:

```python
    def cleanup_expired(self):
        with self._lock:
            expired = [sid for sid, s in self._sessions.items() if s.is_expired]
            for sid in expired:
                session = self._sessions[sid]
                if session.db:
                    try:
                        session.db.close()
                    except Exception:
                        pass
                del self._sessions[sid]
```

- [ ] **Step 2: Initialize DB in dataset_service.load_dataset**

In `backend/app/services/dataset_service.py`, add the DB initialization after `session.dataset = dataset`:

Add import at top:
```python
from app.db import open_db, sync_db_with_filesystem
```

Modify `load_dataset` to add DB init after line 29 (`session.dataset = dataset`):

```python
def load_dataset(
    session: Session,
    path: str,
    masks_path: Optional[str] = None,
    only_missing_captions: bool = False,
    include_subdirectories: bool = False,
):
    dataset = ImageDataSet()
    dataset.load(
        path,
        masks_dir=masks_path,
        subdirectories=include_subdirectories,
        only_missing_captions=only_missing_captions,
    )
    session.dataset = dataset
    session.config = read_settings()

    session.db = open_db(path)
    sync_db_with_filesystem(session.db, dataset)
```

- [ ] **Step 3: Verify by opening a project**

Start the backend server and open a project via the frontend, or test with curl:

```bash
source .venv/bin/activate
python -c "
import os, sys
sys.path.insert(0, '.')
from app.sessions import Session
from app.services.dataset_service import load_dataset

# Use a test dataset path that has images with .txt captions
# Replace with an actual dataset path for testing
s = Session(id='test')
# load_dataset(s, '/path/to/test/dataset')
# print('DB tables:', [r[0] for r in s.db.execute(\"SELECT name FROM sqlite_master WHERE type='table'\").fetchall()])
# print('Image count:', s.db.execute('SELECT COUNT(*) FROM images').fetchone()[0])
# print('Caption count:', s.db.execute('SELECT COUNT(*) FROM captions').fetchone()[0])
print('Session db field exists:', hasattr(s, 'db'))
print('OK')
"
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/sessions.py backend/app/services/dataset_service.py
git commit -m "feat: integrate metadata DB into session lifecycle with auto-import on load"
```

---

### Task 5: Switch Caption Read/Write to DB

**Files:**
- Modify: `backend/app/models/schemas.py`
- Modify: `backend/app/services/caption_service.py`
- Modify: `backend/app/services/dataset_service.py`
- Modify: `backend/app/routers/captions.py`

- [ ] **Step 1: Add new schemas**

In `backend/app/models/schemas.py`, add after the `MediaItemResponse` class (around line 35):

```python
class CaptionEntry(BaseModel):
    caption_type: str
    content: str
    is_active: bool
```

Extend `MediaItemResponse` to include captions list (add after the `caption` field):

```python
    caption: str
    captions: list[CaptionEntry] = []
```

Extend `CaptionSaveRequest` to include caption_type:

```python
class CaptionSaveRequest(BaseModel):
    index: int
    caption: str
    caption_type: str = "tags"
```

Add a new request model for setting active caption type:

```python
class SetActiveCaptionRequest(BaseModel):
    index: int
    caption_type: str
```

Add a new request model for caption export:

```python
class ExportCaptionsTxtRequest(BaseModel):
    caption_type: str = "tags"
```

- [ ] **Step 2: Rewrite caption_service to use DB**

Replace the entire content of `backend/app/services/caption_service.py`:

```python
import json
import logging
import os
import re
from datetime import datetime
from typing import Optional

from app.sessions import Session
from app.db.repository import ImageRepository, CaptionRepository

logger = logging.getLogger(__name__)


def _get_image_id(session: Session, index: int) -> Optional[int]:
    ds = session.dataset
    item = ds.get_item(index)
    if not item:
        return None
    rel_path = os.path.relpath(item.media_path, ds.base_dir)
    row = ImageRepository.get_by_filename(session.db, rel_path)
    return row["id"] if row else None


def _rel_path(session: Session, index: int) -> str:
    ds = session.dataset
    item = ds.get_item(index)
    return os.path.relpath(item.media_path, ds.base_dir)


def save_caption(session: Session, index: int, caption: str, caption_type: str = "tags") -> bool:
    image_id = _get_image_id(session, index)
    if image_id is None:
        return False
    CaptionRepository.upsert(session.db, image_id, caption_type, caption)
    return True


def read_caption(session: Session, index: int, caption_type: str = None) -> str:
    image_id = _get_image_id(session, index)
    if image_id is None:
        return ""
    if caption_type:
        content = CaptionRepository.get(session.db, image_id, caption_type)
        return content if content else ""
    active = CaptionRepository.get_active(session.db, image_id)
    return active[1] if active else ""


def get_all_captions(session: Session, index: int) -> list[dict]:
    image_id = _get_image_id(session, index)
    if image_id is None:
        return []
    return CaptionRepository.get_all_for_image(session.db, image_id)


def set_active_caption_type(session: Session, index: int, caption_type: str) -> bool:
    image_id = _get_image_id(session, index)
    if image_id is None:
        return False
    CaptionRepository.set_active(session.db, image_id, caption_type)
    return True


def get_tag_cloud(session: Session, sort_by: str = "frequency", caption_type: str = "tags") -> list[dict]:
    rows = CaptionRepository.get_all_by_type(session.db, caption_type)
    tag_counts: dict[str, int] = {}
    for row in rows:
        content = row["content"]
        if not content:
            continue
        tags = [t.strip() for t in content.split(",") if t.strip()]
        for tag in tags:
            tag_counts[tag] = tag_counts.get(tag, 0) + 1

    items = [{"tag": tag, "count": count} for tag, count in tag_counts.items()]
    if sort_by == "frequency":
        items.sort(key=lambda x: x["count"], reverse=True)
    else:
        items.sort(key=lambda x: x["tag"])
    return items


def remove_tags(session: Session, tags_to_remove: list[str], caption_type: str = "tags") -> int:
    rows = CaptionRepository.get_all_by_type(session.db, caption_type)
    tags_set = set(t.lower() for t in tags_to_remove)
    modified = 0
    for row in rows:
        content = row["content"]
        if not content:
            continue
        tags = [t.strip() for t in content.split(",") if t.strip()]
        new_tags = [t for t in tags if t.lower() not in tags_set]
        if len(new_tags) != len(tags):
            img = ImageRepository.get_by_filename(session.db, row["filename"])
            if img:
                CaptionRepository.upsert(session.db, img["id"], caption_type, ", ".join(new_tags))
                modified += 1
    return modified


def append_tag(session: Session, tag: str, caption_type: str = "tags") -> int:
    rows = CaptionRepository.get_all_by_type(session.db, caption_type)
    modified = 0
    for row in rows:
        content = row["content"]
        existing_tags = [t.strip() for t in content.split(",") if t.strip()] if content else []
        if tag not in existing_tags:
            existing_tags.append(tag)
            img = ImageRepository.get_by_filename(session.db, row["filename"])
            if img:
                CaptionRepository.upsert(session.db, img["id"], caption_type, ", ".join(existing_tags))
                modified += 1
    return modified


def prepend_tag(session: Session, tag: str, caption_type: str = "tags") -> int:
    rows = CaptionRepository.get_all_by_type(session.db, caption_type)
    modified = 0
    for row in rows:
        content = row["content"]
        existing_tags = [t.strip() for t in content.split(",") if t.strip()] if content else []
        if tag not in existing_tags:
            existing_tags.insert(0, tag)
            img = ImageRepository.get_by_filename(session.db, row["filename"])
            if img:
                CaptionRepository.upsert(session.db, img["id"], caption_type, ", ".join(existing_tags))
                modified += 1
    return modified


def search_replace_preview(session: Session, search: str, replace: str, caption_type: str = "tags") -> dict:
    ds = session.dataset
    rows = CaptionRepository.get_all_by_type(session.db, caption_type)
    matches = []
    for row in rows:
        content = row["content"]
        if not content or search not in content:
            continue
        new_content = content.replace(search, replace)
        matches.append({
            "index": _index_for_filename(ds, row["filename"]),
            "filename": os.path.basename(row["filename"]),
            "before": content,
            "after": new_content,
        })
    return {"matches": matches, "total_matches": len(matches)}


def search_replace_apply(session: Session, search: str, replace: str, caption_type: str = "tags") -> int:
    rows = CaptionRepository.get_all_by_type(session.db, caption_type)
    modified = 0
    for row in rows:
        content = row["content"]
        if not content or search not in content:
            continue
        new_content = content.replace(search, replace)
        img = ImageRepository.get_by_filename(session.db, row["filename"])
        if img:
            CaptionRepository.upsert(session.db, img["id"], caption_type, new_content)
            modified += 1
    return modified


def replace_underscores(session: Session, caption_type: str = "tags") -> int:
    rows = CaptionRepository.get_all_by_type(session.db, caption_type)
    modified = 0
    for row in rows:
        content = row["content"]
        if not content or "_" not in content:
            continue
        img = ImageRepository.get_by_filename(session.db, row["filename"])
        if img:
            CaptionRepository.upsert(session.db, img["id"], caption_type, content.replace("_", " "))
            modified += 1
    return modified


def cleanup_tags(session: Session, caption_type: str = "tags") -> int:
    unwanted_patterns = [
        r"\d+girl",
        r"\d+boy",
        "solo",
        "looking at viewer",
    ]
    rows = CaptionRepository.get_all_by_type(session.db, caption_type)
    modified = 0
    for row in rows:
        content = row["content"]
        if not content:
            continue
        tags = [t.strip() for t in content.split(",") if t.strip()]
        new_tags = []
        for tag in tags:
            skip = False
            for pattern in unwanted_patterns:
                if re.match(pattern, tag.lower()):
                    skip = True
                    break
            if not skip:
                new_tags.append(tag)
        if len(new_tags) != len(tags):
            img = ImageRepository.get_by_filename(session.db, row["filename"])
            if img:
                CaptionRepository.upsert(session.db, img["id"], caption_type, ", ".join(new_tags))
                modified += 1
    return modified


def export_to_jsonl(session: Session) -> dict:
    ds = session.dataset
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    export_path = os.path.join(ds.base_dir, f"captions_export_{timestamp}.jsonl")
    count = 0
    with open(export_path, "w", encoding="utf-8") as f:
        for i in range(len(ds)):
            item = ds.get_item(i)
            caption = read_caption(session, i)
            record = {
                "filename": item.filename,
                "caption": caption,
                "has_mask": item.mask_exists(),
            }
            f.write(json.dumps(record) + "\n")
            count += 1
    return {"path": export_path, "count": count}


def export_captions_to_txt(session: Session, caption_type: str = "tags") -> int:
    ds = session.dataset
    rows = CaptionRepository.get_all_by_type(session.db, caption_type)
    count = 0
    for row in rows:
        media_path = os.path.join(ds.base_dir, row["filename"])
        txt_path = os.path.splitext(media_path)[0] + ".txt"
        content = row["content"] or ""
        with open(txt_path, "w", encoding="utf-8") as f:
            f.write(content)
        count += 1
    return count


def move_to_subdirectory(
    session: Session, tags: list[str], inverse: bool, subdirectory_name: str
) -> int:
    ds = session.dataset
    tags_set = set(t.lower() for t in tags)
    target_dir = os.path.join(ds.base_dir, subdirectory_name)
    os.makedirs(target_dir, exist_ok=True)

    moved = 0
    indices_to_move = []
    for i in range(len(ds)):
        caption = read_caption(session, i)
        if not caption:
            continue
        image_tags = set(t.strip().lower() for t in caption.split(",") if t.strip())
        has_match = bool(image_tags & tags_set)
        if (has_match and not inverse) or (not has_match and inverse):
            indices_to_move.append(i)

    for i in reversed(indices_to_move):
        item = ds.get_item(i)
        old_rel = os.path.relpath(item.media_path, ds.base_dir)
        ds.copy_item(i, target_dir)
        ds.delete_item(i)
        ImageRepository.delete_by_filename(session.db, old_rel)
        moved += 1

    return moved


def _index_for_filename(ds, rel_filename: str) -> int:
    basename = os.path.basename(rel_filename)
    for i in range(len(ds)):
        item = ds.get_item(i)
        if item and item.filename == basename:
            return i
    return -1
```

- [ ] **Step 3: Update dataset_service.get_media_item_response to include captions from DB**

In `backend/app/services/dataset_service.py`, update the imports and `get_media_item_response`:

Add import:
```python
from app.db.repository import ImageRepository, CaptionRepository
from app.services.caption_service import read_caption, get_all_captions
```

Replace `get_media_item_response`:

```python
def get_media_item_response(session: Session, index: int) -> dict:
    ds = session.dataset
    item: MediaItem = ds.get_item(index)
    caption = read_caption(session, index)
    all_captions = get_all_captions(session, index)

    rel_path = os.path.relpath(item.media_path, ds.base_dir)
    is_bookmarked = False
    if session.db:
        is_bookmarked = ImageRepository.is_bookmarked(session.db, rel_path)

    width, height, file_size = None, None, None
    try:
        file_size = os.path.getsize(item.media_path)
        if item.is_image:
            with Image.open(item.media_path) as img:
                width, height = img.size
    except Exception:
        pass

    return {
        "index": index,
        "filename": item.filename,
        "basename": item.basename,
        "extension": item.extension,
        "is_video": item.is_video,
        "is_image": item.is_image,
        "has_caption": bool(caption),
        "has_mask": item.mask_exists(),
        "is_bookmarked": is_bookmarked,
        "width": width,
        "height": height,
        "file_size": file_size,
        "media_url": f"/api/media/file/{index}",
        "thumbnail_url": f"/api/media/thumbnail/{index}",
        "caption": caption,
        "captions": [
            {"caption_type": c["caption_type"], "content": c["content"], "is_active": bool(c["is_active"])}
            for c in all_captions
        ],
    }
```

- [ ] **Step 4: Update captions router**

Replace `backend/app/routers/captions.py` to use the new caption_service functions and add new endpoints:

```python
from fastapi import APIRouter, Depends, HTTPException

from app.sessions import Session, get_session
from app.models.schemas import (
    CaptionSaveRequest,
    TagCloudEntry,
    TagOperationRequest,
    AppendTagRequest,
    SearchReplaceRequest,
    SearchReplacePreview,
    MoveToSubdirRequest,
    ExportResponse,
    SetActiveCaptionRequest,
    ExportCaptionsTxtRequest,
)
from app.services import caption_service

router = APIRouter(prefix="/api/captions", tags=["captions"])


@router.put("/save")
def save_caption(req: CaptionSaveRequest, session: Session = Depends(get_session)):
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    caption_service.save_caption(session, req.index, req.caption, req.caption_type)
    return {"ok": True}


@router.put("/set-active")
def set_active(req: SetActiveCaptionRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    caption_service.set_active_caption_type(session, req.index, req.caption_type)
    return {"ok": True}


@router.get("/tags", response_model=list[TagCloudEntry])
def tag_cloud(sort_by: str = "frequency", session: Session = Depends(get_session)):
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    return caption_service.get_tag_cloud(session, sort_by)


@router.post("/tags/remove")
def remove_tags(req: TagOperationRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    modified = caption_service.remove_tags(session, req.tags)
    return {"modified": modified}


@router.post("/tags/append")
def append_tag(req: AppendTagRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    modified = caption_service.append_tag(session, req.tag)
    return {"modified": modified}


@router.post("/tags/prepend")
def prepend_tag(req: AppendTagRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    modified = caption_service.prepend_tag(session, req.tag)
    return {"modified": modified}


@router.post("/tags/cleanup")
def cleanup_tags_ep(session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    modified = caption_service.cleanup_tags(session)
    return {"modified": modified}


@router.post("/tags/replace-underscores")
def replace_underscores_ep(session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    modified = caption_service.replace_underscores(session)
    return {"modified": modified}


@router.post("/search-replace/preview", response_model=SearchReplacePreview)
def search_replace_preview(
    req: SearchReplaceRequest, session: Session = Depends(get_session)
):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    return caption_service.search_replace_preview(session, req.search, req.replace)


@router.post("/search-replace/apply")
def search_replace_apply(
    req: SearchReplaceRequest, session: Session = Depends(get_session)
):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    modified = caption_service.search_replace_apply(session, req.search, req.replace)
    return {"modified": modified}


@router.post("/export", response_model=ExportResponse)
def export_jsonl(session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    return caption_service.export_to_jsonl(session)


@router.post("/export-txt")
def export_captions_txt(req: ExportCaptionsTxtRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    count = caption_service.export_captions_to_txt(session, req.caption_type)
    return {"count": count}


@router.post("/move-to-subdir")
def move_to_subdirectory(
    req: MoveToSubdirRequest, session: Session = Depends(get_session)
):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    moved = caption_service.move_to_subdirectory(
        session, req.tags, req.inverse, req.subdirectory_name
    )
    return {"moved": moved}
```

- [ ] **Step 5: Commit**

```bash
git add backend/app/models/schemas.py backend/app/services/caption_service.py backend/app/services/dataset_service.py backend/app/routers/captions.py
git commit -m "feat: switch caption read/write to DB, add multi-type caption support"
```

---

### Task 6: Switch Bookmarks to DB

**Files:**
- Modify: `backend/app/routers/dataset.py`
- Modify: `backend/app/services/dataset_service.py`

- [ ] **Step 1: Update bookmark toggle in dataset router**

In `backend/app/routers/dataset.py`, add imports:

```python
from app.db.repository import ImageRepository
```

Replace the `toggle_bookmark` endpoint (line 78-84):

```python
@router.post("/bookmark/{index}")
def toggle_bookmark(index: int, session: Session = Depends(get_session)):
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    item = ds.get_item(index)
    if not item:
        raise HTTPException(404, "Item not found")
    rel_path = os.path.relpath(item.media_path, ds.base_dir)
    current = ImageRepository.is_bookmarked(session.db, rel_path)
    row = ImageRepository.get_by_filename(session.db, rel_path)
    if row:
        ImageRepository.set_bookmarked(session.db, row["id"], not current)
    return {"is_bookmarked": not current}
```

Add `import os` to imports if not present.

- [ ] **Step 2: Update gallery to read bookmarks from DB**

In `backend/app/routers/dataset.py`, update the gallery endpoint (line 50-75) to read bookmarks from DB:

```python
@router.get("/gallery", response_model=GalleryResponse)
def gallery(
    page: int = 0, page_size: int = 50, session: Session = Depends(get_session)
):
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")

    start = page * page_size
    end = min(start + page_size, len(ds))
    items = []
    for i in range(start, end):
        item = ds.get_item(i)
        rel_path = os.path.relpath(item.media_path, ds.base_dir)
        is_bm = ImageRepository.is_bookmarked(session.db, rel_path) if session.db else False
        items.append(
            GalleryItem(
                index=i,
                thumbnail_url=f"/api/media/thumbnail/{i}",
                filename=item.filename,
                is_bookmarked=is_bm,
                has_caption=item.caption_exists(),
                width=item.width if hasattr(item, "width") else None,
                height=item.height if hasattr(item, "height") else None,
            )
        )

    return GalleryResponse(items=items, total=len(ds), page=page, page_size=page_size)
```

- [ ] **Step 3: Update delete and rename to sync DB**

In `backend/app/routers/dataset.py`, update `delete_item` and `rename_item`:

```python
@router.delete("/item/{index}")
def delete_item(index: int, session: Session = Depends(get_session)):
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    item = ds.get_item(index)
    if item:
        rel_path = os.path.relpath(item.media_path, ds.base_dir)
        ImageRepository.delete_by_filename(session.db, rel_path)
    ds.delete_item(index)
    return {"total_items": len(ds)}


@router.put("/item/{index}/rename")
def rename_item(index: int, new_name: str, session: Session = Depends(get_session)):
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    item = ds.get_item(index)
    old_rel = os.path.relpath(item.media_path, ds.base_dir) if item else None
    ds.rename_item(index, new_name)
    if old_rel and session.db:
        new_item = ds.get_item(index)
        new_rel = os.path.relpath(new_item.media_path, ds.base_dir)
        ImageRepository.rename(session.db, old_rel, new_rel)
    return get_media_item_response(session, index)
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/routers/dataset.py
git commit -m "feat: switch bookmarks to DB, sync delete/rename with metadata DB"
```

---

### Task 7: Update Batch Processing to Save Captions via DB

**Files:**
- Modify: `backend/app/routers/batch.py`

- [ ] **Step 1: Update batch caption saving**

In `backend/app/routers/batch.py`, the caption section (lines 111-122) currently calls `ds.save_caption()`. Update it to use the DB:

Add import at top:
```python
from app.services.caption_service import save_caption as db_save_caption
```

Replace the caption block in the event_generator (line 111-122):

```python
                if req.caption:
                    tagger_name = req.tagger
                    if tagger_name == "unified":
                        caption = getattr(req, "unified_caption", "") or ""
                    else:
                        from lib.captioning import generate_caption as gen_caption

                        caption = gen_caption(
                            i, tagger_name, {"dataset": session.dataset}
                        )
                    db_save_caption(session, i, caption, "tags")
                    log_lines.append(f"Caption: {caption[:50]}...")
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/routers/batch.py
git commit -m "feat: batch processing saves captions via metadata DB"
```

---

### Task 8: Add Image Version Service

**Files:**
- Create: `backend/app/services/version_service.py`
- Modify: `backend/app/models/schemas.py`

- [ ] **Step 1: Create version_service.py**

Create `backend/app/services/version_service.py`:

```python
import logging
import os
import shutil
from datetime import datetime

from PIL import Image

from app.sessions import Session
from app.db.repository import ImageRepository, VersionRepository

logger = logging.getLogger(__name__)

VERSIONS_DIR = "versions"


def _versions_dir(dataset_path: str) -> str:
    d = os.path.join(dataset_path, ".imagetagger", VERSIONS_DIR)
    os.makedirs(d, exist_ok=True)
    return d


def create_version_backup(session: Session, index: int, operation: str) -> Optional[int]:
    ds = session.dataset
    item = ds.get_item(index)
    if not item or not os.path.exists(item.media_path):
        return None

    rel_path = os.path.relpath(item.media_path, ds.base_dir)
    img_row = ImageRepository.get_by_filename(session.db, rel_path)
    if not img_row:
        return None

    width, height = None, None
    try:
        if item.is_image:
            with Image.open(item.media_path) as img:
                width, height = img.size
    except Exception:
        pass

    file_size = os.path.getsize(item.media_path)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    basename = os.path.splitext(os.path.basename(rel_path))[0]
    ext = os.path.splitext(rel_path)[1]
    version_filename = f"{basename}_{operation}_{timestamp}{ext}"

    versions_dir = _versions_dir(ds.base_dir)
    version_full_path = os.path.join(versions_dir, version_filename)
    shutil.copy2(item.media_path, version_full_path)

    version_rel_path = os.path.join(VERSIONS_DIR, version_filename)
    version_id = VersionRepository.create(
        session.db,
        img_row["id"],
        version_rel_path,
        operation,
        original_width=width,
        original_height=height,
        original_size=file_size,
    )

    logger.info(f"Created version backup: {version_rel_path} for {rel_path} ({operation})")
    return version_id


def restore_version(session: Session, version_id: int) -> bool:
    version = VersionRepository.get_by_id(session.db, version_id)
    if not version:
        return False

    ds = session.dataset
    img_row = ImageRepository.get_by_id(session.db, version["image_id"])
    if not img_row:
        return False

    version_full_path = os.path.join(ds.base_dir, ".imagetagger", version["version_path"])
    target_path = os.path.join(ds.base_dir, img_row["filename"])

    if not os.path.exists(version_full_path):
        logger.warning(f"Version file not found: {version_full_path}")
        return False

    shutil.copy2(version_full_path, target_path)

    if version["original_width"] and version["original_height"]:
        ImageRepository.update_metadata(
            session.db,
            img_row["id"],
            width=version["original_width"],
            height=version["original_height"],
            file_size=version["original_size"],
        )

    logger.info(f"Restored version {version_id} for {img_row['filename']}")
    return True


def get_versions(session: Session, index: int) -> list[dict]:
    ds = session.dataset
    item = ds.get_item(index)
    if not item:
        return []
    rel_path = os.path.relpath(item.media_path, ds.base_dir)
    img_row = ImageRepository.get_by_filename(session.db, rel_path)
    if not img_row:
        return []
    return VersionRepository.get_for_image(session.db, img_row["id"])


def delete_version(session: Session, version_id: int) -> bool:
    version = VersionRepository.get_by_id(session.db, version_id)
    if not version:
        return False

    ds = session.dataset
    version_full_path = os.path.join(ds.base_dir, ".imagetagger", version["version_path"])
    if os.path.exists(version_full_path):
        os.remove(version_full_path)

    VersionRepository.delete(session.db, version_id)
    return True
```

- [ ] **Step 2: Add the missing import**

Add at the top of `backend/app/services/version_service.py`:
```python
from typing import Optional
```

- [ ] **Step 3: Add version schema**

In `backend/app/models/schemas.py`, add:

```python
class ImageVersionEntry(BaseModel):
    id: int
    version_path: str
    operation: str
    original_width: Optional[int] = None
    original_height: Optional[int] = None
    original_size: Optional[int] = None
    created_at: str
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/services/version_service.py backend/app/models/schemas.py
git commit -m "feat: add image version service for backup and restore"
```

---

### Task 9: Integrate Versioning into Processing and Batch

**Files:**
- Modify: `backend/app/services/processing_service.py`
- Modify: `backend/app/routers/batch.py`
- Modify: `backend/app/routers/processing.py`

- [ ] **Step 1: Add version backup to processing_service**

In `backend/app/services/processing_service.py`, add import:

```python
from app.services.version_service import create_version_backup
```

In `save_upscaled` (line 38), add the backup call before overwriting:

```python
def save_upscaled(session: Session, index: int):
    if session.upscaled_image is None or session.upscaled_index != index:
        raise ValueError("No upscaled image cached for this index")

    create_version_backup(session, index, "upscale")

    ds = session.dataset
    item = ds.get_item(index)
    session.upscaled_image.save(item.media_path)
    session.upscaled_image = None
    session.upscaled_index = None
```

- [ ] **Step 2: Add version backup to batch processing**

In `backend/app/routers/batch.py`, add import:

```python
from app.services.version_service import create_version_backup
```

In the event_generator, add backup calls before destructive operations. Before the upscale block (line 55):

```python
                if req.upscale:
                    create_version_backup(session, i, "upscale")
                    from lib.upscaling import upscale_image
                    # ... rest of upscale code unchanged
```

Before the bucket_resize block (line 70):

```python
                if req.bucket_resize and bucket_map and i in bucket_map:
                    create_version_backup(session, i, "bucket_resize")
                    from lib.bucketing import resize_and_crop_to_bucket
                    # ... rest of bucket_resize code unchanged
```

- [ ] **Step 3: Add version endpoints to processing router**

In `backend/app/routers/processing.py`, add imports and new endpoints:

```python
from app.services.version_service import get_versions, restore_version, delete_version
from app.models.schemas import ImageVersionEntry
```

Add endpoints at the end of the file:

```python
@router.get("/versions/{index}", response_model=list[ImageVersionEntry])
def list_versions(index: int, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    return get_versions(session, index)


@router.post("/versions/{version_id}/restore")
def restore_ver(version_id: int, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    ok = restore_version(session, version_id)
    if not ok:
        raise HTTPException(404, "Version not found or restore failed")
    return {"ok": True}


@router.delete("/versions/{version_id}")
def delete_ver(version_id: int, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    ok = delete_version(session, version_id)
    if not ok:
        raise HTTPException(404, "Version not found")
    return {"ok": True}
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/services/processing_service.py backend/app/routers/batch.py backend/app/routers/processing.py
git commit -m "feat: auto-backup originals before upscale/resize, add version endpoints"
```

---

### Task 10: Update Gallery has_caption to Use DB

**Files:**
- Modify: `backend/app/routers/dataset.py`

The gallery currently checks `item.caption_exists()` which reads from the filesystem. Since DB is now the source of truth, update this.

- [ ] **Step 1: Update gallery has_caption check**

In `backend/app/routers/dataset.py`, update the gallery endpoint's inner loop to check captions from DB:

Add import:
```python
from app.db.repository import CaptionRepository
```

In the gallery items loop, replace `has_caption=item.caption_exists()`:

```python
        img_row = ImageRepository.get_by_filename(session.db, rel_path) if session.db else None
        has_caption = False
        if img_row:
            active = CaptionRepository.get_active(session.db, img_row["id"])
            has_caption = bool(active and active[1])
```

So the full gallery item construction becomes:

```python
        item = ds.get_item(i)
        rel_path = os.path.relpath(item.media_path, ds.base_dir)
        is_bm = ImageRepository.is_bookmarked(session.db, rel_path) if session.db else False
        img_row = ImageRepository.get_by_filename(session.db, rel_path) if session.db else None
        has_caption = False
        if img_row:
            active = CaptionRepository.get_active(session.db, img_row["id"])
            has_caption = bool(active and active[1])
        items.append(
            GalleryItem(
                index=i,
                thumbnail_url=f"/api/media/thumbnail/{i}",
                filename=item.filename,
                is_bookmarked=is_bm,
                has_caption=has_caption,
                width=item.width if hasattr(item, "width") else None,
                height=item.height if hasattr(item, "height") else None,
            )
        )
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/routers/dataset.py
git commit -m "feat: gallery reads captions and bookmarks from metadata DB"
```

---

### Task 11: Frontend Type and API Updates

**Files:**
- Modify: `frontend/src/lib/types.ts`
- Modify: `frontend/src/lib/api.ts`

- [ ] **Step 1: Add new types**

In `frontend/src/lib/types.ts`, add:

```typescript
export interface CaptionEntry {
  caption_type: string;
  content: string;
  is_active: boolean;
}

export interface ImageVersion {
  id: number;
  version_path: string;
  operation: string;
  original_width: number | null;
  original_height: number | null;
  original_size: number | null;
  created_at: string;
}
```

Add `captions` to the existing `MediaItem` interface:

```typescript
  captions: CaptionEntry[];
```

- [ ] **Step 2: Add API functions**

In `frontend/src/lib/api.ts`, add new functions (after existing caption-related functions):

```typescript
  async saveCaption(index: number, caption: string, captionType: string = "tags") {
    return apiFetch("/api/captions/save", {
      method: "PUT",
      body: JSON.stringify({ index, caption, caption_type: captionType }),
    });
  },

  async setActiveCaptionType(index: number, captionType: string) {
    return apiFetch("/api/captions/set-active", {
      method: "PUT",
      body: JSON.stringify({ index, caption_type: captionType }),
    });
  },

  async exportCaptionsTxt(captionType: string = "tags") {
    return apiFetch<{ count: number }>("/api/captions/export-txt", {
      method: "POST",
      body: JSON.stringify({ caption_type: captionType }),
    });
  },

  async getVersions(index: number) {
    return apiFetch<ImageVersion[]>(`/api/processing/versions/${index}`);
  },

  async restoreVersion(versionId: number) {
    return apiFetch("/api/processing/versions/${versionId}/restore", {
      method: "POST",
    });
  },

  async deleteVersion(versionId: number) {
    return apiFetch(`/api/processing/versions/${versionId}`, {
      method: "DELETE",
    });
  },
```

Note: The existing `saveCaption` function should be found and updated to include the `captionType` parameter. If it already exists with a different signature, update it rather than adding a duplicate.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/lib/types.ts frontend/src/lib/api.ts
git commit -m "feat: add frontend types and API functions for multi-caption and versioning"
```

---

### Task 12: End-to-End Verification

- [ ] **Step 1: Start the backend and test DB creation**

```bash
cd backend && source .venv/bin/activate && uvicorn app.main:app --reload --port 8000
```

Open a dataset via the frontend or curl:
```bash
curl -X POST http://localhost:8000/api/projects/open \
  -H "Content-Type: application/json" \
  -d '{"path": "/path/to/test/dataset"}'
```

Verify `.imagetagger/metadata.db` is created in the dataset directory.

- [ ] **Step 2: Verify caption import**

Using the session_id from step 1:
```bash
curl -H "X-Session-ID: <session_id>" http://localhost:8000/api/dataset/item/0
```

Verify the response includes `captions` array with imported tags.

- [ ] **Step 3: Test caption save with different type**

```bash
curl -X PUT http://localhost:8000/api/captions/save \
  -H "Content-Type: application/json" \
  -H "X-Session-ID: <session_id>" \
  -d '{"index": 0, "caption": "A beautiful landscape photo", "caption_type": "natural_language"}'
```

Verify the `.txt` file is unchanged, but re-fetching item/0 shows both caption types.

- [ ] **Step 4: Test caption export**

```bash
curl -X POST http://localhost:8000/api/captions/export-txt \
  -H "Content-Type: application/json" \
  -H "X-Session-ID: <session_id>" \
  -d '{"caption_type": "natural_language"}'
```

Verify `.txt` files now contain the natural language captions.

- [ ] **Step 5: Test version backup and restore**

Upscale an image and verify `.imagetagger/versions/` contains the original.
List versions:
```bash
curl -H "X-Session-ID: <session_id>" http://localhost:8000/api/processing/versions/0
```

- [ ] **Step 6: Test DB resilience**

Delete `metadata.db`, reopen the project, verify captions are re-imported from `.txt` files.

- [ ] **Step 7: Commit any fixes**

```bash
git add -A
git commit -m "fix: address issues found during end-to-end verification"
```

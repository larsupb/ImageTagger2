# Metadata Database Design Spec

## Context

ImageTagger2 currently stores image captions as `.txt` files (comma-separated tags) next to each image. This limits us to a single caption format, provides no way to store natural language descriptions alongside tag-based ones, and loses image history when destructive operations (upscale, resize) overwrite originals. The `.imagetagger/` folder already exists per-dataset for project config but holds only `project.json`.

This spec introduces a local SQLite database at `.imagetagger/metadata.db` that becomes the source of truth for all per-image metadata: multiple caption types, image versioning, bookmarks, and extensible key-value metadata.

## Database Location and Technology

- **Engine**: SQLite via Python stdlib `sqlite3` (zero new dependencies)
- **File**: `{dataset_path}/.imagetagger/metadata.db`
- **Mode**: WAL journal for concurrent read access
- **No ORM** -- thin repository layer with raw SQL

## Schema

```sql
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE schema_info (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE images (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    filename TEXT NOT NULL UNIQUE,  -- relative to dataset root
    width INTEGER,
    height INTEGER,
    file_size INTEGER,
    file_hash TEXT,
    is_bookmarked INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE captions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    caption_type TEXT NOT NULL,     -- "tags", "natural_language", "danbooru", etc.
    content TEXT NOT NULL DEFAULT '',
    is_active INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(image_id, caption_type)
);

CREATE INDEX idx_captions_type_active ON captions(caption_type, is_active);

CREATE TABLE image_versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    version_path TEXT NOT NULL,     -- relative to .imagetagger/versions/
    operation TEXT NOT NULL,        -- "upscale", "remove_background", "bucket_resize"
    original_width INTEGER,
    original_height INTEGER,
    original_size INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_versions_image ON image_versions(image_id);

CREATE TABLE metadata (
    image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    value TEXT,
    PRIMARY KEY(image_id, key)
);
```

Schema version tracked in `schema_info` table. Migrations run sequentially on open (`migrate_v1_to_v2()`, etc.) inside transactions.

## Caption Types

Each image can have multiple captions, one per `caption_type`. Exactly one is marked `is_active` -- this is the one exported to `.txt` files.

Built-in types:
- `tags` -- comma-separated tags (current format, imported from existing `.txt` files)
- `natural_language` -- prose description
- `danbooru` -- danbooru-style tag format

Users can also define custom types. The tagger engines map to caption types: JoyTag/WD14 produce `tags`, Florence-2 produces `natural_language`, etc.

## Auto-Import and Filesystem Sync

On every dataset open, run `sync_db_with_filesystem(db, dataset)`:

1. **First open** (images table empty): insert all media files into `images`, import `.txt` captions as `caption_type="tags"` with `is_active=true`, import `bookmarks.json` entries.
2. **Subsequent opens**: scan filesystem for new files not in DB (insert them), flag DB entries whose files are missing (mark or remove). This handles files added/removed outside the app.

## Image Versioning

Before any destructive operation (upscale, bucket resize), the original file is copied to `.imagetagger/versions/`:

- Path: `.imagetagger/versions/{filename}_{operation}_{timestamp}.{ext}`
- A row is inserted into `image_versions` with original dimensions and file size
- Restore copies the backup back to the original location and updates `images` metadata

Background removal already creates a new PNG file and does not overwrite, so no versioning needed for that operation.

## Integration Architecture

### DB Connection on Session

The `Session` dataclass gets a `db: Optional[sqlite3.Connection]` field. Connection is opened during project open and closed on session delete/expire.

```
Session
  ├── dataset: ImageDataSet    (filesystem abstraction for media files)
  ├── db: sqlite3.Connection   (metadata storage)
  └── config: dict             (settings)
```

### Service Layer Changes

**Caption operations** (`caption_service.py`): All functions switch from `ds.read_caption(i)` loops to single SQL queries through `CaptionRepository`. This is both a correctness change (DB is source of truth) and a performance win (one query vs N file reads).

**Processing operations** (`processing_service.py`): `save_upscaled()` calls `create_version_backup()` before overwriting. Same for batch upscale and bucket resize in `batch.py`.

**Bookmark operations**: Move from `bookmarks.json` file I/O to `ImageRepository.set_bookmarked()`.

**ImageDataSet** remains the filesystem abstraction for media files only. It no longer owns caption read/write.

### New Files

```
backend/app/db/
    __init__.py          # exports init_db(), sync_db_with_filesystem()
    connection.py        # open/close connection, WAL mode, pragmas
    schema.py            # CREATE TABLE statements, version constant
    migrations.py        # version check + sequential migration functions
    repository.py        # ImageRepository, CaptionRepository, VersionRepository

backend/app/services/
    version_service.py   # create_version_backup(), restore_version()
```

### Modified Files

| File | Change |
|------|--------|
| `backend/app/sessions.py` | Add `db` field to Session, close connection in cleanup |
| `backend/app/services/project_service.py` | DB init in open_project flow |
| `backend/app/services/caption_service.py` | All functions read/write via CaptionRepository |
| `backend/app/services/processing_service.py` | Version backup before destructive ops |
| `backend/app/routers/batch.py` | Version backup in batch loop |
| `backend/app/routers/captions.py` | Accept `caption_type` param, add export endpoint |
| `backend/app/routers/processing.py` | Add version list/restore endpoints |
| `backend/app/routers/dataset.py` | Bookmark via DB |
| `backend/app/models/schemas.py` | New schemas: CaptionEntry, ImageVersionEntry; extend MediaItemResponse |
| `backend/lib/image_dataset.py` | Remove bookmark file I/O (or deprecate) |
| `frontend/src/lib/types.ts` | Add CaptionEntry, ImageVersion types |
| `frontend/src/lib/api.ts` | Caption type param, version endpoints, export endpoint |
| `frontend/src/components/edit/CaptionEditor.tsx` | Caption type selector UI |

### API Changes

New endpoints:
- `POST /api/captions/export-txt` -- export a caption type to `.txt` files
- `GET /api/processing/versions/{index}` -- list version history for an image
- `POST /api/processing/versions/{version_id}/restore` -- restore a version

Modified endpoints:
- `PUT /api/captions/save` -- add optional `caption_type` field (default: active type)
- `GET /api/dataset/item/{index}` -- response includes `captions: CaptionEntry[]`
- All caption bulk operations accept optional `caption_type` parameter

### Frontend Changes

- **CaptionEditor**: Add tabs/dropdown for caption type selection. Switching type loads that type's content. Save writes to selected type.
- **VersionHistory panel**: Show version backups for current image with restore buttons. In the edit page sidebar or toolbar area.
- **Export UI**: Button in captions page to export a selected caption type to `.txt` files.

## Implementation Phases

### Phase 1: DB Foundation + Auto-Import
Create `backend/app/db/` package, schema, connection management, `sync_db_with_filesystem()`. Add `db` field to Session. Hook into project open flow. **Must ship as one unit.**

### Phase 2: Caption Read/Write via DB + Bookmarks
Switch all caption operations to use CaptionRepository. Move bookmarks to DB. Update schemas to include `caption_type`. This is the "flip the switch" phase where DB becomes the actual source of truth.

### Phase 3: Image Versioning
Add `version_service.py`, integrate backup into processing and batch operations. Add version list/restore API endpoints.

### Phase 4: Caption Export
Add `.txt` export endpoint. This is the escape hatch for training tool compatibility.

### Phase 5: Frontend
Caption type selector in editor. Version history panel. Export UI. Can be done incrementally per backend phase.

## Risks and Mitigations

**DB deleted/corrupted**: `sync_db_with_filesystem` re-creates from `.txt` files if DB is missing. After DB becomes source of truth, users should periodically export to `.txt` as a safety measure.

**Filesystem out of sync**: The sync function runs on every open, reconciling new/removed files.

**Concurrent sessions**: WAL mode handles concurrent readers + single writer without blocking.

## Verification

1. Open a dataset with existing `.txt` captions -- verify DB is created and captions imported
2. Add a natural language caption via API -- verify it's stored in DB, `.txt` file unchanged
3. Switch active caption type and export -- verify `.txt` files reflect the new type
4. Upscale an image -- verify original is backed up in `.imagetagger/versions/`
5. Restore a version -- verify image reverts to original dimensions
6. Delete `.imagetagger/metadata.db` and reopen -- verify captions are re-imported from `.txt` files
7. Add files to dataset folder externally, reopen -- verify new files appear in DB

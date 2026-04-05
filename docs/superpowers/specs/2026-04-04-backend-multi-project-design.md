# Backend Multi-Project Support — Design Spec

## Overview

Extend the backend to support full multi-project management with project config files, session persistence, recent projects tracking, and project-specific settings overrides. This is a prerequisite for the frontend redesign (spec: `2026-04-04-frontend-redesign-design.md`).

## Current State

The backend has a `SessionManager` with in-memory sessions but:
- No API to list or enumerate sessions
- No project metadata (name, display name)
- No session persistence across restarts
- No project config files
- No recent projects tracking
- No project-specific settings
- `cleanup_expired()` exists but is never called
- Session creation and dataset loading are two separate API calls

## Architecture

### Project Config File

Each dataset directory can contain a `.imagetagger/project.json` file:

```json
{
  "name": "My Dataset",
  "masks_path": "/path/to/masks",
  "settings_overrides": {
    "tagger": "florence2",
    "upscaler": "realesrgan-x4",
    "florence_prompt": "detailed"
  },
  "last_opened": "2026-04-04T12:00:00Z",
  "version": 1
}
```

- `name`: Display name for the project (defaults to directory basename)
- `masks_path`: Default masks directory path
- `settings_overrides`: Key-value pairs that override global settings when this project is loaded
- `last_opened`: ISO timestamp of last open
- `version`: Config file version for future migrations

### Global Projects Registry

Stored in `backend/data/projects.json`:

```json
{
  "projects": [
    {
      "id": "proj_abc123",
      "path": "/path/to/dataset",
      "name": "My Dataset",
      "last_opened": "2026-04-04T12:00:00Z",
      "open_count": 15
    }
  ],
  "version": 1
}
```

- Tracks all projects ever opened (not just active sessions)
- Used for "recent projects" list in frontend
- `id` is a stable identifier derived from the path hash
- `open_count` tracks how many times opened

### Session Model (Enhanced)

```python
@dataclass
class Session:
    id: str                          # UUID4
    project_id: str                  # Stable project ID from registry
    dataset: Optional[ImageDataSet]  # Loaded dataset
    config: dict                     # Merged settings (global + project overrides)
    created_at: float
    last_accessed: float
    upscaled_image: Optional[object]
    upscaled_index: Optional[int]
```

### Session Manager (Enhanced)

```python
class SessionManager:
    def create(self, project_id: str) -> Session
    def get(self, session_id: str) -> Optional[Session]
    def delete(self, session_id: str) -> None
    def list_active(self) -> list[SessionInfo]
    def cleanup_expired(self) -> None
    def cleanup_all(self) -> None
```

- `list_active()` returns lightweight `SessionInfo` objects (id, project_id, project_name, created_at, last_accessed)
- Background cleanup task runs every 5 minutes (configurable)
- TTL remains 3600 seconds from last access

### Settings Merge Logic

When a project is loaded:
1. Read global settings from `settings.json`
2. If project config exists, read `settings_overrides`
3. Merge: `effective_config = {**global_settings, **project_overrides}`
4. Store merged config in session
5. Project overrides are applied on top of global settings, not replacing them

## API Endpoints

### New Endpoints

#### `POST /api/projects/open`

Open a project (creates session + loads dataset in one call).

**Request:**
```json
{
  "path": "/path/to/dataset",
  "masks_path": "/optional/masks/path",
  "only_missing_captions": false,
  "include_subdirectories": false
}
```

**Response (200):**
```json
{
  "session_id": "uuid-here",
  "project_id": "proj_abc123",
  "project_name": "My Dataset",
  "dataset_info": {
    "total_items": 150,
    "base_dir": "/path/to/dataset",
    "masks_dir": "/optional/masks/path"
  }
}
```

**Behavior:**
1. Check if path exists and is a valid dataset directory
2. Look up or create project in registry
3. Create new session with project ID
4. Load dataset into session
5. Update project's `last_opened` timestamp
6. If project config exists, apply settings overrides
7. Return session ID + project info

#### `DELETE /api/projects/{session_id}`

Close a project session.

**Response (200):** `{"status": "closed"}`

**Behavior:**
1. Delete session from session manager
2. Clear upscaled image cache
3. Dataset is dereferenced (garbage collected)

#### `GET /api/projects`

List all active project sessions.

**Response (200):**
```json
{
  "projects": [
    {
      "session_id": "uuid-1",
      "project_id": "proj_abc123",
      "project_name": "Dataset A",
      "path": "/path/to/dataset/a",
      "total_items": 150,
      "current_index": 42,
      "created_at": 1712345678.0,
      "last_accessed": 1712349278.0
    }
  ]
}
```

#### `GET /api/projects/recent`

List recently opened projects (from registry, not just active sessions).

**Query params:** `limit` (default 10, max 50)

**Response (200):**
```json
{
  "projects": [
    {
      "project_id": "proj_abc123",
      "name": "My Dataset",
      "path": "/path/to/dataset",
      "last_opened": "2026-04-04T12:00:00Z",
      "open_count": 15,
      "is_active": true
    }
  ]
}
```

#### `PUT /api/projects/{project_id}/config`

Update project configuration (name, settings overrides, masks path).

**Request:**
```json
{
  "name": "New Name",
  "masks_path": "/new/masks/path",
  "settings_overrides": {
    "tagger": "florence2"
  }
}
```

**Response (200):** Updated project config

**Behavior:**
1. Update `.imagetagger/project.json` in dataset directory
2. If session is active, update session config with new overrides
3. Update registry entry

#### `DELETE /api/projects/recent/{project_id}`

Remove a project from the recent projects registry (does not close active session).

**Response (200):** `{"status": "removed"}`

### Existing Endpoints

All existing session-dependent endpoints continue to work unchanged via `X-Session-ID` header. No modifications needed to their signatures or behavior.

## File Structure

```
backend/
├── app/
│   ├── routers/
│   │   ├── projects.py          # New: project management endpoints
│   │   └── ...                  # Existing routers (unchanged)
│   ├── services/
│   │   ├── project_service.py   # New: project management logic
│   │   └── ...                  # Existing services (unchanged)
│   ├── models/
│   │   └── project.py           # New: Pydantic schemas for project API
│   ├── sessions.py              # Enhanced: project_id field, list_active()
│   ├── config.py                # Enhanced: settings merge logic
│   └── main.py                  # Enhanced: register projects router, background cleanup
├── data/
│   └── projects.json            # New: global projects registry
└── lib/
    └── ...                      # Existing utilities (unchanged)
```

## Project Config Discovery

When opening a project:
1. Check `{path}/.imagetagger/project.json` for existing config
2. If not found, create it with defaults (name = directory basename)
3. Load settings overrides if present
4. Update `last_opened` timestamp

## Background Cleanup

- Async task started during FastAPI lifespan
- Runs every 5 minutes (configurable via settings)
- Calls `session_manager.cleanup_expired()` to remove expired sessions
- On shutdown, calls `session_manager.cleanup_all()` (existing behavior)

## Error Handling

| Error | Status | Detail |
|-------|--------|--------|
| Path does not exist | 400 | "Dataset path not found" |
| Path is not a directory | 400 | "Dataset path is not a directory" |
| No media files found | 400 | "No supported media files found in directory" |
| Invalid session ID | 401 | "Invalid or expired session" |
| Project not in registry | 404 | "Project not found" |
| Config file write error | 500 | "Failed to save project config" |

## Migration Strategy

1. Create `ProjectService` with registry management (read/write `projects.json`)
2. Enhance `Session` dataclass with `project_id` field
3. Enhance `SessionManager` with `list_active()` method
4. Add background cleanup task to FastAPI lifespan
5. Create `projects.py` router with all new endpoints
6. Add project config file discovery and creation logic
7. Add settings merge logic to `config.py`
8. Update `dataset_service.load_dataset()` to accept and apply project overrides
9. Register new router in `main.py`
10. Test: open multiple projects, verify isolation, verify cleanup

## Backward Compatibility

- Existing `POST /api/dataset/session` endpoint remains for backward compatibility
- Existing `POST /api/dataset/load` endpoint remains for backward compatibility
- New `POST /api/projects/open` is the recommended approach for new frontend
- Both flows produce valid sessions that work with all existing endpoints
- `X-Session-ID` header requirement unchanged for all existing endpoints

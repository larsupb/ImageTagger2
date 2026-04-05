# Backend Multi-Project Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multi-project management API with project config files, session persistence, recent projects tracking, and project-specific settings overrides.

**Architecture:** Enhance the existing in-memory SessionManager with project metadata, add a project registry stored on disk, create project config files per dataset, and expose new REST endpoints for project lifecycle management. All existing endpoints remain unchanged and backward compatible.

**Tech Stack:** Python 3.11+, FastAPI, Pydantic v2, JSON file storage

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `backend/app/models/project.py` | Create | Pydantic schemas for project API requests/responses |
| `backend/app/services/project_service.py` | Create | Project management logic (registry, config files, settings merge) |
| `backend/app/routers/projects.py` | Create | Project management REST endpoints |
| `backend/app/sessions.py` | Modify | Add `project_id` to Session, add `list_active()` to SessionManager |
| `backend/app/config.py` | Modify | Add `merge_settings()` function for global + project overrides |
| `backend/app/services/dataset_service.py` | Modify | Accept optional project overrides when loading dataset |
| `backend/app/main.py` | Modify | Register projects router, add background cleanup task |
| `backend/data/projects.json` | Create (at runtime) | Global projects registry |

---

### Task 1: Project Models

**Files:**
- Create: `backend/app/models/project.py`

- [ ] **Step 1: Create Pydantic schemas for project API**

```python
from pydantic import BaseModel
from typing import Optional


class ProjectOpenRequest(BaseModel):
    path: str
    masks_path: Optional[str] = None
    only_missing_captions: bool = False
    include_subdirectories: bool = False


class ProjectDatasetInfo(BaseModel):
    total_items: int
    base_dir: str
    masks_dir: Optional[str]


class ProjectOpenResponse(BaseModel):
    session_id: str
    project_id: str
    project_name: str
    dataset_info: ProjectDatasetInfo


class ProjectCloseResponse(BaseModel):
    status: str


class ActiveProjectInfo(BaseModel):
    session_id: str
    project_id: str
    project_name: str
    path: str
    total_items: int
    current_index: int
    created_at: float
    last_accessed: float


class ActiveProjectsResponse(BaseModel):
    projects: list[ActiveProjectInfo]


class RecentProjectEntry(BaseModel):
    project_id: str
    name: str
    path: str
    last_opened: str
    open_count: int
    is_active: bool


class RecentProjectsResponse(BaseModel):
    projects: list[RecentProjectEntry]


class ProjectConfigUpdateRequest(BaseModel):
    name: Optional[str] = None
    masks_path: Optional[str] = None
    settings_overrides: Optional[dict] = None


class ProjectConfigResponse(BaseModel):
    name: str
    masks_path: Optional[str]
    settings_overrides: dict
    last_opened: str
    version: int
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/models/project.py
git commit -m "feat: add project API models"
```

---

### Task 2: Settings Merge Logic

**Files:**
- Modify: `backend/app/config.py`

- [ ] **Step 1: Add merge_settings function to config.py**

Read `backend/app/config.py` and add this function at the end:

```python
def merge_settings(project_overrides: Optional[dict] = None) -> dict:
    """Merge global settings with optional project-specific overrides."""
    global_settings = read_settings()
    if not project_overrides:
        return global_settings
    merged = dict(global_settings)
    _deep_merge(merged, project_overrides)
    return merged


def _deep_merge(base: dict, override: dict) -> None:
    """Recursively merge override dict into base dict in-place."""
    for key, value in override.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            _deep_merge(base[key], value)
        else:
            base[key] = value
```

Also add `from typing import Optional` at the top if not present.

- [ ] **Step 2: Commit**

```bash
git add backend/app/config.py
git commit -m "feat: add settings merge logic for project overrides"
```

---

### Task 3: Project Service

**Files:**
- Create: `backend/app/services/project_service.py`

- [ ] **Step 1: Create project service with registry and config management**

```python
import os
import json
import hashlib
from datetime import datetime, timezone
from typing import Optional
from pathlib import Path

from app.config import read_settings, merge_settings

PROJECTS_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "data")
PROJECTS_FILE = os.path.join(PROJECTS_DIR, "projects.json")
PROJECT_CONFIG_DIR = ".imagetagger"
PROJECT_CONFIG_FILE = "project.json"
PROJECT_CONFIG_VERSION = 1


def _ensure_projects_dir():
    os.makedirs(PROJECTS_DIR, exist_ok=True)


def _read_registry() -> dict:
    _ensure_projects_dir()
    if not os.path.exists(PROJECTS_FILE):
        return {"projects": [], "version": 1}
    with open(PROJECTS_FILE, "r") as f:
        return json.load(f)


def _write_registry(data: dict):
    _ensure_projects_dir()
    with open(PROJECTS_FILE, "w") as f:
        json.dump(data, f, indent=2)


def compute_project_id(path: str) -> str:
    """Stable project ID derived from absolute path hash."""
    abs_path = os.path.abspath(path)
    return "proj_" + hashlib.sha256(abs_path.encode()).hexdigest()[:12]


def get_project_config_path(dataset_path: str) -> str:
    return os.path.join(dataset_path, PROJECT_CONFIG_DIR, PROJECT_CONFIG_FILE)


def read_project_config(dataset_path: str) -> Optional[dict]:
    config_path = get_project_config_path(dataset_path)
    if not os.path.exists(config_path):
        return None
    with open(config_path, "r") as f:
        return json.load(f)


def write_project_config(dataset_path: str, config: dict):
    config_dir = os.path.join(dataset_path, PROJECT_CONFIG_DIR)
    os.makedirs(config_dir, exist_ok=True)
    config_path = os.path.join(config_dir, PROJECT_CONFIG_FILE)
    config["version"] = PROJECT_CONFIG_VERSION
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)


def create_or_update_project_config(dataset_path: str, name: Optional[str] = None, masks_path: Optional[str] = None) -> dict:
    """Create or update project config in dataset directory."""
    existing = read_project_config(dataset_path) or {}
    display_name = name or existing.get("name") or os.path.basename(os.path.abspath(dataset_path))
    config = {
        "name": display_name,
        "masks_path": masks_path or existing.get("masks_path"),
        "settings_overrides": existing.get("settings_overrides", {}),
        "last_opened": datetime.now(timezone.utc).isoformat(),
        "version": PROJECT_CONFIG_VERSION,
    }
    write_project_config(dataset_path, config)
    return config


def get_or_create_registry_entry(path: str, name: Optional[str] = None) -> dict:
    """Get existing registry entry or create new one."""
    project_id = compute_project_id(path)
    registry = _read_registry()
    for entry in registry["projects"]:
        if entry["project_id"] == project_id:
            entry["last_opened"] = datetime.now(timezone.utc).isoformat()
            entry["open_count"] = entry.get("open_count", 0) + 1
            if name:
                entry["name"] = name
            _write_registry(registry)
            return entry
    new_entry = {
        "project_id": project_id,
        "name": name or os.path.basename(os.path.abspath(path)),
        "path": os.path.abspath(path),
        "last_opened": datetime.now(timezone.utc).isoformat(),
        "open_count": 1,
    }
    registry["projects"].append(new_entry)
    _write_registry(registry)
    return new_entry


def remove_from_registry(project_id: str) -> bool:
    """Remove project from registry. Returns True if found and removed."""
    registry = _read_registry()
    before = len(registry["projects"])
    registry["projects"] = [p for p in registry["projects"] if p["project_id"] != project_id]
    if len(registry["projects"]) < before:
        _write_registry(registry)
        return True
    return False


def get_recent_projects(limit: int = 10) -> list[dict]:
    """Get recently opened projects sorted by last_opened descending."""
    registry = _read_registry()
    projects = sorted(registry["projects"], key=lambda p: p.get("last_opened", ""), reverse=True)
    return projects[:limit]


def update_project_config(dataset_path: str, name: Optional[str] = None, masks_path: Optional[str] = None, settings_overrides: Optional[dict] = None) -> dict:
    """Update project config with partial changes."""
    existing = read_project_config(dataset_path)
    if existing is None:
        return create_or_update_project_config(dataset_path, name=name, masks_path=masks_path)
    if name is not None:
        existing["name"] = name
    if masks_path is not None:
        existing["masks_path"] = masks_path
    if settings_overrides is not None:
        existing["settings_overrides"] = settings_overrides
    existing["last_opened"] = datetime.now(timezone.utc).isoformat()
    write_project_config(dataset_path, existing)
    return existing


def get_effective_settings(dataset_path: str) -> dict:
    """Get merged settings: global + project overrides."""
    config = read_project_config(dataset_path)
    overrides = config.get("settings_overrides", {}) if config else {}
    return merge_settings(overrides if overrides else None)
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/services/project_service.py
git commit -m "feat: add project service with registry and config management"
```

---

### Task 4: Enhance Session Manager

**Files:**
- Modify: `backend/app/sessions.py`

- [ ] **Step 1: Add project_id to Session dataclass**

Read `backend/app/sessions.py` and modify the Session dataclass:

```python
@dataclass
class Session:
    id: str
    project_id: str = ""
    dataset: Optional[ImageDataSet] = None
    config: dict = field(default_factory=dict)
    created_at: float = field(default_factory=time.time)
    last_accessed: float = field(default_factory=time.time)
    upscaled_image: Optional[object] = None
    upscaled_index: Optional[int] = None
```

- [ ] **Step 2: Update create() to accept project_id**

```python
def create(self, project_id: str = "") -> Session:
    session_id = str(uuid.uuid4())
    session = Session(id=session_id, project_id=project_id)
    with self._lock:
        self._sessions[session_id] = session
    return session
```

- [ ] **Step 3: Add list_active() method to SessionManager**

Add after `cleanup_expired()`:

```python
def list_active(self) -> list[dict]:
    """Return list of active (non-expired) sessions with basic info."""
    now = time.time()
    with self._lock:
        return [
            {
                "id": s.id,
                "project_id": s.project_id,
                "created_at": s.created_at,
                "last_accessed": s.last_accessed,
                "has_dataset": s.dataset is not None,
                "total_items": len(s.dataset) if s.dataset else 0,
                "current_index": s.dataset._current_index if s.dataset else 0,
            }
            for s in self._sessions.values()
            if now - s.last_accessed <= SESSION_TTL_SECONDS
        ]
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/sessions.py
git commit -m "feat: enhance session manager with project_id and list_active"
```

---

### Task 5: Projects Router

**Files:**
- Create: `backend/app/routers/projects.py`

- [ ] **Step 1: Create the projects router with all endpoints**

```python
import os
from fastapi import APIRouter, Depends, HTTPException

from app.sessions import Session, get_session, session_manager
from app.models.project import (
    ProjectOpenRequest,
    ProjectOpenResponse,
    ProjectDatasetInfo,
    ProjectCloseResponse,
    ActiveProjectInfo,
    ActiveProjectsResponse,
    RecentProjectEntry,
    RecentProjectsResponse,
    ProjectConfigUpdateRequest,
    ProjectConfigResponse,
)
from app.services.project_service import (
    compute_project_id,
    get_or_create_registry_entry,
    remove_from_registry,
    get_recent_projects,
    create_or_update_project_config,
    read_project_config,
    update_project_config,
    get_effective_settings,
)
from app.services.dataset_service import load_dataset
from app.config import read_settings

router = APIRouter(prefix="/api/projects", tags=["projects"])


@router.post("/open", response_model=ProjectOpenResponse)
def open_project(req: ProjectOpenRequest):
    """Open a project: creates session + loads dataset in one call."""
    path = os.path.abspath(req.path)
    if not os.path.exists(path):
        raise HTTPException(status_code=400, detail="Dataset path not found")
    if not os.path.isdir(path):
        raise HTTPException(status_code=400, detail="Dataset path is not a directory")

    # Get or create registry entry
    entry = get_or_create_registry_entry(path)
    project_id = entry["project_id"]
    project_name = entry["name"]

    # Create or update project config
    create_or_update_project_config(path, name=project_name, masks_path=req.masks_path)

    # Create session with project_id
    session = session_manager.create(project_id=project_id)

    # Load dataset into session
    load_dataset(
        session,
        path,
        req.masks_path,
        req.only_missing_captions,
        req.include_subdirectories,
    )

    # Apply project-specific settings overrides
    effective_settings = get_effective_settings(path)
    session.config = effective_settings

    ds = session.dataset
    return ProjectOpenResponse(
        session_id=session.id,
        project_id=project_id,
        project_name=project_name,
        dataset_info=ProjectDatasetInfo(
            total_items=len(ds),
            base_dir=ds._base_dir,
            masks_dir=ds._masks_dir,
        ),
    )


@router.delete("/{session_id}", response_model=ProjectCloseResponse)
def close_project(session_id: str):
    """Close a project session."""
    session = session_manager.get(session_id)
    if session is None:
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    session_manager.delete(session_id)
    return ProjectCloseResponse(status="closed")


@router.get("/", response_model=ActiveProjectsResponse)
def list_active_projects():
    """List all active project sessions."""
    active = session_manager.list_active()
    projects = []
    for info in active:
        if not info["has_dataset"]:
            continue
        # Get project name from registry
        registry_entries = get_recent_projects(limit=100)
        project_name = "Unknown"
        project_path = ""
        for entry in registry_entries:
            if entry["project_id"] == info["project_id"]:
                project_name = entry["name"]
                project_path = entry["path"]
                break
        projects.append(
            ActiveProjectInfo(
                session_id=info["id"],
                project_id=info["project_id"],
                project_name=project_name,
                path=project_path,
                total_items=info["total_items"],
                current_index=info["current_index"],
                created_at=info["created_at"],
                last_accessed=info["last_accessed"],
            )
        )
    return ActiveProjectsResponse(projects=projects)


@router.get("/recent", response_model=RecentProjectsResponse)
def recent_projects(limit: int = 10):
    """List recently opened projects from registry."""
    limit = min(limit, 50)
    recent = get_recent_projects(limit)
    active_sessions = session_manager.list_active()
    active_project_ids = {s["project_id"] for s in active_sessions}
    projects = [
        RecentProjectEntry(
            project_id=p["project_id"],
            name=p["name"],
            path=p["path"],
            last_opened=p["last_opened"],
            open_count=p.get("open_count", 0),
            is_active=p["project_id"] in active_project_ids,
        )
        for p in recent
    ]
    return RecentProjectsResponse(projects=projects)


@router.put("/{project_id}/config", response_model=ProjectConfigResponse)
def update_project_configuration(project_id: str, req: ProjectConfigUpdateRequest):
    """Update project configuration."""
    # Find the project path from registry
    recent = get_recent_projects(limit=200)
    project_entry = None
    for p in recent:
        if p["project_id"] == project_id:
            project_entry = p
            break
    if project_entry is None:
        raise HTTPException(status_code=404, detail="Project not found")

    config = update_project_config(
        project_entry["path"],
        name=req.name,
        masks_path=req.masks_path,
        settings_overrides=req.settings_overrides,
    )

    # If session is active, update its config
    active = session_manager.list_active()
    for info in active:
        if info["project_id"] == project_id:
            session = session_manager.get(info["id"])
            if session:
                session.config = get_effective_settings(project_entry["path"])

    return ProjectConfigResponse(
        name=config["name"],
        masks_path=config.get("masks_path"),
        settings_overrides=config.get("settings_overrides", {}),
        last_opened=config["last_opened"],
        version=config.get("version", 1),
    )


@router.delete("/recent/{project_id}")
def remove_recent_project(project_id: str):
    """Remove a project from the recent projects registry."""
    if not remove_from_registry(project_id):
        raise HTTPException(status_code=404, detail="Project not found")
    return {"status": "removed"}
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/routers/projects.py
git commit -m "feat: add projects router with open/close/list/recent/config endpoints"
```

---

### Task 6: Register Router and Add Background Cleanup

**Files:**
- Modify: `backend/app/main.py`

- [ ] **Step 1: Update main.py with projects router and background cleanup**

Replace the entire `main.py` with:

```python
import sys
import os
import asyncio

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware


async def background_cleanup():
    """Periodic cleanup of expired sessions."""
    from app.sessions import session_manager
    while True:
        await asyncio.sleep(300)  # Every 5 minutes
        session_manager.cleanup_expired()


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(background_cleanup())
    yield
    task.cancel()
    from app.sessions import session_manager
    session_manager.cleanup_all()


app = FastAPI(title="ImageTagger API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:3001"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from app.routers import dataset, media, captions, processing, tagging, batch, settings, projects

app.include_router(dataset.router)
app.include_router(media.router)
app.include_router(captions.router)
app.include_router(processing.router)
app.include_router(tagging.router)
app.include_router(batch.router)
app.include_router(settings.router)
app.include_router(projects.router)


@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/main.py
git commit -m "feat: register projects router and add background session cleanup"
```

---

### Task 7: Integration Test

**Files:**
- Test: Manual verification via curl or API client

- [ ] **Step 1: Start the backend server**

```bash
cd backend
uvicorn app.main:app --reload --port 8000
```

- [ ] **Step 2: Test project open**

```bash
curl -X POST http://localhost:8000/api/projects/open \
  -H "Content-Type: application/json" \
  -d '{"path": "/path/to/test/dataset"}'
```

Expected: 200 response with `session_id`, `project_id`, `project_name`, `dataset_info`.

- [ ] **Step 3: Test list active projects**

```bash
curl http://localhost:8000/api/projects/
```

Expected: 200 response with list containing the opened project.

- [ ] **Step 4: Test existing endpoints still work with the new session**

Use the `session_id` from Step 2:

```bash
curl http://localhost:8000/api/dataset/gallery?page=0&page_size=10 \
  -H "X-Session-ID: <session_id_from_step_2>"
```

Expected: 200 response with gallery items.

- [ ] **Step 5: Test backward compatibility — old session flow**

```bash
curl -X POST http://localhost:8000/api/dataset/session
```

Expected: 200 with `session_id`. Then load dataset with old endpoint:

```bash
curl -X POST http://localhost:8000/api/dataset/load \
  -H "Content-Type: application/json" \
  -H "X-Session-ID: <old_session_id>" \
  -d '{"path": "/path/to/test/dataset"}'
```

Expected: 200 with dataset info.

- [ ] **Step 6: Test close project**

```bash
curl -X DELETE http://localhost:8000/api/projects/<session_id>
```

Expected: 200 with `{"status": "closed"}`.

- [ ] **Step 7: Verify project config file was created**

```bash
cat /path/to/test/dataset/.imagetagger/project.json
```

Expected: JSON with `name`, `masks_path`, `settings_overrides`, `last_opened`, `version`.

- [ ] **Step 8: Verify projects registry was created**

```bash
cat backend/data/projects.json
```

Expected: JSON with `projects` array containing the opened project.

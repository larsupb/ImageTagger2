# ImageTagger Next.js + FastAPI Rewrite

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the Gradio-based ImageTagger application as a Next.js (Tailwind CSS) frontend with a FastAPI backend, preserving all existing functionality.

**Architecture:** The backend (FastAPI) handles all file I/O, AI model inference, dataset management, and image processing. The frontend (Next.js App Router + Tailwind CSS) provides the UI with client-side state management. Sessions are UUID-based with server-side dataset state. Server-Sent Events (SSE) stream progress for long-running batch operations. FastAPI serves media files (images, videos, thumbnails) directly.

**Tech Stack:** Python 3.11+, FastAPI, Uvicorn, Pydantic v2, PIL/Pillow, torch, transformers, spandrel, rembg, onnxruntime | Next.js 15 (App Router), React 19, TypeScript, Tailwind CSS 4, Zustand (client state), TanStack Query (server state)

---

## Scope Note

This plan covers the **full rewrite** organized into 6 phases. Each phase produces working, testable software. Phases are sequential — each builds on the previous. Within each phase, tasks are independent where possible.

The existing Python AI/image processing libraries (`lib/tagging/`, `lib/upscaling/`, `lib/masking.py`, `lib/bucketing.py`) are **reused as-is** — they are wrapped with FastAPI endpoints, not rewritten.

---

## Project Structure

```
image-tagger/
├── backend/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py                    # FastAPI app, CORS, lifespan
│   │   ├── config.py                  # Settings persistence (reuse existing logic)
│   │   ├── sessions.py                # Session manager (UUID → DatasetState)
│   │   ├── models/
│   │   │   ├── __init__.py
│   │   │   ├── schemas.py             # Pydantic request/response models
│   │   │   └── media_item.py          # MediaItem dataclass (reuse existing)
│   │   ├── routers/
│   │   │   ├── __init__.py
│   │   │   ├── dataset.py             # Dataset CRUD: load, navigate, list
│   │   │   ├── media.py               # Media serving: images, videos, thumbnails
│   │   │   ├── captions.py            # Caption CRUD + tag operations
│   │   │   ├── processing.py          # Upscale, mask, background removal
│   │   │   ├── batch.py               # Batch processing with SSE progress
│   │   │   ├── tagging.py             # AI caption generation
│   │   │   └── settings.py            # Settings CRUD
│   │   └── services/
│   │       ├── __init__.py
│   │       ├── dataset_service.py     # ImageDataSet wrapper
│   │       ├── caption_service.py     # Tag cloud, search/replace, JSONL export
│   │       ├── processing_service.py  # Upscale, mask, rembg wrappers
│   │       └── tagger_service.py      # Tagger orchestration (reuses lib/captioning.py)
│   ├── lib/                           # COPIED from existing project (unchanged)
│   │   ├── image_dataset.py
│   │   ├── media_item.py
│   │   ├── media_cache.py
│   │   ├── captioning.py
│   │   ├── bucketing.py
│   │   ├── validation.py
│   │   ├── masking.py
│   │   ├── image_aspects.py
│   │   ├── tagging/                   # All tagger implementations
│   │   └── upscaling/                 # All upscaler implementations
│   ├── upscalers.json                 # Copied from existing
│   ├── requirements.txt
│   └── pyproject.toml
│
├── frontend/
│   ├── src/
│   │   ├── app/
│   │   │   ├── layout.tsx             # Root layout, sidebar nav
│   │   │   ├── page.tsx               # Redirect to /browse
│   │   │   ├── browse/
│   │   │   │   └── page.tsx           # Gallery grid view
│   │   │   ├── edit/
│   │   │   │   └── page.tsx           # Single image editor
│   │   │   ├── captions/
│   │   │   │   └── page.tsx           # Tag cloud + caption tools
│   │   │   ├── batch/
│   │   │   │   └── page.tsx           # Batch processing
│   │   │   ├── tools/
│   │   │   │   └── page.tsx           # Copy tools
│   │   │   ├── validation/
│   │   │   │   └── page.tsx           # Bucket validation
│   │   │   └── settings/
│   │   │       └── page.tsx           # Settings form
│   │   ├── components/
│   │   │   ├── layout/
│   │   │   │   ├── Sidebar.tsx        # Tab navigation sidebar
│   │   │   │   └── DatasetHeader.tsx  # Folder picker + load controls
│   │   │   ├── browse/
│   │   │   │   └── GalleryGrid.tsx    # Thumbnail grid with click-to-edit
│   │   │   ├── edit/
│   │   │   │   ├── ImageViewer.tsx    # Image display + zoom
│   │   │   │   ├── VideoPlayer.tsx    # Video playback
│   │   │   │   ├── CaptionEditor.tsx  # Caption textarea + tagger controls
│   │   │   │   ├── ImageToolbar.tsx   # Upscale, rembg, mask buttons
│   │   │   │   ├── NavigationBar.tsx  # Prev/next/slider/bookmark
│   │   │   │   └── MaskEditor.tsx     # Canvas-based mask painting
│   │   │   ├── captions/
│   │   │   │   ├── TagCloud.tsx       # Tag frequency display
│   │   │   │   ├── TagOperations.tsx  # Remove, cleanup, append, prepend
│   │   │   │   └── SearchReplace.tsx  # Find/replace in captions
│   │   │   ├── batch/
│   │   │   │   ├── BatchForm.tsx      # Batch operation checkboxes
│   │   │   │   └── ProgressLog.tsx    # SSE-driven progress display
│   │   │   └── shared/
│   │   │       ├── ConfirmDialog.tsx   # Reusable confirmation modal
│   │   │       └── FolderPicker.tsx    # Folder path input
│   │   ├── lib/
│   │   │   ├── api.ts                 # Typed fetch wrapper for backend API
│   │   │   └── types.ts              # TypeScript interfaces matching backend schemas
│   │   └── stores/
│   │       └── session.ts             # Zustand store: session ID, current index, dataset info
│   ├── tailwind.config.ts
│   ├── next.config.ts
│   ├── tsconfig.json
│   └── package.json
│
└── README.md
```

---

## Phase 1: Backend Foundation

### Task 1: Project Scaffolding & Dependency Setup

**Files:**
- Create: `backend/pyproject.toml`
- Create: `backend/requirements.txt`
- Create: `backend/app/__init__.py`
- Create: `backend/app/main.py`
- Copy: `lib/` → `backend/lib/` (entire directory, unchanged)
- Copy: `upscalers.json` → `backend/upscalers.json`

- [ ] **Step 1: Create backend directory and copy existing libraries**

```bash
mkdir -p backend/app/models backend/app/routers backend/app/services
cp -r lib backend/lib
cp upscalers.json backend/upscalers.json
touch backend/app/__init__.py backend/app/models/__init__.py backend/app/routers/__init__.py backend/app/services/__init__.py
```

- [ ] **Step 2: Create pyproject.toml**

```toml
# backend/pyproject.toml
[project]
name = "imagetagger-backend"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "fastapi>=0.115",
    "uvicorn[standard]>=0.34",
    "pydantic>=2.0",
    "Pillow>=10.0",
    "torch>=2.0",
    "torchvision>=0.15",
    "transformers>=4.40",
    "huggingface-hub>=0.20",
    "onnxruntime-gpu>=1.17",
    "spandrel>=0.4",
    "rembg>=2.0",
    "imageio[ffmpeg]>=2.30",
    "python-multipart>=0.0.9",
    "sse-starlette>=2.0",
]
```

- [ ] **Step 3: Create requirements.txt**

```
fastapi>=0.115
uvicorn[standard]>=0.34
pydantic>=2.0
Pillow>=10.0
torch>=2.0
torchvision>=0.15
transformers>=4.40
huggingface-hub>=0.20
onnxruntime-gpu>=1.17
spandrel>=0.4
rembg>=2.0
imageio[ffmpeg]>=2.30
python-multipart>=0.0.9
sse-starlette>=2.0
```

- [ ] **Step 4: Create FastAPI app entry point**

```python
# backend/app/main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: nothing needed yet (models load lazily)
    yield
    # Shutdown: cleanup sessions
    from app.sessions import session_manager
    session_manager.cleanup_all()


app = FastAPI(title="ImageTagger API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 5: Verify the server starts**

```bash
cd backend
pip install -e .
uvicorn app.main:app --reload --port 8000
# GET http://localhost:8000/health → {"status": "ok"}
```

- [ ] **Step 6: Commit**

```bash
git add backend/
git commit -m "feat: scaffold FastAPI backend with existing lib libraries"
```

---

### Task 2: Pydantic Schemas

**Files:**
- Create: `backend/app/models/schemas.py`

- [ ] **Step 1: Define all request/response schemas**

```python
# backend/app/models/schemas.py
from pydantic import BaseModel
from typing import Optional


# --- Dataset ---
class DatasetLoadRequest(BaseModel):
    path: str
    masks_path: Optional[str] = None
    only_missing_captions: bool = False
    include_subdirectories: bool = False


class DatasetInfo(BaseModel):
    total_items: int
    base_dir: str
    masks_dir: Optional[str]


class MediaItemResponse(BaseModel):
    index: int
    filename: str
    basename: str
    extension: str
    is_video: bool
    is_image: bool
    has_caption: bool
    has_mask: bool
    is_bookmarked: bool
    width: Optional[int] = None
    height: Optional[int] = None
    file_size: Optional[int] = None
    media_url: str
    thumbnail_url: str
    caption: str


class NavigationResponse(BaseModel):
    item: MediaItemResponse
    dataset_info: DatasetInfo


# --- Captions ---
class CaptionSaveRequest(BaseModel):
    index: int
    caption: str


class CaptionGenerateRequest(BaseModel):
    index: int
    tagger: str  # 'joytag' | 'wd14' | 'florence' | 'qwen2-vl' | 'openai' | 'combo'


class CaptionGenerateResponse(BaseModel):
    caption: str


class TagCloudEntry(BaseModel):
    tag: str
    count: int


class SearchReplaceRequest(BaseModel):
    search: str
    replace: str


class SearchReplacePreview(BaseModel):
    matches: list[dict]  # [{index, filename, before, after}]
    total_matches: int


class TagOperationRequest(BaseModel):
    tags: list[str]


class AppendTagRequest(BaseModel):
    tag: str


class MoveToSubdirRequest(BaseModel):
    tags: list[str]
    inverse: bool = False
    subdirectory_name: str


# --- Processing ---
class UpscaleRequest(BaseModel):
    index: int
    upscaler: Optional[str] = None
    target_megapixels: Optional[float] = None


class MaskGenerateRequest(BaseModel):
    index: int


# --- Batch ---
class BatchProcessRequest(BaseModel):
    rename: bool = False
    upscale: bool = False
    bucket_resize: bool = False
    mask: bool = False
    caption: bool = False
    tagger: str = "florence"
    bucket_resolution: int = 1024
    bucket_step: int = 64
    bucket_max_steps: int = 4


class BucketAnalyzeRequest(BaseModel):
    resolution: int = 1024
    step: int = 64
    max_steps: int = 4


class BucketAnalyzeResponse(BaseModel):
    buckets: list[dict]  # [{width, height, count, images}]
    total_images: int


# --- Settings ---
class SettingsResponse(BaseModel):
    models_dir: str
    ignore_list: list[str]
    upscaler: str
    upscale_target_megapixels: float
    tagger_instruction: str
    combo_taggers: list[str]
    florence_settings: dict
    rembg: dict
    openai_settings: dict


class SettingsUpdateRequest(BaseModel):
    key: str
    value: str | int | float | bool | list | dict


# --- Tools ---
class CopyRequest(BaseModel):
    target_directory: str
    copy_option: str  # 'all' | 'bookmarks'


class ExportResponse(BaseModel):
    path: str
    count: int


# --- Gallery ---
class GalleryItem(BaseModel):
    index: int
    thumbnail_url: str
    filename: str
    is_bookmarked: bool


class GalleryResponse(BaseModel):
    items: list[GalleryItem]
    total: int
    page: int
    page_size: int


# --- Validation ---
class ValidationReport(BaseModel):
    buckets: list[dict]
    total_images: int
    summary: str
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/models/schemas.py
git commit -m "feat: add Pydantic schemas for all API request/response models"
```

---

### Task 3: Session Manager

**Files:**
- Create: `backend/app/sessions.py`

The Gradio app stored dataset state in `gr.State()`. We replace this with a server-side session manager keyed by UUID. Sessions hold the loaded `ImageDataSet` instance and per-session config.

- [ ] **Step 1: Implement session manager**

```python
# backend/app/sessions.py
import uuid
import time
import threading
from dataclasses import dataclass, field
from typing import Optional

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from lib.image_dataset import ImageDataSet


SESSION_TTL_SECONDS = 3600  # 1 hour inactivity timeout


@dataclass
class Session:
    id: str
    dataset: Optional[ImageDataSet] = None
    config: dict = field(default_factory=dict)
    created_at: float = field(default_factory=time.time)
    last_accessed: float = field(default_factory=time.time)
    # Transient state (like cached upscaled image)
    upscaled_image: Optional[object] = None  # PIL.Image
    upscaled_index: Optional[int] = None

    def touch(self):
        self.last_accessed = time.time()

    @property
    def is_expired(self) -> bool:
        return time.time() - self.last_accessed > SESSION_TTL_SECONDS


class SessionManager:
    def __init__(self):
        self._sessions: dict[str, Session] = {}
        self._lock = threading.Lock()

    def create(self) -> Session:
        session_id = str(uuid.uuid4())
        session = Session(id=session_id)
        with self._lock:
            self._sessions[session_id] = session
        return session

    def get(self, session_id: str) -> Optional[Session]:
        with self._lock:
            session = self._sessions.get(session_id)
        if session is None:
            return None
        if session.is_expired:
            self.delete(session_id)
            return None
        session.touch()
        return session

    def delete(self, session_id: str):
        with self._lock:
            self._sessions.pop(session_id, None)

    def cleanup_all(self):
        with self._lock:
            self._sessions.clear()

    def cleanup_expired(self):
        with self._lock:
            expired = [sid for sid, s in self._sessions.items() if s.is_expired]
            for sid in expired:
                del self._sessions[sid]


session_manager = SessionManager()
```

- [ ] **Step 2: Create session dependency for FastAPI routes**

Add to the bottom of `backend/app/sessions.py`:

```python
from fastapi import Header, HTTPException


def get_session(x_session_id: str = Header(...)) -> Session:
    """FastAPI dependency: extract session from X-Session-ID header."""
    session = session_manager.get(x_session_id)
    if session is None:
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    return session
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/sessions.py
git commit -m "feat: add UUID-based session manager for per-user dataset state"
```

---

### Task 4: Config Service

**Files:**
- Create: `backend/app/config.py`

Reuses the logic from the existing `config.py` but adapted for the new session-based architecture.

- [ ] **Step 1: Create config service**

```python
# backend/app/config.py
import json
import os

SETTINGS_FILE = os.path.join(os.path.dirname(__file__), "..", "settings.json")

DEFAULTS = {
    "models_dir": "models",
    "ignore_list": ["masklabel"],
    "upscaler": "NMKD_Siax_200k_4x",
    "upscale_target_megapixels": 2.0,
    "tagger_instruction": "A descriptive caption for this image:\n",
    "combo_taggers": ["florence", "wd14"],
    "florence_settings": {"prompt": "<DETAILED_CAPTION>"},
    "rembg": {"model": "u2net_human_seg"},
    "openai_settings": {
        "api_key": "",
        "base_url": "http://localhost:11434/v1",
        "model": "qwen3:32b",
        "prompt": "Describe the image in continuous text.",
    },
}


def read_settings() -> dict:
    if not os.path.exists(SETTINGS_FILE):
        with open(SETTINGS_FILE, "w") as f:
            json.dump({}, f)
        return dict(DEFAULTS)
    with open(SETTINGS_FILE, "r") as f:
        data = json.load(f)
    # Merge with defaults
    merged = dict(DEFAULTS)
    merged.update(data)
    return merged


def save_settings(settings: dict):
    # Filter out non-serializable keys
    serializable = {
        k: v for k, v in settings.items()
        if isinstance(v, (str, int, float, bool, list, dict, type(None)))
    }
    with open(SETTINGS_FILE, "w") as f:
        json.dump(serializable, f, indent=2)


def update_setting(key: str, value) -> dict:
    settings = read_settings()
    settings[key] = value
    save_settings(settings)
    return settings


def get_setting(key: str, default=None):
    settings = read_settings()
    return settings.get(key, default)
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/config.py
git commit -m "feat: add settings persistence service"
```

---

### Task 5: Dataset Router

**Files:**
- Create: `backend/app/routers/dataset.py`
- Create: `backend/app/services/dataset_service.py`
- Modify: `backend/app/main.py` (register router)

- [ ] **Step 1: Create dataset service**

```python
# backend/app/services/dataset_service.py
import os
from typing import Optional
from PIL import Image

import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from lib.image_dataset import ImageDataSet
from lib.media_item import MediaItem

from app.sessions import Session
from app.config import read_settings


def load_dataset(session: Session, path: str, masks_path: Optional[str] = None,
                 only_missing_captions: bool = False, include_subdirectories: bool = False):
    """Load a dataset from the given path into the session."""
    dataset = ImageDataSet()
    dataset.load(path, masks_dir=masks_path, include_subdirectories=include_subdirectories,
                 only_missing_captions=only_missing_captions)
    session.dataset = dataset
    session.config = read_settings()


def get_media_item_response(session: Session, index: int) -> dict:
    """Build a MediaItemResponse dict for the given index."""
    ds = session.dataset
    item: MediaItem = ds.get_item(index)
    caption = ds.read_caption(index)
    is_bookmarked = ds.is_bookmarked(index)

    # Get image dimensions if possible
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
        "has_caption": item.caption_exists(),
        "has_mask": item.mask_exists(),
        "is_bookmarked": is_bookmarked,
        "width": width,
        "height": height,
        "file_size": file_size,
        "media_url": f"/api/media/file/{index}",
        "thumbnail_url": f"/api/media/thumbnail/{index}",
        "caption": caption,
    }
```

- [ ] **Step 2: Create dataset router**

```python
# backend/app/routers/dataset.py
from fastapi import APIRouter, Depends, HTTPException

from app.sessions import Session, get_session, session_manager
from app.models.schemas import (
    DatasetLoadRequest, DatasetInfo, MediaItemResponse,
    NavigationResponse, GalleryResponse, GalleryItem,
)
from app.services.dataset_service import load_dataset, get_media_item_response

router = APIRouter(prefix="/api/dataset", tags=["dataset"])


@router.post("/session")
def create_session():
    """Create a new session and return the session ID."""
    session = session_manager.create()
    return {"session_id": session.id}


@router.post("/load", response_model=DatasetInfo)
def load(req: DatasetLoadRequest, session: Session = Depends(get_session)):
    """Load a dataset from a directory path."""
    load_dataset(
        session, req.path, req.masks_path,
        req.only_missing_captions, req.include_subdirectories,
    )
    ds = session.dataset
    return DatasetInfo(
        total_items=len(ds),
        base_dir=ds._base_dir,
        masks_dir=ds._masks_dir,
    )


@router.get("/item/{index}", response_model=MediaItemResponse)
def get_item(index: int, session: Session = Depends(get_session)):
    """Get a single media item by index."""
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    if index < 0 or index >= len(ds):
        raise HTTPException(404, f"Index {index} out of range [0, {len(ds)})")
    return get_media_item_response(session, index)


@router.get("/gallery", response_model=GalleryResponse)
def gallery(page: int = 0, page_size: int = 50, session: Session = Depends(get_session)):
    """Get paginated gallery of thumbnails."""
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")

    start = page * page_size
    end = min(start + page_size, len(ds))
    items = []
    for i in range(start, end):
        item = ds.get_item(i)
        items.append(GalleryItem(
            index=i,
            thumbnail_url=f"/api/media/thumbnail/{i}",
            filename=item.filename,
            is_bookmarked=ds.is_bookmarked(i),
        ))

    return GalleryResponse(items=items, total=len(ds), page=page, page_size=page_size)


@router.post("/bookmark/{index}")
def toggle_bookmark(index: int, session: Session = Depends(get_session)):
    """Toggle bookmark status for an item."""
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    ds.toggle_bookmark(index)
    return {"is_bookmarked": ds.is_bookmarked(index)}


@router.delete("/item/{index}")
def delete_item(index: int, session: Session = Depends(get_session)):
    """Delete a media item and its associated files."""
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    ds.delete_item(index)
    return {"total_items": len(ds)}


@router.put("/item/{index}/rename")
def rename_item(index: int, new_name: str, session: Session = Depends(get_session)):
    """Rename a media item."""
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    ds.rename_item(index, new_name)
    return get_media_item_response(session, index)
```

- [ ] **Step 3: Register the router in main.py**

Add to `backend/app/main.py` before the health endpoint:

```python
from app.routers import dataset

app.include_router(dataset.router)
```

- [ ] **Step 4: Test dataset endpoints manually**

```bash
cd backend
uvicorn app.main:app --reload --port 8000

# Create session
curl -X POST http://localhost:8000/api/dataset/session
# Returns: {"session_id": "..."}

# Load dataset (use a test folder with images)
curl -X POST http://localhost:8000/api/dataset/load \
  -H "X-Session-ID: <session_id>" \
  -H "Content-Type: application/json" \
  -d '{"path": "/path/to/test/images"}'
```

- [ ] **Step 5: Commit**

```bash
git add backend/app/routers/dataset.py backend/app/services/dataset_service.py backend/app/main.py
git commit -m "feat: add dataset router with session management, gallery, and CRUD endpoints"
```

---

### Task 6: Media Serving Router

**Files:**
- Create: `backend/app/routers/media.py`
- Modify: `backend/app/main.py` (register router)

- [ ] **Step 1: Create media router**

```python
# backend/app/routers/media.py
import os
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse

from app.sessions import Session, get_session

router = APIRouter(prefix="/api/media", tags=["media"])

IMAGE_MEDIA_TYPES = {
    ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".png": "image/png", ".gif": "image/gif", ".webp": "image/webp",
}
VIDEO_MEDIA_TYPES = {
    ".mp4": "video/mp4", ".avi": "video/x-msvideo",
    ".mov": "video/quicktime", ".mkv": "video/x-matroska",
}


@router.get("/file/{index}")
def serve_media(index: int, session: Session = Depends(get_session)):
    """Serve the original media file."""
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    if index < 0 or index >= len(ds):
        raise HTTPException(404, "Index out of range")

    item = ds.get_item(index)
    if not item.media_exists():
        raise HTTPException(404, "Media file not found")

    ext = item.extension.lower()
    media_type = IMAGE_MEDIA_TYPES.get(ext) or VIDEO_MEDIA_TYPES.get(ext, "application/octet-stream")
    return FileResponse(item.media_path, media_type=media_type)


@router.get("/thumbnail/{index}")
def serve_thumbnail(index: int, session: Session = Depends(get_session)):
    """Serve a thumbnail image."""
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    if index < 0 or index >= len(ds):
        raise HTTPException(404, "Index out of range")

    item = ds.get_item(index)
    # If thumbnail exists, serve it; otherwise serve original
    if item.thumbnail_exists():
        return FileResponse(item.thumbnail_path, media_type="image/jpeg")
    elif item.media_exists():
        ext = item.extension.lower()
        media_type = IMAGE_MEDIA_TYPES.get(ext, "image/jpeg")
        return FileResponse(item.media_path, media_type=media_type)
    else:
        raise HTTPException(404, "No thumbnail or media file found")


@router.get("/mask/{index}")
def serve_mask(index: int, session: Session = Depends(get_session)):
    """Serve a mask file."""
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    if index < 0 or index >= len(ds):
        raise HTTPException(404, "Index out of range")

    item = ds.get_item(index)
    if not item.mask_exists():
        raise HTTPException(404, "Mask file not found")
    return FileResponse(item.mask_path, media_type="image/png")
```

- [ ] **Step 2: Register router in main.py**

```python
from app.routers import dataset, media

app.include_router(dataset.router)
app.include_router(media.router)
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/routers/media.py backend/app/main.py
git commit -m "feat: add media serving router for images, videos, thumbnails, and masks"
```

---

### Task 7: Captions Router

**Files:**
- Create: `backend/app/routers/captions.py`
- Create: `backend/app/services/caption_service.py`
- Modify: `backend/app/main.py` (register router)

- [ ] **Step 1: Create caption service**

```python
# backend/app/services/caption_service.py
import os
import json
import re
from datetime import datetime
from typing import Optional

from app.sessions import Session


def get_tag_cloud(session: Session, sort_by: str = "frequency") -> list[dict]:
    """Build tag cloud from all captions. Returns list of {tag, count}."""
    ds = session.dataset
    tag_counts: dict[str, int] = {}
    for i in range(len(ds)):
        caption = ds.read_caption(i)
        if not caption:
            continue
        tags = [t.strip() for t in caption.split(",") if t.strip()]
        for tag in tags:
            tag_counts[tag] = tag_counts.get(tag, 0) + 1

    items = [{"tag": tag, "count": count} for tag, count in tag_counts.items()]
    if sort_by == "frequency":
        items.sort(key=lambda x: x["count"], reverse=True)
    else:
        items.sort(key=lambda x: x["tag"])
    return items


def remove_tags(session: Session, tags_to_remove: list[str]) -> int:
    """Remove specified tags from all captions. Returns number of modified captions."""
    ds = session.dataset
    modified = 0
    tags_set = set(t.lower() for t in tags_to_remove)
    for i in range(len(ds)):
        caption = ds.read_caption(i)
        if not caption:
            continue
        tags = [t.strip() for t in caption.split(",") if t.strip()]
        new_tags = [t for t in tags if t.lower() not in tags_set]
        if len(new_tags) != len(tags):
            ds.save_caption(i, ", ".join(new_tags))
            modified += 1
    return modified


def append_tag(session: Session, tag: str) -> int:
    """Append a tag to all captions. Returns number of modified captions."""
    ds = session.dataset
    modified = 0
    for i in range(len(ds)):
        caption = ds.read_caption(i)
        existing_tags = [t.strip() for t in caption.split(",") if t.strip()] if caption else []
        if tag not in existing_tags:
            existing_tags.append(tag)
            ds.save_caption(i, ", ".join(existing_tags))
            modified += 1
    return modified


def prepend_tag(session: Session, tag: str) -> int:
    """Prepend a tag to all captions. Returns number of modified captions."""
    ds = session.dataset
    modified = 0
    for i in range(len(ds)):
        caption = ds.read_caption(i)
        existing_tags = [t.strip() for t in caption.split(",") if t.strip()] if caption else []
        if tag not in existing_tags:
            existing_tags.insert(0, tag)
            ds.save_caption(i, ", ".join(existing_tags))
            modified += 1
    return modified


def search_replace_preview(session: Session, search: str, replace: str) -> dict:
    """Preview search and replace results."""
    ds = session.dataset
    matches = []
    for i in range(len(ds)):
        caption = ds.read_caption(i)
        if not caption or search not in caption:
            continue
        new_caption = caption.replace(search, replace)
        matches.append({
            "index": i,
            "filename": ds.get_item(i).filename,
            "before": caption,
            "after": new_caption,
        })
    return {"matches": matches, "total_matches": len(matches)}


def search_replace_apply(session: Session, search: str, replace: str) -> int:
    """Apply search and replace to all captions. Returns modified count."""
    ds = session.dataset
    modified = 0
    for i in range(len(ds)):
        caption = ds.read_caption(i)
        if not caption or search not in caption:
            continue
        new_caption = caption.replace(search, replace)
        ds.save_caption(i, new_caption)
        modified += 1
    return modified


def replace_underscores(session: Session) -> int:
    """Replace underscores with spaces in all tag names."""
    ds = session.dataset
    modified = 0
    for i in range(len(ds)):
        caption = ds.read_caption(i)
        if not caption or "_" not in caption:
            continue
        ds.save_caption(i, caption.replace("_", " "))
        modified += 1
    return modified


def cleanup_tags(session: Session) -> int:
    """Remove common unwanted tags (body parts, etc.)."""
    ds = session.dataset
    # Body part tags to remove — mirrors existing cleanup logic
    unwanted_patterns = [
        r"\d+girl", r"\d+boy", "solo", "looking at viewer",
    ]
    modified = 0
    for i in range(len(ds)):
        caption = ds.read_caption(i)
        if not caption:
            continue
        tags = [t.strip() for t in caption.split(",") if t.strip()]
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
            ds.save_caption(i, ", ".join(new_tags))
            modified += 1
    return modified


def export_to_jsonl(session: Session) -> dict:
    """Export all captions to JSONL file. Returns path and count."""
    ds = session.dataset
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    export_path = os.path.join(ds._base_dir, f"captions_export_{timestamp}.jsonl")
    count = 0
    with open(export_path, "w", encoding="utf-8") as f:
        for i in range(len(ds)):
            item = ds.get_item(i)
            caption = ds.read_caption(i)
            record = {
                "filename": item.filename,
                "caption": caption,
                "has_mask": item.mask_exists(),
            }
            f.write(json.dumps(record) + "\n")
            count += 1
    return {"path": export_path, "count": count}


def move_to_subdirectory(session: Session, tags: list[str], inverse: bool,
                         subdirectory_name: str) -> int:
    """Move images matching tags to a subdirectory. Returns moved count."""
    ds = session.dataset
    tags_set = set(t.lower() for t in tags)
    target_dir = os.path.join(ds._base_dir, subdirectory_name)
    os.makedirs(target_dir, exist_ok=True)

    moved = 0
    indices_to_move = []
    for i in range(len(ds)):
        caption = ds.read_caption(i)
        if not caption:
            continue
        image_tags = set(t.strip().lower() for t in caption.split(",") if t.strip())
        has_match = bool(image_tags & tags_set)
        if (has_match and not inverse) or (not has_match and inverse):
            indices_to_move.append(i)

    # Move in reverse order to preserve indices
    for i in reversed(indices_to_move):
        item = ds.get_item(i)
        ds.copy_item(i, target_dir)
        ds.delete_item(i)
        moved += 1

    return moved
```

- [ ] **Step 2: Create captions router**

```python
# backend/app/routers/captions.py
from fastapi import APIRouter, Depends, HTTPException

from app.sessions import Session, get_session
from app.models.schemas import (
    CaptionSaveRequest, TagCloudEntry, TagOperationRequest,
    AppendTagRequest, SearchReplaceRequest, SearchReplacePreview,
    MoveToSubdirRequest, ExportResponse,
)
from app.services import caption_service

router = APIRouter(prefix="/api/captions", tags=["captions"])


@router.put("/save")
def save_caption(req: CaptionSaveRequest, session: Session = Depends(get_session)):
    ds = session.dataset
    if ds is None:
        raise HTTPException(400, "No dataset loaded")
    ds.save_caption(req.index, req.caption)
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
def cleanup_tags(session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    modified = caption_service.cleanup_tags(session)
    return {"modified": modified}


@router.post("/tags/replace-underscores")
def replace_underscores(session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    modified = caption_service.replace_underscores(session)
    return {"modified": modified}


@router.post("/search-replace/preview", response_model=SearchReplacePreview)
def search_replace_preview(req: SearchReplaceRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    return caption_service.search_replace_preview(session, req.search, req.replace)


@router.post("/search-replace/apply")
def search_replace_apply(req: SearchReplaceRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    modified = caption_service.search_replace_apply(session, req.search, req.replace)
    return {"modified": modified}


@router.post("/export", response_model=ExportResponse)
def export_jsonl(session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    return caption_service.export_to_jsonl(session)


@router.post("/move-to-subdir")
def move_to_subdirectory(req: MoveToSubdirRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    moved = caption_service.move_to_subdirectory(
        session, req.tags, req.inverse, req.subdirectory_name
    )
    return {"moved": moved}
```

- [ ] **Step 3: Register router in main.py**

```python
from app.routers import dataset, media, captions

app.include_router(dataset.router)
app.include_router(media.router)
app.include_router(captions.router)
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/routers/captions.py backend/app/services/caption_service.py backend/app/main.py
git commit -m "feat: add captions router with tag cloud, search/replace, and export"
```

---

### Task 8: Processing Router (Upscale, Mask, Background Removal)

**Files:**
- Create: `backend/app/routers/processing.py`
- Create: `backend/app/services/processing_service.py`
- Modify: `backend/app/main.py` (register router)

- [ ] **Step 1: Create processing service**

```python
# backend/app/services/processing_service.py
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from PIL import Image
from app.sessions import Session
from app.config import read_settings


def upscale_image(session: Session, index: int, upscaler_name: str = None,
                  target_megapixels: float = None) -> str:
    """Upscale an image and save it. Returns path to upscaled image."""
    from lib.upscaling import upscale

    ds = session.dataset
    item = ds.get_item(index)
    settings = read_settings()

    upscaler = upscaler_name or settings.get("upscaler", "NMKD_Siax_200k_4x")
    target_mp = target_megapixels or settings.get("upscale_target_megapixels", 2.0)
    models_dir = settings.get("models_dir", "models")

    img = Image.open(item.media_path)
    upscaled = upscale(img, upscaler, models_dir, target_mp)

    # Cache in session for preview
    session.upscaled_image = upscaled
    session.upscaled_index = index

    return "ok"


def save_upscaled(session: Session, index: int):
    """Save the cached upscaled image back to disk."""
    if session.upscaled_image is None or session.upscaled_index != index:
        raise ValueError("No upscaled image cached for this index")

    ds = session.dataset
    item = ds.get_item(index)
    session.upscaled_image.save(item.media_path)
    session.upscaled_image = None
    session.upscaled_index = None


def remove_background(session: Session, index: int) -> str:
    """Remove background from image. Returns path to processed image."""
    from lib.masking import remove_bg

    ds = session.dataset
    item = ds.get_item(index)
    settings = read_settings()
    model_name = settings.get("rembg", {}).get("model", "u2net_human_seg")
    models_dir = settings.get("models_dir", "models")

    img = Image.open(item.media_path)
    result = remove_bg(img, model_name, models_dir)

    # Save as PNG (RGBA)
    png_path = os.path.splitext(item.media_path)[0] + ".png"
    result.save(png_path)
    return png_path


def generate_mask(session: Session, index: int) -> str:
    """Generate a segmentation mask. Returns mask path."""
    from lib.masking import generate_mask as gen_mask

    ds = session.dataset
    item = ds.get_item(index)
    settings = read_settings()
    model_name = settings.get("rembg", {}).get("model", "u2net_human_seg")
    models_dir = settings.get("models_dir", "models")

    img = Image.open(item.media_path)
    mask = gen_mask(img, model_name, models_dir)

    mask_path = item.mask_path
    if mask_path:
        os.makedirs(os.path.dirname(mask_path), exist_ok=True)
        mask.save(mask_path)
    return mask_path
```

- [ ] **Step 2: Create processing router**

```python
# backend/app/routers/processing.py
from fastapi import APIRouter, Depends, HTTPException

from app.sessions import Session, get_session
from app.models.schemas import UpscaleRequest, MaskGenerateRequest
from app.services import processing_service

router = APIRouter(prefix="/api/processing", tags=["processing"])


@router.post("/upscale")
def upscale(req: UpscaleRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    try:
        processing_service.upscale_image(
            session, req.index, req.upscaler, req.target_megapixels
        )
        return {"status": "upscaled", "index": req.index}
    except Exception as e:
        raise HTTPException(500, str(e))


@router.post("/upscale/save")
def save_upscaled(index: int, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    try:
        processing_service.save_upscaled(session, index)
        return {"status": "saved"}
    except ValueError as e:
        raise HTTPException(400, str(e))


@router.post("/remove-background")
def remove_background(index: int, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    try:
        processing_service.remove_background(session, index)
        return {"status": "done", "index": index}
    except Exception as e:
        raise HTTPException(500, str(e))


@router.post("/mask/generate")
def generate_mask(req: MaskGenerateRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    try:
        mask_path = processing_service.generate_mask(session, req.index)
        return {"status": "done", "mask_url": f"/api/media/mask/{req.index}"}
    except Exception as e:
        raise HTTPException(500, str(e))
```

- [ ] **Step 3: Register router in main.py**

```python
from app.routers import dataset, media, captions, processing

app.include_router(processing.router)
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/routers/processing.py backend/app/services/processing_service.py backend/app/main.py
git commit -m "feat: add processing router for upscale, background removal, and mask generation"
```

---

### Task 9: Tagging Router

**Files:**
- Create: `backend/app/routers/tagging.py`
- Create: `backend/app/services/tagger_service.py`
- Modify: `backend/app/main.py` (register router)

- [ ] **Step 1: Create tagger service**

```python
# backend/app/services/tagger_service.py
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from PIL import Image
from app.sessions import Session
from app.config import read_settings


def generate_caption(session: Session, index: int, tagger: str) -> str:
    """Generate a caption using the specified tagger. Returns caption text."""
    from lib.captioning import generate_caption as gen_caption

    ds = session.dataset
    item = ds.get_item(index)
    settings = read_settings()

    img = Image.open(item.media_path)
    caption = gen_caption(img, tagger, settings)
    return caption
```

- [ ] **Step 2: Create tagging router**

```python
# backend/app/routers/tagging.py
from fastapi import APIRouter, Depends, HTTPException

from app.sessions import Session, get_session
from app.models.schemas import CaptionGenerateRequest, CaptionGenerateResponse
from app.services import tagger_service

router = APIRouter(prefix="/api/tagging", tags=["tagging"])


@router.post("/generate", response_model=CaptionGenerateResponse)
def generate(req: CaptionGenerateRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    try:
        caption = tagger_service.generate_caption(session, req.index, req.tagger)
        return CaptionGenerateResponse(caption=caption)
    except Exception as e:
        raise HTTPException(500, str(e))
```

- [ ] **Step 3: Register router in main.py**

```python
from app.routers import dataset, media, captions, processing, tagging

app.include_router(tagging.router)
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/routers/tagging.py backend/app/services/tagger_service.py backend/app/main.py
git commit -m "feat: add tagging router for AI caption generation"
```

---

### Task 10: Batch Processing Router (with SSE)

**Files:**
- Create: `backend/app/routers/batch.py`
- Modify: `backend/app/main.py` (register router)

- [ ] **Step 1: Create batch router with SSE streaming**

```python
# backend/app/routers/batch.py
import asyncio
import json
from fastapi import APIRouter, Depends, HTTPException
from sse_starlette.sse import EventSourceResponse

from app.sessions import Session, get_session
from app.models.schemas import BatchProcessRequest, BucketAnalyzeRequest, BucketAnalyzeResponse
from app.config import read_settings

router = APIRouter(prefix="/api/batch", tags=["batch"])


@router.post("/process")
async def batch_process(req: BatchProcessRequest, session: Session = Depends(get_session)):
    """Start batch processing. Returns SSE stream with progress updates."""
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")

    ds = session.dataset
    settings = read_settings()

    async def event_generator():
        total = len(ds)
        for i in range(total):
            item = ds.get_item(i)
            log_lines = []

            try:
                if req.rename:
                    new_name = f"{i:05d}"
                    ds.rename_item(i, new_name)
                    log_lines.append(f"Renamed to {new_name}")

                if req.upscale:
                    from lib.upscaling import upscale
                    from PIL import Image
                    img = Image.open(item.media_path)
                    upscaler_name = settings.get("upscaler", "NMKD_Siax_200k_4x")
                    target_mp = settings.get("upscale_target_megapixels", 2.0)
                    models_dir = settings.get("models_dir", "models")
                    result = upscale(img, upscaler_name, models_dir, target_mp)
                    result.save(item.media_path)
                    log_lines.append("Upscaled")

                if req.bucket_resize:
                    from lib.bucketing import get_bucket_for_image, resize_to_bucket
                    from PIL import Image
                    img = Image.open(item.media_path)
                    bucket = get_bucket_for_image(
                        img, req.bucket_resolution, req.bucket_step, req.bucket_max_steps
                    )
                    if bucket:
                        resized = resize_to_bucket(img, bucket)
                        resized.save(item.media_path)
                        log_lines.append(f"Resized to bucket {bucket.width}x{bucket.height}")

                if req.mask:
                    from app.services.processing_service import generate_mask
                    generate_mask(session, i)
                    log_lines.append("Mask generated")

                if req.caption:
                    from app.services.tagger_service import generate_caption
                    caption = generate_caption(session, i, req.tagger)
                    ds.save_caption(i, caption)
                    log_lines.append(f"Caption: {caption[:50]}...")

            except Exception as e:
                log_lines.append(f"ERROR: {str(e)}")

            progress = {
                "index": i,
                "total": total,
                "filename": item.filename,
                "progress": (i + 1) / total,
                "log": "; ".join(log_lines),
            }
            yield {"event": "progress", "data": json.dumps(progress)}
            await asyncio.sleep(0)  # yield control

        yield {"event": "done", "data": json.dumps({"total_processed": total})}

    return EventSourceResponse(event_generator())


@router.post("/analyze-buckets", response_model=BucketAnalyzeResponse)
def analyze_buckets(req: BucketAnalyzeRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")

    from lib.bucketing import analyze_buckets
    ds = session.dataset
    result = analyze_buckets(ds, req.resolution, req.step, req.max_steps)
    return BucketAnalyzeResponse(
        buckets=result["buckets"],
        total_images=result["total_images"],
    )
```

- [ ] **Step 2: Register router in main.py**

```python
from app.routers import dataset, media, captions, processing, tagging, batch

app.include_router(batch.router)
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/routers/batch.py backend/app/main.py
git commit -m "feat: add batch processing router with SSE progress streaming"
```

---

### Task 11: Settings & Validation Routers

**Files:**
- Create: `backend/app/routers/settings.py`
- Modify: `backend/app/main.py` (register router)

- [ ] **Step 1: Create settings router**

```python
# backend/app/routers/settings.py
import json
import os
from fastapi import APIRouter, Depends, HTTPException

from app.sessions import Session, get_session
from app.models.schemas import SettingsResponse, SettingsUpdateRequest, CopyRequest, ValidationReport
from app.config import read_settings, update_setting

router = APIRouter(prefix="/api/settings", tags=["settings"])


@router.get("/", response_model=SettingsResponse)
def get_settings():
    settings = read_settings()
    return SettingsResponse(**settings)


@router.put("/")
def update_settings(req: SettingsUpdateRequest):
    update_setting(req.key, req.value)
    return {"ok": True}


@router.get("/upscalers")
def list_upscalers():
    """List available upscaler models from upscalers.json."""
    upscalers_path = os.path.join(os.path.dirname(__file__), "..", "..", "upscalers.json")
    with open(upscalers_path) as f:
        return json.load(f)


@router.get("/taggers")
def list_taggers():
    """List available taggers."""
    return [
        {"id": "joytag", "name": "JoyTag", "description": "Simple tag generation"},
        {"id": "wd14", "name": "WD14", "description": "Waifu Diffusion tags"},
        {"id": "florence", "name": "Florence-2", "description": "Detailed descriptions"},
        {"id": "qwen2-vl", "name": "Qwen2-VL", "description": "Alibaba VL model captions"},
        {"id": "openai", "name": "OpenAI-compatible", "description": "API-based (Ollama, etc.)"},
        {"id": "combo", "name": "Combo", "description": "Combination of selected taggers"},
    ]


@router.post("/tools/copy")
def copy_images(req: CopyRequest, session: Session = Depends(get_session)):
    """Copy images to target directory."""
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")

    ds = session.dataset
    os.makedirs(req.target_directory, exist_ok=True)
    copied = 0

    for i in range(len(ds)):
        if req.copy_option == "bookmarks" and not ds.is_bookmarked(i):
            continue
        ds.copy_item(i, req.target_directory)
        copied += 1

    return {"copied": copied}


@router.get("/validation", response_model=ValidationReport)
def validate(session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")

    from lib.validation import validate_dataset
    ds = session.dataset
    result = validate_dataset(ds)
    return ValidationReport(**result)
```

- [ ] **Step 2: Register router in main.py — final version**

```python
# backend/app/main.py — final router registration
from app.routers import dataset, media, captions, processing, tagging, batch, settings

app.include_router(dataset.router)
app.include_router(media.router)
app.include_router(captions.router)
app.include_router(processing.router)
app.include_router(tagging.router)
app.include_router(batch.router)
app.include_router(settings.router)
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/routers/settings.py backend/app/main.py
git commit -m "feat: add settings, validation, tools, and upscaler list endpoints"
```

---

## Phase 2: Frontend Foundation

### Task 12: Next.js Project Scaffolding

**Files:**
- Create: `frontend/` (entire Next.js project)

- [ ] **Step 1: Create Next.js project**

```bash
cd image-tagger  # project root
npx create-next-app@latest frontend --typescript --tailwind --eslint --app --src-dir --no-import-alias
cd frontend
```

- [ ] **Step 2: Install dependencies**

```bash
npm install zustand @tanstack/react-query
```

- [ ] **Step 3: Configure next.config.ts for API proxy**

```typescript
// frontend/next.config.ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:8000/api/:path*",
      },
    ];
  },
};

export default nextConfig;
```

- [ ] **Step 4: Verify dev server starts**

```bash
npm run dev
# http://localhost:3000 should show the Next.js default page
```

- [ ] **Step 5: Commit**

```bash
git add frontend/
git commit -m "feat: scaffold Next.js frontend with Tailwind CSS, Zustand, TanStack Query"
```

---

### Task 13: TypeScript Types & API Client

**Files:**
- Create: `frontend/src/lib/types.ts`
- Create: `frontend/src/lib/api.ts`

- [ ] **Step 1: Define TypeScript interfaces**

```typescript
// frontend/src/lib/types.ts

export interface DatasetInfo {
  total_items: number;
  base_dir: string;
  masks_dir: string | null;
}

export interface MediaItem {
  index: number;
  filename: string;
  basename: string;
  extension: string;
  is_video: boolean;
  is_image: boolean;
  has_caption: boolean;
  has_mask: boolean;
  is_bookmarked: boolean;
  width: number | null;
  height: number | null;
  file_size: number | null;
  media_url: string;
  thumbnail_url: string;
  caption: string;
}

export interface GalleryItem {
  index: number;
  thumbnail_url: string;
  filename: string;
  is_bookmarked: boolean;
}

export interface GalleryResponse {
  items: GalleryItem[];
  total: number;
  page: number;
  page_size: number;
}

export interface TagCloudEntry {
  tag: string;
  count: number;
}

export interface SearchReplacePreview {
  matches: Array<{
    index: number;
    filename: string;
    before: string;
    after: string;
  }>;
  total_matches: number;
}

export interface BatchProgress {
  index: number;
  total: number;
  filename: string;
  progress: number;
  log: string;
}

export interface Settings {
  models_dir: string;
  ignore_list: string[];
  upscaler: string;
  upscale_target_megapixels: number;
  tagger_instruction: string;
  combo_taggers: string[];
  florence_settings: { prompt: string };
  rembg: { model: string };
  openai_settings: {
    api_key: string;
    base_url: string;
    model: string;
    prompt: string;
  };
}

export interface Tagger {
  id: string;
  name: string;
  description: string;
}

export interface Upscaler {
  name: string;
  filename: string;
  scale_factor: number;
  url: string | null;
}

export interface BucketResult {
  buckets: Array<{ width: number; height: number; count: number; images: string[] }>;
  total_images: number;
}
```

- [ ] **Step 2: Create typed API client**

```typescript
// frontend/src/lib/api.ts

let sessionId: string | null = null;

async function getSessionId(): Promise<string> {
  if (sessionId) return sessionId;
  const res = await fetch("/api/dataset/session", { method: "POST" });
  const data = await res.json();
  sessionId = data.session_id;
  return sessionId!;
}

async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const sid = await getSessionId();
  const res = await fetch(path, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "X-Session-ID": sid,
      ...options.headers,
    },
  });
  if (!res.ok) {
    const error = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(error.detail || "API error");
  }
  return res.json();
}

// --- Dataset ---
import type {
  DatasetInfo, MediaItem, GalleryResponse, TagCloudEntry,
  SearchReplacePreview, Settings, Tagger, Upscaler, BucketResult,
} from "./types";

export const api = {
  // Dataset
  loadDataset: (path: string, masksPath?: string, onlyMissing = false, subdirs = false) =>
    apiFetch<DatasetInfo>("/api/dataset/load", {
      method: "POST",
      body: JSON.stringify({
        path, masks_path: masksPath,
        only_missing_captions: onlyMissing,
        include_subdirectories: subdirs,
      }),
    }),

  getItem: (index: number) =>
    apiFetch<MediaItem>(`/api/dataset/item/${index}`),

  getGallery: (page = 0, pageSize = 50) =>
    apiFetch<GalleryResponse>(`/api/dataset/gallery?page=${page}&page_size=${pageSize}`),

  toggleBookmark: (index: number) =>
    apiFetch<{ is_bookmarked: boolean }>(`/api/dataset/bookmark/${index}`, { method: "POST" }),

  deleteItem: (index: number) =>
    apiFetch<{ total_items: number }>(`/api/dataset/item/${index}`, { method: "DELETE" }),

  renameItem: (index: number, newName: string) =>
    apiFetch<MediaItem>(`/api/dataset/item/${index}/rename?new_name=${encodeURIComponent(newName)}`, { method: "PUT" }),

  // Captions
  saveCaption: (index: number, caption: string) =>
    apiFetch("/api/captions/save", {
      method: "PUT",
      body: JSON.stringify({ index, caption }),
    }),

  getTagCloud: (sortBy = "frequency") =>
    apiFetch<TagCloudEntry[]>(`/api/captions/tags?sort_by=${sortBy}`),

  removeTags: (tags: string[]) =>
    apiFetch("/api/captions/tags/remove", { method: "POST", body: JSON.stringify({ tags }) }),

  appendTag: (tag: string) =>
    apiFetch("/api/captions/tags/append", { method: "POST", body: JSON.stringify({ tag }) }),

  prependTag: (tag: string) =>
    apiFetch("/api/captions/tags/prepend", { method: "POST", body: JSON.stringify({ tag }) }),

  cleanupTags: () =>
    apiFetch("/api/captions/tags/cleanup", { method: "POST" }),

  replaceUnderscores: () =>
    apiFetch("/api/captions/tags/replace-underscores", { method: "POST" }),

  searchReplacePreview: (search: string, replace: string) =>
    apiFetch<SearchReplacePreview>("/api/captions/search-replace/preview", {
      method: "POST",
      body: JSON.stringify({ search, replace }),
    }),

  searchReplaceApply: (search: string, replace: string) =>
    apiFetch("/api/captions/search-replace/apply", {
      method: "POST",
      body: JSON.stringify({ search, replace }),
    }),

  exportJsonl: () =>
    apiFetch<{ path: string; count: number }>("/api/captions/export", { method: "POST" }),

  moveToSubdir: (tags: string[], inverse: boolean, subdirectoryName: string) =>
    apiFetch("/api/captions/move-to-subdir", {
      method: "POST",
      body: JSON.stringify({ tags, inverse, subdirectory_name: subdirectoryName }),
    }),

  // Tagging
  generateCaption: (index: number, tagger: string) =>
    apiFetch<{ caption: string }>("/api/tagging/generate", {
      method: "POST",
      body: JSON.stringify({ index, tagger }),
    }),

  // Processing
  upscale: (index: number, upscaler?: string, targetMp?: number) =>
    apiFetch("/api/processing/upscale", {
      method: "POST",
      body: JSON.stringify({ index, upscaler, target_megapixels: targetMp }),
    }),

  saveUpscaled: (index: number) =>
    apiFetch("/api/processing/upscale/save?index=" + index, { method: "POST" }),

  removeBackground: (index: number) =>
    apiFetch("/api/processing/remove-background?index=" + index, { method: "POST" }),

  generateMask: (index: number) =>
    apiFetch("/api/processing/mask/generate", {
      method: "POST",
      body: JSON.stringify({ index }),
    }),

  // Batch (SSE)
  batchProcess: (options: {
    rename?: boolean; upscale?: boolean; bucket_resize?: boolean;
    mask?: boolean; caption?: boolean; tagger?: string;
  }) => {
    // Returns EventSource — consumer handles events
    return getSessionId().then((sid) => {
      const source = new EventSource(
        `/api/batch/process?session_id=${sid}`
      );
      // POST the config separately, SSE reads from session
      apiFetch("/api/batch/process", {
        method: "POST",
        body: JSON.stringify(options),
      });
      return source;
    });
  },

  analyzeBuckets: (resolution = 1024, step = 64, maxSteps = 4) =>
    apiFetch<BucketResult>("/api/batch/analyze-buckets", {
      method: "POST",
      body: JSON.stringify({ resolution, step, max_steps: maxSteps }),
    }),

  // Settings
  getSettings: () => apiFetch<Settings>("/api/settings/"),
  updateSetting: (key: string, value: unknown) =>
    apiFetch("/api/settings/", { method: "PUT", body: JSON.stringify({ key, value }) }),
  getUpscalers: () => apiFetch<Upscaler[]>("/api/settings/upscalers"),
  getTaggers: () => apiFetch<Tagger[]>("/api/settings/taggers"),

  // Tools
  copyImages: (targetDir: string, option: string) =>
    apiFetch("/api/settings/tools/copy", {
      method: "POST",
      body: JSON.stringify({ target_directory: targetDir, copy_option: option }),
    }),

  // Validation
  validate: () => apiFetch("/api/settings/validation"),

  // Media URLs (not API calls — used in <img> src)
  mediaUrl: async (index: number) => {
    const sid = await getSessionId();
    return `/api/media/file/${index}?session_id=${sid}`;
  },
  thumbnailUrl: async (index: number) => {
    const sid = await getSessionId();
    return `/api/media/thumbnail/${index}?session_id=${sid}`;
  },
};
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/lib/
git commit -m "feat: add TypeScript types and typed API client for all backend endpoints"
```

---

### Task 14: Zustand Session Store

**Files:**
- Create: `frontend/src/stores/session.ts`

- [ ] **Step 1: Create session store**

```typescript
// frontend/src/stores/session.ts
import { create } from "zustand";
import type { DatasetInfo, MediaItem } from "@/lib/types";

interface SessionState {
  // Dataset state
  datasetInfo: DatasetInfo | null;
  currentIndex: number;
  currentItem: MediaItem | null;

  // UI state
  isLoading: boolean;
  error: string | null;

  // Actions
  setDatasetInfo: (info: DatasetInfo | null) => void;
  setCurrentIndex: (index: number) => void;
  setCurrentItem: (item: MediaItem | null) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  reset: () => void;
}

export const useSessionStore = create<SessionState>((set) => ({
  datasetInfo: null,
  currentIndex: 0,
  currentItem: null,
  isLoading: false,
  error: null,

  setDatasetInfo: (info) => set({ datasetInfo: info }),
  setCurrentIndex: (index) => set({ currentIndex: index }),
  setCurrentItem: (item) => set({ currentItem: item }),
  setLoading: (loading) => set({ isLoading: loading }),
  setError: (error) => set({ error }),
  reset: () =>
    set({
      datasetInfo: null,
      currentIndex: 0,
      currentItem: null,
      isLoading: false,
      error: null,
    }),
}));
```

- [ ] **Step 2: Commit**

```bash
git add frontend/src/stores/session.ts
git commit -m "feat: add Zustand session store for dataset and UI state"
```

---

### Task 15: Root Layout & Sidebar Navigation

**Files:**
- Create: `frontend/src/components/layout/Sidebar.tsx`
- Create: `frontend/src/components/layout/DatasetHeader.tsx`
- Modify: `frontend/src/app/layout.tsx`

- [ ] **Step 1: Create Sidebar component**

```tsx
// frontend/src/components/layout/Sidebar.tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const navItems = [
  { href: "/browse", label: "Browse", icon: "🖼" },
  { href: "/edit", label: "Edit", icon: "✏" },
  { href: "/captions", label: "Captions", icon: "💬" },
  { href: "/batch", label: "Batch", icon: "⚙" },
  { href: "/tools", label: "Tools", icon: "🔧" },
  { href: "/validation", label: "Validation", icon: "✓" },
  { href: "/settings", label: "Settings", icon: "⚡" },
];

export default function Sidebar() {
  const pathname = usePathname();

  return (
    <nav className="w-48 shrink-0 border-r border-zinc-700 bg-zinc-900 flex flex-col">
      <div className="p-4 border-b border-zinc-700">
        <h1 className="text-lg font-bold text-white">ImageTagger</h1>
      </div>
      <ul className="flex-1 py-2">
        {navItems.map((item) => {
          const isActive = pathname.startsWith(item.href);
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                className={`flex items-center gap-2 px-4 py-2 text-sm transition-colors ${
                  isActive
                    ? "bg-zinc-700 text-white font-medium"
                    : "text-zinc-400 hover:text-white hover:bg-zinc-800"
                }`}
              >
                <span>{item.icon}</span>
                {item.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
```

- [ ] **Step 2: Create DatasetHeader component**

```tsx
// frontend/src/components/layout/DatasetHeader.tsx
"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { useSessionStore } from "@/stores/session";

export default function DatasetHeader() {
  const [path, setPath] = useState("");
  const [masksPath, setMasksPath] = useState("");
  const [onlyMissing, setOnlyMissing] = useState(false);
  const [subdirs, setSubdirs] = useState(false);

  const { setDatasetInfo, setLoading, setError, datasetInfo } = useSessionStore();

  const handleLoad = async () => {
    if (!path.trim()) return;
    setLoading(true);
    setError(null);
    try {
      const info = await api.loadDataset(path, masksPath || undefined, onlyMissing, subdirs);
      setDatasetInfo(info);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load dataset");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex items-center gap-3 p-3 border-b border-zinc-700 bg-zinc-800">
      <input
        type="text"
        value={path}
        onChange={(e) => setPath(e.target.value)}
        placeholder="Dataset folder path..."
        className="flex-1 px-3 py-1.5 bg-zinc-900 border border-zinc-600 rounded text-sm text-white placeholder-zinc-500 focus:outline-none focus:border-blue-500"
      />
      <input
        type="text"
        value={masksPath}
        onChange={(e) => setMasksPath(e.target.value)}
        placeholder="Masks folder (optional)"
        className="w-56 px-3 py-1.5 bg-zinc-900 border border-zinc-600 rounded text-sm text-white placeholder-zinc-500 focus:outline-none focus:border-blue-500"
      />
      <label className="flex items-center gap-1 text-xs text-zinc-400">
        <input
          type="checkbox"
          checked={onlyMissing}
          onChange={(e) => setOnlyMissing(e.target.checked)}
          className="rounded"
        />
        Missing only
      </label>
      <label className="flex items-center gap-1 text-xs text-zinc-400">
        <input
          type="checkbox"
          checked={subdirs}
          onChange={(e) => setSubdirs(e.target.checked)}
          className="rounded"
        />
        Subdirs
      </label>
      <button
        onClick={handleLoad}
        className="px-4 py-1.5 bg-blue-600 hover:bg-blue-700 text-white text-sm rounded font-medium transition-colors"
      >
        Open
      </button>
      {datasetInfo && (
        <span className="text-xs text-zinc-400">
          {datasetInfo.total_items} items
        </span>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Update root layout**

```tsx
// frontend/src/app/layout.tsx
import type { Metadata } from "next";
import "./globals.css";
import Sidebar from "@/components/layout/Sidebar";
import DatasetHeader from "@/components/layout/DatasetHeader";
import { QueryProvider } from "@/components/layout/QueryProvider";

export const metadata: Metadata = {
  title: "ImageTagger",
  description: "AI-powered image tagging and dataset management",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className="bg-zinc-950 text-white antialiased">
        <QueryProvider>
          <div className="flex h-screen">
            <Sidebar />
            <div className="flex flex-col flex-1 overflow-hidden">
              <DatasetHeader />
              <main className="flex-1 overflow-auto p-4">
                {children}
              </main>
            </div>
          </div>
        </QueryProvider>
      </body>
    </html>
  );
}
```

- [ ] **Step 4: Create QueryProvider wrapper**

```tsx
// frontend/src/components/layout/QueryProvider.tsx
"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";

export function QueryProvider({ children }: { children: React.ReactNode }) {
  const [client] = useState(() => new QueryClient({
    defaultOptions: {
      queries: { staleTime: 30_000, retry: 1 },
    },
  }));

  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}
```

- [ ] **Step 5: Create root page redirect**

```tsx
// frontend/src/app/page.tsx
import { redirect } from "next/navigation";

export default function Home() {
  redirect("/browse");
}
```

- [ ] **Step 6: Commit**

```bash
git add frontend/src/
git commit -m "feat: add root layout with sidebar navigation and dataset header"
```

---

## Phase 3: Browse & Edit Pages

### Task 16: Browse Page (Gallery Grid)

**Files:**
- Create: `frontend/src/app/browse/page.tsx`
- Create: `frontend/src/components/browse/GalleryGrid.tsx`

- [ ] **Step 1: Create GalleryGrid component**

```tsx
// frontend/src/components/browse/GalleryGrid.tsx
"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { useSessionStore } from "@/stores/session";
import type { GalleryItem } from "@/lib/types";

export default function GalleryGrid() {
  const { datasetInfo } = useSessionStore();
  const router = useRouter();
  const [page, setPage] = useState(0);
  const pageSize = 60;

  const { data, isLoading } = useQuery({
    queryKey: ["gallery", page, datasetInfo?.total_items],
    queryFn: () => api.getGallery(page, pageSize),
    enabled: !!datasetInfo,
  });

  const totalPages = data ? Math.ceil(data.total / pageSize) : 0;

  const handleClick = (item: GalleryItem) => {
    useSessionStore.getState().setCurrentIndex(item.index);
    router.push("/edit");
  };

  if (!datasetInfo) {
    return (
      <div className="flex items-center justify-center h-64 text-zinc-500">
        Load a dataset to browse images
      </div>
    );
  }

  return (
    <div>
      {/* Pagination */}
      <div className="flex items-center justify-between mb-4">
        <span className="text-sm text-zinc-400">
          {data?.total ?? 0} images
        </span>
        <div className="flex gap-2">
          <button
            onClick={() => setPage((p) => Math.max(0, p - 1))}
            disabled={page === 0}
            className="px-3 py-1 text-sm bg-zinc-800 rounded disabled:opacity-50 hover:bg-zinc-700"
          >
            Prev
          </button>
          <span className="text-sm text-zinc-400 self-center">
            {page + 1} / {totalPages}
          </span>
          <button
            onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
            disabled={page >= totalPages - 1}
            className="px-3 py-1 text-sm bg-zinc-800 rounded disabled:opacity-50 hover:bg-zinc-700"
          >
            Next
          </button>
        </div>
      </div>

      {/* Grid */}
      {isLoading ? (
        <div className="text-center text-zinc-500 py-8">Loading...</div>
      ) : (
        <div className="grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-2">
          {data?.items.map((item) => (
            <button
              key={item.index}
              onClick={() => handleClick(item)}
              className="group relative aspect-square bg-zinc-800 rounded overflow-hidden hover:ring-2 hover:ring-blue-500 transition-all"
            >
              <img
                src={`/api/media/thumbnail/${item.index}`}
                alt={item.filename}
                className="w-full h-full object-cover"
                loading="lazy"
              />
              {item.is_bookmarked && (
                <span className="absolute top-1 right-1 text-yellow-400 text-xs">★</span>
              )}
              <div className="absolute bottom-0 inset-x-0 bg-black/60 px-1 py-0.5 text-[10px] text-zinc-300 truncate opacity-0 group-hover:opacity-100 transition-opacity">
                {item.filename}
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Create browse page**

```tsx
// frontend/src/app/browse/page.tsx
import GalleryGrid from "@/components/browse/GalleryGrid";

export default function BrowsePage() {
  return <GalleryGrid />;
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/app/browse/ frontend/src/components/browse/
git commit -m "feat: add browse page with paginated thumbnail gallery grid"
```

---

### Task 17: Edit Page — Image Viewer & Navigation

**Files:**
- Create: `frontend/src/app/edit/page.tsx`
- Create: `frontend/src/components/edit/ImageViewer.tsx`
- Create: `frontend/src/components/edit/VideoPlayer.tsx`
- Create: `frontend/src/components/edit/NavigationBar.tsx`
- Create: `frontend/src/components/edit/CaptionEditor.tsx`
- Create: `frontend/src/components/edit/ImageToolbar.tsx`
- Create: `frontend/src/components/shared/ConfirmDialog.tsx`

- [ ] **Step 1: Create ConfirmDialog**

```tsx
// frontend/src/components/shared/ConfirmDialog.tsx
"use client";

interface ConfirmDialogProps {
  open: boolean;
  title: string;
  message: string;
  onConfirm: () => void;
  onCancel: () => void;
}

export default function ConfirmDialog({ open, title, message, onConfirm, onCancel }: ConfirmDialogProps) {
  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-zinc-800 rounded-lg p-6 max-w-sm w-full shadow-xl">
        <h3 className="text-lg font-medium text-white mb-2">{title}</h3>
        <p className="text-sm text-zinc-400 mb-4">{message}</p>
        <div className="flex justify-end gap-2">
          <button
            onClick={onCancel}
            className="px-4 py-1.5 text-sm bg-zinc-700 hover:bg-zinc-600 rounded"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            className="px-4 py-1.5 text-sm bg-red-600 hover:bg-red-700 rounded text-white"
          >
            Confirm
          </button>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Create ImageViewer**

```tsx
// frontend/src/components/edit/ImageViewer.tsx
"use client";

interface ImageViewerProps {
  mediaUrl: string;
  filename: string;
}

export default function ImageViewer({ mediaUrl, filename }: ImageViewerProps) {
  return (
    <div className="flex items-center justify-center bg-zinc-900 rounded-lg overflow-hidden h-full">
      <img
        src={mediaUrl}
        alt={filename}
        className="max-w-full max-h-full object-contain"
      />
    </div>
  );
}
```

- [ ] **Step 3: Create VideoPlayer**

```tsx
// frontend/src/components/edit/VideoPlayer.tsx
"use client";

interface VideoPlayerProps {
  mediaUrl: string;
}

export default function VideoPlayer({ mediaUrl }: VideoPlayerProps) {
  return (
    <div className="flex items-center justify-center bg-zinc-900 rounded-lg overflow-hidden h-full">
      <video src={mediaUrl} controls className="max-w-full max-h-full" />
    </div>
  );
}
```

- [ ] **Step 4: Create NavigationBar**

```tsx
// frontend/src/components/edit/NavigationBar.tsx
"use client";

import { api } from "@/lib/api";
import { useSessionStore } from "@/stores/session";

interface NavigationBarProps {
  onNavigate: (index: number) => void;
}

export default function NavigationBar({ onNavigate }: NavigationBarProps) {
  const { currentIndex, currentItem, datasetInfo } = useSessionStore();
  const total = datasetInfo?.total_items ?? 0;

  const handleBookmark = async () => {
    await api.toggleBookmark(currentIndex);
    onNavigate(currentIndex); // reload current
  };

  return (
    <div className="flex items-center gap-3 py-2">
      <button
        onClick={() => onNavigate(Math.max(0, currentIndex - 1))}
        disabled={currentIndex <= 0}
        className="px-3 py-1.5 bg-zinc-700 hover:bg-zinc-600 rounded text-sm disabled:opacity-50"
      >
        ← Prev
      </button>

      <input
        type="range"
        min={0}
        max={Math.max(0, total - 1)}
        value={currentIndex}
        onChange={(e) => onNavigate(Number(e.target.value))}
        className="flex-1"
      />

      <span className="text-sm text-zinc-400 min-w-[80px] text-center">
        {currentIndex + 1} / {total}
      </span>

      <button
        onClick={() => onNavigate(Math.min(total - 1, currentIndex + 1))}
        disabled={currentIndex >= total - 1}
        className="px-3 py-1.5 bg-zinc-700 hover:bg-zinc-600 rounded text-sm disabled:opacity-50"
      >
        Next →
      </button>

      <button
        onClick={handleBookmark}
        className={`px-3 py-1.5 rounded text-sm ${
          currentItem?.is_bookmarked
            ? "bg-yellow-600 hover:bg-yellow-700"
            : "bg-zinc-700 hover:bg-zinc-600"
        }`}
      >
        {currentItem?.is_bookmarked ? "★" : "☆"}
      </button>
    </div>
  );
}
```

- [ ] **Step 5: Create CaptionEditor**

```tsx
// frontend/src/components/edit/CaptionEditor.tsx
"use client";

import { useState, useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { useSessionStore } from "@/stores/session";

interface CaptionEditorProps {
  caption: string;
  index: number;
  onCaptionChange: (caption: string) => void;
}

export default function CaptionEditor({ caption, index, onCaptionChange }: CaptionEditorProps) {
  const [text, setText] = useState(caption);
  const [tagger, setTagger] = useState("florence");
  const [generating, setGenerating] = useState(false);

  const { data: taggers } = useQuery({
    queryKey: ["taggers"],
    queryFn: () => api.getTaggers(),
  });

  useEffect(() => {
    setText(caption);
  }, [caption]);

  const handleSave = async () => {
    await api.saveCaption(index, text);
    onCaptionChange(text);
  };

  const handleGenerate = async () => {
    setGenerating(true);
    try {
      const result = await api.generateCaption(index, tagger);
      setText(result.caption);
      onCaptionChange(result.caption);
    } finally {
      setGenerating(false);
    }
  };

  return (
    <div className="flex flex-col gap-2">
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        rows={4}
        className="w-full px-3 py-2 bg-zinc-900 border border-zinc-600 rounded text-sm text-white resize-y focus:outline-none focus:border-blue-500"
        placeholder="Caption text..."
      />

      <div className="flex items-center gap-2">
        <select
          value={tagger}
          onChange={(e) => setTagger(e.target.value)}
          className="px-2 py-1.5 bg-zinc-800 border border-zinc-600 rounded text-sm text-white"
        >
          {taggers?.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name}
            </option>
          ))}
        </select>

        <button
          onClick={handleGenerate}
          disabled={generating}
          className="px-3 py-1.5 bg-green-600 hover:bg-green-700 rounded text-sm font-medium disabled:opacity-50"
        >
          {generating ? "Generating..." : "Generate"}
        </button>

        <button
          onClick={handleSave}
          className="px-3 py-1.5 bg-blue-600 hover:bg-blue-700 rounded text-sm font-medium"
        >
          Save Caption
        </button>
      </div>
    </div>
  );
}
```

- [ ] **Step 6: Create ImageToolbar**

```tsx
// frontend/src/components/edit/ImageToolbar.tsx
"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import ConfirmDialog from "@/components/shared/ConfirmDialog";
import { useSessionStore } from "@/stores/session";

interface ImageToolbarProps {
  index: number;
  onRefresh: () => void;
}

export default function ImageToolbar({ index, onRefresh }: ImageToolbarProps) {
  const { currentItem, datasetInfo } = useSessionStore();
  const [processing, setProcessing] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [renaming, setRenaming] = useState(false);
  const [newName, setNewName] = useState("");

  const handleUpscale = async () => {
    setProcessing("upscale");
    try {
      await api.upscale(index);
      await api.saveUpscaled(index);
      onRefresh();
    } finally {
      setProcessing(null);
    }
  };

  const handleRemoveBg = async () => {
    setProcessing("rembg");
    try {
      await api.removeBackground(index);
      onRefresh();
    } finally {
      setProcessing(null);
    }
  };

  const handleGenerateMask = async () => {
    setProcessing("mask");
    try {
      await api.generateMask(index);
      onRefresh();
    } finally {
      setProcessing(null);
    }
  };

  const handleDelete = async () => {
    setConfirmDelete(false);
    await api.deleteItem(index);
    onRefresh();
  };

  const handleRename = async () => {
    if (!newName.trim()) return;
    await api.renameItem(index, newName);
    setRenaming(false);
    onRefresh();
  };

  return (
    <div className="flex flex-wrap items-center gap-2">
      {/* File info */}
      <span className="text-xs text-zinc-400 mr-2">
        {currentItem?.filename}
        {currentItem?.width && ` — ${currentItem.width}×${currentItem.height}`}
        {currentItem?.file_size && ` — ${(currentItem.file_size / 1024).toFixed(0)}KB`}
      </span>

      {/* Processing buttons */}
      <button
        onClick={handleUpscale}
        disabled={!!processing}
        className="px-3 py-1 bg-purple-600 hover:bg-purple-700 rounded text-xs disabled:opacity-50"
      >
        {processing === "upscale" ? "Upscaling..." : "Upscale"}
      </button>
      <button
        onClick={handleRemoveBg}
        disabled={!!processing}
        className="px-3 py-1 bg-teal-600 hover:bg-teal-700 rounded text-xs disabled:opacity-50"
      >
        {processing === "rembg" ? "Removing..." : "Remove BG"}
      </button>
      <button
        onClick={handleGenerateMask}
        disabled={!!processing}
        className="px-3 py-1 bg-orange-600 hover:bg-orange-700 rounded text-xs disabled:opacity-50"
      >
        {processing === "mask" ? "Generating..." : "Gen Mask"}
      </button>

      <div className="flex-1" />

      {/* File operations */}
      {renaming ? (
        <div className="flex gap-1">
          <input
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            className="w-32 px-2 py-1 bg-zinc-900 border border-zinc-600 rounded text-xs text-white"
            placeholder="New name"
          />
          <button onClick={handleRename} className="px-2 py-1 bg-blue-600 rounded text-xs">OK</button>
          <button onClick={() => setRenaming(false)} className="px-2 py-1 bg-zinc-700 rounded text-xs">Cancel</button>
        </div>
      ) : (
        <button
          onClick={() => { setRenaming(true); setNewName(currentItem?.basename ?? ""); }}
          className="px-3 py-1 bg-zinc-700 hover:bg-zinc-600 rounded text-xs"
        >
          Rename
        </button>
      )}

      <button
        onClick={() => setConfirmDelete(true)}
        className="px-3 py-1 bg-red-600 hover:bg-red-700 rounded text-xs"
      >
        Delete
      </button>

      <ConfirmDialog
        open={confirmDelete}
        title="Delete Image"
        message={`Delete ${currentItem?.filename}? This also removes its caption and mask.`}
        onConfirm={handleDelete}
        onCancel={() => setConfirmDelete(false)}
      />
    </div>
  );
}
```

- [ ] **Step 7: Create Edit page**

```tsx
// frontend/src/app/edit/page.tsx
"use client";

import { useEffect, useCallback } from "react";
import { api } from "@/lib/api";
import { useSessionStore } from "@/stores/session";
import ImageViewer from "@/components/edit/ImageViewer";
import VideoPlayer from "@/components/edit/VideoPlayer";
import NavigationBar from "@/components/edit/NavigationBar";
import CaptionEditor from "@/components/edit/CaptionEditor";
import ImageToolbar from "@/components/edit/ImageToolbar";

export default function EditPage() {
  const { currentIndex, currentItem, datasetInfo, setCurrentItem, setCurrentIndex } =
    useSessionStore();

  const loadItem = useCallback(async (index: number) => {
    try {
      const item = await api.getItem(index);
      setCurrentIndex(index);
      setCurrentItem(item);
    } catch {
      // index out of range — stay put
    }
  }, [setCurrentIndex, setCurrentItem]);

  useEffect(() => {
    if (datasetInfo) {
      loadItem(currentIndex);
    }
  }, [datasetInfo]); // eslint-disable-line react-hooks/exhaustive-deps

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLTextAreaElement || e.target instanceof HTMLInputElement) return;
      if (e.key === "ArrowLeft") loadItem(Math.max(0, currentIndex - 1));
      if (e.key === "ArrowRight") loadItem(Math.min((datasetInfo?.total_items ?? 1) - 1, currentIndex + 1));
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [currentIndex, datasetInfo, loadItem]);

  if (!datasetInfo) {
    return <div className="text-zinc-500 text-center py-12">Load a dataset to start editing</div>;
  }

  if (!currentItem) {
    return <div className="text-zinc-500 text-center py-12">Loading...</div>;
  }

  return (
    <div className="flex flex-col h-full gap-3">
      <ImageToolbar index={currentIndex} onRefresh={() => loadItem(currentIndex)} />

      <div className="flex-1 min-h-0">
        {currentItem.is_video ? (
          <VideoPlayer mediaUrl={currentItem.media_url} />
        ) : (
          <ImageViewer mediaUrl={currentItem.media_url} filename={currentItem.filename} />
        )}
      </div>

      <CaptionEditor
        caption={currentItem.caption}
        index={currentIndex}
        onCaptionChange={(caption) =>
          setCurrentItem({ ...currentItem, caption })
        }
      />

      <NavigationBar onNavigate={loadItem} />
    </div>
  );
}
```

- [ ] **Step 8: Commit**

```bash
git add frontend/src/app/edit/ frontend/src/components/edit/ frontend/src/components/shared/
git commit -m "feat: add edit page with image viewer, caption editor, toolbar, and keyboard navigation"
```

---

## Phase 4: Captions Page

### Task 18: Captions Page (Tag Cloud + Operations)

**Files:**
- Create: `frontend/src/app/captions/page.tsx`
- Create: `frontend/src/components/captions/TagCloud.tsx`
- Create: `frontend/src/components/captions/TagOperations.tsx`
- Create: `frontend/src/components/captions/SearchReplace.tsx`

- [ ] **Step 1: Create TagCloud component**

```tsx
// frontend/src/components/captions/TagCloud.tsx
"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { useSessionStore } from "@/stores/session";
import type { TagCloudEntry } from "@/lib/types";

interface TagCloudProps {
  onSelectedTagsChange: (tags: string[]) => void;
}

export default function TagCloud({ onSelectedTagsChange }: TagCloudProps) {
  const { datasetInfo } = useSessionStore();
  const [sortBy, setSortBy] = useState<"frequency" | "alpha">("frequency");
  const [selected, setSelected] = useState<Set<string>>(new Set());

  const { data: tags, isLoading, refetch } = useQuery({
    queryKey: ["tagCloud", sortBy, datasetInfo?.total_items],
    queryFn: () => api.getTagCloud(sortBy),
    enabled: !!datasetInfo,
  });

  const toggleTag = (tag: string) => {
    const next = new Set(selected);
    if (next.has(tag)) next.delete(tag);
    else next.add(tag);
    setSelected(next);
    onSelectedTagsChange(Array.from(next));
  };

  const selectAll = () => {
    const all = new Set(tags?.map((t) => t.tag) ?? []);
    setSelected(all);
    onSelectedTagsChange(Array.from(all));
  };

  const clearSelection = () => {
    setSelected(new Set());
    onSelectedTagsChange([]);
  };

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-2">
        <h3 className="text-sm font-medium">Tag Cloud</h3>
        <select
          value={sortBy}
          onChange={(e) => setSortBy(e.target.value as "frequency" | "alpha")}
          className="text-xs bg-zinc-800 border border-zinc-600 rounded px-2 py-1"
        >
          <option value="frequency">By frequency</option>
          <option value="alpha">Alphabetical</option>
        </select>
        <button onClick={selectAll} className="text-xs text-blue-400 hover:text-blue-300">Select all</button>
        <button onClick={clearSelection} className="text-xs text-zinc-400 hover:text-zinc-300">Clear</button>
        <button onClick={() => refetch()} className="text-xs text-zinc-400 hover:text-zinc-300">Refresh</button>
      </div>

      {isLoading ? (
        <div className="text-zinc-500 text-sm">Loading tags...</div>
      ) : (
        <div className="flex flex-wrap gap-1 max-h-64 overflow-y-auto p-2 bg-zinc-900 rounded border border-zinc-700">
          {tags?.map((entry) => (
            <button
              key={entry.tag}
              onClick={() => toggleTag(entry.tag)}
              className={`px-2 py-0.5 rounded text-xs transition-colors ${
                selected.has(entry.tag)
                  ? "bg-blue-600 text-white"
                  : "bg-zinc-800 text-zinc-300 hover:bg-zinc-700"
              }`}
            >
              {entry.tag} ({entry.count})
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Create TagOperations component**

```tsx
// frontend/src/components/captions/TagOperations.tsx
"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { useQueryClient } from "@tanstack/react-query";

interface TagOperationsProps {
  selectedTags: string[];
}

export default function TagOperations({ selectedTags }: TagOperationsProps) {
  const [appendTag, setAppendTag] = useState("");
  const [prependTag, setPrependTag] = useState("");
  const [subdirName, setSubdirName] = useState("");
  const [inverse, setInverse] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["tagCloud"] });

  const handleRemove = async () => {
    if (selectedTags.length === 0) return;
    const result = await api.removeTags(selectedTags);
    setStatus(`Removed from ${(result as { modified: number }).modified} captions`);
    refresh();
  };

  const handleCleanup = async () => {
    const result = await api.cleanupTags();
    setStatus(`Cleaned ${(result as { modified: number }).modified} captions`);
    refresh();
  };

  const handleReplaceUnderscores = async () => {
    const result = await api.replaceUnderscores();
    setStatus(`Updated ${(result as { modified: number }).modified} captions`);
    refresh();
  };

  const handleAppend = async () => {
    if (!appendTag.trim()) return;
    const result = await api.appendTag(appendTag.trim());
    setStatus(`Appended to ${(result as { modified: number }).modified} captions`);
    setAppendTag("");
    refresh();
  };

  const handlePrepend = async () => {
    if (!prependTag.trim()) return;
    const result = await api.prependTag(prependTag.trim());
    setStatus(`Prepended to ${(result as { modified: number }).modified} captions`);
    setPrependTag("");
    refresh();
  };

  const handleMoveToSubdir = async () => {
    if (selectedTags.length === 0 || !subdirName.trim()) return;
    const result = await api.moveToSubdir(selectedTags, inverse, subdirName.trim());
    setStatus(`Moved ${(result as { moved: number }).moved} images`);
    refresh();
  };

  const handleExport = async () => {
    const result = await api.exportJsonl();
    setStatus(`Exported ${result.count} captions to ${result.path}`);
  };

  return (
    <div className="flex flex-col gap-3">
      {status && (
        <div className="text-xs text-green-400 bg-green-900/20 px-3 py-1.5 rounded">
          {status}
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        <button onClick={handleRemove} disabled={selectedTags.length === 0}
          className="px-3 py-1.5 bg-red-600 hover:bg-red-700 rounded text-xs disabled:opacity-50">
          Remove Selected Tags
        </button>
        <button onClick={handleCleanup}
          className="px-3 py-1.5 bg-orange-600 hover:bg-orange-700 rounded text-xs">
          Cleanup Tags
        </button>
        <button onClick={handleReplaceUnderscores}
          className="px-3 py-1.5 bg-zinc-700 hover:bg-zinc-600 rounded text-xs">
          Replace Underscores
        </button>
        <button onClick={handleExport}
          className="px-3 py-1.5 bg-zinc-700 hover:bg-zinc-600 rounded text-xs">
          Export JSONL
        </button>
      </div>

      <div className="flex gap-2">
        <input
          value={appendTag}
          onChange={(e) => setAppendTag(e.target.value)}
          placeholder="Tag to append..."
          className="flex-1 px-2 py-1 bg-zinc-900 border border-zinc-600 rounded text-xs text-white"
        />
        <button onClick={handleAppend} className="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-xs">
          Append
        </button>
      </div>

      <div className="flex gap-2">
        <input
          value={prependTag}
          onChange={(e) => setPrependTag(e.target.value)}
          placeholder="Tag to prepend..."
          className="flex-1 px-2 py-1 bg-zinc-900 border border-zinc-600 rounded text-xs text-white"
        />
        <button onClick={handlePrepend} className="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-xs">
          Prepend
        </button>
      </div>

      <div className="flex gap-2 items-center">
        <input
          value={subdirName}
          onChange={(e) => setSubdirName(e.target.value)}
          placeholder="Subdirectory name..."
          className="flex-1 px-2 py-1 bg-zinc-900 border border-zinc-600 rounded text-xs text-white"
        />
        <label className="flex items-center gap-1 text-xs text-zinc-400">
          <input type="checkbox" checked={inverse} onChange={(e) => setInverse(e.target.checked)} />
          Inverse
        </label>
        <button onClick={handleMoveToSubdir} disabled={selectedTags.length === 0}
          className="px-3 py-1 bg-purple-600 hover:bg-purple-700 rounded text-xs disabled:opacity-50">
          Move to Subdir
        </button>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Create SearchReplace component**

```tsx
// frontend/src/components/captions/SearchReplace.tsx
"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import type { SearchReplacePreview } from "@/lib/types";
import { useQueryClient } from "@tanstack/react-query";

export default function SearchReplace() {
  const [search, setSearch] = useState("");
  const [replace, setReplace] = useState("");
  const [preview, setPreview] = useState<SearchReplacePreview | null>(null);
  const queryClient = useQueryClient();

  const handlePreview = async () => {
    if (!search.trim()) return;
    const result = await api.searchReplacePreview(search, replace);
    setPreview(result);
  };

  const handleApply = async () => {
    if (!search.trim()) return;
    await api.searchReplaceApply(search, replace);
    setPreview(null);
    setSearch("");
    setReplace("");
    queryClient.invalidateQueries({ queryKey: ["tagCloud"] });
  };

  return (
    <div className="flex flex-col gap-2">
      <h3 className="text-sm font-medium">Search & Replace</h3>
      <div className="flex gap-2">
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search..."
          className="flex-1 px-2 py-1 bg-zinc-900 border border-zinc-600 rounded text-xs text-white"
        />
        <input
          value={replace}
          onChange={(e) => setReplace(e.target.value)}
          placeholder="Replace with..."
          className="flex-1 px-2 py-1 bg-zinc-900 border border-zinc-600 rounded text-xs text-white"
        />
        <button onClick={handlePreview} className="px-3 py-1 bg-zinc-700 hover:bg-zinc-600 rounded text-xs">
          Preview
        </button>
        <button onClick={handleApply} disabled={!preview} className="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-xs disabled:opacity-50">
          Apply
        </button>
      </div>

      {preview && (
        <div className="max-h-48 overflow-y-auto bg-zinc-900 rounded border border-zinc-700 p-2 text-xs">
          <p className="text-zinc-400 mb-1">{preview.total_matches} matches</p>
          {preview.matches.slice(0, 20).map((m) => (
            <div key={m.index} className="mb-1">
              <span className="text-zinc-500">{m.filename}:</span>{" "}
              <span className="text-red-400 line-through">{m.before.substring(0, 80)}</span>{" "}
              → <span className="text-green-400">{m.after.substring(0, 80)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Create captions page**

```tsx
// frontend/src/app/captions/page.tsx
"use client";

import { useState } from "react";
import { useSessionStore } from "@/stores/session";
import TagCloud from "@/components/captions/TagCloud";
import TagOperations from "@/components/captions/TagOperations";
import SearchReplace from "@/components/captions/SearchReplace";

export default function CaptionsPage() {
  const { datasetInfo } = useSessionStore();
  const [selectedTags, setSelectedTags] = useState<string[]>([]);

  if (!datasetInfo) {
    return <div className="text-zinc-500 text-center py-12">Load a dataset to manage captions</div>;
  }

  return (
    <div className="flex flex-col gap-6 max-w-4xl">
      <TagCloud onSelectedTagsChange={setSelectedTags} />
      <TagOperations selectedTags={selectedTags} />
      <SearchReplace />
    </div>
  );
}
```

- [ ] **Step 5: Commit**

```bash
git add frontend/src/app/captions/ frontend/src/components/captions/
git commit -m "feat: add captions page with tag cloud, bulk operations, and search/replace"
```

---

## Phase 5: Batch, Tools, Validation, Settings Pages

### Task 19: Batch Processing Page

**Files:**
- Create: `frontend/src/app/batch/page.tsx`
- Create: `frontend/src/components/batch/BatchForm.tsx`
- Create: `frontend/src/components/batch/ProgressLog.tsx`

- [ ] **Step 1: Create ProgressLog component**

```tsx
// frontend/src/components/batch/ProgressLog.tsx
"use client";

import type { BatchProgress } from "@/lib/types";

interface ProgressLogProps {
  entries: BatchProgress[];
  isRunning: boolean;
}

export default function ProgressLog({ entries, isRunning }: ProgressLogProps) {
  const latest = entries[entries.length - 1];
  const progressPercent = latest ? Math.round(latest.progress * 100) : 0;

  return (
    <div className="flex flex-col gap-2">
      {latest && (
        <div className="flex items-center gap-3">
          <div className="flex-1 h-2 bg-zinc-800 rounded overflow-hidden">
            <div
              className="h-full bg-blue-600 transition-all duration-300"
              style={{ width: `${progressPercent}%` }}
            />
          </div>
          <span className="text-xs text-zinc-400 min-w-[60px]">
            {latest.index + 1} / {latest.total}
          </span>
        </div>
      )}

      <div className="h-64 overflow-y-auto bg-zinc-900 rounded border border-zinc-700 p-2 font-mono text-xs text-zinc-300">
        {entries.map((entry, i) => (
          <div key={i} className="py-0.5">
            <span className="text-zinc-500">[{entry.index + 1}/{entry.total}]</span>{" "}
            <span className="text-zinc-400">{entry.filename}</span>{" "}
            {entry.log}
          </div>
        ))}
        {isRunning && <div className="text-blue-400 animate-pulse">Processing...</div>}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Create BatchForm component**

```tsx
// frontend/src/components/batch/BatchForm.tsx
"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";
import type { BatchProgress, BucketResult } from "@/lib/types";
import ProgressLog from "./ProgressLog";

export default function BatchForm() {
  const [rename, setRename] = useState(false);
  const [upscale, setUpscale] = useState(false);
  const [bucketResize, setBucketResize] = useState(false);
  const [mask, setMask] = useState(false);
  const [caption, setCaption] = useState(false);
  const [tagger, setTagger] = useState("florence");
  const [resolution, setResolution] = useState(1024);
  const [step, setStep] = useState(64);
  const [maxSteps, setMaxSteps] = useState(4);
  const [isRunning, setIsRunning] = useState(false);
  const [logEntries, setLogEntries] = useState<BatchProgress[]>([]);
  const [bucketResult, setBucketResult] = useState<BucketResult | null>(null);

  const { data: taggers } = useQuery({
    queryKey: ["taggers"],
    queryFn: () => api.getTaggers(),
  });

  const handleStart = async () => {
    setIsRunning(true);
    setLogEntries([]);
    try {
      // Note: batch processing with SSE requires a different approach.
      // For now, we use the POST endpoint and parse SSE events.
      const response = await fetch("/api/batch/process", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Session-ID": (await api.getSettings(), ""), // get session from api module
        },
        body: JSON.stringify({
          rename, upscale, bucket_resize: bucketResize,
          mask, caption, tagger,
          bucket_resolution: resolution,
          bucket_step: step,
          bucket_max_steps: maxSteps,
        }),
      });

      const reader = response.body?.getReader();
      const decoder = new TextDecoder();
      if (reader) {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          const text = decoder.decode(value);
          // Parse SSE events
          const lines = text.split("\n");
          for (const line of lines) {
            if (line.startsWith("data: ")) {
              try {
                const data = JSON.parse(line.substring(6));
                if (data.index !== undefined) {
                  setLogEntries((prev) => [...prev, data as BatchProgress]);
                }
              } catch { /* ignore parse errors */ }
            }
          }
        }
      }
    } finally {
      setIsRunning(false);
    }
  };

  const handleAnalyzeBuckets = async () => {
    const result = await api.analyzeBuckets(resolution, step, maxSteps);
    setBucketResult(result);
  };

  return (
    <div className="flex flex-col gap-4 max-w-2xl">
      <h2 className="text-lg font-medium">Batch Processing</h2>

      <div className="grid grid-cols-2 gap-3">
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={rename} onChange={(e) => setRename(e.target.checked)} />
          Rename (sequential numbering)
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={upscale} onChange={(e) => setUpscale(e.target.checked)} />
          Upscale
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={bucketResize} onChange={(e) => setBucketResize(e.target.checked)} />
          Bucket Resize
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={mask} onChange={(e) => setMask(e.target.checked)} />
          Generate Masks
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={caption} onChange={(e) => setCaption(e.target.checked)} />
          Generate Captions
        </label>
      </div>

      {caption && (
        <div className="flex items-center gap-2">
          <label className="text-sm text-zinc-400">Tagger:</label>
          <select
            value={tagger}
            onChange={(e) => setTagger(e.target.value)}
            className="px-2 py-1 bg-zinc-800 border border-zinc-600 rounded text-sm"
          >
            {taggers?.map((t) => (
              <option key={t.id} value={t.id}>{t.name}</option>
            ))}
          </select>
        </div>
      )}

      {bucketResize && (
        <div className="flex gap-3">
          <div>
            <label className="block text-xs text-zinc-400 mb-1">Resolution</label>
            <input type="number" value={resolution} onChange={(e) => setResolution(Number(e.target.value))}
              className="w-24 px-2 py-1 bg-zinc-900 border border-zinc-600 rounded text-sm" />
          </div>
          <div>
            <label className="block text-xs text-zinc-400 mb-1">Step</label>
            <input type="number" value={step} onChange={(e) => setStep(Number(e.target.value))}
              className="w-20 px-2 py-1 bg-zinc-900 border border-zinc-600 rounded text-sm" />
          </div>
          <div>
            <label className="block text-xs text-zinc-400 mb-1">Max Steps</label>
            <input type="number" value={maxSteps} onChange={(e) => setMaxSteps(Number(e.target.value))}
              className="w-20 px-2 py-1 bg-zinc-900 border border-zinc-600 rounded text-sm" />
          </div>
        </div>
      )}

      <div className="flex gap-2">
        <button
          onClick={handleStart}
          disabled={isRunning || (!rename && !upscale && !bucketResize && !mask && !caption)}
          className="px-4 py-2 bg-green-600 hover:bg-green-700 rounded text-sm font-medium disabled:opacity-50"
        >
          {isRunning ? "Processing..." : "Start Batch"}
        </button>
        <button
          onClick={handleAnalyzeBuckets}
          className="px-4 py-2 bg-zinc-700 hover:bg-zinc-600 rounded text-sm"
        >
          Analyze Buckets
        </button>
      </div>

      <ProgressLog entries={logEntries} isRunning={isRunning} />

      {bucketResult && (
        <div className="bg-zinc-900 rounded border border-zinc-700 p-3">
          <h3 className="text-sm font-medium mb-2">Bucket Analysis ({bucketResult.total_images} images)</h3>
          <div className="grid grid-cols-3 gap-2 text-xs">
            {bucketResult.buckets.map((b, i) => (
              <div key={i} className="bg-zinc-800 rounded p-2">
                {b.width}×{b.height}: {b.count} images
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Create batch page**

```tsx
// frontend/src/app/batch/page.tsx
"use client";

import { useSessionStore } from "@/stores/session";
import BatchForm from "@/components/batch/BatchForm";

export default function BatchPage() {
  const { datasetInfo } = useSessionStore();

  if (!datasetInfo) {
    return <div className="text-zinc-500 text-center py-12">Load a dataset for batch processing</div>;
  }

  return <BatchForm />;
}
```

- [ ] **Step 4: Commit**

```bash
git add frontend/src/app/batch/ frontend/src/components/batch/
git commit -m "feat: add batch processing page with SSE progress streaming"
```

---

### Task 20: Tools, Validation, and Settings Pages

**Files:**
- Create: `frontend/src/app/tools/page.tsx`
- Create: `frontend/src/app/validation/page.tsx`
- Create: `frontend/src/app/settings/page.tsx`

- [ ] **Step 1: Create Tools page**

```tsx
// frontend/src/app/tools/page.tsx
"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { useSessionStore } from "@/stores/session";

export default function ToolsPage() {
  const { datasetInfo } = useSessionStore();
  const [targetDir, setTargetDir] = useState("");
  const [option, setOption] = useState("all");
  const [status, setStatus] = useState<string | null>(null);

  if (!datasetInfo) {
    return <div className="text-zinc-500 text-center py-12">Load a dataset first</div>;
  }

  const handleCopy = async () => {
    if (!targetDir.trim()) return;
    const result = await api.copyImages(targetDir, option);
    setStatus(`Copied ${(result as { copied: number }).copied} images to ${targetDir}`);
  };

  return (
    <div className="max-w-lg flex flex-col gap-4">
      <h2 className="text-lg font-medium">Copy Images</h2>

      <input
        value={targetDir}
        onChange={(e) => setTargetDir(e.target.value)}
        placeholder="Target directory..."
        className="px-3 py-2 bg-zinc-900 border border-zinc-600 rounded text-sm text-white"
      />

      <div className="flex gap-4">
        <label className="flex items-center gap-2 text-sm">
          <input type="radio" value="all" checked={option === "all"} onChange={() => setOption("all")} />
          All images
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="radio" value="bookmarks" checked={option === "bookmarks"} onChange={() => setOption("bookmarks")} />
          Bookmarked only
        </label>
      </div>

      <button onClick={handleCopy} className="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded text-sm font-medium w-fit">
        Copy
      </button>

      {status && <div className="text-xs text-green-400">{status}</div>}
    </div>
  );
}
```

- [ ] **Step 2: Create Validation page**

```tsx
// frontend/src/app/validation/page.tsx
"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { useSessionStore } from "@/stores/session";

export default function ValidationPage() {
  const { datasetInfo } = useSessionStore();
  const [report, setReport] = useState<{ buckets: Array<{ width: number; height: number; count: number }>; total_images: number; summary: string } | null>(null);

  if (!datasetInfo) {
    return <div className="text-zinc-500 text-center py-12">Load a dataset to validate</div>;
  }

  const handleValidate = async () => {
    const result = await api.validate();
    setReport(result as typeof report);
  };

  return (
    <div className="max-w-2xl flex flex-col gap-4">
      <button onClick={handleValidate} className="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded text-sm font-medium w-fit">
        Run Validation
      </button>

      {report && (
        <div className="bg-zinc-900 rounded border border-zinc-700 p-4">
          <h3 className="text-sm font-medium mb-2">Validation Report ({report.total_images} images)</h3>
          <p className="text-xs text-zinc-400 mb-3">{report.summary}</p>
          <div className="grid grid-cols-3 gap-2 text-xs">
            {report.buckets.map((b, i) => (
              <div key={i} className="bg-zinc-800 rounded p-2">
                {b.width}×{b.height}: {b.count}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Create Settings page**

```tsx
// frontend/src/app/settings/page.tsx
"use client";

import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api";
import type { Settings, Upscaler, Tagger } from "@/lib/types";

export default function SettingsPage() {
  const queryClient = useQueryClient();
  const { data: settings, isLoading } = useQuery({ queryKey: ["settings"], queryFn: () => api.getSettings() });
  const { data: upscalers } = useQuery({ queryKey: ["upscalers"], queryFn: () => api.getUpscalers() });
  const { data: taggers } = useQuery({ queryKey: ["taggers"], queryFn: () => api.getTaggers() });

  const [localSettings, setLocalSettings] = useState<Settings | null>(null);

  useEffect(() => {
    if (settings) setLocalSettings(settings);
  }, [settings]);

  if (isLoading || !localSettings) {
    return <div className="text-zinc-500">Loading settings...</div>;
  }

  const save = async (key: string, value: unknown) => {
    await api.updateSetting(key, value);
    queryClient.invalidateQueries({ queryKey: ["settings"] });
  };

  return (
    <div className="max-w-2xl flex flex-col gap-6">
      <h2 className="text-lg font-medium">Settings</h2>

      {/* Upscaler */}
      <div>
        <label className="block text-sm text-zinc-400 mb-1">Upscaler</label>
        <select
          value={localSettings.upscaler}
          onChange={(e) => { setLocalSettings({ ...localSettings, upscaler: e.target.value }); save("upscaler", e.target.value); }}
          className="w-full px-3 py-2 bg-zinc-900 border border-zinc-600 rounded text-sm"
        >
          {upscalers?.map((u) => (
            <option key={u.name} value={u.name}>{u.name} ({u.scale_factor}x)</option>
          ))}
        </select>
      </div>

      {/* Target megapixels */}
      <div>
        <label className="block text-sm text-zinc-400 mb-1">Upscale Target (megapixels)</label>
        <input
          type="number"
          step="0.5"
          value={localSettings.upscale_target_megapixels}
          onChange={(e) => { const v = Number(e.target.value); setLocalSettings({ ...localSettings, upscale_target_megapixels: v }); save("upscale_target_megapixels", v); }}
          className="w-32 px-3 py-2 bg-zinc-900 border border-zinc-600 rounded text-sm"
        />
      </div>

      {/* Combo taggers */}
      <div>
        <label className="block text-sm text-zinc-400 mb-1">Combo Taggers</label>
        <div className="flex gap-3">
          {taggers?.filter((t) => t.id !== "combo").map((t) => (
            <label key={t.id} className="flex items-center gap-1 text-sm">
              <input
                type="checkbox"
                checked={localSettings.combo_taggers.includes(t.id)}
                onChange={(e) => {
                  const next = e.target.checked
                    ? [...localSettings.combo_taggers, t.id]
                    : localSettings.combo_taggers.filter((x) => x !== t.id);
                  setLocalSettings({ ...localSettings, combo_taggers: next });
                  save("combo_taggers", next);
                }}
              />
              {t.name}
            </label>
          ))}
        </div>
      </div>

      {/* Florence prompt */}
      <div>
        <label className="block text-sm text-zinc-400 mb-1">Florence Prompt</label>
        <select
          value={localSettings.florence_settings.prompt}
          onChange={(e) => {
            const next = { prompt: e.target.value };
            setLocalSettings({ ...localSettings, florence_settings: next });
            save("florence_settings", next);
          }}
          className="w-full px-3 py-2 bg-zinc-900 border border-zinc-600 rounded text-sm"
        >
          <option value="<GENERATE_PROMPT>">Generate Prompt</option>
          <option value="<DETAILED_CAPTION>">Detailed Caption</option>
          <option value="<MORE_DETAILED_CAPTION>">More Detailed Caption</option>
        </select>
      </div>

      {/* Tagger instruction */}
      <div>
        <label className="block text-sm text-zinc-400 mb-1">Tagger Instruction</label>
        <textarea
          value={localSettings.tagger_instruction}
          onChange={(e) => setLocalSettings({ ...localSettings, tagger_instruction: e.target.value })}
          onBlur={() => save("tagger_instruction", localSettings.tagger_instruction)}
          rows={3}
          className="w-full px-3 py-2 bg-zinc-900 border border-zinc-600 rounded text-sm resize-y"
        />
      </div>

      {/* Rembg model */}
      <div>
        <label className="block text-sm text-zinc-400 mb-1">Background Removal Model</label>
        <select
          value={localSettings.rembg.model}
          onChange={(e) => {
            const next = { model: e.target.value };
            setLocalSettings({ ...localSettings, rembg: next });
            save("rembg", next);
          }}
          className="w-full px-3 py-2 bg-zinc-900 border border-zinc-600 rounded text-sm"
        >
          <option value="u2net_human_seg">u2net_human_seg</option>
          <option value="u2net">u2net</option>
          <option value="u2net_cloth_seg">u2net_cloth_seg</option>
        </select>
      </div>

      {/* OpenAI settings */}
      <div className="border border-zinc-700 rounded p-4">
        <h3 className="text-sm font-medium mb-3">OpenAI-Compatible API</h3>
        <div className="flex flex-col gap-3">
          <div>
            <label className="block text-xs text-zinc-400 mb-1">Base URL</label>
            <input
              value={localSettings.openai_settings.base_url}
              onChange={(e) => setLocalSettings({
                ...localSettings,
                openai_settings: { ...localSettings.openai_settings, base_url: e.target.value },
              })}
              onBlur={() => save("openai_settings", localSettings.openai_settings)}
              className="w-full px-3 py-1.5 bg-zinc-900 border border-zinc-600 rounded text-sm"
            />
          </div>
          <div>
            <label className="block text-xs text-zinc-400 mb-1">Model</label>
            <input
              value={localSettings.openai_settings.model}
              onChange={(e) => setLocalSettings({
                ...localSettings,
                openai_settings: { ...localSettings.openai_settings, model: e.target.value },
              })}
              onBlur={() => save("openai_settings", localSettings.openai_settings)}
              className="w-full px-3 py-1.5 bg-zinc-900 border border-zinc-600 rounded text-sm"
            />
          </div>
          <div>
            <label className="block text-xs text-zinc-400 mb-1">API Key</label>
            <input
              type="password"
              value={localSettings.openai_settings.api_key}
              onChange={(e) => setLocalSettings({
                ...localSettings,
                openai_settings: { ...localSettings.openai_settings, api_key: e.target.value },
              })}
              onBlur={() => save("openai_settings", localSettings.openai_settings)}
              className="w-full px-3 py-1.5 bg-zinc-900 border border-zinc-600 rounded text-sm"
            />
          </div>
          <div>
            <label className="block text-xs text-zinc-400 mb-1">Prompt</label>
            <textarea
              value={localSettings.openai_settings.prompt}
              onChange={(e) => setLocalSettings({
                ...localSettings,
                openai_settings: { ...localSettings.openai_settings, prompt: e.target.value },
              })}
              onBlur={() => save("openai_settings", localSettings.openai_settings)}
              rows={2}
              className="w-full px-3 py-1.5 bg-zinc-900 border border-zinc-600 rounded text-sm resize-y"
            />
          </div>
        </div>
      </div>

      {/* Models directory */}
      <div>
        <label className="block text-sm text-zinc-400 mb-1">Models Directory</label>
        <input
          value={localSettings.models_dir}
          onChange={(e) => setLocalSettings({ ...localSettings, models_dir: e.target.value })}
          onBlur={() => save("models_dir", localSettings.models_dir)}
          className="w-full px-3 py-2 bg-zinc-900 border border-zinc-600 rounded text-sm"
        />
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Commit**

```bash
git add frontend/src/app/tools/ frontend/src/app/validation/ frontend/src/app/settings/
git commit -m "feat: add tools, validation, and settings pages"
```

---

## Phase 6: Integration & Polish

### Task 21: Backend sys.path Fixes & Startup Script

**Files:**
- Modify: `backend/app/main.py` (add sys.path setup at top)
- Create: `run.sh` (convenience script)

- [ ] **Step 1: Fix sys.path in main.py for lib imports**

Add at the top of `backend/app/main.py`, before any imports:

```python
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
```

- [ ] **Step 2: Create run.sh convenience script**

```bash
#!/bin/bash
# run.sh — Start both backend and frontend dev servers

echo "Starting ImageTagger..."

# Backend
cd backend
uvicorn app.main:app --reload --port 8000 &
BACKEND_PID=$!

# Frontend
cd ../frontend
npm run dev &
FRONTEND_PID=$!

echo "Backend: http://localhost:8000"
echo "Frontend: http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop both servers."

trap "kill $BACKEND_PID $FRONTEND_PID 2>/dev/null" EXIT
wait
```

- [ ] **Step 3: Commit**

```bash
chmod +x run.sh
git add run.sh backend/app/main.py
git commit -m "feat: add startup script and fix backend sys.path for lib imports"
```

---

### Task 22: Media URL Authentication for Image Tags

The `<img>` and `<video>` tags cannot send custom headers. We need to support session ID via query parameter for media endpoints.

**Files:**
- Modify: `backend/app/routers/media.py` (accept session_id as query param)
- Modify: `backend/app/sessions.py` (add query param dependency)

- [ ] **Step 1: Add query param session support**

Add to `backend/app/sessions.py`:

```python
from fastapi import Query

def get_session_flexible(
    x_session_id: str = Header(None),
    session_id: str = Query(None),
) -> Session:
    """Accept session ID from header or query param (for img/video src)."""
    sid = x_session_id or session_id
    if not sid:
        raise HTTPException(status_code=401, detail="Session ID required")
    session = session_manager.get(sid)
    if session is None:
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    return session
```

- [ ] **Step 2: Update media router to use flexible session**

Replace `get_session` with `get_session_flexible` in all media router endpoints:

```python
from app.sessions import Session, get_session_flexible

@router.get("/file/{index}")
def serve_media(index: int, session: Session = Depends(get_session_flexible)):
    # ... unchanged body

@router.get("/thumbnail/{index}")
def serve_thumbnail(index: int, session: Session = Depends(get_session_flexible)):
    # ... unchanged body

@router.get("/mask/{index}")
def serve_mask(index: int, session: Session = Depends(get_session_flexible)):
    # ... unchanged body
```

- [ ] **Step 3: Update frontend API client media URLs**

The `api.ts` file's `mediaUrl` and `thumbnailUrl` already include session_id as a query param — verify this works with the new flexible dependency.

- [ ] **Step 4: Update frontend components to use session-aware URLs**

In `GalleryGrid.tsx` and `ImageViewer.tsx`, the thumbnail/media URLs need the session_id query param. Update `api.ts`:

```typescript
// Add to api.ts — synchronous URL builder (session must be initialized)
export function getMediaUrl(index: number): string {
  return `/api/media/file/${index}?session_id=${sessionId}`;
}

export function getThumbnailUrl(index: number): string {
  return `/api/media/thumbnail/${index}?session_id=${sessionId}`;
}
```

Then update components to use these instead of hardcoded paths.

- [ ] **Step 5: Commit**

```bash
git add backend/app/sessions.py backend/app/routers/media.py frontend/src/lib/api.ts
git commit -m "feat: support session ID via query param for media URLs in img/video tags"
```

---

### Task 23: End-to-End Smoke Test

- [ ] **Step 1: Start both servers**

```bash
./run.sh
```

- [ ] **Step 2: Manual verification checklist**

Test each feature in order:

1. Open `http://localhost:3000` → redirects to `/browse`
2. Enter a folder path with images → click Open → gallery loads
3. Click an image → redirects to `/edit` with the image displayed
4. Arrow keys navigate between images
5. Type caption text → click Save Caption
6. Select a tagger → click Generate → caption appears
7. Click Upscale → image is upscaled
8. Navigate to `/captions` → tag cloud loads with correct frequencies
9. Select tags → click Remove → tags are removed from captions
10. Search & Replace → preview shows correctly → Apply works
11. Navigate to `/batch` → select operations → Start → progress streams
12. Navigate to `/settings` → change upscaler → setting persists after page reload
13. Navigate to `/tools` → copy images to a target dir

- [ ] **Step 3: Fix any issues found**

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete Next.js + FastAPI rewrite of ImageTagger"
```

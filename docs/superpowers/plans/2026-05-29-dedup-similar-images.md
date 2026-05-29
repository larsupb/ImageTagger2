# Duplicate / Similar Image Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/dedup` page that finds perceptually similar images (pHash + SSIM), lets the user review groups and pick a keeper, then deletes the rest.

**Architecture:** Backend service computes pHash for each image, groups candidate pairs by Hamming distance, confirms pairs with SSIM at 256×256, returns groups to the router. A new dedicated frontend page drives a three-phase state machine (idle → scanning → reviewing → done).

**Tech Stack:** Python `imagehash` (pHash), `scikit-image` (SSIM, already installed), `PIL` (image loading), FastAPI, React 19 / Next.js 15, TypeScript, Tailwind CSS 4.

---

## Files

**Create:**
- `backend/app/services/dedup_service.py` — pHash + SSIM grouping logic
- `backend/app/routers/dedup.py` — `/api/dedup/scan` and `/api/dedup/remove` endpoints
- `frontend/src/app/dedup/page.tsx` — thin page wrapper (matches export/browse pattern)
- `frontend/src/components/dedup/DedupPage.tsx` — full three-phase state machine UI

**Modify:**
- `backend/requirements.txt` — add `imagehash`
- `backend/app/models/schemas.py` — add dedup Pydantic schemas
- `backend/app/main.py` — register dedup router
- `frontend/src/lib/types.ts` — add dedup TypeScript types
- `frontend/src/lib/api.ts` — add `scanForDuplicates`, `removeDuplicates`
- `frontend/src/components/layout/Sidebar.tsx` — add Dedup nav link

---

## Task 1: Add imagehash dependency

**Files:**
- Modify: `backend/requirements.txt`

- [ ] **Step 1: Add imagehash to requirements.txt**

Open `backend/requirements.txt` and add the line `imagehash` (place it alphabetically near the `i` entries):

```
imagehash
```

- [ ] **Step 2: Install the dependency**

```bash
cd backend && source .venv/bin/activate && pip install imagehash
```

Expected: `Successfully installed imagehash-...`

- [ ] **Step 3: Verify import works**

```bash
cd backend && source .venv/bin/activate && python -c "import imagehash; print('ok')"
```

Expected: `ok`

- [ ] **Step 4: Commit**

```bash
git add backend/requirements.txt
git commit -m "Add imagehash dependency for perceptual hashing"
```

---

## Task 2: Add dedup Pydantic schemas

**Files:**
- Modify: `backend/app/models/schemas.py`

- [ ] **Step 1: Add dedup schemas to the bottom of schemas.py**

Append to `backend/app/models/schemas.py`:

```python
# --- Dedup ---
class DedupScanRequest(BaseModel):
    phash_threshold: int = 10
    ssim_threshold: float = 0.85


class DedupImageInfo(BaseModel):
    index: int
    filename: str
    width: Optional[int] = None
    height: Optional[int] = None
    file_size: Optional[int] = None
    thumbnail_url: str
    path: str


class DedupGroup(BaseModel):
    images: list[DedupImageInfo]
    keep_index: int


class DedupScanResponse(BaseModel):
    groups: list[DedupGroup]


class DedupRemoveRequest(BaseModel):
    paths: list[str]
```

- [ ] **Step 2: Verify the file parses cleanly**

```bash
cd backend && source .venv/bin/activate && python -c "from app.models.schemas import DedupScanRequest, DedupScanResponse; print('ok')"
```

Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add backend/app/models/schemas.py
git commit -m "Add dedup Pydantic schemas"
```

---

## Task 3: Implement dedup_service.py

**Files:**
- Create: `backend/app/services/dedup_service.py`

- [ ] **Step 1: Create the service file**

Create `backend/app/services/dedup_service.py`:

```python
import logging
from collections import defaultdict
from typing import Optional

import imagehash
import numpy as np
from PIL import Image
from skimage.metrics import structural_similarity as ssim

from lib.media_item import MediaItem

logger = logging.getLogger(__name__)


def compute_phash(media_path: str) -> Optional[imagehash.ImageHash]:
    try:
        img = Image.open(media_path).convert("RGB")
        return imagehash.phash(img)
    except Exception as e:
        logger.warning("compute_phash: failed for %s: %s", media_path, e)
        return None


def find_candidate_pairs(
    items: list[MediaItem],
    hashes: list[Optional[imagehash.ImageHash]],
    phash_threshold: int,
) -> list[tuple[int, int]]:
    pairs = []
    for i in range(len(hashes)):
        if hashes[i] is None:
            continue
        for j in range(i + 1, len(hashes)):
            if hashes[j] is None:
                continue
            if hashes[i] - hashes[j] <= phash_threshold:
                pairs.append((i, j))
    return pairs


def confirm_with_ssim(path_a: str, path_b: str, ssim_threshold: float) -> bool:
    try:
        size = (256, 256)
        img_a = np.array(Image.open(path_a).convert("L").resize(size))
        img_b = np.array(Image.open(path_b).convert("L").resize(size))
        score = ssim(img_a, img_b, data_range=255)
        return float(score) >= ssim_threshold
    except Exception as e:
        logger.warning("confirm_with_ssim: failed for %s / %s: %s", path_a, path_b, e)
        return False


def group_duplicates(
    items: list[MediaItem],
    phash_threshold: int = 10,
    ssim_threshold: float = 0.85,
) -> list[list[int]]:
    hashes = [compute_phash(item.media_path) for item in items]
    candidates = find_candidate_pairs(items, hashes, phash_threshold)

    confirmed = [
        (i, j)
        for i, j in candidates
        if confirm_with_ssim(items[i].media_path, items[j].media_path, ssim_threshold)
    ]

    parent = list(range(len(items)))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(x: int, y: int) -> None:
        parent[find(x)] = find(y)

    for i, j in confirmed:
        union(i, j)

    groups_map: dict[int, list[int]] = defaultdict(list)
    for idx in range(len(items)):
        groups_map[find(idx)].append(idx)

    return [sorted(g) for g in groups_map.values() if len(g) > 1]
```

- [ ] **Step 2: Verify the module imports correctly**

```bash
cd backend && source .venv/bin/activate && python -c "from app.services.dedup_service import group_duplicates; print('ok')"
```

Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add backend/app/services/dedup_service.py
git commit -m "Implement dedup_service with pHash + SSIM grouping"
```

---

## Task 4: Implement dedup router and register it

**Files:**
- Create: `backend/app/routers/dedup.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Create backend/app/routers/dedup.py**

```python
import logging
import os

from fastapi import APIRouter, Depends, HTTPException
from PIL import Image

from app.models.schemas import (
    DedupRemoveRequest,
    DedupScanRequest,
    DedupScanResponse,
    DedupGroup,
    DedupImageInfo,
)
from app.services import dedup_service
from app.sessions import Session, get_session

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/dedup", tags=["dedup"])


def _image_dimensions(path: str) -> tuple[int | None, int | None]:
    try:
        with Image.open(path) as img:
            return img.width, img.height
    except Exception:
        return None, None


@router.post("/scan", response_model=DedupScanResponse)
def scan(req: DedupScanRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")

    ds = session.dataset
    image_items = []
    dataset_indices = []
    for i in range(len(ds)):
        item = ds.get_item(i)
        if item and item.is_image:
            image_items.append(item)
            dataset_indices.append(i)

    try:
        groups = dedup_service.group_duplicates(
            image_items, req.phash_threshold, req.ssim_threshold
        )
    except Exception as e:
        logger.error("dedup scan failed: %s", e, exc_info=True)
        raise HTTPException(500, str(e))

    result_groups = []
    for group_indices in groups:
        images = []
        for filtered_idx in group_indices:
            ds_idx = dataset_indices[filtered_idx]
            item = image_items[filtered_idx]
            width, height = _image_dimensions(item.media_path)
            file_size = os.path.getsize(item.media_path) if os.path.exists(item.media_path) else None
            images.append(
                DedupImageInfo(
                    index=ds_idx,
                    filename=item.filename,
                    width=width,
                    height=height,
                    file_size=file_size,
                    thumbnail_url=f"/api/media/thumbnail/{ds_idx}?session_id={session.id}",
                    path=item.media_path,
                )
            )
        keep_idx = max(
            range(len(images)),
            key=lambda i: (images[i].width or 0) * (images[i].height or 0),
        )
        result_groups.append(DedupGroup(images=images, keep_index=keep_idx))

    return DedupScanResponse(groups=result_groups)


@router.delete("/remove")
def remove(req: DedupRemoveRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")

    ds = session.dataset
    valid_paths = {
        ds.get_item(i).media_path
        for i in range(len(ds))
        if ds.get_item(i) is not None
    }
    invalid = [p for p in req.paths if p not in valid_paths]
    if invalid:
        raise HTTPException(400, f"Paths not in current session: {invalid[:3]}")

    deleted = 0
    for path in req.paths:
        try:
            idx = ds.find_index(path)
            if ds.delete_item(idx):
                deleted += 1
        except ValueError:
            logger.warning("remove: path already gone: %s", path)

    return {"deleted": deleted}
```

- [ ] **Step 2: Register the router in main.py**

In `backend/app/main.py`, add `dedup` to the import block and `app.include_router` calls:

```python
from app.routers import (
    dataset,
    media,
    captions,
    categories,
    processing,
    tagging,
    batch,
    export,
    settings,
    projects,
    promptgen,
    tasks,
    dedup,          # add this line
)
```

And add after the existing `include_router` calls:

```python
app.include_router(dedup.router)
```

- [ ] **Step 3: Start the backend and verify endpoints appear**

```bash
cd backend && source .venv/bin/activate && uvicorn app.main:app --reload --port 8000 &
sleep 2 && curl -s http://localhost:8000/openapi.json | python3 -c "import json,sys; paths=json.load(sys.stdin)['paths']; [print(p) for p in paths if 'dedup' in p]"
```

Expected output includes:
```
/api/dedup/scan
/api/dedup/remove
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/routers/dedup.py backend/app/main.py
git commit -m "Add dedup router with scan and remove endpoints"
```

---

## Task 5: Add TypeScript types and API functions

**Files:**
- Modify: `frontend/src/lib/types.ts`
- Modify: `frontend/src/lib/api.ts`

- [ ] **Step 1: Add dedup types to types.ts**

Append to the end of `frontend/src/lib/types.ts`:

```typescript
export interface DedupImageInfo {
  index: number;
  filename: string;
  width: number | null;
  height: number | null;
  file_size: number | null;
  thumbnail_url: string;
  path: string;
}

export interface DedupGroup {
  images: DedupImageInfo[];
  keep_index: number;
}

export interface DedupScanResponse {
  groups: DedupGroup[];
}
```

- [ ] **Step 2: Add DedupScanResponse to the existing type import block in api.ts**

At the top of `frontend/src/lib/api.ts` there is an `import type { ... } from "./types"` block. Add `DedupScanResponse` to it:

```typescript
import type {
  DatasetInfo,
  MediaItem,
  GalleryResponse,
  TagCloudEntry,
  SearchReplacePreview,
  Settings,
  Tagger,
  TaggersResponse,
  Upscaler,
  BackgroundRemover,
  BucketResult,
  ProjectOpenResponse,
  ActiveProjectsResponse,
  RecentProjectsResponse,
  ImageVersion,
  ColorMatchPreviewResult,
  BatchTask,
  DedupScanResponse,       // add this line
} from "./types";
```

- [ ] **Step 3: Append the two API functions to the end of api.ts**

```typescript
export async function scanForDuplicates(
  phashThreshold: number,
  ssimThreshold: number
): Promise<DedupScanResponse> {
  return apiFetch<DedupScanResponse>("/api/dedup/scan", {
    method: "POST",
    body: JSON.stringify({
      phash_threshold: phashThreshold,
      ssim_threshold: ssimThreshold,
    }),
  });
}

export async function removeDuplicates(paths: string[]): Promise<{ deleted: number }> {
  return apiFetch<{ deleted: number }>("/api/dedup/remove", {
    method: "DELETE",
    body: JSON.stringify({ paths }),
  });
}
```

- [ ] **Step 4: Verify TypeScript compiles**

```bash
cd frontend && npx tsc --noEmit 2>&1 | grep -E "types\.ts|api\.ts" | head -10
```

Expected: no output (zero type errors in those files).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/lib/types.ts frontend/src/lib/api.ts
git commit -m "Add dedup TypeScript types and API functions"
```

---

## Task 6: Add Dedup link to the sidebar

**Files:**
- Modify: `frontend/src/components/layout/Sidebar.tsx`

- [ ] **Step 1: Add the Dedup nav item**

In `frontend/src/components/layout/Sidebar.tsx`, find the `navItems` array at the top. Add a `ScanSearch` icon import and a new nav item.

Add `ScanSearch` to the lucide-react import:

```typescript
import {
  Image,
  Pencil,
  Tags,
  Layers,
  Settings,
  Wand2,
  Download,
  ScanSearch,
} from "lucide-react";
```

Add to `navItems` array (after the Browse entry, before Edit):

```typescript
{ href: "/dedup", label: "Dedup", icon: ScanSearch },
```

The full updated `navItems` array:

```typescript
const navItems = [
  { href: "/browse", label: "Browse", icon: Image },
  { href: "/dedup", label: "Dedup", icon: ScanSearch },
  { href: "/edit", label: "Edit", icon: Pencil },
  { href: "/captions", label: "Captions", icon: Tags },
  { href: "/batch", label: "Batch", icon: Layers },
  { href: "/export", label: "Export", icon: Download },
  { href: "/promptgen", label: "PromptGen", icon: Wand2 },
  { href: "/settings", label: "Settings", icon: Settings },
];
```

- [ ] **Step 2: Verify no TypeScript errors**

```bash
cd frontend && npx tsc --noEmit 2>&1 | grep -i "sidebar\|ScanSearch" | head -5
```

Expected: no output (no errors).

- [ ] **Step 3: Commit**

```bash
git add frontend/src/components/layout/Sidebar.tsx
git commit -m "Add Dedup link to sidebar navigation"
```

---

## Task 7: Create the dedup page and component

**Files:**
- Create: `frontend/src/app/dedup/page.tsx`
- Create: `frontend/src/components/dedup/DedupPage.tsx`

- [ ] **Step 1: Create the page directory**

```bash
mkdir -p /home/lars/PycharmProjects/ImageTagger2/frontend/src/app/dedup
mkdir -p /home/lars/PycharmProjects/ImageTagger2/frontend/src/components/dedup
```

- [ ] **Step 2: Create frontend/src/app/dedup/page.tsx**

```typescript
"use client";

import { useProjectStore } from "@/stores/projectStore";
import EmptyState from "@/components/shared/EmptyState";
import DedupPage from "@/components/dedup/DedupPage";
import { ScanSearch } from "lucide-react";

export default function Page() {
  const activeProjectId = useProjectStore((s) => s.activeProjectId);

  if (!activeProjectId) {
    return (
      <EmptyState
        icon={ScanSearch}
        title="No project open"
        description="Open a project to find and remove duplicate images."
      />
    );
  }

  return <DedupPage />;
}
```

- [ ] **Step 3: Create frontend/src/components/dedup/DedupPage.tsx**

```typescript
"use client";

import { useState } from "react";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { scanForDuplicates, removeDuplicates } from "@/lib/api";
import type { DedupGroup } from "@/lib/types";

type Phase = "idle" | "scanning" | "reviewing" | "done";

interface DoneInfo {
  deleted: number;
  groupCount: number;
}

export default function DedupPage() {
  const [phase, setPhase] = useState<Phase>("idle");
  const [phashThreshold, setPhashThreshold] = useState(10);
  const [ssimThreshold, setSsimThreshold] = useState(0.85);
  const [groups, setGroups] = useState<DedupGroup[]>([]);
  const [keepSelections, setKeepSelections] = useState<number[]>([]);
  const [doneInfo, setDoneInfo] = useState<DoneInfo | null>(null);

  const handleScan = async () => {
    setPhase("scanning");
    try {
      const result = await scanForDuplicates(phashThreshold, ssimThreshold);
      setGroups(result.groups);
      setKeepSelections(result.groups.map((g) => g.keep_index));
      if (result.groups.length === 0) {
        setDoneInfo({ deleted: 0, groupCount: 0 });
        setPhase("done");
      } else {
        setPhase("reviewing");
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Scan failed");
      setPhase("idle");
    }
  };

  const handleKeepSelect = (groupIdx: number, imageIdx: number) => {
    setKeepSelections((prev) => {
      const next = [...prev];
      next[groupIdx] = imageIdx;
      return next;
    });
  };

  const handleDelete = async () => {
    const paths: string[] = [];
    groups.forEach((group, groupIdx) => {
      group.images.forEach((img, imgIdx) => {
        if (imgIdx !== keepSelections[groupIdx]) {
          paths.push(img.path);
        }
      });
    });

    try {
      const result = await removeDuplicates(paths);
      setDoneInfo({ deleted: result.deleted, groupCount: groups.length });
      setPhase("done");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Delete failed");
    }
  };

  const deleteCount = groups.reduce(
    (sum, group) => sum + group.images.length - 1,
    0
  );

  if (phase === "idle" || phase === "scanning") {
    return (
      <div className="p-6 flex flex-col gap-6 max-w-2xl">
        <h1 className="text-xl font-semibold text-text">Find Duplicates</h1>

        <div className="flex flex-col gap-5">
          <div className="flex flex-col gap-2">
            <label className="text-xs font-medium text-text-secondary uppercase tracking-wide">
              pHash distance threshold
            </label>
            <div className="flex items-center gap-3">
              <input
                type="range"
                min={0}
                max={20}
                value={phashThreshold}
                onChange={(e) => setPhashThreshold(Number(e.target.value))}
                disabled={phase === "scanning"}
                className="w-48 accent-primary"
              />
              <span className="text-sm font-semibold w-4 text-text">{phashThreshold}</span>
              <span className="text-xs text-text-muted">0 = exact copy, 20 = loose</span>
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <label className="text-xs font-medium text-text-secondary uppercase tracking-wide">
              SSIM confirmation threshold
            </label>
            <div className="flex items-center gap-3">
              <input
                type="range"
                min={50}
                max={99}
                value={Math.round(ssimThreshold * 100)}
                onChange={(e) => setSsimThreshold(Number(e.target.value) / 100)}
                disabled={phase === "scanning"}
                className="w-48 accent-primary"
              />
              <span className="text-sm font-semibold w-12 text-text">
                {ssimThreshold.toFixed(2)}
              </span>
              <span className="text-xs text-text-muted">higher = stricter</span>
            </div>
          </div>
        </div>

        {phase === "scanning" ? (
          <div className="flex items-center gap-2 text-text-secondary text-sm">
            <Loader2 className="w-4 h-4 animate-spin" />
            <span>Scanning...</span>
          </div>
        ) : (
          <button
            onClick={handleScan}
            className="w-fit px-4 py-2 bg-primary text-white rounded-md text-sm font-medium hover:bg-primary/90 transition-colors"
          >
            Scan Dataset
          </button>
        )}
      </div>
    );
  }

  if (phase === "done") {
    return (
      <div className="p-6 flex flex-col gap-4 max-w-2xl">
        <h1 className="text-xl font-semibold text-text">Done</h1>
        {doneInfo && (
          <>
            <p className="text-text-secondary text-sm">
              {doneInfo.groupCount === 0
                ? "No duplicate groups found."
                : `${doneInfo.deleted} images deleted from ${doneInfo.groupCount} groups.`}
            </p>
            <a
              href="/browse"
              className="w-fit px-4 py-2 bg-surface-raised rounded-md text-sm hover:bg-surface-border transition-colors text-text"
            >
              Back to Browse
            </a>
          </>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      <div className="p-6 flex flex-col gap-4 flex-1 overflow-y-auto">
        <h1 className="text-xl font-semibold text-text">Review Duplicates</h1>
        <p className="text-sm text-text-secondary">
          Found {groups.length} duplicate {groups.length === 1 ? "group" : "groups"}. Click the
          image to keep in each group — the rest will be deleted.
        </p>

        <div className="flex flex-col gap-4 max-w-4xl">
          {groups.map((group, groupIdx) => (
            <div key={groupIdx} className="border border-border rounded-lg p-4">
              <p className="text-xs text-text-muted mb-3">
                GROUP {groupIdx + 1} OF {groups.length} — {group.images.length} images
              </p>
              <div className="flex gap-3 flex-wrap">
                {group.images.map((img, imgIdx) => {
                  const isKeep = keepSelections[groupIdx] === imgIdx;
                  return (
                    <div
                      key={imgIdx}
                      onClick={() => handleKeepSelect(groupIdx, imgIdx)}
                      className="flex flex-col gap-1 items-center cursor-pointer"
                    >
                      <div
                        className={`relative w-28 h-28 rounded overflow-hidden border-2 transition-colors ${
                          isKeep ? "border-green-500" : "border-border hover:border-border-hover"
                        }`}
                      >
                        <img
                          src={img.thumbnail_url}
                          alt={img.filename}
                          className="w-full h-full object-cover"
                        />
                        <div
                          className={`absolute bottom-1 left-1 text-xs px-1 rounded font-medium ${
                            isKeep ? "bg-green-500 text-black" : "bg-red-600/80 text-white"
                          }`}
                        >
                          {isKeep ? "KEEP" : "DELETE"}
                        </div>
                      </div>
                      <span className="text-xs text-text-muted">
                        {img.width && img.height
                          ? `${img.width}×${img.height}`
                          : img.filename}
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="sticky bottom-0 border-t border-red-500/20 bg-background/95 backdrop-blur-sm p-4 flex items-center justify-between">
        <span className="text-sm text-text">
          <strong>{deleteCount}</strong> images marked for deletion
        </span>
        <button
          onClick={handleDelete}
          className="px-4 py-2 bg-red-600 text-white rounded-md text-sm font-medium hover:bg-red-700 transition-colors disabled:opacity-50"
          disabled={deleteCount === 0}
        >
          Delete {deleteCount} Images
        </button>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Verify TypeScript compiles with no errors**

```bash
cd frontend && npx tsc --noEmit 2>&1 | head -20
```

Expected: no output (zero type errors).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/app/dedup/page.tsx frontend/src/components/dedup/DedupPage.tsx
git commit -m "Add dedup page and DedupPage component"
```

---

## Task 8: Integration test

- [ ] **Step 1: Start both servers**

```bash
cd /home/lars/PycharmProjects/ImageTagger2 && ./run.sh
```

- [ ] **Step 2: Open the app and load a project**

Navigate to `http://localhost:3000`. Open a project with some images.

- [ ] **Step 3: Navigate to the Dedup page**

Click "Dedup" in the sidebar. Verify the idle phase renders: two sliders and a "Scan Dataset" button.

- [ ] **Step 4: Run a scan**

Click "Scan Dataset" with default thresholds. Verify:
- Spinner appears ("Scanning...")
- After completion, either "No duplicate groups found" (done phase) or group cards appear (reviewing phase)

- [ ] **Step 5: Test group review (if groups found)**

If groups appear:
- Verify the largest-resolution image is pre-selected as KEEP (green border)
- Click a different image in a group — verify KEEP badge moves to it
- Verify the footer shows the correct delete count

- [ ] **Step 6: Test deletion**

Click "Delete X Images". Verify:
- Done phase appears with correct deleted count
- "Back to Browse" link works
- Deleted files are no longer visible in Browse

- [ ] **Step 7: Test empty result**

Re-scan the same (now deduplicated) dataset. Verify "No duplicate groups found." message appears in done phase.

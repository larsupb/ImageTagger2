# Export Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create new Export page that exports dataset to standard format with optional bucket resizing. Move Bucket Resize from Batch page to Export page.

**Architecture:** New export router and service for backend, new page and form component for frontend, remove bucket resize from batch page.

**Tech Stack:** FastAPI (backend), Next.js 15 + React 19 + TypeScript (frontend), PIL for image processing, zipfile for compression.

---

## File Structure

### Backend New Files
- `backend/app/routers/export.py` - Export API endpoints
- `backend/app/services/export_service.py` - Export business logic

### Backend Modified Files
- `backend/app/main.py` - Register export router
- `backend/app/models/schemas.py` - Add ExportRequest schema

### Frontend New Files
- `frontend/src/app/export/page.tsx` - Export page
- `frontend/src/components/export/ExportForm.tsx` - Export form component

### Frontend Modified Files
- `frontend/src/lib/api.ts` - Add export API methods
- `frontend/src/components/layout/Sidebar.tsx` - Add Export to navigation
- `frontend/src/components/batch/BatchForm.tsx` - Remove bucket resize

---

### Task 1: Backend - Add ExportRequest Schema

**Files:**
- Modify: `backend/app/models/schemas.py`

- [ ] **Step 1: Read current schema file to find insertion point**

Run: `read backend/app/models/schemas.py` at lines 155-200

- [ ] **Step 2: Add ExportRequest schema after BucketAnalyzeRequest**

Add after line ~190:
```python
class ExportRequest(BaseModel):
    format: str = "standard"
    bucket_resize: bool = False
    bucket_resolution: int = 1024
    bucket_step: int = 128
    bucket_max_steps: int = 2
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/models/schemas.py
git commit -m "feat: add ExportRequest schema"
```

---

### Task 2: Backend - Create Export Service

**Files:**
- Create: `backend/app/services/export_service.py`

- [ ] **Step 1: Write export service module**

```python
import os
import zipfile
import tempfile
import shutil
from typing import Optional
from PIL import Image

from app.sessions import Session
from lib.bucketing import generate_buckets, find_nearest_bucket, resize_and_crop_to_bucket


class ExportOptions:
    def __init__(
        self,
        format: str = "standard",
        bucket_resize: bool = False,
        bucket_resolution: int = 1024,
        bucket_step: int = 128,
        bucket_max_steps: int = 2,
    ):
        self.format = format
        self.bucket_resize = bucket_resize
        self.bucket_resolution = bucket_resolution
        self.bucket_step = bucket_step
        self.bucket_max_steps = bucket_max_steps


def export_dataset(session: Session, options: ExportOptions) -> str:
    """
    Export dataset to standard format.
    
    Creates:
    - output_dir/img/ with images and .txt caption files
    - output_dir/masks/ with mask files (if exist)
    
    Returns path to output directory.
    """
    ds = session.dataset
    if ds is None:
        raise ValueError("No dataset loaded")

    output_dir = tempfile.mkdtemp(prefix="imagetagger_export_")
    img_dir = os.path.join(output_dir, "img")
    masks_dir = os.path.join(output_dir, "masks")
    os.makedirs(img_dir)
    os.makedirs(masks_dir)

    buckets = None
    bucket_map = None
    if options.bucket_resize:
        buckets = generate_buckets(
            options.bucket_resolution,
            options.bucket_step,
            options.bucket_max_steps,
        )

    total = len(ds)
    for i in range(total):
        item = ds.get_item(i)
        if item is None:
            continue

        new_filename = f"{i:05d}"

        img = Image.open(item.media_path)
        if img.mode != "RGB":
            img = img.convert("RGB")

        if options.bucket_resize and buckets:
            bucket = find_nearest_bucket(img.width, img.height, buckets)
            img = resize_and_crop_to_bucket(img, bucket)

        img_path = os.path.join(img_dir, f"{new_filename}.jpg")
        img.save(img_path, format="JPEG", quality=95)

        caption = item.caption or ""
        caption_path = os.path.join(img_dir, f"{new_filename}.txt")
        with open(caption_path, "w", encoding="utf-8") as f:
            f.write(caption)

        if item.mask_path and os.path.exists(item.mask_path):
            mask = Image.open(item.mask_path)
            mask_path = os.path.join(masks_dir, f"{new_filename}.png")
            mask.save(mask_path, format="PNG")

    return output_dir


def create_zip_archive(source_dir: str, zip_path: str) -> str:
    """Create ZIP archive from source directory."""
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, _, files in os.walk(source_dir):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, source_dir)
                zipf.write(file_path, arcname)
    return zip_path


def cleanup_export_dir(output_dir: str):
    """Remove temporary export directory."""
    if os.path.exists(output_dir):
        shutil.rmtree(output_dir)
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/services/export_service.py
git commit -m "feat: add export service module"
```

---

### Task 3: Backend - Create Export Router

**Files:**
- Create: `backend/app/routers/export.py`

- [ ] **Step 1: Write export router**

```python
import asyncio
import tempfile
import os
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse

from app.sessions import Session, get_session
from app.models.schemas import ExportRequest
from app.services import export_service, task_service

router = APIRouter(prefix="/api/export", tags=["export"])


@router.post("")
async def export_dataset(
    req: ExportRequest, session: Session = Depends(get_session)
):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")

    ds = session.dataset
    total = len(ds)

    task_id = task_service.create_task(total)
    task_service.start_task(task_id)

    async def run_export():
        try:
            output_dir = None
            zip_path = None
            try:
                options = export_service.ExportOptions(
                    format=req.format,
                    bucket_resize=req.bucket_resize,
                    bucket_resolution=req.bucket_resolution,
                    bucket_step=req.bucket_step,
                    bucket_max_steps=req.bucket_max_steps,
                )

                output_dir = export_service.export_dataset(session, options)

                temp_dir = os.path.dirname(output_dir)
                zip_filename = f"export_{session.session_id[:8]}.zip"
                zip_path = os.path.join(temp_dir, zip_filename)

                export_service.create_zip_archive(output_dir, zip_path)

                task_service.update_progress(
                    task_id,
                    total - 1,
                    total,
                    "export.zip",
                    "Creating ZIP archive",
                )

                task_service.complete_task(task_id)
            except Exception as e:
                task_service.complete_task(task_id, str(e))
            finally:
                if output_dir:
                    export_service.cleanup_export_dir(output_dir)
        except Exception as e:
            task_service.complete_task(task_id, str(e))

    asyncio.create_task(run_export())
    return {"task_id": task_id}


@router.get("/download/{task_id}")
async def download_export(task_id: str):
    task = task_service.get_task(task_id)
    if task is None:
        raise HTTPException(404, "Task not found")

    if task.status != "completed":
        raise HTTPException(400, "Export not completed")

    if not hasattr(task, "zip_path") or not os.path.exists(task.zip_path):
        raise HTTPException(404, "Export file not found")

    return FileResponse(
        task.zip_path,
        media_type="application/zip",
        filename="dataset_export.zip",
    )


@router.get("/progress/{task_id}")
async def get_export_progress(task_id: str):
    task = task_service.get_task(task_id)
    if task is None:
        raise HTTPException(404, "Task not found")
    return {
        "status": task.status,
        "progress": task.progress,
        "total": task.total,
        "current_index": task.current_index,
        "current_filename": task.current_filename,
        "error": task.error,
    }
```

- [ ] **Step 2: Register router in main.py**

Modify `backend/app/main.py`, add after batch router include:
```python
from app.routers import export
app.include_router(export.router)
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/routers/export.py backend/app/main.py
git commit -m "feat: add export router and register it"
```

---

### Task 4: Frontend - Add Export API Methods

**Files:**
- Modify: `frontend/src/lib/api.ts`

- [ ] **Step 1: Read api.ts to find insertion point**

Look at lines 276-340 for batch API methods pattern

- [ ] **Step 2: Add export API methods**

Add after batch methods (around line 332):
```typescript
// Export
exportDataset: (options: Record<string, unknown>) => {
  return getSessionId().then((sid) => {
    const params = new URLSearchParams();
    Object.entries(options).forEach(([k, v]) => {
      if (v !== undefined) params.set(k, String(v));
    });
    const source = new EventSource(`/api/export?session_id=${sid}&${params.toString()}`);
    return source;
  });
},

startExportTask: async (options: Record<string, unknown>): Promise<{ task_id: string }> => {
  const sid = await getSessionId();
  const response = await fetch("/api/export", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Session-ID": sid,
    },
    body: JSON.stringify(options),
  });
  if (!response.ok) {
    throw new Error(`Failed to start export: ${response.statusText}`);
  }
  return response.json();
},

getExportStatus: async (taskId: string): Promise<BatchTask> => {
  const sid = await getSessionId();
  const response = await fetch(`/api/export/progress/${taskId}`, {
    headers: { "X-Session-ID": sid },
  });
  if (!response.ok) {
    throw new Error(`Task not found: ${response.statusText}`);
  }
  return response.json();
},
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/lib/api.ts
git commit -m "feat: add export API methods"
```

---

### Task 5: Frontend - Create Export Page and Form

**Files:**
- Create: `frontend/src/app/export/page.tsx`
- Create: `frontend/src/components/export/ExportForm.tsx`

- [ ] **Step 1: Create export page**

```tsx
"use client";

import { useProjectStore } from "@/stores/projectStore";
import { useSessionStore } from "@/stores/session";
import EmptyState from "@/components/shared/EmptyState";
import ExportForm from "@/components/export/ExportForm";
import { FolderOpen } from "lucide-react";

export default function ExportPage() {
  const activeProjectId = useProjectStore((s) => s.activeProjectId);
  const session = activeProjectId
    ? useSessionStore((s) => s.getProjectSession(activeProjectId))
    : undefined;
  const { datasetInfo } = session ?? {};

  if (!activeProjectId) {
    return (
      <EmptyState
        icon={FolderOpen}
        title="No project open"
        description="Open a project to export your dataset."
      />
    );
  }

  if (!datasetInfo) {
    return <div className="text-text-muted text-center py-12">Loading...</div>;
  }

  return <ExportForm />;
}
```

- [ ] **Step 2: Create ExportForm component**

```tsx
"use client";

import { useState, useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { api, getCurrentSessionId } from "@/lib/api";
import type { BucketResult } from "@/lib/types";
import { useTaskPolling } from "../../hooks/useTaskPolling";
import ProgressLog from "../batch/ProgressLog";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "sonner";
import {
  Download,
  Grid3X3,
  BarChart3,
};

interface OperationCardProps {
  icon: React.ReactNode;
  title: string;
  description: string;
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  children?: React.ReactNode;
}

function OperationCard({ icon, title, description, checked, onCheckedChange, children }: OperationCardProps) {
  const [expanded, setExpanded] = useState(checked);

  const handleCheckedChange = (c: boolean) => {
    onCheckedChange(c);
    if (c) setExpanded(true);
  };

  return (
    <div className={`bg-surface rounded-lg border border-border p-4 transition-colors hover:border-border/80 ${checked ? "border-primary/30" : ""}`}>
      <div className="flex items-start gap-3">
        <Checkbox checked={checked} onCheckedChange={handleCheckedChange} className="mt-0.5" />
        <div className="flex flex-1 items-start gap-3">
          <div className="text-text-muted">{icon}</div>
          <div className="flex-1">
            <label className="text-sm font-medium cursor-pointer">
              {title}
            </label>
            <p className="text-xs text-text-muted mt-0.5">{description}</p>
          </div>
        </div>
      </div>
      {checked && children && (
        <div className="mt-4 pt-4 border-t border-border">{children}</div>
      )}
    </div>
  );
}

export default function ExportForm() {
  const [format, setFormat] = useState("standard");
  const [bucketResize, setBucketResize] = useState(false);
  const [resolution, setResolution] = useState(1024);
  const [step, setStep] = useState(128);
  const [maxSteps, setMaxSteps] = useState(2);
  const [isExporting, setIsExporting] = useState(false);
  const [currentTaskId, setCurrentTaskId] = useState<string | null>(null);
  const [logEntry, setLogEntry] = useState<{ index: number; total: number; filename: string; progress: number; log: string } | null>(null);
  const [bucketResult, setBucketResult] = useState<BucketResult | null>(null);

  const { data: datasetInfo } = useQuery({
    queryKey: ["datasetInfo"],
    queryFn: () => api.getDatasetInfo(),
  });

  const { task } = useTaskPolling(currentTaskId);

  useEffect(() => {
    if (task) {
      if (task.logs && task.logs.length > 0) {
        const lastLog = task.logs[task.logs.length - 1];
        setLogEntry({
          index: lastLog.index,
          total: task.total,
          filename: lastLog.filename,
          progress: (lastLog.index + 1) / task.total,
          log: lastLog.message,
        });
      }
      if (task.status === "completed") {
        toast.success("Export completed");
        setIsExporting(false);
        setCurrentTaskId(null);
        handleDownload();
      } else if (task.status === "failed") {
        toast.error(task.error || "Export failed");
        setIsExporting(false);
        setCurrentTaskId(null);
      }
    }
  }, [task]);

  const handleExport = async () => {
    setIsExporting(true);
    setLogEntry(null);
    try {
      const result = await api.startExportTask({
        format,
        bucket_resize: bucketResize,
        bucket_resolution: resolution,
        bucket_step: step,
        bucket_max_steps: maxSteps,
      });
      setCurrentTaskId(result.task_id);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to start export");
      setIsExporting(false);
    }
  };

  const handleDownload = async () => {
    if (!currentTaskId) return;
    try {
      const response = await fetch(`/api/export/download/${currentTaskId}`);
      if (!response.ok) throw new Error("Download failed");
      
      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "dataset_export.zip";
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      window.URL.revokeObjectURL(url);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Download failed");
    }
  };

  const handleAnalyzeBuckets = async () => {
    try {
      const result = await api.analyzeBuckets(resolution, step, maxSteps);
      setBucketResult(result);
      toast.success("Bucket analysis complete");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Bucket analysis failed");
    }
  };

  return (
    <div className="flex flex-col gap-6 max-w-3xl">
      <div>
        <h2 className="text-lg font-medium text-text">Export Dataset</h2>
        <p className="text-sm text-text-muted mt-1">Export your dataset to a standard format with optional bucket resizing.</p>
      </div>

      <div className="grid grid-cols-1 gap-3">
        <OperationCard
          icon={<Download className="w-5 h-5" />}
          title="Format"
          description="Select export format"
          checked={true}
          onCheckedChange={() => {}}
        >
          <div className="flex items-center gap-3">
            <label className="text-sm text-text-secondary">Export Format</label>
            <Select value={format} onValueChange={(v) => setFormat(v ?? "standard")}>
              <SelectTrigger className="w-40">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="standard">Standard</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </OperationCard>

        <OperationCard
          icon={<Grid3X3 className="w-5 h-5" />}
          title="Bucket Resize"
          description="Resize images to optimal bucket dimensions for training."
          checked={bucketResize}
          onCheckedChange={setBucketResize}
        >
          <div className="flex flex-col gap-3">
            <div className="flex gap-4">
              <div className="flex items-center gap-2">
                <label className="text-sm text-text-secondary">Base Res</label>
                <Select value={String(resolution)} onValueChange={(v) => setResolution(Number(v))}>
                  <SelectTrigger className="w-24">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {[512, 768, 1024, 1280, 1536, 1792, 2048].map((r) => (
                      <SelectItem key={r} value={String(r)}>{r}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex items-center gap-2">
                <label className="text-sm text-text-secondary">Step</label>
                <Input
                  type="number"
                  value={step}
                  onChange={(e) => setStep(Number(e.target.value))}
                  min={64}
                  max={512}
                  step={64}
                  className="w-20"
                />
              </div>
              <div className="flex items-center gap-2">
                <label className="text-sm text-text-secondary">Max Steps</label>
                <Input
                  type="number"
                  value={maxSteps}
                  onChange={(e) => setMaxSteps(Number(e.target.value))}
                  min={1}
                  max={4}
                  className="w-16"
                />
              </div>
            </div>
            <div>
              <Button variant="outline" size="sm" onClick={handleAnalyzeBuckets} disabled={isExporting}>
                <BarChart3 className="w-4 h-4 mr-1.5" />
                Analyze Buckets
              </Button>
            </div>
            {bucketResult && (
              <div>
                <p className="text-xs text-text-muted mb-2">
                  Bucket Analysis ({bucketResult.total_images} images)
                </p>
                <div className="grid grid-cols-3 gap-2">
                  {bucketResult.buckets.map((b, i) => (
                    <div key={i} className="bg-surface-raised rounded border border-border p-2 text-xs text-text-secondary">
                      {b.width}×{b.height}: {b.count} images
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </OperationCard>
      </div>

      <div className="flex gap-3 pt-2">
        <Button
          onClick={handleExport}
          disabled={isExporting}
          className="ml-auto"
        >
          <Download className="w-4 h-4 mr-1.5" />
          {isExporting ? "Exporting..." : "Export"}
        </Button>
      </div>

      {logEntry && (
        <div className="mt-4">
          <p className="text-sm text-text-secondary">
            Exporting {logEntry.index + 1} of {logEntry.total}: {logEntry.filename}
          </p>
          <div className="w-full bg-surface-raised rounded-full h-2 mt-2">
            <div
              className="bg-primary rounded-full h-2 transition-all"
              style={{ width: `${logEntry.progress * 100}%` }}
            />
          </div>
          {logEntry.log && (
            <p className="text-xs text-text-muted mt-2">{logEntry.log}</p>
          )}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/app/export/page.tsx frontend/src/components/export/ExportForm.tsx
git commit -m "feat: add export page and form component"
```

---

### Task 6: Frontend - Add Export to Sidebar Navigation

**Files:**
- Modify: `frontend/src/components/layout/Sidebar.tsx`

- [ ] **Step 1: Add Download icon import and Export nav item**

Add import:
```typescript
import {
  Image,
  Pencil,
  Tags,
  Layers,
  Wrench,
  CheckCircle,
  Settings,
  Wand2,
  Download,
} from "lucide-react";
```

Add to navItems array (before Settings):
```typescript
{ href: "/export", label: "Export", icon: Download },
```

- [ ] **Step 2: Commit**

```bash
git add frontend/src/components/layout/Sidebar.tsx
git commit -m "feat: add Export to sidebar navigation"
```

---

### Task 7: Frontend - Remove Bucket Resize from Batch Page

**Files:**
- Modify: `frontend/src/components/batch/BatchForm.tsx`

- [ ] **Step 1: Read BatchForm.tsx and identify removal points**

Need to remove:
- Line 81: `const [bucketResize, setBucketResize] = useState(false);`
- Lines 87-89: `resolution`, `step`, `maxSteps` state
- Line 93: `const [bucketResult, setBucketResult] = useState<BucketResult | null>(null);`
- Lines 186: `bucket_resize: bucketResize,` from API call
- Lines 192-194: bucket config from handleStart
- Lines 208-216: handleAnalyzeBuckets function
- Lines 299-365: Bucket Resize OperationCard

- [ ] **Step 2: Remove bucket resize state variables**

Remove line 81:
```typescript
const [bucketResize, setBucketResize] = useState(false);
```

- [ ] **Step 3: Remove bucket config state variables**

Remove lines 87-89:
```typescript
const [resolution, setResolution] = useState(1024);
const [step, setStep] = useState(128);
const [maxSteps, setMaxSteps] = useState(2);
```

- [ ] **Step 4: Remove bucket result state**

Remove line 93:
```typescript
const [bucketResult, setBucketResult] = useState<BucketResult | null>(null);
```

- [ ] **Step 5: Remove bucket_resize from API call in handleStart**

Around line 185-194, remove:
```typescript
bucket_resize: bucketResize,
```
And remove bucket config:
```typescript
bucket_resolution: resolution,
bucket_step: step,
bucket_max_steps: maxSteps,
```

- [ ] **Step 6: Remove handleAnalyzeBuckets function**

Remove lines 208-216:
```typescript
const handleAnalyzeBuckets = async () => {
  try {
    const result = await api.analyzeBuckets(resolution, step, maxSteps);
    setBucketResult(result);
    toast.success("Bucket analysis complete");
  } catch (e) {
    toast.error(e instanceof Error ? e.message : "Bucket analysis failed");
  }
};
```

- [ ] **Step 7: Remove Bucket Resize OperationCard**

Remove lines 299-365 (the entire Bucket Resize card)

- [ ] **Step 8: Update hasAnyOperation**

Remove `bucketResize` from the hasAnyOperation check (line 244):
```typescript
const hasAnyOperation = rename || upscale || mask || caption || colorMatch || whiteBalance;
```

- [ ] **Step 9: Commit**

```bash
git add frontend/src/components/batch/BatchForm.tsx
git commit -m "feat: remove bucket resize from batch page"
```

---

### Task 8: Integration Testing

**Files:**
- Test: Full stack verification

- [ ] **Step 1: Start backend server**

Run: `cd backend && uvicorn app.main:app --reload --port 8000`

- [ ] **Step 2: Start frontend server**

Run: `cd frontend && npm run dev`

- [ ] **Step 3: Verify Export page loads**

Open: http://localhost:3000/export
Check: Page loads, shows format selector and bucket resize card

- [ ] **Step 4: Test Analyze Buckets**

Click Analyze Buckets button
Check: Shows bucket distribution

- [ ] **Step 5: Test Export**

Click Export button
Check: Progress shows, ZIP downloads after completion

- [ ] **Step 6: Verify ZIP contents**

Unzip and check:
- img/ folder with images and .txt files
- masks/ folder with masks (if any)
- Correct bucket resizing if enabled

- [ ] **Step 7: Verify Batch page no longer has bucket resize**

Navigate to /batch
Check: Bucket Resize card is gone

---

## Self-Review

**Spec coverage:**
- [x] New Export page accessible - Task 5-6
- [x] Format selector shows "standard" - Task 5
- [x] Bucket Resize configuration card - Task 5
- [x] Analyze Buckets button - Task 5
- [x] Export button triggers export - Task 5
- [x] Progress shown during export - Task 5
- [x] ZIP downloaded on completion - Task 5
- [x] Correct output structure (img/, masks/) - Task 2
- [x] Bucket resized images if enabled - Task 2
- [x] Bucket Resize removed from Batch - Task 7

**Placeholder scan:** No placeholders found.

**Type consistency:** API methods match frontend usage.
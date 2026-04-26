# Export Caption Type Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a caption type selector to the Export page so users can choose which caption type (e.g., "tags", "prompt") to export. The export reads from the DB instead of legacy sidecar `.txt` files.

**Architecture:** Backend adds `caption_type` to `ExportRequest`/`ExportOptions` and reads captions from DB via `caption_service.read_caption()`. Frontend adds a new `OperationCard` with a `Select` dropdown to `ExportForm`, fetching available caption types from `/api/captions/types` and defaulting to the active type.

**Tech Stack:** FastAPI, Python, SQLite (caption DB), React, TypeScript, TanStack Query, Tailwind CSS

---

## File Map

| File | Change |
|------|--------|
| `backend/app/models/schemas.py` | Add `caption_type` field to `ExportRequest` |
| `backend/app/services/export_service.py` | Add `caption_type` to `ExportOptions`, pass `session`, read from DB |
| `backend/app/routers/export.py` | Pass `session` and `caption_type` to export service |
| `frontend/src/components/export/ExportForm.tsx` | Add caption type state, queries, and `OperationCard` |
| `frontend/src/lib/api.ts` | No change needed — `startExportTask` already forwards arbitrary options |

---

### Task 1: Add `caption_type` to `ExportRequest` schema

**Files:**
- Modify: `backend/app/models/schemas.py:212-218`

- [ ] **Step 1: Add field to ExportRequest**

Edit `backend/app/models/schemas.py`, replace the `ExportRequest` class (lines 212-218):

```python
class ExportRequest(BaseModel):
    format: str = "standard"
    caption_type: str = "tags"
    bucket_resize: bool = False
    bucket_resolution: int = 1024
    bucket_step: int = 128
    bucket_max_steps: int = 2
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/models/schemas.py
git commit -m "feat(export): add caption_type to ExportRequest schema"
```

---

### Task 2: Update `ExportOptions` and `export_dataset` to use `caption_type`

**Files:**
- Modify: `backend/app/services/export_service.py`

- [ ] **Step 1: Add `caption_type` to `ExportOptions`**

Edit the `ExportOptions.__init__` method in `backend/app/services/export_service.py` (lines 16-29):

```python
class ExportOptions:
    def __init__(
        self,
        format: str = "standard",
        caption_type: str = "tags",
        bucket_resize: bool = False,
        bucket_resolution: int = 1024,
        bucket_step: int = 128,
        bucket_max_steps: int = 2,
    ):
        self.format = format
        self.caption_type = caption_type
        self.bucket_resize = bucket_resize
        self.bucket_resolution = bucket_resolution
        self.bucket_step = bucket_step
        self.bucket_max_steps = bucket_max_steps
```

- [ ] **Step 2: Change `export_dataset` signature to accept `session` and read from DB**

Edit `backend/app/services/export_service.py`, replace the `export_dataset` function signature and caption reading logic (lines 32-96):

```python
def export_dataset(session: Session, options: ExportOptions) -> str:
    """
    Export dataset to standard format.

    Creates:
    - output_dir/img/ with images and .txt caption files
    - output_dir/masks/ with mask files (if exist)

    Returns path to output directory.
    """
    from app.services import caption_service

    ds = session.dataset
    if ds is None:
        raise ValueError("No dataset loaded")

    output_dir = tempfile.mkdtemp(prefix="imagetagger_export_")
    img_dir = os.path.join(output_dir, "img")
    masks_dir = os.path.join(output_dir, "masks")
    os.makedirs(img_dir)
    os.makedirs(masks_dir)

    buckets = None
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

        caption = caption_service.read_caption(session, i, options.caption_type)
        caption_path = os.path.join(img_dir, f"{new_filename}.txt")
        with open(caption_path, "w", encoding="utf-8") as f:
            f.write(caption)

        if item.mask_path and os.path.exists(item.mask_path):
            mask = Image.open(item.mask_path)
            mask_path = os.path.join(masks_dir, f"{new_filename}.png")
            mask.save(mask_path, format="PNG")

    return output_dir
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/services/export_service.py
git commit -m "feat(export): read caption from DB by type instead of sidecar file"
```

---

### Task 3: Update export router to pass `session` and `caption_type`

**Files:**
- Modify: `backend/app/routers/export.py`

- [ ] **Step 1: Pass `session` and `caption_type` to ExportOptions**

Edit `backend/app/routers/export.py`, inside the `run_export` function where `ExportOptions` is created (lines 33-41):

```python
options = export_service.ExportOptions(
    format=req.format,
    caption_type=req.caption_type,
    bucket_resize=req.bucket_resize,
    bucket_resolution=req.bucket_resolution,
    bucket_step=req.bucket_step,
    bucket_max_steps=req.bucket_max_steps,
)

output_dir = export_service.export_dataset(session, options)
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/routers/export.py
git commit -m "feat(export): pass caption_type and session to export_service"
```

---

### Task 4: Add caption type selector to ExportForm

**Files:**
- Modify: `frontend/src/components/export/ExportForm.tsx`

- [ ] **Step 1: Add imports for Tag and Select components**

Add to the import block after the existing lucide-react imports:

```typescript
import { Tag } from "lucide-react";
```

- [ ] **Step 2: Add `captionType` state**

After existing useState declarations (after line 55):

```typescript
const [captionType, setCaptionType] = useState("tags");
```

- [ ] **Step 3: Add useQuery for caption types and active type**

After the existing `datasetInfo` query (after line 63):

```typescript
const { data: captionTypes = [] } = useQuery({
  queryKey: ["captionTypes"],
  queryFn: () => api.getCaptionTypes(),
});

const { data: firstItem } = useQuery({
  queryKey: ["exportActiveCaptionType"],
  queryFn: () => api.getItem(0),
  enabled: captionTypes.length > 0,
});

useEffect(() => {
  if (firstItem?.captions && captionTypes.length > 0) {
    const active = firstItem.captions.find((c: { is_active: boolean }) => c.is_active);
    const defaultType = active?.caption_type ?? captionTypes[0] ?? "tags";
    setCaptionType(defaultType);
  }
}, [firstItem, captionTypes]);
```

- [ ] **Step 4: Add OperationCard for caption type**

Add after the Format OperationCard (after line 170) and before the Bucket Resize card:

```typescript
<OperationCard
  icon={<Tag className="w-5 h-5" />}
  title="Caption Type"
  description="Select which caption type to export"
  checked={true}
  onCheckedChange={() => {}}
>
  <div className="flex items-center gap-3">
    <label className="text-sm text-text-secondary">Type</label>
    <Select
      value={captionType}
      onValueChange={(v) => setCaptionType(v ?? "tags")}
      disabled={captionTypes.length === 0}
    >
      <SelectTrigger className="w-40">
        <SelectValue placeholder={captionTypes.length === 0 ? "No caption types available" : ""} />
      </SelectTrigger>
      <SelectContent>
        {captionTypes.map((type: string) => (
          <SelectItem key={type} value={type}>
            {type}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  </div>
</OperationCard>
```

- [ ] **Step 5: Pass caption_type in export call**

Edit the `handleExport` function where `api.startExportTask` is called (lines 100-106):

```typescript
const result = await api.startExportTask({
  format,
  caption_type: captionType,
  bucket_resize: bucketResize,
  bucket_resolution: resolution,
  bucket_step: step,
  bucket_max_steps: maxSteps,
});
```

- [ ] **Step 6: Commit**

```bash
git add frontend/src/components/export/ExportForm.tsx
git commit -m "feat(export): add caption type selector OperationCard"
```

---

## Self-Review Checklist

1. **Spec coverage:** All spec requirements have tasks: schema (Task 1), service (Task 2), router (Task 3), frontend (Task 4).
2. **Placeholder scan:** No TODOs, no TBDs. All code is concrete.
3. **Type consistency:** `api.getCaptionTypes()` returns `string[]` (already in api.ts line 170). `api.getItem(0)` returns `MediaItem` which has `captions: CaptionEntry[]`. `CaptionEntry.is_active` matches the spec design.
4. **API compatibility:** `startExportTask` already forwards arbitrary `Record<string, unknown>` options — no change needed to api.ts.

---

Plan complete and saved to `docs/superpowers/plans/2026-04-26-export-caption-type-selector.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
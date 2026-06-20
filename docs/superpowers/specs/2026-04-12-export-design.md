# Export Page Design

## Overview

Create a new **Export** page that combines dataset export with bucket configuration. The Bucket Resize operation moves from the Batch page to this new page.

## UI Structure

### Page: `/export`

**Header:**
- Title: "Export Dataset"
- Description: "Export your dataset to a standard format with optional bucket resizing."

**Format Selector:**
- Dropdown with options: "standard" (default), future formats hidden/disabled
- Stored in state as `format`

**Bucket Resize Configuration (Card):**
- Collapsible card, similar to BatchForm OperationCard style
- Checkbox to enable/disable bucket resizing
- When enabled:
  - Base Resolution dropdown: 512, 768, 1024, 1280, 1536, 1792, 2048 (default: 1024)
  - Step input: number, default 128, range 64-512, step 64
  - Max Steps input: number, default 2, range 1-4
  - "Analyze Buckets" button → calls API, displays bucket distribution grid
  - Bucket result display: grid showing each bucket (WxH) with image count

**Export Button:**
- Position: bottom right, "Export" with download icon
- Disabled when no operations selected (format always selected)
- Shows "Exporting..." and progress during export

**Progress Display:**
- Similar to BatchForm ProgressLog component
- Shows: index/total, filename, progress bar, log messages

### Output Structure (Standard Format)

```
export_folder/
├── img/
│   ├── 00001.jpg
│   ├── 00001.txt    (caption)
│   ├── 00002.jpg
│   ├── 00002.txt
│   └── ...
└── masks/
    ├── 00001.png   (if mask exists)
    ├── 00002.png
    └── ...
```

- Images: written to `img/` folder with 5-digit zero-padded filenames
- Captions: corresponding `.txt` file with same base name, content = caption text
- Masks: written to `masks/` folder if exists, same naming pattern

## Backend Design

### Router: `app/routers/export.py`

**Endpoint:** `POST /api/export`

Request:
```python
class ExportRequest(BaseModel):
    format: str = "standard"  # "standard" for now
    bucket_resize: bool = False
    bucket_resolution: int = 1024
    bucket_step: int = 128
    bucket_max_steps: int = 2
```

Response:
- If processing: SSE stream with progress events
- On completion: ZIP file download (application/zip)

**Endpoint:** `GET /api/export/progress/{task_id}`
- Returns current export task status

### Service: `app/services/export_service.py`

Functions:
- `export_dataset(session, options) -> str` — main export orchestrator
  - Creates temp output directory
  - Iterates through dataset items
  - For each item:
    - If bucket_resize: resize to bucket using bucketing.py
    - Write image to `img/` with new name
    - Write caption to `img/{name}.txt`
    - Copy mask to `masks/{name}.png` if exists
  - Create ZIP from output directory
  - Return ZIP path for serving

- `create_zip_archive(source_dir, zip_path)` — compress folder to ZIP

### Cleanup
- Temp directories cleaned up after ZIP is served or on error

## Frontend Changes

### New Files

1. `frontend/src/app/export/page.tsx` — Page component
2. `frontend/src/components/export/ExportForm.tsx` — Main form component

### API Integration

Add to `frontend/src/lib/api.ts`:
```typescript
exportDataset: (options: ExportOptions) => EventSource,
startExportTask: (options: ExportOptions) => Promise<{ task_id: string }>,
getExportStatus: (taskId: string) => Promise<BatchTask>,
analyzeBuckets: (resolution, step, maxSteps) => Promise<BucketResult>,
```

## Batch Page Changes

### Remove from BatchForm.tsx

1. State variables: `bucketResize` (line 81)
2. State variables: `resolution`, `step`, `maxSteps` (lines 87-89)
3. State variable: `bucketResult` (line 93)
4. Handler: `handleAnalyzeBuckets` (lines 208-216)
5. OperationCard for Bucket Resize (lines 299-365)
6. Remove `bucket_resize` from API call (line 186)
7. Remove bucket config from `handleStart` (lines 192-194)

## Acceptance Criteria

1. New `/export` page accessible from navigation
2. Format selector shows "standard" (and future options disabled)
3. Bucket Resize configuration card functional:
   - Enable/disable toggle works
   - Resolution/step/maxSteps inputs work
   - Analyze Buckets shows distribution
4. Export button triggers export process
5. Progress shown during export
6. ZIP downloaded to user on completion
7. ZIP contains correct structure: `img/` with images+txt, `masks/` with masks files
8. Bucket resized images if enabled
9. Bucket Resize completely removed from Batch page
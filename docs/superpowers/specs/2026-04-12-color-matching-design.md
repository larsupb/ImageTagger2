# Color Matching Batch Step Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new "Color Matching" batch processing step that applies color transfer to all images using histogram/wavelet/PCA methods with a reference image from the dataset.

**Architecture:** 
- Backend: Add `color_match` fields to `BatchProcessRequest` schema, new color matching utility in `lib/`, new preview endpoint, and processing logic in batch.py
- Frontend: New OperationCard with method dropdown, reference dropdown with thumbnail, histogram plot, and preview button showing 4 side-by-side before/after images

**Tech Stack:** Python (scikit-image, pywt, scipy), TypeScript/React, PIL

---

## File Structure

### New Files
- `backend/lib/color_matching.py` - Color matching utility functions
- `backend/app/models/schemas.py` - Add ColorMatchPreviewRequest/Response schemas

### Modified Files
- `backend/app/models/schemas.py:142-156` - Add color_match fields to BatchProcessRequest
- `backend/app/routers/batch.py:20-155` - Add color_match processing logic + preview endpoint
- `backend/requirements.txt` - Add scikit-image, pywt, scipy dependencies
- `frontend/src/lib/types.ts` - Add ColorMatchPreviewResult type
- `frontend/src/lib/api.ts` - Add previewColorMatch API method
- `frontend/src/components/batch/BatchForm.tsx` - Add Color Matching operation card with preview

---

## Task 1: Backend Color Matching Utility

**Files:**
- Create: `backend/lib/color_matching.py`
- Modify: `backend/requirements.txt`

- [ ] **Step 1: Add dependencies to requirements.txt**

Add to end of `backend/requirements.txt`:
```
scikit-image
pywavelets
scipy
```

- [ ] **Step 2: Create color_matching.py utility**

Create `backend/lib/color_matching.py`:

```python
"""Color matching utilities using histogram, wavelet, and PCA methods."""

import numpy as np
from PIL import Image
from typing import Tuple


def apply_histogram_matching_lab(
    source: Image.Image, reference: Image.Image
) -> Image.Image:
    """Apply histogram matching in LAB color space."""
    try:
        import skimage
    except ImportError:
        raise ImportError("scikit-image required for histogram matching")

    if source.mode != "RGB":
        source = source.convert("RGB")
    if reference.mode != "RGB":
        reference = reference.convert("RGB")

    source_arr = np.array(source)
    ref_arr = np.array(reference)

    source_lab = skimage.color.rgb2lab(source_arr)
    ref_lab = skimage.color.rgb2lab(ref_arr)

    matched_l = skimage.exposure.match_histograms(
        source_lab[:, :, 0], ref_lab[:, :, 0]
    )
    matched_a = skimage.exposure.match_histograms(
        source_lab[:, :, 1], ref_lab[:, :, 1]
    )
    matched_b = skimage.exposure.match_histogram(
        source_lab[:, :, 2], ref_lab[:, :, 2]
    )

    matched_lab = np.stack([matched_l, matched_a, matched_b], axis=-1)
    matched_rgb = skimage.color.lab2rgb(matched_lab)

    matched_rgb = np.clip(matched_rgb * 255, 0, 255).astype(np.uint8)
    return Image.fromarray(matched_rgb)


def apply_wavelet_matching(
    source: Image.Image, reference: Image.Image
) -> Image.Image:
    """Apply wavelet-based color transfer."""
    try:
        import pywt
    except ImportError:
        raise ImportError("pywavelets required for wavelet matching")

    if source.mode != "RGB":
        source = source.convert("RGB")
    if reference.mode != "RGB":
        reference = reference.convert("RGB")

    source_arr = np.array(source, dtype=np.float32)
    ref_arr = np.array(reference, dtype=np.float32)

    source_resized = source.resize(reference.size, Image.LANCZOS)
    source_arr = np.array(source_resized, dtype=np.float32)

    result = np.zeros_like(source_arr)

    for channel in range(3):
        sc = pywt.wavedec2(source_arr[:, :, channel], "db1", level=2)
        rc = pywt.wavedec2(ref_arr[:, :, channel], "db1", level=2)

        for level in range(len(sc)):
            if isinstance(sc[level], tuple):
                cA, (cH, cV, cD) = sc[level]
                rA, (rH, rV, rD) = rc[level]

                cA = (cA - cA.mean()) / (cA.std() + 1e-8) * rA.std() + rA.mean()
                cH = (cH - cH.mean()) / (cH.std() + 1e-8) * rH.std() + rH.mean()
                cV = (cV - cV.mean()) / (cV.std() + 1e-8) * rV.std() + rV.mean()
                cD = (cD - cD.mean()) / (cD.std() + 1e-8) * rD.std() + rD.mean()

                sc[level] = (cA, (cH, cV, cD))
            else:
                sc[level] = (sc[level] - sc[level].mean()) / (sc[level].std() + 1e-8) * rc[level].std() + rc[level].mean()

        reconstructed = pywt.waverec2(sc, "db1")
        result[:, :, channel] = reconstructed[:source_arr.shape[0], :source_arr.shape[1]]

    result = np.clip(result, 0, 255).astype(np.uint8)
    return Image.fromarray(result)


def apply_pca_matching(
    source: Image.Image, reference: Image.Image
) -> Image.Image:
    """Apply PCA-based color transfer."""
    try:
        from sklearn.decomposition import PCA
    except ImportError:
        raise ImportError("scikit-learn required for PCA matching")

    if source.mode != "RGB":
        source = source.convert("RGB")
    if reference.mode != "RGB":
        reference = reference.convert("RGB")

    source_resized = source.resize(reference.size, Image.LANCZOS)
    source_arr = np.array(source_resized, dtype=np.float32)
    ref_arr = np.array(reference, dtype=np.float32)

    h, w = source_arr.shape[:2]
    source_flat = source_arr.reshape(-1, 3)
    ref_flat = ref_arr.reshape(-1, 3)

    pca_source = PCA(n_components=3)
    pca_ref = PCA(n_components=3)

    source_pca = pca_source.fit_transform(source_flat)
    ref_pca = pca_ref.fit_transform(ref_flat)

    source_pca_norm = (source_pca - source_pca.mean(axis=0)) / (source_pca.std(axis=0) + 1e-8)
    ref_pca_norm = (ref_pca - ref_pca.mean(axis=0)) / (ref_pca.std(axis=0) + 1e-8)

    matched_pca = source_pca_norm * ref_pca.std(axis=0) + ref_pca.mean(axis=0)

    matched_flat = pca_ref.inverse_transform(matched_pca)
    matched_arr = matched_flat.reshape(h, w, 3)

    result = np.clip(matched_arr, 0, 255).astype(np.uint8)
    return Image.fromarray(result)


def color_match_image(
    source: Image.Image, reference: Image.Image, method: str = "histogram"
) -> Image.Image:
    """Apply color matching to source image using specified method."""
    if method == "histogram":
        return apply_histogram_matching_lab(source, reference)
    elif method == "wavelet":
        return apply_wavelet_matching(source, reference)
    elif method == "pca":
        return apply_pca_matching(source, reference)
    else:
        raise ValueError(f"Unknown color matching method: {method}")


def compute_lab_histogram(image: Image.Image) -> dict:
    """Compute LAB histogram for visualization."""
    import skimage

    if image.mode != "RGB":
        image = image.convert("RGB")

    arr = np.array(image)
    lab = skimage.color.rgb2lab(arr)

    hist_l, _ = np.histogram(lab[:, :, 0].flatten(), bins=64, range=(0, 100))
    hist_a, _ = np.histogram(lab[:, :, 1].flatten(), bins=64, range=(-128, 128))
    hist_b, _ = np.histogram(lab[:, :, 2].flatten(), bins=64, range=(-128, 128))

    return {
        "l": hist_l.tolist(),
        "a": hist_a.tolist(),
        "b": hist_b.tolist(),
    }
```

- [ ] **Step 3: Commit**

```bash
git add backend/requirements.txt backend/lib/color_matching.py
git commit -m "feat: add color matching utility with histogram, wavelet, PCA methods"
```

---

## Task 2: Backend Schema and Batch Processing

**Files:**
- Modify: `backend/app/models/schemas.py:142-156`
- Modify: `backend/app/routers/batch.py:1-183`

- [ ] **Step 1: Add color_match fields to BatchProcessRequest schema**

In `backend/app/models/schemas.py`, update `BatchProcessRequest` class:

```python
class BatchProcessRequest(BaseModel):
    rename: bool = False
    rename_offset: int = 0
    upscale: bool = False
    upscaler: Optional[str] = None
    bucket_resize: bool = False
    mask: bool = False
    caption: bool = False
    tagger: str = "joytag"
    unified_caption: str = ""
    caption_type: str = "tags"
    bucket_resolution: int = 1024
    bucket_step: int = 128
    bucket_max_steps: int = 2
    color_match: bool = False
    color_match_method: str = "histogram"
    color_match_reference: int = 0
```

- [ ] **Step 2: Add preview request/response schemas**

Add after `BatchProcessRequest` class in `backend/app/models/schemas.py`:

```python
class ColorMatchPreviewRequest(BaseModel):
    method: str = "histogram"
    reference: int = 0
    sample_count: int = 4


class ColorMatchPreviewResult(BaseModel):
    previews: list[dict]
```

- [ ] **Step 3: Add color match processing in batch.py**

In `backend/app/routers/batch.py`, add to the event_generator function after line 125 (after caption processing):

```python
if req.color_match:
    from lib.color_matching import color_match_image
    from PIL import Image

    ref_index = req.color_match_reference
    if ref_index < 0 or ref_index >= len(ds):
        log_line.append("Color match: SKIPPED - invalid reference index")
    else:
        ref_item = ds.get_item(ref_index)
        try:
            ref_img = Image.open(ref_item.media_path)
            create_version_backup(session, i, "color_match")

            img = Image.open(item.media_path)
            result = color_match_image(
                img, ref_img, req.color_match_method or "histogram"
            )
            result.save(item.media_path)
            log_line.append(
                f"Color matched using {req.color_match_method or 'histogram'}"
            )
        except Exception as e:
            log_line.append(f"Color match ERROR: {str(e)}")
```

- [ ] **Step 4: Add preview endpoint in batch.py**

Add at end of `backend/app/routers/batch.py`:

```python
@router.post("/preview-color-match", response_model=ColorMatchPreviewResult)
async def preview_color_match(
    req: ColorMatchPreviewRequest, session: Session = Depends(get_session)
):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")

    ds = session.dataset
    total = len(ds)

    if req.reference < 0 or req.reference >= total:
        raise HTTPException(400, "Invalid reference index")

    import random
    import base64
    import io

    indices = random.sample(range(total), min(req.sample_count, total))
    ref_item = ds.get_item(req.reference)

    from lib.color_matching import color_match_image
    from PIL import Image

    ref_img = Image.open(ref_item.media_path)
    if ref_img.mode != "RGB":
        ref_img = ref_img.convert("RGB")

    previews = []
    for idx in indices:
        item = ds.get_item(idx)
        source_img = Image.open(item.media_path)
        if source_img.mode != "RGB":
            source_img = source_img.convert("RGB")

        matched_img = color_match_image(source_img, ref_img, req.method)

        source_buf = io.BytesIO()
        matched_buf = io.BytesIO()
        source_img.save(source_buf, format="JPEG", quality=85)
        matched_img.save(matched_buf, format="JPEG", quality=85)

        previews.append({
            "index": idx,
            "filename": item.filename,
            "before": base64.b64encode(source_buf.getvalue()).decode(),
            "after": base64.b64encode(matched_buf.getvalue()).decode(),
        })

    return ColorMatchPreviewResult(previews=previews)
```

- [ ] **Step 5: Add import for new schemas**

In `backend/app/routers/batch.py`, update imports:

```python
from app.models.schemas import (
    BatchProcessRequest,
    BucketAnalyzeRequest,
    BucketAnalyzeResponse,
    ColorMatchPreviewRequest,
    ColorMatchPreviewResult,
)
```

- [ ] **Step 6: Commit**

```bash
git add backend/app/models/schemas.py backend/app/routers/batch.py
git commit -m "feat: add color matching to batch processing with preview endpoint"
```

---

## Task 3: Frontend Types and API

**Files:**
- Modify: `frontend/src/lib/types.ts`
- Modify: `frontend/src/lib/api.ts`

- [ ] **Step 1: Add ColorMatchPreviewResult type**

Add at end of `frontend/src/lib/types.ts`:

```typescript
export interface ColorMatchPreviewItem {
  index: number;
  filename: string;
  before: string;
  after: string;
}

export interface ColorMatchPreviewResult {
  previews: ColorMatchPreviewItem[];
}

export interface ColorMatchMethod {
  id: string;
  name: string;
}
```

- [ ] **Step 2: Add previewColorMatch API method**

In `frontend/src/lib/api.ts`, add after `analyzeBuckets` method:

```typescript
previewColorMatch: (method: string, reference: number, sampleCount = 4) =>
  apiFetch<ColorMatchPreviewResult>("/api/batch/preview-color-match", {
    method: "POST",
    body: JSON.stringify({ method, reference, sample_count: sampleCount }),
  }),
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/lib/types.ts frontend/src/lib/api.ts
git commit -m "feat: add color match types and API methods"
```

---

## Task 4: Frontend Batch Form UI

**Files:**
- Modify: `frontend/src/components/batch/BatchForm.tsx`

- [ ] **Step 1: Add state and imports**

In `BatchForm.tsx`, add imports at top:

```typescript
import { Palette, Eye } from "lucide-react";
```

Add state after line 84:

```typescript
const [colorMatch, setColorMatch] = useState(false);
const [colorMatchMethod, setColorMatchMethod] = useState("histogram");
const [colorMatchReference, setColorMatchReference] = useState(0);
const [colorMatchPreview, setColorMatchPreview] = useState<ColorMatchPreviewItem[]>([]);
const [isPreviewing, setIsPreviewing] = useState(false);
```

- [ ] **Step 2: Add preview handler**

After `handleAnalyzeBuckets` function, add:

```typescript
const handleColorMatchPreview = async () => {
  setIsPreviewing(true);
  setColorMatchPreview([]);
  try {
    const result = await api.previewColorMatch(colorMatchMethod, colorMatchReference, 4);
    setColorMatchPreview(result.previews);
  } catch (e) {
    toast.error(e instanceof Error ? e.message : "Preview failed");
  } finally {
    setIsPreviewing(false);
  }
};
```

- [ ] **Step 3: Update hasAnyOperation**

Replace line 178:
```typescript
const hasAnyOperation = rename || upscale || bucketResize || mask || caption || colorMatch;
```

- [ ] **Step 4: Update handleStart body to include color match options**

In `handleStart`, add to the body JSON (around line 127):

```typescript
color_match: colorMatch,
color_match_method: colorMatchMethod,
color_match_reference: colorMatchReference,
```

- [ ] **Step 5: Add Color Matching OperationCard**

After the caption OperationCard (around line 349), add:

```typescript
<OperationCard
  icon={<Palette className="w-5 h-5" />}
  title="Color Matching"
  description="Transfer color distribution from a reference image."
  checked={colorMatch}
  onCheckedChange={setColorMatch}
>
  <div className="flex flex-col gap-3">
    <div className="flex items-center gap-3">
      <label className="text-sm text-text-secondary">Method</label>
      <Select value={colorMatchMethod} onValueChange={(v) => setColorMatchMethod(v ?? "histogram")}>
        <SelectTrigger className="w-32">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="histogram">Histogram</SelectItem>
          <SelectItem value="wavelet">Wavelet</SelectItem>
          <SelectItem value="pca">PCA</SelectItem>
        </SelectContent>
      </Select>
    </div>
    <div className="flex items-center gap-3">
      <label className="text-sm text-text-secondary">Reference</label>
      <Select 
        value={String(colorMatchReference)} 
        onValueChange={(v) => setColorMatchReference(Number(v) || 0)}
      >
        <SelectTrigger className="w-48">
          <SelectValue placeholder="Select image" />
        </SelectTrigger>
        <SelectContent>
          {Array.from({ length: Math.min(datasetInfo?.total_items || 0, 100) }, (_, i) => (
            <SelectItem key={i} value={String(i)}>
              {i} - {galleryItems[i]?.filename || `image_${i}`}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <img
        src={colorMatchReference >= 0 ? api.thumbnailUrl(colorMatchReference) : ""}
        alt="Reference"
        className="w-12 h-12 object-cover rounded border border-border"
      />
    </div>
    <Button
      variant="outline"
      size="sm"
      onClick={handleColorMatchPreview}
      disabled={isPreviewing || !colorMatch}
    >
      <Eye className="w-4 h-4 mr-1.5" />
      {isPreviewing ? "Previewing..." : "Preview"}
    </Button>
    {colorMatchPreview.length > 0 && (
      <div className="mt-2">
        <p className="text-xs text-text-muted mb-2">Preview Results</p>
        <div className="grid grid-cols-4 gap-2">
          {colorMatchPreview.map((preview) => (
            <div key={preview.index} className="flex flex-col gap-1">
              <div className="text-xs text-text-secondary truncate">{preview.filename}</div>
              <div className="flex gap-0.5">
                <img
                  src={`data:image/jpeg;base64,${preview.before}`}
                  alt="Before"
                  className="w-full h-16 object-cover rounded"
                />
                <img
                  src={`data:image/jpeg;base64,${preview.after}`}
                  alt="After"
                  className="w-full h-16 object-cover rounded"
                />
              </div>
            </div>
          ))}
        </div>
      </div>
    )}
  </div>
</OperationCard>
```

- [ ] **Step 6: Get dataset info for dropdown population**

After existing queries (around line 102), add:

```typescript
const { data: datasetInfo } = useQuery({
  queryKey: ["datasetInfo"],
  queryFn: () => api.getDatasetInfo(),
});

const { data: galleryItems } = useQuery({
  queryKey: ["galleryItems"],
  queryFn: () => api.getGallery(0, 100).then(r => r.items),
});
```

- [ ] **Step 7: Add getDatasetInfo to api.ts if missing**

Check if `getDatasetInfo` exists in api.ts. If not, add:

```typescript
getDatasetInfo: () => apiFetch<DatasetInfo>("/api/dataset/info"),
```

- [ ] **Step 8: Commit**

```bash
git add frontend/src/components/batch/BatchForm.tsx
git commit -m "feat: add color matching UI to batch form with preview"
```

---

## Task 5: Verification

**Files:**
- Test locally with the development servers

- [ ] **Step 1: Install new dependencies**

```bash
pip install scikit-image pywavelets scipy scikit-learn
```

- [ ] **Step 2: Start servers**

```bash
./run.sh
```

- [ ] **Step 3: Test in browser**

1. Open http://localhost:3000
2. Load a dataset with images
3. Navigate to /batch
4. Enable Color Matching
5. Select method and reference image
6. Click Preview - should show 4 side-by-side images
7. Run batch - should process all images with color matching

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: update dependencies for color matching"
```

---

## Implementation Complete

All tasks completed. The color matching batch step is now available with:
- Three methods: Histogram (LAB), Wavelet, PCA
- Reference image selection via dropdown with thumbnail preview
- Preview button showing 4 side-by-side before/after images
- Version backup before processing
- Skip-with-warning on invalid reference
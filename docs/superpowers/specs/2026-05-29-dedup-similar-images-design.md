# Design: Duplicate / Similar Image Detection

**Date:** 2026-05-29
**Status:** Approved

## Problem

Training datasets often accumulate the same source image at different resolutions or with different post-processing applied (sharpening, blurring, compression). These near-duplicates waste storage, bloat training steps, and can bias model outputs. The goal is a workflow that finds these groups, lets the user pick the best copy to keep, and deletes the rest.

## Scope

- Detect perceptually similar images within the currently loaded dataset session
- Support groups of 2+ near-duplicates
- Let the user review groups and choose which image to keep per group
- Delete the unwanted images from disk and remove them from the session
- Does NOT handle video deduplication (out of scope for now)

## Similarity Strategy: pHash + SSIM

**Phase 1 — pHash candidate filtering**
Compute a 64-bit perceptual hash (via `imagehash.phash`) for each image. Compare all pairs using Hamming distance. Pairs with distance ≤ threshold are candidate duplicates. This is O(n²) in comparisons but trivially fast for < 500 images.

**Phase 2 — SSIM confirmation**
For each candidate pair, compute SSIM (`skimage.metrics.structural_similarity`) on images resized to 256×256 grayscale. Only pairs with SSIM ≥ threshold are confirmed as duplicates.

**Why two phases:** pHash is fast but has false positives at looser thresholds. SSIM catches blur/sharpen differences that pHash misses (different frequency content), and eliminates pHash false positives at the cost of loading images.

**Default thresholds:** pHash distance ≤ 10 (out of 64), SSIM ≥ 0.85. Both exposed as UI sliders.

**Group merging:** Confirmed pairs are merged into groups via union-find. Within each group, the image with the largest pixel area is pre-selected as the default "keep."

## New Dependency

- `imagehash` — lightweight pHash implementation (MIT license). Add to `backend/requirements.txt`.
- `scikit-image` — already present. Used for `structural_similarity`.

## Backend

### `backend/app/services/dedup_service.py`

Single module with four functions:

```
compute_phash(media_path: str) -> imagehash.ImageHash
    Load image (or reuse thumbnail), return pHash.

find_candidate_pairs(
    items: list[MediaItem],
    phash_threshold: int
) -> list[tuple[int, int]]
    Return index pairs where Hamming distance ≤ threshold.

confirm_with_ssim(
    path_a: str,
    path_b: str,
    ssim_threshold: float
) -> bool
    Resize both to 256×256 grayscale, compute SSIM, return True if ≥ threshold.

group_duplicates(
    items: list[MediaItem],
    phash_threshold: int = 10,
    ssim_threshold: float = 0.85
) -> list[list[int]]
    Run both phases, merge pairs via union-find, return groups as lists of indices.
    Groups of size 1 (no confirmed duplicate) are excluded.
```

### `backend/app/routers/dedup.py`

Two endpoints, both require `X-Session-ID` header.

**`POST /api/dedup/scan`**

Request body:
```json
{ "phash_threshold": 10, "ssim_threshold": 0.85 }
```

Response:
```json
{
  "groups": [
    {
      "images": [
        {
          "index": 0,
          "filename": "img_001.jpg",
          "width": 1920,
          "height": 1080,
          "file_size": 2150400,
          "thumbnail_url": "/api/media/0/thumbnail?session_id=..."
        }
      ],
      "keep_index": 0
    }
  ]
}
```

`keep_index` is the position within `images` array pre-selected by the service (largest area). Frontend may override.

**`DELETE /api/dedup/remove`**

Request body:
```json
{ "paths": ["/abs/path/to/img_002.jpg", "/abs/path/to/img_003.jpg"] }
```

Validates each path belongs to the current session (reject with 400 if not). Deletes each file from disk. Removes corresponding items from the session's `ImageDataSet`. Returns `{ "deleted": 2 }`.

### Router registration

Mount in `backend/app/main.py`:
```python
from app.routers import dedup
app.include_router(dedup.router, prefix="/api/dedup")
```

## Frontend

### Page: `frontend/src/app/dedup/page.tsx`

Three-phase state machine: `idle | scanning | reviewing | done`

**Idle phase**
- Title: "Find Duplicates"
- Two sliders:
  - pHash distance: range 0–20, default 10, labeled "0 = exact copy, 20 = loose match"
  - SSIM threshold: range 0.50–0.99 (step 0.01), default 0.85, labeled "higher = stricter"
- "Scan Dataset" button — triggers `POST /api/dedup/scan`, transitions to `scanning`

**Scanning phase**
- Inline spinner + "Scanning…" label
- No SSE needed (synchronous, fast for small datasets)

**Reviewing phase**
- Summary bar: "Found N groups (M images total). Select the image to keep in each group."
- One card per group:
  - Images displayed as thumbnails (same size, ~120px)
  - Selected (keep) image: green border + "KEEP" badge
  - Others: red-tinted border + "DELETE" badge
  - Clicking any image in the group sets it as the new keep for that group
- Sticky footer:
  - Left: "X images marked for deletion"
  - Right: "Skip Unresolved" button + "Delete X Images" button (destructive red)
- "Skip Unresolved" allows proceeding without resolving groups the user is uncertain about (those groups are simply not acted on)

**Done phase**
- Summary: "Done. X images deleted."
- Detail line: "N groups resolved · M images kept · K groups skipped"
- "Back to Browse" link

### Navigation

Add "Dedup" link to the main nav alongside Browse, Edit, etc.

### API calls

Uses existing `apiFetch<T>()` from `src/lib/api.ts`. No new patterns needed.

## Error Handling

- Scan fails (no session, corrupt image during hashing): return HTTP 400/500 with message; frontend shows error banner and stays in `idle`
- Delete partially fails (file already deleted externally): log warning, continue, report partial success in done summary
- Images that fail pHash computation (e.g. corrupt file) are skipped silently; logged at WARNING level

## Out of Scope

- Video deduplication
- Cross-dataset deduplication
- Automatic deduplication without review
- SSE progress streaming (not needed at < 500 images)
- Undo after deletion

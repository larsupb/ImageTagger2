# Mask Edit Mode — Design Spec

**Date:** 2026-06-04
**Status:** Approved

## Overview

Add a mask edit mode to the Edit page that lets users paint on the mask overlay using a white brush (adds to mask / marks foreground) and an eraser (paints black / removes foreground). The edited canvas replaces the mask file entirely on save. Architecture mirrors the existing Paint mode.

## User Flow

1. Image has a mask → eye icon is visible in ImageToolbar (existing behaviour)
2. User clicks eye icon → mask overlay appears; an **Edit** button (pencil icon, blue) appears adjacent to the eye icon
3. User clicks Edit → mask edit mode activates:
   - The mask `<img>` overlay is hidden
   - A canvas pre-loaded with the existing mask is shown in its place (same `opacity-50 mix-blend-multiply` styling — looks identical to the overlay but is now editable)
4. User paints: Pencil/Quad brush stamps white pixels (add to mask); Eraser stamps black pixels (remove from mask). Zoom/pan work as normal.
5. **Save** → canvas blob sent to backend, mask file replaced entirely, mask edit mode exits, mask overlay reloads with cache-busting `v=` param, `showMask` stays true
6. **Cancel** → canvas discarded, mask overlay restored, no file changes

## Components

### New: `MaskToolbar` (`src/components/edit/MaskToolbar.tsx`)

Presentational component, no internal state. Same structure as `PaintToolbar` but without the color row.

Props:
- `tool: PaintTool` / `setTool`
- `size: number` / `setSize`
- `onSave: () => void`
- `onCancel: () => void`

Contains:
- Tool chips: Pencil / Quad / Eraser (using existing `PaintTool` type from `@/lib/types`)
- Size chips: 4 / 8 / 16 / 32
- Save (green) / Cancel (red) buttons, all with `type="button"` and `aria-pressed`

### Modified: `ImageToolbar`

- Add `maskEditMode?: boolean` and `setMaskEditMode?: (v: boolean) => void` props
- Edit button (pencil icon, `text-blue-400`) appears only when `showMask && !maskEditMode`
- Entering mask edit mode forces paint mode off; entering paint mode forces mask edit mode off

### Modified: `ImageViewer`

New props:
- `maskEditMode?: boolean`
- `maskEditTool?: PaintTool`
- `maskEditSize?: number`
- `maskCanvasRef?: React.RefObject<HTMLCanvasElement | null>`

Canvas changes:
- Mask `<img>` overlay renders only when `showMask && maskUrl && !maskEditMode`
- When `maskEditMode && imageLoaded && imageDisplayRect`: render canvas at `imageDisplayRect` position/size with `opacity-50 mix-blend-multiply imageRendering: pixelated`
- Canvas uses a dedicated `handleMaskCanvasMount` callback ref (parallel to `handleCanvasMount` for paint) to set `naturalWidth × naturalHeight` dimensions on mount
- `useEffect` on `maskEditMode`: when true, loads `maskUrl` via `new Image()` → `ctx.drawImage(...)` to initialise canvas with existing mask data

Stamp logic (reuses existing `stamp()` helper, parameterised by tool/size/color/canvasRef):
- Brush (Pencil/Quad): `ctx.fillStyle = 'white'; ctx.globalCompositeOperation = 'source-over'`
- Eraser: `ctx.fillStyle = 'black'; ctx.globalCompositeOperation = 'source-over'` — paints black, does not punch transparent holes

Mouse event handlers: `handleContainerMouseDown/Move/Up` get a mask-edit branch parallel to the paint branch, using `maskCanvasRef` and `toCanvasCoords` (unchanged — same coordinate mapping applies).

### Modified: `edit/page.tsx`

New state:
- `maskEditMode: boolean`
- `maskEditTool: PaintTool` (default `"pencil"`)
- `maskEditSize: number` (default `8`)
- `maskCanvasRef: React.RefObject<HTMLCanvasElement | null>`
- `maskVersion: number` (default `0`) — incremented after each save to cache-bust the mask URL

Mask URL passed to `ImageViewer`: `` `${api.getMaskUrl(safeIndex)}&v=${maskVersion}` ``

New handlers:
- `handleMaskSave`: `canvas.toBlob('image/png')` → `api.saveMask(index, blob)` → `setMaskEditMode(false)` + `setMaskVersion(v => v + 1)` + `loadItem()` + `invalidateVersions()`, with `try/catch/finally` matching `handlePaintSave` pattern
- `handleMaskCancel`: `setMaskEditMode(false)`

### Modified: `api.ts`

```typescript
saveMask: async (index: number, blob: Blob): Promise<void> => {
  const sid = await getSessionId();
  const form = new FormData();
  form.append("index", String(index));
  form.append("mask_png", blob, "mask.png");
  const res = await fetch("/api/processing/mask/save", {
    method: "POST",
    headers: { "X-Session-ID": sid },
    body: form,
  });
  if (!res.ok) {
    const error = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(error.detail || "Mask save failed");
  }
},
```

## Backend

### `processing_service.py` — `save_mask(session, index, mask_png_bytes)`

```python
def save_mask(session: Session, index: int, mask_png_bytes: bytes):
    import io
    create_version_backup(session, index, "mask")
    ds = session.dataset
    item = ds.get_item(index)
    mask_layer = Image.open(io.BytesIO(mask_png_bytes)).convert("RGBA")
    os.makedirs(os.path.dirname(item.mask_path), exist_ok=True)
    mask_layer.save(item.mask_path)
```

Note: no `update_metadata` call needed — only the mask file changes, not the image file. Cache-busting of the mask URL is handled on the frontend via the `maskVersion` counter in `page.tsx`.

### `processing.py` router — `POST /api/processing/mask/save`

```python
@router.post("/mask/save")
async def save_mask_endpoint(
    index: int = Form(...),
    mask_png: UploadFile = File(...),
    session: Session = Depends(get_session),
):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    try:
        data = await mask_png.read()
        processing_service.save_mask(session, index, data)
        return {"status": "saved", "index": index}
    except Exception as e:
        logger.error("mask save failed for index %s: %s", index, e, exc_info=True)
        raise HTTPException(500, str(e))
```

No changes needed to `media.py` — `GET /api/media/mask/{index}` already serves the updated file.

## Canvas Initialisation Detail

```typescript
useEffect(() => {
  if (!maskEditMode || !maskCanvasRef?.current || !maskUrl) return;
  const canvas = maskCanvasRef.current;
  const img = new Image();
  img.crossOrigin = "anonymous";
  img.onload = () => {
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
  };
  img.src = maskUrl;
}, [maskEditMode, maskUrl, maskCanvasRef]);
```

## Mask Format Note

Masks are RGBA PNGs where white (255,255,255,255) = foreground and black (0,0,0,255) = background. The display overlay uses `mix-blend-multiply` at 50% opacity: white areas show the underlying image normally, black areas darken it. The edited canvas preserves this format.

## Mutual Exclusions

- Mask edit mode and paint mode are mutually exclusive
- Mask edit mode and crop mode are mutually exclusive (crop resets zoom/pan; entering crop exits mask edit)
- `cropModeRef` guard on the wheel handler already prevents zoom during crop; mask edit does not need this guard (zoom/pan remain active during mask editing)

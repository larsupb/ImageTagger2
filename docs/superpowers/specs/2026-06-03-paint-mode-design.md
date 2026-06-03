# Paint Mode — Design Spec

**Date:** 2026-06-03
**Status:** Approved

## Overview

Paint mode is a new interactive modification type on the Edit page. The user draws on a transparent canvas overlay on top of the image. On save, the paint canvas PNG is sent to the backend, which composites it onto the original image using PIL and creates a version backup before writing — consistent with existing modification types (Crop, Upscale, etc.).

## User Flow

1. User clicks **Paint** button in `ImageToolbar`.
2. A horizontal paint toolbar appears below the image viewer (same region as crop's Accept/Cancel bar).
3. The image viewer overlays a transparent `<canvas>` on top of the image.
4. User selects tool, size, and color. Draws on the canvas with mouse.
5. **Save** → paint canvas PNG blob + image natural dimensions posted to `/api/processing/paint` → backend composites + version backup + saves → image refreshes.
6. **Cancel** → canvas cleared, paint mode exits with no changes saved.

Paint mode and Crop mode are mutually exclusive — activating one deactivates the other.

## Tools

| Tool | Brush shape | Composite op |
|------|-------------|--------------|
| Pencil | Filled circle | `source-over` |
| Quad | Filled square | `source-over` |
| Eraser | Filled circle | `destination-out` |

The eraser removes only paint strokes from the canvas overlay. It never touches the underlying image.

## Drawing Mechanics

- `mousedown` → set `isDrawing = true`, stamp brush at cursor position
- `mousemove` → if `isDrawing`, stamp brush at cursor position
- `mouseup` / `mouseleave` → set `isDrawing = false`

Each stamp is a filled shape (circle or square) drawn at the cursor position. No path interpolation between points. Brush size is applied in canvas natural pixels (scaled from display pixels) so stroke thickness is consistent regardless of image zoom.

## Paint Toolbar (horizontal bar below image viewer)

Controls rendered only when `paintMode` is active:

- **Tool selector** — three toggle chips: `Pencil` / `Quad` / `Eraser`
- **Size selector** — four size chips: `4px` / `8px` / `16px` / `32px`
- **Color swatches** — six fixed colors: white, red, teal, yellow, blue, black (eraser ignores color)
- **Save** and **Cancel** buttons (right-aligned)

## State (edit/page.tsx)

```typescript
paintMode: boolean                          // default: false
paintTool: "pencil" | "quad" | "eraser"    // default: "pencil"
paintSize: 4 | 8 | 16 | 32                 // default: 8
paintColor: string                          // hex, default: "#ffffff"
```

## Components

### ImageToolbar.tsx

- Add **Paint** toggle button (activates/deactivates paint mode).
- When `paintMode` is true, render the horizontal paint toolbar bar below the viewer with tool chips, size chips, color swatches, Save and Cancel buttons.
- `onPaintSave` and `onPaintCancel` callbacks passed from the page.

### ImageViewer.tsx

- When `paintMode` is true, render a `<canvas>` overlay positioned absolute over the image.
- Canvas `width`/`height` attributes are set to the image's `naturalWidth`/`naturalHeight` so `toBlob()` produces a full-resolution PNG. CSS scales the canvas visually to match the displayed image size.
- Mouse coordinates from events (in display pixels) are scaled to natural pixels before drawing: `naturalX = eventX * (naturalWidth / displayWidth)`.
- Canvas handles all mouse events for drawing. The canvas ref is exposed so the page can call `canvas.toBlob()` on save.
- Existing crop canvas logic is unaffected.

### api.ts

```typescript
paint: (index: number, blob: Blob, width: number, height: number) => Promise<void>
```

Posts multipart form data: `index` and the paint PNG blob. The blob is already at full image resolution (canvas is sized to natural dimensions).

## Backend

### New endpoint

`POST /api/processing/paint`

Request: multipart form — `index: int`, `paint_png: UploadFile`

### processing_service.paint_image()

```python
def paint_image(session, index, paint_png_bytes):
    create_version_backup(session, index, "paint")
    item = session.dataset.get_item(index)
    with Image.open(item.media_path) as img:
        original_mode = img.mode
        base = img.convert("RGBA")
    paint_layer = Image.open(io.BytesIO(paint_png_bytes)).convert("RGBA")
    composited = Image.alpha_composite(base, paint_layer)
    composited.convert(original_mode).save(item.media_path)
    item.thumbnail_path = generate_thumbnail(item.media_path)
```

The paint PNG arrives at full image resolution and is composited directly with no resizing needed.

### schemas.py

No new Pydantic model needed — the endpoint uses multipart form fields directly.

## Version Backup

`create_version_backup(session, index, "paint")` is called before any image modification, exactly as with crop and other operations. The user can restore previous versions via the existing Version History UI.

## Error Handling

- If the paint canvas is empty (all transparent), Save still proceeds — results in a no-op composite, which is harmless.
- Backend returns standard `HTTPException` on failure; frontend handles via existing `apiFetch` error path.
- Cancel always exits paint mode safely regardless of canvas state.

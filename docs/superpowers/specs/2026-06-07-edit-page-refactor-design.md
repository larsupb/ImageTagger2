# Edit Page Refactor Design

**Date:** 2026-06-07  
**Motivation:** The edit-page surface (~2,600 lines across 11 files) has grown hard to work in. `ImageViewer.tsx` (706 lines) does three independent jobs. `ImageToolbar.tsx` (417 lines) copies the same 200-character Tailwind class string 8 times. `page.tsx` manages 12+ state variables, many of which belong to subsystems.

**Goal:** Cut files to a size that fits in your head by splitting at natural seams. No new abstractions — just extracting existing logic into focused files.

---

## File Map

| File | Before | After | Change |
|---|---|---|---|
| `components/edit/ImageViewer.tsx` | 706 lines | ~200 lines | zoom/pan/display orchestration only |
| `components/edit/CropOverlay.tsx` | — | ~200 lines | crop state + resize handles + UI (new) |
| `components/edit/PaintCanvas.tsx` | — | ~120 lines | paint canvas, stamp logic, `getBlob()` handle (new) |
| `components/edit/MaskCanvas.tsx` | — | ~100 lines | mask canvas, mask-load-on-entry, `getBlob()` handle (new) |
| `components/edit/ToolbarButton.tsx` | — | ~30 lines | shared icon button, kills 8× copy-pasted className (new) |
| `components/edit/ImageToolbar.tsx` | 417 lines | ~250 lines | uses `ToolbarButton` |
| `app/edit/page.tsx` | 409 lines | ~330 lines | drops raw canvas ref management |

---

## Component Interfaces

### CropOverlay

Owns all crop state internally: `cropRect`, drag start, resize handle, move state, aspect preset. Renders its own event-capturing `div`, so `ImageViewer` needs no knowledge of crop mouse events.

```tsx
interface CropOverlayProps {
  imageDisplayRect: { x: number; y: number; width: number; height: number };
  naturalWidth: number;
  naturalHeight: number;
  onCropComplete: (x: number, y: number, w: number, h: number) => void;
  onCropCancel: () => void;
}
```

Receives display geometry as plain values (not a DOM ref) — `ImageViewer` already computes `imageDisplayRect` via its `ResizeObserver`.

### PaintCanvas / MaskCanvas

Render the `<canvas>` positioned over the image. `ImageViewer`'s container mouse handlers call in via imperative handles:

```tsx
interface PaintCanvasHandle {
  onMouseDown(e: React.MouseEvent): void;
  onMouseMove(e: React.MouseEvent): void;
  onMouseUp(): void;
  getBlob(): Promise<Blob>;
}

interface MaskCanvasHandle {
  onMouseDown(e: React.MouseEvent): void;
  onMouseMove(e: React.MouseEvent): void;
  onMouseUp(): void;
  getBlob(): Promise<Blob>;
  loadMask(url: string): void;
}
```

`PaintCanvas` accepts `tool`, `size`, `color`, `imageDisplayRect` as props.  
`MaskCanvas` accepts `tool`, `size`, `imageDisplayRect` as props. When `maskEditMode` becomes true, `ImageViewer` calls `maskCanvasRef.current.loadMask(maskUrl)` from a `useEffect` — same trigger as the current inline effect.

`page.tsx` save handlers simplify to:

```tsx
const blob = await paintCanvasRef.current.getBlob();
await api.paint(safeIndex, blob);
```

### ToolbarButton

Wraps `Tooltip` + `TooltipTrigger` with the shared button className. Replaces the 8 copy-pasted inline class strings in `ImageToolbar`.

```tsx
interface ToolbarButtonProps {
  tooltip: string;
  onClick?: () => void;
  disabled?: boolean;
  variant?: "default" | "destructive";
  children: React.ReactNode;
}
```

Usage:
```tsx
<ToolbarButton tooltip="Crop" onClick={handleCrop} disabled={!!processing}>
  <Crop className="size-4 text-green-500" />
</ToolbarButton>
```

---

## State Ownership

| State | Currently | After |
|---|---|---|
| `cropRect`, drag, resize, aspect preset | `ImageViewer` | `CropOverlay` (internal) |
| `isPainting`, `isPanning`, `panStart` | `ImageViewer` | `ImageViewer` (stays — shared with pan) |
| `imageDisplayRect`, zoom, pan | `ImageViewer` | `ImageViewer` (stays — needed by all overlays) |
| Raw paint canvas ref | `page.tsx` | `PaintCanvas` (internal; exposes `PaintCanvasHandle`) |
| Raw mask canvas ref | `page.tsx` | `MaskCanvas` (internal; exposes `MaskCanvasHandle`) |
| `paintTool`, `paintSize`, `paintColor` | `page.tsx` | stays — shared between `PaintToolbar` and `PaintCanvas` |
| `maskEditTool`, `maskEditSize` | `page.tsx` | stays — shared between `MaskToolbar` and `MaskCanvas` |

`page.tsx` loses `paintCanvasRef` and `maskCanvasRef` as raw `HTMLCanvasElement` refs and the `toBlob` ceremony. The typed component handles replace them.

---

## ImageViewer After Refactor

`ImageViewer`'s props interface becomes:

```tsx
interface ImageViewerProps {
  mediaUrl: string;
  maskUrl?: string | null;
  filename: string;
  showMask?: boolean;
  processing?: string | null;
  // crop
  cropMode?: boolean;
  onCropComplete?: (x: number, y: number, w: number, h: number) => void;
  onCropCancel?: () => void;
  // paint
  paintMode?: boolean;
  paintTool?: PaintTool;
  paintSize?: number;
  paintColor?: string;
  paintCanvasRef?: React.RefObject<PaintCanvasHandle | null>;
  // mask edit
  maskEditMode?: boolean;
  maskEditTool?: PaintTool;
  maskEditSize?: number;
  maskCanvasRef?: React.RefObject<MaskCanvasHandle | null>;
}
```

The prop count is the same, but the refs are now typed handles rather than raw DOM refs. The body of `ImageViewer` shrinks because crop state and the stamp/draw functions move into their respective components.

---

## What Is Not Changing

- No changes to `CaptionEditor`, `CategorySelector`, `NavigationBar`, `PaintToolbar`, `MaskToolbar`, `VersionHistoryDialog`
- No changes to the backend or API layer
- No new state management libraries or contexts
- `paintTool/Size/Color` and `maskEditTool/Size` remain in `page.tsx` — they are genuinely shared between toolbar siblings and don't belong in either one
- The zoom/pan interaction model is unchanged

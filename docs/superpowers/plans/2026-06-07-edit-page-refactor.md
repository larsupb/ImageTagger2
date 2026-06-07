# Edit Page Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `ImageViewer.tsx` (706 lines) into focused components and eliminate repeated boilerplate in `ImageToolbar.tsx` so every file fits in your head.

**Architecture:** Extract three overlay/canvas components from `ImageViewer` (CropOverlay, PaintCanvas, MaskCanvas), each owning its own state and event handling. Add a shared `ToolbarButton` component to kill the 8× copy-pasted `TooltipTrigger` className in `ImageToolbar`.

**Tech Stack:** React 19 (forwardRef + useImperativeHandle), TypeScript, Tailwind CSS 4, shadcn/Radix Tooltip.

> **Note:** No test framework is configured (see CLAUDE.md). TDD steps are replaced by dev-server verification.

---

## File Map

| File | Action | Responsibility after |
|---|---|---|
| `src/components/edit/ToolbarButton.tsx` | Create | Shared icon button with tooltip, kills repeated className |
| `src/components/edit/CropOverlay.tsx` | Create | All crop state, resize handles, aspect presets, crop UI |
| `src/components/edit/PaintCanvas.tsx` | Create | Paint canvas, stamp logic, exposes `PaintCanvasHandle` via ref |
| `src/components/edit/MaskCanvas.tsx` | Create | Mask canvas, mask-load-on-mount, exposes `MaskCanvasHandle` via ref |
| `src/components/edit/ImageViewer.tsx` | Modify | Zoom/pan/display only; delegates to the four new components |
| `src/components/edit/ImageToolbar.tsx` | Modify | Replace all TooltipTrigger blocks with `<ToolbarButton>` |
| `src/app/edit/page.tsx` | Modify | Use typed canvas handles; simplify handlePaintSave / handleMaskSave |

---

## Task 1: Extract ToolbarButton

**Files:**
- Create: `src/components/edit/ToolbarButton.tsx`
- Modify: `src/components/edit/ImageToolbar.tsx`

### Step 1.1: Create ToolbarButton

Create `src/components/edit/ToolbarButton.tsx`:

```tsx
"use client";

import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";

const BASE =
  "inline-flex items-center justify-center rounded-lg border border-transparent bg-clip-padding text-sm font-medium whitespace-nowrap transition-all outline-none select-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 active:not-aria-[haspopup]:translate-y-px disabled:pointer-events-none disabled:opacity-50 h-7 gap-1.5 px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2 shrink-0 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4";

const VARIANTS = {
  default:
    "bg-background hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground dark:border-input dark:bg-input/30 dark:hover:bg-input/50",
  destructive:
    "bg-destructive/10 text-destructive hover:bg-destructive/20 focus-visible:border-destructive/40 focus-visible:ring-destructive/20 dark:bg-destructive/20 dark:hover:bg-destructive/30 dark:focus-visible:ring-destructive/40",
};

interface ToolbarButtonProps {
  tooltip: string;
  onClick?: () => void;
  disabled?: boolean;
  variant?: "default" | "destructive";
  children: React.ReactNode;
}

export default function ToolbarButton({
  tooltip,
  onClick,
  disabled,
  variant = "default",
  children,
}: ToolbarButtonProps) {
  return (
    <Tooltip>
      <TooltipTrigger
        className={`${BASE} ${VARIANTS[variant]}`}
        onClick={onClick}
        disabled={disabled}
      >
        {children}
      </TooltipTrigger>
      <TooltipContent>{tooltip}</TooltipContent>
    </Tooltip>
  );
}
```

### Step 1.2: Update ImageToolbar to use ToolbarButton

In `src/components/edit/ImageToolbar.tsx`, add the import after the existing imports:

```tsx
import ToolbarButton from "./ToolbarButton";
```

Then replace each `<Tooltip>…<TooltipTrigger className="inline-flex …">…</Tooltip>` block with `<ToolbarButton>`. Apply all 9 replacements below.

**Replace 1 — Gen Mask:**
```tsx
// BEFORE
<Tooltip>
  <TooltipTrigger
    className="inline-flex items-center ... [&_svg:not([class*='size-'])]:size-4"
    onClick={handleGenerateMask}
    disabled={!!processing}
  >
    <VenetianMask className="size-4 text-orange-500" />
  </TooltipTrigger>
  <TooltipContent>
    {processing === "mask" ? "Generating..." : "Gen Mask"}
  </TooltipContent>
</Tooltip>

// AFTER
<ToolbarButton
  tooltip={processing === "mask" ? "Generating..." : "Gen Mask"}
  onClick={handleGenerateMask}
  disabled={!!processing}
>
  <VenetianMask className="size-4 text-orange-500" />
</ToolbarButton>
```

**Replace 2 — Show/Hide Mask:**
```tsx
// BEFORE
{currentItem?.has_mask && (
  <Tooltip>
    <TooltipTrigger
      className="inline-flex items-center ... [&_svg:not([class*='size-'])]:size-4"
      onClick={() => setShowMask(!showMask)}
    >
      {showMask ? <EyeOff className="size-4 text-orange-500" /> : <Eye className="size-4 text-orange-500" />}
    </TooltipTrigger>
    <TooltipContent>{showMask ? "Hide Mask" : "Show Mask"}</TooltipContent>
  </Tooltip>
)}

// AFTER
{currentItem?.has_mask && (
  <ToolbarButton tooltip={showMask ? "Hide Mask" : "Show Mask"} onClick={() => setShowMask(!showMask)}>
    {showMask ? <EyeOff className="size-4 text-orange-500" /> : <Eye className="size-4 text-orange-500" />}
  </ToolbarButton>
)}
```

**Replace 3 — Edit Mask:**
```tsx
// BEFORE
{currentItem?.has_mask && showMask && !maskEditMode && (
  <Tooltip>
    <TooltipTrigger
      className="inline-flex items-center ... [&_svg:not([class*='size-'])]:size-4"
      onClick={handleMaskEdit}
      disabled={!!processing || currentItem?.is_video}
    >
      <Pencil className="size-4 text-blue-400" />
    </TooltipTrigger>
    <TooltipContent>Edit Mask</TooltipContent>
  </Tooltip>
)}

// AFTER
{currentItem?.has_mask && showMask && !maskEditMode && (
  <ToolbarButton tooltip="Edit Mask" onClick={handleMaskEdit} disabled={!!processing || currentItem?.is_video}>
    <Pencil className="size-4 text-blue-400" />
  </ToolbarButton>
)}
```

**Replace 4 — Version History:**
```tsx
// BEFORE
<Tooltip>
  <TooltipTrigger
    className="inline-flex items-center ... [&_svg:not([class*='size-'])]:size-4"
    onClick={() => setHistoryOpen(true)}
  >
    <History className="size-4 text-blue-500" />
  </TooltipTrigger>
  <TooltipContent>Version History</TooltipContent>
</Tooltip>

// AFTER
<ToolbarButton tooltip="Version History" onClick={() => setHistoryOpen(true)}>
  <History className="size-4 text-blue-500" />
</ToolbarButton>
```

**Replace 5 — Crop:**
```tsx
// BEFORE
<Tooltip>
  <TooltipTrigger
    className="inline-flex items-center ... [&_svg:not([class*='size-'])]:size-4"
    onClick={handleCrop}
    disabled={!!processing || currentItem?.is_video}
  >
    <Crop className={`size-4 ${cropMode ? "text-green-400" : "text-green-500"}`} />
  </TooltipTrigger>
  <TooltipContent>Crop</TooltipContent>
</Tooltip>

// AFTER
<ToolbarButton tooltip="Crop" onClick={handleCrop} disabled={!!processing || currentItem?.is_video}>
  <Crop className={`size-4 ${cropMode ? "text-green-400" : "text-green-500"}`} />
</ToolbarButton>
```

**Replace 6 — Paint:**
```tsx
// BEFORE
<Tooltip>
  <TooltipTrigger
    className="inline-flex items-center ... [&_svg:not([class*='size-'])]:size-4"
    onClick={handlePaint}
    disabled={!!processing || currentItem?.is_video}
  >
    <Brush className={`size-4 ${paintMode ? "text-pink-400" : "text-pink-500"}`} />
  </TooltipTrigger>
  <TooltipContent>Paint</TooltipContent>
</Tooltip>

// AFTER
<ToolbarButton tooltip="Paint" onClick={handlePaint} disabled={!!processing || currentItem?.is_video}>
  <Brush className={`size-4 ${paintMode ? "text-pink-400" : "text-pink-500"}`} />
</ToolbarButton>
```

**Replace 7 — Revert (inside the `!renaming` branch):**
```tsx
// BEFORE
<Tooltip>
  <TooltipTrigger
    className="inline-flex items-center ... [&_svg:not([class*='size-'])]:size-4"
    onClick={() => revertMutation.mutate()}
    disabled={!versions || versions.length === 0 || revertMutation.isPending}
  >
    <RotateCcw className={`size-4 ${revertMutation.isPending ? "animate-spin" : "text-indigo-500"}`} />
  </TooltipTrigger>
  <TooltipContent>{versions && versions.length > 0 ? "Revert to Previous" : "No version to revert"}</TooltipContent>
</Tooltip>

// AFTER
<ToolbarButton
  tooltip={versions && versions.length > 0 ? "Revert to Previous" : "No version to revert"}
  onClick={() => revertMutation.mutate()}
  disabled={!versions || versions.length === 0 || revertMutation.isPending}
>
  <RotateCcw className={`size-4 ${revertMutation.isPending ? "animate-spin" : "text-indigo-500"}`} />
</ToolbarButton>
```

**Replace 8 — Rename:**
```tsx
// BEFORE
<Tooltip>
  <TooltipTrigger
    className="inline-flex items-center ... [&_svg:not([class*='size-'])]:size-4"
    onClick={() => { setRenaming(true); setNewName(currentItem?.basename ?? ""); }}
  >
    <Pencil className="size-4" />
  </TooltipTrigger>
  <TooltipContent>Rename</TooltipContent>
</Tooltip>

// AFTER
<ToolbarButton tooltip="Rename" onClick={() => { setRenaming(true); setNewName(currentItem?.basename ?? ""); }}>
  <Pencil className="size-4" />
</ToolbarButton>
```

**Replace 9 — Delete (destructive variant):**
```tsx
// BEFORE
<Tooltip>
  <TooltipTrigger
    className="inline-flex items-center ... dark:focus-visible:ring-destructive/40 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4"
    onClick={() => setConfirmDelete(true)}
  >
    <Trash2 className="size-4" />
  </TooltipTrigger>
  <TooltipContent>Delete</TooltipContent>
</Tooltip>

// AFTER
<ToolbarButton tooltip="Delete" variant="destructive" onClick={() => setConfirmDelete(true)}>
  <Trash2 className="size-4" />
</ToolbarButton>
```

Also remove the now-unused `Tooltip, TooltipContent, TooltipTrigger` import from `ImageToolbar.tsx` if nothing else uses it.

### Step 1.3: Verify

Start the dev server:
```bash
./run.sh
```
Open the edit page. Confirm all toolbar buttons render correctly, tooltips appear on hover, disabled state works (buttons greyed out during processing), and the delete button has its red styling.

### Step 1.4: Commit

```bash
git add src/components/edit/ToolbarButton.tsx src/components/edit/ImageToolbar.tsx
git commit -m "refactor(edit): extract ToolbarButton, remove repeated className"
```

---

## Task 2: Extract CropOverlay

**Files:**
- Create: `src/components/edit/CropOverlay.tsx`
- Modify: `src/components/edit/ImageViewer.tsx`

### Step 2.1: Create CropOverlay.tsx

Create `src/components/edit/CropOverlay.tsx` with all crop state, mouse handlers, and UI extracted from `ImageViewer`:

```tsx
"use client";

import { useState } from "react";

interface CropOverlayProps {
  imageDisplayRect: { x: number; y: number; width: number; height: number };
  naturalWidth: number;
  naturalHeight: number;
  onCropComplete: (x: number, y: number, w: number, h: number) => void;
  onCropCancel: () => void;
}

type ResizeHandle = "nw" | "ne" | "sw" | "se" | "n" | "s" | "e" | "w" | null;

const ASPECTS = [
  { label: "1:1", ratio: 1 },
  { label: "3:2", ratio: 3 / 2 },
  { label: "2:3", ratio: 2 / 3 },
  { label: "5:4", ratio: 5 / 4 },
  { label: "4:5", ratio: 4 / 5 },
  { label: "Free", ratio: null },
];

export default function CropOverlay({
  imageDisplayRect,
  naturalWidth,
  naturalHeight,
  onCropComplete,
  onCropCancel,
}: CropOverlayProps) {
  const [cropRect, setCropRect] = useState<{ x: number; y: number; width: number; height: number } | null>(null);
  const [isDrawing, setIsDrawing] = useState(false);
  const [dragStart, setDragStart] = useState<{ x: number; y: number } | null>(null);
  const [aspectPreset, setAspectPreset] = useState<string | null>(null);
  const [resizing, setResizing] = useState<ResizeHandle>(null);
  const [resizeStart, setResizeStart] = useState<{ x: number; y: number; rect: { x: number; y: number; width: number; height: number } } | null>(null);
  const [moving, setMoving] = useState(false);
  const [moveStart, setMoveStart] = useState<{ x: number; y: number; rect: { x: number; y: number; width: number; height: number } } | null>(null);

  const getOverlayCoords = (e: React.MouseEvent): { x: number; y: number } => {
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  };

  const handleMouseDown = (e: React.MouseEvent) => {
    const target = e.target as HTMLElement;
    if (target.tagName === "BUTTON" || target.closest("button")) return;
    const { x, y } = getOverlayCoords(e);

    if (cropRect && !resizing) {
      const inRect =
        x >= cropRect.x && x <= cropRect.x + cropRect.width &&
        y >= cropRect.y && y <= cropRect.y + cropRect.height;
      if (inRect) {
        setMoveStart({ x, y, rect: { ...cropRect } });
        setMoving(true);
        setIsDrawing(false);
        return;
      }
    }

    setDragStart({ x, y });
    setIsDrawing(true);
    setCropRect(null);
    setResizing(null);
    setMoving(false);
  };

  const handleResizeMouseDown = (e: React.MouseEvent, handle: ResizeHandle) => {
    e.stopPropagation();
    if (!cropRect || !handle) return;
    const overlayRect = (e.currentTarget.closest("[data-crop-overlay]") as HTMLElement)?.getBoundingClientRect();
    if (!overlayRect) return;
    setResizeStart({ x: e.clientX - overlayRect.left, y: e.clientY - overlayRect.top, rect: { ...cropRect } });
    setResizing(handle);
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    const overlayRect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    const mouseX = Math.max(0, Math.min(e.clientX - overlayRect.left, overlayRect.width));
    const mouseY = Math.max(0, Math.min(e.clientY - overlayRect.top, overlayRect.height));

    if (moving && moveStart && cropRect) {
      const dx = mouseX - moveStart.x;
      const dy = mouseY - moveStart.y;
      const s = moveStart.rect;
      setCropRect({
        ...cropRect,
        x: Math.max(0, Math.min(s.x + dx, overlayRect.width - s.width)),
        y: Math.max(0, Math.min(s.y + dy, overlayRect.height - s.height)),
      });
      return;
    }

    if (resizing && resizeStart) {
      const dx = mouseX - resizeStart.x;
      const dy = mouseY - resizeStart.y;
      const s = resizeStart.rect;
      const newRect = { ...s };

      if (resizing.includes("e")) newRect.width = Math.max(20, s.width + dx);
      if (resizing.includes("w")) { newRect.width = Math.max(20, s.width - dx); newRect.x = s.x + (s.width - newRect.width); }
      if (resizing.includes("s")) newRect.height = Math.max(20, s.height + dy);
      if (resizing.includes("n")) { newRect.height = Math.max(20, s.height - dy); newRect.y = s.y + (s.height - newRect.height); }

      if (aspectPreset) {
        const preset = ASPECTS.find((a) => a.label === aspectPreset);
        if (preset?.ratio) {
          if (resizing === "e" || resizing === "w") newRect.height = newRect.width / preset.ratio;
          else if (resizing === "n" || resizing === "s") newRect.width = newRect.height * preset.ratio;
        }
      }

      setCropRect(newRect);
      return;
    }

    if (!isDrawing || !dragStart) return;

    let width = mouseX - dragStart.x;
    let height = mouseY - dragStart.y;

    if (aspectPreset) {
      const preset = ASPECTS.find((a) => a.label === aspectPreset);
      if (preset?.ratio) {
        if (Math.abs(width) > Math.abs(height)) height = width / preset.ratio;
        else width = height * preset.ratio;
      }
    }

    if (width < 0) setCropRect({ x: mouseX, y: dragStart.y, width: -width, height });
    else if (height < 0) setCropRect({ x: dragStart.x, y: mouseY, width, height: -height });
    else setCropRect({ x: dragStart.x, y: dragStart.y, width, height });
  };

  const handleMouseUp = () => {
    setIsDrawing(false);
    setDragStart(null);
    setResizing(null);
    setResizeStart(null);
    setMoving(false);
    setMoveStart(null);
  };

  const handleAccept = () => {
    if (!cropRect) return;
    const { x: offsetX, y: offsetY, width: displayedWidth, height: displayedHeight } = imageDisplayRect;
    const scaleX = naturalWidth / displayedWidth;
    const scaleY = naturalHeight / displayedHeight;
    const crop = {
      x: Math.max(0, Math.round((cropRect.x - offsetX) * scaleX)),
      y: Math.max(0, Math.round((cropRect.y - offsetY) * scaleY)),
      width: Math.round(cropRect.width * scaleX),
      height: Math.round(cropRect.height * scaleY),
    };
    if (crop.width > 10 && crop.height > 10) {
      onCropComplete(crop.x, crop.y, crop.width, crop.height);
      setCropRect(null);
    }
  };

  return (
    <div
      data-crop-overlay
      className="absolute inset-0 cursor-crosshair"
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      onMouseLeave={handleMouseUp}
    >
      <div className="absolute top-2 left-1/2 -translate-x-1/2 flex gap-1 bg-black/70 rounded p-1 z-10">
        {ASPECTS.map((a) => (
          <button
            key={a.label}
            className={`px-2 py-1 text-xs rounded ${
              aspectPreset === a.label ? "bg-blue-500 text-white" : "text-white hover:bg-white/20"
            }`}
            onClick={(e) => { e.stopPropagation(); setAspectPreset(a.label); }}
          >
            {a.label}
          </button>
        ))}
      </div>

      {cropRect && (
        <div
          className="absolute border-2 border-green-500 bg-green-500/20 cursor-move"
          style={{ left: cropRect.x, top: cropRect.y, width: cropRect.width, height: cropRect.height }}
        >
          {(["nw", "ne", "sw", "se"] as const).map((h) => (
            <div
              key={h}
              className={`absolute w-3 h-3 bg-green-500 hover:bg-green-400 ${
                h === "nw" ? "-top-1 -left-1 cursor-nw-resize" :
                h === "ne" ? "-top-1 -right-1 cursor-ne-resize" :
                h === "sw" ? "-bottom-1 -left-1 cursor-sw-resize" :
                             "-bottom-1 -right-1 cursor-se-resize"
              }`}
              onMouseDown={(e) => handleResizeMouseDown(e, h)}
            />
          ))}
          <div className="absolute top-0 -left-2 w-2 h-full bg-green-500 cursor-w-resize hover:bg-green-400" onMouseDown={(e) => handleResizeMouseDown(e, "w")} />
          <div className="absolute top-0 -right-2 w-2 h-full bg-green-500 cursor-e-resize hover:bg-green-400" onMouseDown={(e) => handleResizeMouseDown(e, "e")} />
          <div className="absolute left-0 -top-2 w-full h-2 bg-green-500 cursor-n-resize hover:bg-green-400" onMouseDown={(e) => handleResizeMouseDown(e, "n")} />
          <div className="absolute left-0 -bottom-2 w-full h-2 bg-green-500 cursor-s-resize hover:bg-green-400" onMouseDown={(e) => handleResizeMouseDown(e, "s")} />
        </div>
      )}

      {cropRect && cropRect.width > 5 && cropRect.height > 5 && (
        <div className="absolute bottom-2 left-1/2 -translate-x-1/2 flex gap-2 z-10">
          <button
            className="px-3 py-1.5 bg-green-500 text-white rounded text-sm font-medium hover:bg-green-600"
            onMouseDown={(e) => { e.stopPropagation(); e.preventDefault(); handleAccept(); }}
          >
            Accept
          </button>
          <button
            className="px-3 py-1.5 bg-red-500 text-white rounded text-sm font-medium hover:bg-red-600"
            onMouseDown={(e) => { e.stopPropagation(); e.preventDefault(); onCropCancel(); setCropRect(null); }}
          >
            Cancel
          </button>
        </div>
      )}
    </div>
  );
}
```

### Step 2.2: Add naturalSize state to ImageViewer

In `src/components/edit/ImageViewer.tsx`, add `naturalSize` state so it can pass natural dimensions to overlays. Add after the existing state declarations (around line 72):

```tsx
// ADD this line
const [naturalSize, setNaturalSize] = useState<{ w: number; h: number }>({ w: 1, h: 1 });
```

In `handleImageLoad` (around line 165), add a line to set naturalSize. Insert after `setImageDisplayRect(...)`:

```tsx
// BEFORE (end of handleImageLoad, around line 193)
setImageDisplayRect({ x: offsetX, y: offsetY, width: displayedWidth, height: displayedHeight });
setImageLoaded(true);

// AFTER
setImageDisplayRect({ x: offsetX, y: offsetY, width: displayedWidth, height: displayedHeight });
setNaturalSize({ w: img.naturalWidth || 1, h: img.naturalHeight || 1 });
setImageLoaded(true);
```

Also update the ResizeObserver `update` function (around line 124) to update naturalSize when it computes:

```tsx
// BEFORE (end of update function inside ResizeObserver)
setImageDisplayRect({ x: ox, y: oy, width: dw, height: dh });

// AFTER
setImageDisplayRect({ x: ox, y: oy, width: dw, height: dh });
setNaturalSize({ w: img.naturalWidth || 1, h: img.naturalHeight || 1 });
```

### Step 2.3: Remove crop code from ImageViewer and render CropOverlay

In `src/components/edit/ImageViewer.tsx`:

**Remove these state declarations** (lines 51–67 approximately):
```tsx
// DELETE all of these:
const [cropRect, setCropRect] = useState<...>(null);
const [isDrawing, setIsDrawing] = useState(false);
const [dragStart, setDragStart] = useState<...>(null);
const [aspectPreset, setAspectPreset] = useState<string | null>(null);
const [resizing, setResizing] = useState<ResizeHandle>(null);
const [resizeStart, setResizeStart] = useState<...>(null);
const [moving, setMoving] = useState(false);
const [moveStart, setMoveStart] = useState<...>(null);
```

**Remove** the `type ResizeHandle = ...` declaration.

**Remove** the `const aspects = [...]` array.

**Remove** the functions: `handleMouseDown`, `handleResizeMouseDown`, `handleMouseMove`, `handleMouseUp`, `handleAccept`, `handleCancel`.

**Remove** the `useEffect` that resets zoom/pan on cropMode change (around line 114–119). Keep the one that resets on `mediaUrl` change.

**Add the import** at the top:
```tsx
import CropOverlay from "./CropOverlay";
```

**Replace the `{cropMode && ...}` JSX block** (the large absolute-positioned div with all the crop UI, approximately lines 594–691) with:

```tsx
{cropMode && imageDisplayRect && (
  <CropOverlay
    imageDisplayRect={imageDisplayRect}
    naturalWidth={naturalSize.w}
    naturalHeight={naturalSize.h}
    onCropComplete={onCropComplete!}
    onCropCancel={onCropCancel!}
  />
)}
```

**Remove `cropModeRef`** and its effect (lines 88–89) — no longer needed in ImageViewer since the crop overlay owns its own mouse events now.

**Update `handleContainerMouseDown`** — remove the `if (cropMode) return;` guard (CropOverlay has its own event div, so container events don't fire during crop):

```tsx
// BEFORE
const handleContainerMouseDown = (e: React.MouseEvent) => {
  if (cropMode) return;
  if (e.shiftKey) { ... }
  ...
};

// AFTER
const handleContainerMouseDown = (e: React.MouseEvent) => {
  if (e.shiftKey) { ... }
  ...
};
```

Wait — actually keep `if (cropMode) return;` to prevent panning while the crop overlay is active. The overlay has `pointer-events: auto` (the default) which means container events bubble through. Keep the guard to be safe.

### Step 2.4: Verify

In the browser:
- Enter crop mode (click the Crop button in the toolbar)
- Draw a crop rectangle
- Drag a resize handle
- Move the crop rectangle
- Click Accept — image should crop
- Click Cancel — crop rect should clear
- Zoom/pan should work normally outside crop mode

### Step 2.5: Commit

```bash
git add src/components/edit/CropOverlay.tsx src/components/edit/ImageViewer.tsx
git commit -m "refactor(edit): extract CropOverlay from ImageViewer"
```

---

## Task 3: Extract PaintCanvas

**Files:**
- Create: `src/components/edit/PaintCanvas.tsx`
- Modify: `src/components/edit/ImageViewer.tsx`
- Modify: `src/app/edit/page.tsx`

### Step 3.1: Create PaintCanvas.tsx

Create `src/components/edit/PaintCanvas.tsx`:

```tsx
"use client";

import { forwardRef, useEffect, useImperativeHandle, useRef } from "react";
import type { PaintTool } from "@/lib/types";

export interface PaintCanvasHandle {
  onMouseDown(e: React.MouseEvent): void;
  onMouseMove(e: React.MouseEvent): void;
  onMouseUp(): void;
  getBlob(): Promise<Blob>;
}

interface PaintCanvasProps {
  tool: PaintTool;
  size: number;
  color: string;
  imageDisplayRect: { x: number; y: number; width: number; height: number };
  naturalWidth: number;
  naturalHeight: number;
}

function toCanvasCoords(
  e: React.MouseEvent,
  canvas: HTMLCanvasElement
): { x: number; y: number } | null {
  const rect = canvas.getBoundingClientRect();
  if (rect.width === 0 || rect.height === 0) return null;
  return {
    x: (e.clientX - rect.left) * (canvas.width / rect.width),
    y: (e.clientY - rect.top) * (canvas.height / rect.height),
  };
}

function stamp(
  canvas: HTMLCanvasElement,
  x: number,
  y: number,
  tool: PaintTool,
  size: number,
  color: string
) {
  const ctx = canvas.getContext("2d");
  if (!ctx) return;
  const half = size / 2;
  if (tool === "eraser") {
    ctx.globalCompositeOperation = "destination-out";
    ctx.fillStyle = "rgba(0,0,0,1)";
  } else {
    ctx.globalCompositeOperation = "source-over";
    ctx.fillStyle = color;
  }
  if (tool === "quad") {
    ctx.fillRect(x - half, y - half, size, size);
  } else {
    ctx.beginPath();
    ctx.arc(x, y, half, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalCompositeOperation = "source-over";
}

const PaintCanvas = forwardRef<PaintCanvasHandle, PaintCanvasProps>(
  function PaintCanvas({ tool, size, color, imageDisplayRect, naturalWidth, naturalHeight }, ref) {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const isPaintingRef = useRef(false);

    useEffect(() => {
      const canvas = canvasRef.current;
      if (!canvas) return;
      canvas.width = naturalWidth;
      canvas.height = naturalHeight;
      canvas.getContext("2d")?.clearRect(0, 0, naturalWidth, naturalHeight);
    }, [naturalWidth, naturalHeight]);

    useImperativeHandle(ref, () => ({
      onMouseDown(e) {
        const canvas = canvasRef.current;
        if (!canvas) return;
        const coords = toCanvasCoords(e, canvas);
        if (coords) {
          isPaintingRef.current = true;
          stamp(canvas, coords.x, coords.y, tool, size, color);
        }
      },
      onMouseMove(e) {
        if (!isPaintingRef.current) return;
        const canvas = canvasRef.current;
        if (!canvas) return;
        const coords = toCanvasCoords(e, canvas);
        if (coords) stamp(canvas, coords.x, coords.y, tool, size, color);
      },
      onMouseUp() {
        isPaintingRef.current = false;
      },
      getBlob() {
        return new Promise<Blob>((resolve, reject) => {
          canvasRef.current?.toBlob(
            (b) => (b ? resolve(b) : reject(new Error("Canvas empty"))),
            "image/png"
          );
        });
      },
    }), [tool, size, color]);

    return (
      <canvas
        ref={canvasRef}
        style={{
          position: "absolute",
          left: imageDisplayRect.x,
          top: imageDisplayRect.y,
          width: imageDisplayRect.width,
          height: imageDisplayRect.height,
          cursor: "crosshair",
          imageRendering: "pixelated",
        }}
      />
    );
  }
);

export default PaintCanvas;
```

### Step 3.2: Update ImageViewer to use PaintCanvas

**Add import** to `ImageViewer.tsx`:
```tsx
import PaintCanvas, { type PaintCanvasHandle } from "./PaintCanvas";
```

**Update the props interface** — change `paintCanvasRef`:
```tsx
// BEFORE
paintCanvasRef?: React.RefObject<HTMLCanvasElement | null>;

// AFTER
paintCanvasRef?: React.RefObject<PaintCanvasHandle | null>;
```

**Remove** the `stamp` function, `toCanvasCoords` function, `handleCanvasMount` callback, and the canvas-initialization `useEffect` (the one that depends on `[mediaUrl, paintCanvasRef]`).

> **Do NOT remove `isPainting` state yet** — mask mode still uses it in `handleContainerMouseDown/Move`. It will be removed in Task 4.

**Update `handleContainerMouseDown`** — replace the paint block:
```tsx
// BEFORE
if (paintMode) {
  const coords = toCanvasCoords(e);
  if (coords && paintCanvasRef?.current) {
    setIsPainting(true);
    stamp(paintCanvasRef.current, coords.x, coords.y);
  }
}

// AFTER
if (paintMode) paintCanvasRef?.current?.onMouseDown(e);
```

**Update `handleContainerMouseMove`** — replace the paint block:
```tsx
// BEFORE
if (isPainting && paintMode && paintCanvasRef?.current) {
  const coords = toCanvasCoords(e);
  if (coords) stamp(paintCanvasRef.current, coords.x, coords.y);
}

// AFTER
if (paintMode) paintCanvasRef?.current?.onMouseMove(e);
```

**Update `handleContainerMouseUp`** — add paint onMouseUp:
```tsx
// BEFORE
const handleContainerMouseUp = () => {
  setIsPanning(false);
  setPanStart(null);
  setIsPainting(false);
};

// AFTER
const handleContainerMouseUp = () => {
  setIsPanning(false);
  setPanStart(null);
  paintCanvasRef?.current?.onMouseUp();
};
```

**Replace the paint canvas JSX** inside the pannable div:
```tsx
// BEFORE
{paintMode && imageLoaded && imageDisplayRect && (
  <canvas
    ref={handleCanvasMount}
    style={{
      position: "absolute",
      left: imageDisplayRect.x,
      top: imageDisplayRect.y,
      width: imageDisplayRect.width,
      height: imageDisplayRect.height,
      cursor: "crosshair",
      imageRendering: "pixelated",
    }}
  />
)}

// AFTER
{paintMode && imageLoaded && imageDisplayRect && (
  <PaintCanvas
    ref={paintCanvasRef ?? null}
    tool={paintTool ?? "pencil"}
    size={paintSize ?? 8}
    color={paintColor ?? "#ffffff"}
    imageDisplayRect={imageDisplayRect}
    naturalWidth={naturalSize.w}
    naturalHeight={naturalSize.h}
  />
)}
```

### Step 3.3: Update page.tsx to use PaintCanvasHandle

**Add import**:
```tsx
import PaintCanvas, { type PaintCanvasHandle } from "@/components/edit/PaintCanvas";
```

**Change the ref type**:
```tsx
// BEFORE
const paintCanvasRef = useRef<HTMLCanvasElement | null>(null);

// AFTER
const paintCanvasRef = useRef<PaintCanvasHandle | null>(null);
```

**Simplify `handlePaintSave`**:
```tsx
// BEFORE
const handlePaintSave = async () => {
  const canvas = paintCanvasRef.current;
  if (!canvas) return;
  setProcessing("paint");
  try {
    const blob = await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob(
        (b) => (b ? resolve(b) : reject(new Error("Canvas empty"))),
        "image/png"
      );
    });
    await api.paint(safeIndex, blob);
    setPaintMode(false);
    loadItem(safeIndex);
    queryClient.invalidateQueries({ queryKey: ["versions", safeIndex] });
  } catch (e) {
    toast.error(e instanceof Error ? e.message : "Paint failed");
  } finally {
    setProcessing(null);
  }
};

// AFTER
const handlePaintSave = async () => {
  if (!paintCanvasRef.current) return;
  setProcessing("paint");
  try {
    const blob = await paintCanvasRef.current.getBlob();
    await api.paint(safeIndex, blob);
    setPaintMode(false);
    loadItem(safeIndex);
    queryClient.invalidateQueries({ queryKey: ["versions", safeIndex] });
  } catch (e) {
    toast.error(e instanceof Error ? e.message : "Paint failed");
  } finally {
    setProcessing(null);
  }
};
```

### Step 3.4: Verify

In the browser:
- Enter paint mode (Brush button)
- Draw on the image
- Change tool (pencil/eraser/quad) and brush size
- Click Save — the painted strokes should be saved to the image
- Click Cancel — paint mode exits, no changes saved

### Step 3.5: Commit

```bash
git add src/components/edit/PaintCanvas.tsx src/components/edit/ImageViewer.tsx src/app/edit/page.tsx
git commit -m "refactor(edit): extract PaintCanvas from ImageViewer"
```

---

## Task 4: Extract MaskCanvas

**Files:**
- Create: `src/components/edit/MaskCanvas.tsx`
- Modify: `src/components/edit/ImageViewer.tsx`
- Modify: `src/app/edit/page.tsx`

### Step 4.1: Create MaskCanvas.tsx

Create `src/components/edit/MaskCanvas.tsx`:

```tsx
"use client";

import { forwardRef, useEffect, useImperativeHandle, useRef } from "react";
import type { PaintTool } from "@/lib/types";

export interface MaskCanvasHandle {
  onMouseDown(e: React.MouseEvent): void;
  onMouseMove(e: React.MouseEvent): void;
  onMouseUp(): void;
  getBlob(): Promise<Blob>;
}

interface MaskCanvasProps {
  tool: PaintTool;
  size: number;
  imageDisplayRect: { x: number; y: number; width: number; height: number };
  naturalWidth: number;
  naturalHeight: number;
  maskUrl?: string | null;
}

function toCanvasCoords(
  e: React.MouseEvent,
  canvas: HTMLCanvasElement
): { x: number; y: number } | null {
  const rect = canvas.getBoundingClientRect();
  if (rect.width === 0 || rect.height === 0) return null;
  return {
    x: (e.clientX - rect.left) * (canvas.width / rect.width),
    y: (e.clientY - rect.top) * (canvas.height / rect.height),
  };
}

function stampMask(
  canvas: HTMLCanvasElement,
  x: number,
  y: number,
  tool: PaintTool,
  size: number
) {
  const ctx = canvas.getContext("2d");
  if (!ctx) return;
  const half = size / 2;
  ctx.globalCompositeOperation = "source-over";
  ctx.fillStyle = tool === "eraser" ? "black" : "white";
  if (tool === "quad") {
    ctx.fillRect(x - half, y - half, size, size);
  } else {
    ctx.beginPath();
    ctx.arc(x, y, half, 0, Math.PI * 2);
    ctx.fill();
  }
}

const MaskCanvas = forwardRef<MaskCanvasHandle, MaskCanvasProps>(
  function MaskCanvas({ tool, size, imageDisplayRect, naturalWidth, naturalHeight, maskUrl }, ref) {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const isPaintingRef = useRef(false);

    useEffect(() => {
      const canvas = canvasRef.current;
      if (!canvas) return;
      canvas.width = naturalWidth;
      canvas.height = naturalHeight;
    }, [naturalWidth, naturalHeight]);

    useEffect(() => {
      if (!maskUrl || !canvasRef.current) return;
      const canvas = canvasRef.current;
      const img = new Image();
      img.crossOrigin = "anonymous";
      img.onload = () => {
        const ctx = canvas.getContext("2d");
        if (!ctx) return;
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      };
      img.src = maskUrl;
    }, [maskUrl]);

    useImperativeHandle(ref, () => ({
      onMouseDown(e) {
        const canvas = canvasRef.current;
        if (!canvas) return;
        const coords = toCanvasCoords(e, canvas);
        if (coords) {
          isPaintingRef.current = true;
          stampMask(canvas, coords.x, coords.y, tool, size);
        }
      },
      onMouseMove(e) {
        if (!isPaintingRef.current) return;
        const canvas = canvasRef.current;
        if (!canvas) return;
        const coords = toCanvasCoords(e, canvas);
        if (coords) stampMask(canvas, coords.x, coords.y, tool, size);
      },
      onMouseUp() {
        isPaintingRef.current = false;
      },
      getBlob() {
        return new Promise<Blob>((resolve, reject) => {
          canvasRef.current?.toBlob(
            (b) => (b ? resolve(b) : reject(new Error("Canvas empty"))),
            "image/png"
          );
        });
      },
    }), [tool, size]);

    return (
      <canvas
        ref={canvasRef}
        style={{
          position: "absolute",
          left: imageDisplayRect.x,
          top: imageDisplayRect.y,
          width: imageDisplayRect.width,
          height: imageDisplayRect.height,
          opacity: 0.5,
          mixBlendMode: "multiply",
          imageRendering: "pixelated",
        }}
      />
    );
  }
);

export default MaskCanvas;
```

### Step 4.2: Update ImageViewer to use MaskCanvas

**Add import**:
```tsx
import MaskCanvas, { type MaskCanvasHandle } from "./MaskCanvas";
```

**Update props interface** — change `maskCanvasRef` and remove now-unneeded mask effect inputs:
```tsx
// BEFORE
maskCanvasRef?: React.RefObject<HTMLCanvasElement | null>;

// AFTER
maskCanvasRef?: React.RefObject<MaskCanvasHandle | null>;
```

**Remove** the `stampMask` function, `handleMaskCanvasMount` callback, and the mask-loading `useEffect` (the one that depends on `[maskEditMode, maskUrl, maskCanvasRef]`).

**Update `handleContainerMouseDown`** — replace the mask block:
```tsx
// BEFORE
if (maskEditMode) {
  const coords = toCanvasCoords(e, maskCanvasRef?.current);
  if (coords && maskCanvasRef?.current) {
    setIsPainting(true);
    stampMask(maskCanvasRef.current, coords.x, coords.y);
  }
}

// AFTER
if (maskEditMode) maskCanvasRef?.current?.onMouseDown(e);
```

**Update `handleContainerMouseMove`** — replace the mask block:
```tsx
// BEFORE
if (isPainting && maskEditMode && maskCanvasRef?.current) {
  const coords = toCanvasCoords(e, maskCanvasRef.current);
  if (coords) stampMask(maskCanvasRef.current, coords.x, coords.y);
}

// AFTER
if (maskEditMode) maskCanvasRef?.current?.onMouseMove(e);
```

**Update `handleContainerMouseUp`** — add mask onMouseUp:
```tsx
const handleContainerMouseUp = () => {
  setIsPanning(false);
  setPanStart(null);
  paintCanvasRef?.current?.onMouseUp();
  maskCanvasRef?.current?.onMouseUp();
};
```

**Replace the mask canvas JSX** inside the pannable div:
```tsx
// BEFORE
{maskEditMode && imageLoaded && imageDisplayRect && (
  <canvas
    ref={handleMaskCanvasMount}
    style={{
      position: "absolute",
      left: imageDisplayRect.x,
      top: imageDisplayRect.y,
      width: imageDisplayRect.width,
      height: imageDisplayRect.height,
      opacity: 0.5,
      mixBlendMode: "multiply",
      imageRendering: "pixelated",
    }}
  />
)}

// AFTER
{maskEditMode && imageLoaded && imageDisplayRect && (
  <MaskCanvas
    ref={maskCanvasRef ?? null}
    tool={maskEditTool ?? "pencil"}
    size={maskEditSize ?? 8}
    imageDisplayRect={imageDisplayRect}
    naturalWidth={naturalSize.w}
    naturalHeight={naturalSize.h}
    maskUrl={maskUrl}
  />
)}
```

Now that both canvas modes use handles, **remove `isPainting` state and all `setIsPainting` calls** from `ImageViewer` — it's fully replaced by the internal `isPaintingRef` in each canvas component.

### Step 4.3: Update page.tsx to use MaskCanvasHandle

**Add import**:
```tsx
import MaskCanvas, { type MaskCanvasHandle } from "@/components/edit/MaskCanvas";
```

**Change the ref type**:
```tsx
// BEFORE
const maskCanvasRef = useRef<HTMLCanvasElement | null>(null);

// AFTER
const maskCanvasRef = useRef<MaskCanvasHandle | null>(null);
```

**Simplify `handleMaskSave`**:
```tsx
// BEFORE
const handleMaskSave = async () => {
  const canvas = maskCanvasRef.current;
  if (!canvas) return;
  setProcessing("mask_save");
  try {
    const blob = await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob(
        (b) => (b ? resolve(b) : reject(new Error("Canvas empty"))),
        "image/png"
      );
    });
    await api.saveMask(safeIndex, blob);
    setMaskEditMode(false);
    setMaskVersion((v) => v + 1);
    loadItem(safeIndex);
    queryClient.invalidateQueries({ queryKey: ["versions", safeIndex] });
  } catch (e) {
    toast.error(e instanceof Error ? e.message : "Mask save failed");
  } finally {
    setProcessing(null);
  }
};

// AFTER
const handleMaskSave = async () => {
  if (!maskCanvasRef.current) return;
  setProcessing("mask_save");
  try {
    const blob = await maskCanvasRef.current.getBlob();
    await api.saveMask(safeIndex, blob);
    setMaskEditMode(false);
    setMaskVersion((v) => v + 1);
    loadItem(safeIndex);
    queryClient.invalidateQueries({ queryKey: ["versions", safeIndex] });
  } catch (e) {
    toast.error(e instanceof Error ? e.message : "Mask save failed");
  } finally {
    setProcessing(null);
  }
};
```

### Step 4.4: Verify

In the browser (requires an image that has a mask):
- Generate a mask for an image
- Show the mask (Eye button)
- Click Edit Mask (pencil button)
- Draw on the mask with pencil tool (adds white)
- Draw with eraser tool (adds black / removes white)
- Click Save — the edited mask should persist
- Click Cancel — exits mask edit mode, no changes

Also verify that normal paint mode still works (not broken by this change).

### Step 4.5: Commit

```bash
git add src/components/edit/MaskCanvas.tsx src/components/edit/ImageViewer.tsx src/app/edit/page.tsx
git commit -m "refactor(edit): extract MaskCanvas from ImageViewer"
```

---

## Final Verification

After all four tasks:

```bash
npm run lint
npm run build
```

Expected: no errors. Then smoke-test the full edit page:
- Navigation (arrow keys, click nav bar)
- Caption editing and dirty-dialog (navigate away with unsaved changes)
- Crop mode end-to-end
- Paint mode end-to-end
- Mask generate → show → edit → save
- Upscale, Remove BG, White Balance buttons (should still trigger correctly)
- Rename and Delete
- Version history dialog

Check the final line counts match the spec:

```bash
wc -l src/components/edit/ImageViewer.tsx \
       src/components/edit/CropOverlay.tsx \
       src/components/edit/PaintCanvas.tsx \
       src/components/edit/MaskCanvas.tsx \
       src/components/edit/ToolbarButton.tsx \
       src/components/edit/ImageToolbar.tsx \
       src/app/edit/page.tsx
```

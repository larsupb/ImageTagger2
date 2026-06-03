# Paint Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Paint mode to the Edit page where users can draw on images with pencil/quad/eraser tools, then save the result as a new image version.

**Architecture:** Frontend draws on a transparent HTML5 Canvas overlay (sized to natural image dimensions) inside a zoomable/pannable image viewer. On save, the canvas PNG blob is POSTed to a new `/api/processing/paint` endpoint which composites it onto the original image with PIL after creating a version backup.

**Tech Stack:** Next.js 15 / React 19 / TypeScript (frontend), FastAPI / Pillow (backend), HTML5 Canvas 2D API, Tailwind CSS 4, shadcn/lucide-react

---

## File Map

**Create:**
- `frontend/src/components/edit/PaintToolbar.tsx` — horizontal bar with tool/size/color/save/cancel controls

**Modify:**
- `backend/app/services/processing_service.py` — add `paint_image()`
- `backend/app/routers/processing.py` — add `POST /api/processing/paint`
- `frontend/src/lib/api.ts` — add `paint()` method
- `frontend/src/components/edit/ImageViewer.tsx` — add zoom/pan + paint canvas overlay
- `frontend/src/components/edit/ImageToolbar.tsx` — add Paint toggle button, mutual exclusion with Crop
- `frontend/src/app/edit/page.tsx` — add paint state, handlers, wire PaintToolbar + ImageViewer props

---

## Task 1: Backend — paint_image service function

**Files:**
- Modify: `backend/app/services/processing_service.py`

- [ ] **Step 1: Add `paint_image()` to processing_service.py**

  Open `backend/app/services/processing_service.py`. Append this function at the end of the file:

  ```python
  def paint_image(session: Session, index: int, paint_png_bytes: bytes):
      import io
      from lib.media_cache import generate_thumbnail

      create_version_backup(session, index, "paint")

      ds = session.dataset
      item = ds.get_item(index)

      with Image.open(item.media_path) as img:
          original_mode = img.mode
          base = img.convert("RGBA")

      paint_layer = Image.open(io.BytesIO(paint_png_bytes)).convert("RGBA")
      composited = Image.alpha_composite(base, paint_layer)
      composited.convert(original_mode).save(item.media_path)

      item.thumbnail_path = generate_thumbnail(item.media_path)
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add backend/app/services/processing_service.py
  git commit -m "feat: add paint_image service function"
  ```

---

## Task 2: Backend — paint endpoint

**Files:**
- Modify: `backend/app/routers/processing.py`

- [ ] **Step 1: Add imports for multipart form handling**

  At the top of `backend/app/routers/processing.py`, the existing import line is:
  ```python
  from fastapi import APIRouter, Depends, HTTPException, Query
  ```
  Replace it with:
  ```python
  from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
  ```

- [ ] **Step 2: Add the paint endpoint**

  Append before the `@router.get("/versions/{index}")` endpoint:

  ```python
  @router.post("/paint")
  async def paint(
      index: int = Form(...),
      paint_png: UploadFile = File(...),
      session: Session = Depends(get_session),
  ):
      if session.dataset is None:
          raise HTTPException(400, "No dataset loaded")
      try:
          data = await paint_png.read()
          processing_service.paint_image(session, index, data)
          return {"status": "painted", "index": index}
      except Exception as e:
          logger.error("paint failed for index %s: %s", index, e, exc_info=True)
          raise HTTPException(500, str(e))
  ```

- [ ] **Step 3: Verify the backend starts without errors**

  ```bash
  cd backend && source .venv/bin/activate && python -c "from app.routers.processing import router; print('OK')"
  ```
  Expected: `OK`

- [ ] **Step 4: Commit**

  ```bash
  git add backend/app/routers/processing.py
  git commit -m "feat: add POST /api/processing/paint endpoint"
  ```

---

## Task 3: Frontend API — paint() method

**Files:**
- Modify: `frontend/src/lib/api.ts`

- [ ] **Step 1: Add `paint()` to the api object**

  In `frontend/src/lib/api.ts`, find the `crop:` entry (around line 230–245). Add the `paint` method directly after it:

  ```typescript
  paint: async (index: number, blob: Blob): Promise<void> => {
    const sid = await getSessionId();
    const form = new FormData();
    form.append("index", String(index));
    form.append("paint_png", blob, "paint.png");
    const res = await fetch("/api/processing/paint", {
      method: "POST",
      headers: { "X-Session-ID": sid },
      body: form,
    });
    if (!res.ok) {
      const error = await res.json().catch(() => ({ detail: res.statusText }));
      throw new Error(error.detail || "Paint failed");
    }
  },
  ```

  Note: do NOT use `apiFetch` here — `apiFetch` sets `Content-Type: application/json` which breaks multipart. Use raw `fetch` with only `X-Session-ID`.

- [ ] **Step 2: Type-check**

  ```bash
  cd frontend && npm run build 2>&1 | head -40
  ```
  Expected: no TypeScript errors related to `api.paint`.

- [ ] **Step 3: Commit**

  ```bash
  git add frontend/src/lib/api.ts
  git commit -m "feat: add api.paint() for multipart canvas upload"
  ```

---

## Task 4: ImageViewer — zoom & pan

**Files:**
- Modify: `frontend/src/components/edit/ImageViewer.tsx`

This task restructures `ImageViewer` to support mousewheel zoom (cursor-centered, 0.25x–8x) and Shift+drag pan. No paint logic yet.

- [ ] **Step 1: Add zoom/pan state and refs**

  In `frontend/src/components/edit/ImageViewer.tsx`, after the existing `const imgRef = useRef...` line, add:

  ```typescript
  const containerRef = useRef<HTMLDivElement>(null);
  const [zoom, setZoom] = useState(1);
  const [panOffset, setPanOffset] = useState({ x: 0, y: 0 });
  const [isPanning, setIsPanning] = useState(false);
  const [panStart, setPanStart] = useState<{ x: number; y: number } | null>(null);
  const zoomRef = useRef(1);
  const panOffsetRef = useRef({ x: 0, y: 0 });
  ```

  Then add two effects to keep the refs in sync (refs avoid stale closures in the non-passive wheel listener):

  ```typescript
  useEffect(() => { zoomRef.current = zoom; }, [zoom]);
  useEffect(() => { panOffsetRef.current = panOffset; }, [panOffset]);
  ```

- [ ] **Step 2: Reset zoom/pan when item changes or crop mode activates**

  Add these two effects after the sync effects above:

  ```typescript
  useEffect(() => {
    setZoom(1);
    setPanOffset({ x: 0, y: 0 });
  }, [mediaUrl]);

  useEffect(() => {
    if (cropMode) {
      setZoom(1);
      setPanOffset({ x: 0, y: 0 });
    }
  }, [cropMode]);
  ```

- [ ] **Step 3: Add the non-passive wheel listener**

  Add this effect (must be non-passive to call `preventDefault` and block page scroll):

  ```typescript
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    const handler = (e: WheelEvent) => {
      e.preventDefault();
      const rect = container.getBoundingClientRect();
      const cursorX = e.clientX - rect.left;
      const cursorY = e.clientY - rect.top;
      const currentZoom = zoomRef.current;
      const currentPan = panOffsetRef.current;
      const factor = e.deltaY < 0 ? 1.15 : 1 / 1.15;
      const newZoom = Math.min(8, Math.max(0.25, currentZoom * factor));
      setZoom(newZoom);
      setPanOffset({
        x: cursorX - (cursorX - currentPan.x) * (newZoom / currentZoom),
        y: cursorY - (cursorY - currentPan.y) * (newZoom / currentZoom),
      });
    };
    container.addEventListener("wheel", handler, { passive: false });
    return () => container.removeEventListener("wheel", handler);
  }, []);
  ```

- [ ] **Step 4: Add container-level mouse handlers for pan**

  Add these three handlers alongside the existing crop handlers:

  ```typescript
  const handleContainerMouseDown = (e: React.MouseEvent) => {
    if (cropMode) return;
    if (!e.shiftKey) return;
    setIsPanning(true);
    setPanStart({ x: e.clientX - panOffset.x, y: e.clientY - panOffset.y });
  };

  const handleContainerMouseMove = (e: React.MouseEvent) => {
    if (isPanning && panStart) {
      setPanOffset({ x: e.clientX - panStart.x, y: e.clientY - panStart.y });
    }
  };

  const handleContainerMouseUp = () => {
    setIsPanning(false);
    setPanStart(null);
  };
  ```

- [ ] **Step 5: Wrap image and mask in a transform div, attach containerRef and handlers to outer div**

  Replace the existing JSX return (the outer `<div>` and its direct children) with:

  ```tsx
  return (
    <div
      ref={containerRef}
      className="relative bg-surface rounded-lg overflow-hidden h-full w-full"
      style={{ cursor: isPanning ? "grabbing" : undefined }}
      onMouseDown={handleContainerMouseDown}
      onMouseMove={handleContainerMouseMove}
      onMouseUp={handleContainerMouseUp}
      onMouseLeave={handleContainerMouseUp}
    >
      <div
        className="absolute inset-0"
        style={{
          transform: `translate(${panOffset.x}px, ${panOffset.y}px) scale(${zoom})`,
          transformOrigin: "0 0",
        }}
      >
        <img
          ref={imgRef}
          src={mediaUrl}
          alt={filename}
          className="absolute inset-0 w-full h-full object-contain"
          onLoad={handleImageLoad}
        />
        {showMask && maskUrl && (
          <img
            src={maskUrl}
            alt="mask"
            className="absolute inset-0 w-full h-full object-contain opacity-50 mix-blend-multiply pointer-events-none"
          />
        )}
      </div>
      {cropMode && (
        <div
          className="absolute inset-0 cursor-crosshair"
          onMouseDown={handleMouseDown}
          onMouseMove={handleMouseMove}
          onMouseUp={handleMouseUp}
          onMouseLeave={handleMouseUp}
        >
          {/* ... all existing crop UI unchanged ... */}
        </div>
      )}
      {processing && (
        <div className="absolute inset-0 flex flex-col items-center justify-center bg-black/50 rounded-lg gap-2">
          <Loader2 className="size-10 text-white animate-spin" />
          <span className="text-white text-sm font-medium">
            {processing === "upscale" && "Upscaling..."}
            {processing === "rembg" && "Removing background..."}
            {processing === "mask" && "Generating mask..."}
            {processing === "crop" && "Cropping..."}
            {processing === "paint" && "Painting..."}
          </span>
        </div>
      )}
    </div>
  );
  ```

  Keep all existing crop JSX inside the `{cropMode && <div>}` block exactly as before — only the outer wrapper and image wrapper change.

- [ ] **Step 6: Verify crop still works**

  Start the dev server (`./run.sh`), open the Edit page, activate Crop, draw a crop rect, accept. Confirm it crops correctly.

- [ ] **Step 7: Verify zoom works**

  On the Edit page, scroll the mousewheel over an image. Confirm it zooms in/out centered on the cursor. Hold Shift and drag — confirm panning.

- [ ] **Step 8: Commit**

  ```bash
  git add frontend/src/components/edit/ImageViewer.tsx
  git commit -m "feat: add zoom and pan to ImageViewer"
  ```

---

## Task 5: ImageViewer — paint canvas overlay

**Files:**
- Modify: `frontend/src/components/edit/ImageViewer.tsx`

- [ ] **Step 1: Extend ImageViewerProps with paint props**

  Replace the existing `interface ImageViewerProps` with:

  ```typescript
  interface ImageViewerProps {
    mediaUrl: string;
    maskUrl?: string | null;
    filename: string;
    showMask?: boolean;
    processing?: string | null;
    cropMode?: boolean;
    onCropComplete?: (x: number, y: number, width: number, height: number) => void;
    onCropCancel?: () => void;
    paintMode?: boolean;
    paintTool?: "pencil" | "quad" | "eraser";
    paintSize?: number;
    paintColor?: string;
    paintCanvasRef?: React.RefObject<HTMLCanvasElement | null>;
  }
  ```

  Update the function signature to destructure the new props:

  ```typescript
  export default function ImageViewer({
    mediaUrl,
    maskUrl,
    filename,
    showMask,
    processing,
    cropMode,
    onCropComplete,
    onCropCancel,
    paintMode,
    paintTool,
    paintSize,
    paintColor,
    paintCanvasRef,
  }: ImageViewerProps) {
  ```

- [ ] **Step 2: Add paint drawing state**

  After the existing `const imgRef = useRef...` add:

  ```typescript
  const [isPainting, setIsPainting] = useState(false);
  ```

- [ ] **Step 3: Add the stamp helper function**

  Add this function inside the component (before the return), after all the state declarations:

  ```typescript
  function stamp(canvas: HTMLCanvasElement, x: number, y: number) {
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const tool = paintTool ?? "pencil";
    const size = paintSize ?? 8;
    const color = paintColor ?? "#ffffff";
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
  ```

- [ ] **Step 4: Add a canvas coordinate helper**

  Add this function right after `stamp`:

  ```typescript
  function toCanvasCoords(e: React.MouseEvent): { x: number; y: number } | null {
    const canvas = paintCanvasRef?.current;
    if (!canvas) return null;
    const rect = canvas.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) return null;
    return {
      x: (e.clientX - rect.left) * (canvas.width / rect.width),
      y: (e.clientY - rect.top) * (canvas.height / rect.height),
    };
  }
  ```

- [ ] **Step 5: Add a canvas mount callback to set natural dimensions**

  Add this callback after `toCanvasCoords`:

  ```typescript
  const handleCanvasMount = useCallback(
    (canvas: HTMLCanvasElement | null) => {
      if (paintCanvasRef) {
        (paintCanvasRef as React.MutableRefObject<HTMLCanvasElement | null>).current = canvas;
      }
      if (canvas && imgRef.current) {
        canvas.width = imgRef.current.naturalWidth || 1;
        canvas.height = imgRef.current.naturalHeight || 1;
      }
    },
    [paintCanvasRef]
  );
  ```

  Add `useCallback` to the existing imports at the top: `import { useState, useRef, useCallback } from "react";`

- [ ] **Step 6: Update container mouse handlers to handle paint**

  Replace the three `handleContainer*` functions from Task 4 with these updated versions that also handle painting:

  ```typescript
  const handleContainerMouseDown = (e: React.MouseEvent) => {
    if (cropMode) return;
    if (e.shiftKey) {
      setIsPanning(true);
      setPanStart({ x: e.clientX - panOffset.x, y: e.clientY - panOffset.y });
      return;
    }
    if (paintMode) {
      const coords = toCanvasCoords(e);
      if (coords && paintCanvasRef?.current) {
        setIsPainting(true);
        stamp(paintCanvasRef.current, coords.x, coords.y);
      }
    }
  };

  const handleContainerMouseMove = (e: React.MouseEvent) => {
    if (isPanning && panStart) {
      setPanOffset({ x: e.clientX - panStart.x, y: e.clientY - panStart.y });
      return;
    }
    if (isPainting && paintMode && paintCanvasRef?.current) {
      const coords = toCanvasCoords(e);
      if (coords) stamp(paintCanvasRef.current, coords.x, coords.y);
    }
  };

  const handleContainerMouseUp = () => {
    setIsPanning(false);
    setPanStart(null);
    setIsPainting(false);
  };
  ```

- [ ] **Step 7: Render the canvas inside the transform wrapper**

  Inside the transform wrapper div (after the mask `<img>`), add the canvas:

  ```tsx
  {paintMode && imageLoaded && (
    <canvas
      ref={handleCanvasMount}
      className="absolute inset-0 w-full h-full"
      style={{ cursor: "crosshair", imageRendering: "pixelated" }}
    />
  )}
  ```

  Also update the outer container's cursor style to handle paint mode:

  ```tsx
  style={{ cursor: isPanning ? "grabbing" : (paintMode ? "crosshair" : undefined) }}
  ```

- [ ] **Step 8: Commit**

  ```bash
  git add frontend/src/components/edit/ImageViewer.tsx
  git commit -m "feat: add paint canvas overlay to ImageViewer"
  ```

---

## Task 6: PaintToolbar component

**Files:**
- Create: `frontend/src/components/edit/PaintToolbar.tsx`

- [ ] **Step 1: Create the component**

  Create `frontend/src/components/edit/PaintToolbar.tsx`:

  ```tsx
  "use client";

  import { Button } from "@/components/ui/button";

  type PaintTool = "pencil" | "quad" | "eraser";

  interface PaintToolbarProps {
    tool: PaintTool;
    onToolChange: (t: PaintTool) => void;
    size: number;
    onSizeChange: (s: number) => void;
    color: string;
    onColorChange: (c: string) => void;
    onSave: () => void;
    onCancel: () => void;
    saving?: boolean;
  }

  const SIZES = [4, 8, 16, 32] as const;

  const COLORS: { hex: string; label: string }[] = [
    { hex: "#ffffff", label: "White" },
    { hex: "#e63946", label: "Red" },
    { hex: "#2a9d8f", label: "Teal" },
    { hex: "#e9c46a", label: "Yellow" },
    { hex: "#457b9d", label: "Blue" },
    { hex: "#000000", label: "Black" },
  ];

  export default function PaintToolbar({
    tool,
    onToolChange,
    size,
    onSizeChange,
    color,
    onColorChange,
    onSave,
    onCancel,
    saving,
  }: PaintToolbarProps) {
    return (
      <div className="flex flex-wrap items-center gap-3 px-1 py-1 bg-surface rounded-lg border border-border">
        <div className="flex items-center gap-1">
          <span className="text-xs text-text-muted mr-1">Tool</span>
          {(["pencil", "quad", "eraser"] as PaintTool[]).map((t) => (
            <button
              key={t}
              onClick={() => onToolChange(t)}
              className={`px-2 py-1 text-xs rounded capitalize transition-colors ${
                tool === t
                  ? "bg-primary text-primary-foreground"
                  : "bg-muted text-text-muted hover:bg-muted/80"
              }`}
            >
              {t}
            </button>
          ))}
        </div>

        <div className="w-px h-4 bg-border" />

        <div className="flex items-center gap-1">
          <span className="text-xs text-text-muted mr-1">Size</span>
          {SIZES.map((s) => (
            <button
              key={s}
              onClick={() => onSizeChange(s)}
              className={`px-2 py-1 text-xs rounded transition-colors ${
                size === s
                  ? "bg-primary text-primary-foreground"
                  : "bg-muted text-text-muted hover:bg-muted/80"
              }`}
            >
              {s}px
            </button>
          ))}
        </div>

        <div className="w-px h-4 bg-border" />

        <div className="flex items-center gap-1">
          <span className="text-xs text-text-muted mr-1">Color</span>
          {COLORS.map(({ hex, label }) => (
            <button
              key={hex}
              title={label}
              onClick={() => onColorChange(hex)}
              className="w-5 h-5 rounded-sm transition-transform hover:scale-110"
              style={{
                background: hex,
                border: color === hex ? "2px solid var(--primary)" : "1px solid var(--border)",
                opacity: tool === "eraser" ? 0.3 : 1,
              }}
            />
          ))}
        </div>

        <div className="flex-1" />

        <div className="flex items-center gap-2">
          <Button size="xs" onClick={onSave} disabled={saving}>
            {saving ? "Saving..." : "Save"}
          </Button>
          <Button size="xs" variant="secondary" onClick={onCancel} disabled={saving}>
            Cancel
          </Button>
        </div>
      </div>
    );
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add frontend/src/components/edit/PaintToolbar.tsx
  git commit -m "feat: add PaintToolbar component"
  ```

---

## Task 7: ImageToolbar — Paint toggle button

**Files:**
- Modify: `frontend/src/components/edit/ImageToolbar.tsx`

- [ ] **Step 1: Add paintMode/setPaintMode to ImageToolbarProps**

  Replace the existing `interface ImageToolbarProps` with:

  ```typescript
  interface ImageToolbarProps {
    index: number;
    onRefresh: () => void;
    onDeleted: (deletedIndex: number) => void;
    processing: string | null;
    setProcessing: (v: string | null) => void;
    onMaskGenerated: () => void;
    showMask: boolean;
    setShowMask: (v: boolean) => void;
    cropMode?: boolean;
    setCropMode?: (v: boolean) => void;
    paintMode?: boolean;
    setPaintMode?: (v: boolean) => void;
  }
  ```

  Update the function signature to destructure `paintMode` and `setPaintMode`:

  ```typescript
  export default function ImageToolbar({
    index, onRefresh, onDeleted, processing, setProcessing,
    onMaskGenerated, showMask, setShowMask,
    cropMode, setCropMode,
    paintMode, setPaintMode,
  }: ImageToolbarProps) {
  ```

- [ ] **Step 2: Update handleCrop to exit paint mode**

  Replace the existing `handleCrop` function:

  ```typescript
  const handleCrop = () => {
    if (setPaintMode && paintMode) setPaintMode(false);
    if (setCropMode) setCropMode(!cropMode);
  };
  ```

- [ ] **Step 3: Add handlePaint function**

  Add after `handleCrop`:

  ```typescript
  const handlePaint = () => {
    if (setCropMode && cropMode) setCropMode(false);
    if (setPaintMode) setPaintMode(!paintMode);
  };
  ```

- [ ] **Step 4: Add Brush to lucide-react imports**

  In the existing lucide-react import line (line 5), add `Brush`:

  ```typescript
  import { ArrowUpCircle, Brush, Eraser, VenetianMask, History, Pencil, Trash2, Eye, EyeOff, Crop, Sun, RotateCcw } from "lucide-react";
  ```

- [ ] **Step 5: Add the Paint toggle button to the toolbar JSX**

  Add this Tooltip block immediately after the existing Crop button's closing `</Tooltip>` tag:

  ```tsx
  <Tooltip>
    <TooltipTrigger
      className="inline-flex items-center justify-center rounded-lg border border-transparent bg-clip-padding text-sm font-medium whitespace-nowrap transition-all outline-none select-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 active:not-aria-[haspopup]:translate-y-px disabled:pointer-events-none disabled:opacity-50 h-7 gap-1.5 px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2 shrink-0 bg-background hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground dark:border-input dark:bg-input/30 dark:hover:bg-input/50 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4"
      onClick={handlePaint}
      disabled={!!processing || currentItem?.is_video}
    >
      <Brush className={`size-4 ${paintMode ? "text-pink-400" : "text-pink-500"}`} />
    </TooltipTrigger>
    <TooltipContent>Paint</TooltipContent>
  </Tooltip>
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add frontend/src/components/edit/ImageToolbar.tsx
  git commit -m "feat: add Paint toggle button to ImageToolbar"
  ```

---

## Task 8: Edit page — paint state and wiring

**Files:**
- Modify: `frontend/src/app/edit/page.tsx`

- [ ] **Step 1: Add paint state**

  In `frontend/src/app/edit/page.tsx`, after the existing `const [cropMode, setCropMode] = useState(false);` line, add:

  ```typescript
  const [paintMode, setPaintMode] = useState(false);
  const [paintTool, setPaintTool] = useState<"pencil" | "quad" | "eraser">("pencil");
  const [paintSize, setPaintSize] = useState<number>(8);
  const [paintColor, setPaintColor] = useState("#ffffff");
  const paintCanvasRef = useRef<HTMLCanvasElement | null>(null);
  ```

- [ ] **Step 2: Add paint save and cancel handlers**

  Add after `handleCropComplete`:

  ```typescript
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

  const handlePaintCancel = () => {
    setPaintMode(false);
  };
  ```

  Note: `safeIndex` is defined later in the render function. Move `handlePaintSave` and `handlePaintCancel` into the render function body (after `const safeIndex = currentIndex ?? 0;`), or use `currentIndex ?? 0` directly:

  Actually, to keep them with the other handlers (which already reference `safeIndex` only by reference), define them just before the return statement after `const safeIndex = currentIndex ?? 0;`.

  Place both handlers after `const safeIndex = currentIndex ?? 0;` in the JSX section:

  ```typescript
  const safeIndex = currentIndex ?? 0;

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

  const handlePaintCancel = () => setPaintMode(false);
  ```

- [ ] **Step 3: Import PaintToolbar**

  Add to the existing import block at the top of `page.tsx`:

  ```typescript
  import PaintToolbar from "@/components/edit/PaintToolbar";
  ```

- [ ] **Step 4: Pass paint props to ImageToolbar**

  In the `<ImageToolbar>` JSX, add the new props:

  ```tsx
  <ImageToolbar
    index={safeIndex}
    onRefresh={() => loadItem(safeIndex)}
    onDeleted={handleDeleted}
    processing={processing}
    setProcessing={setProcessing}
    onMaskGenerated={() => setShowMask(true)}
    showMask={showMask}
    setShowMask={setShowMask}
    cropMode={cropMode}
    setCropMode={setCropMode}
    paintMode={paintMode}
    setPaintMode={setPaintMode}
  />
  ```

- [ ] **Step 5: Pass paint props to ImageViewer**

  In the `<ImageViewer>` JSX, add the new props:

  ```tsx
  <ImageViewer
    mediaUrl={`${getMediaUrl(currentItem.index)}&v=${encodeURIComponent(`${currentItem.filename}-${currentItem.file_size ?? ""}`)}`}
    maskUrl={currentItem.has_mask ? getMaskUrl(currentItem.index) : null}
    filename={currentItem.filename}
    showMask={showMask}
    processing={processing}
    cropMode={cropMode}
    onCropComplete={handleCropComplete}
    onCropCancel={() => setCropMode(false)}
    paintMode={paintMode}
    paintTool={paintTool}
    paintSize={paintSize}
    paintColor={paintColor}
    paintCanvasRef={paintCanvasRef}
  />
  ```

- [ ] **Step 6: Render PaintToolbar below ImageViewer**

  After the closing `</div>` of the `<div className="flex-1 min-h-0">` block (the image viewer wrapper), add:

  ```tsx
  {paintMode && (
    <PaintToolbar
      tool={paintTool}
      onToolChange={setPaintTool}
      size={paintSize}
      onSizeChange={setPaintSize}
      color={paintColor}
      onColorChange={setPaintColor}
      onSave={handlePaintSave}
      onCancel={handlePaintCancel}
      saving={processing === "paint"}
    />
  )}
  ```

- [ ] **Step 7: Build check**

  ```bash
  cd frontend && npm run build 2>&1 | tail -20
  ```
  Expected: successful build with no TypeScript errors.

- [ ] **Step 8: End-to-end smoke test**

  Start servers: `./run.sh`

  1. Open a project and navigate to the Edit page
  2. Scroll the mousewheel over the image — confirm zoom in/out centered on cursor
  3. Hold Shift and drag — confirm image pans
  4. Click the Paint (brush) button — confirm paint toolbar appears below the image
  5. Select "Quad" tool, size 16px, red color — draw on the image
  6. Switch to Eraser — erase part of the drawing
  7. Click Save — confirm the spinner shows "Painting...", then the image refreshes with the paint composited in
  8. Open Version History — confirm a new "paint" version entry exists
  9. Click Paint again, draw something, click Cancel — confirm no change to image
  10. Click Crop — confirm paint mode exits and crop mode activates with zoom reset to 1

- [ ] **Step 9: Commit**

  ```bash
  git add frontend/src/app/edit/page.tsx
  git commit -m "feat: wire paint mode into Edit page"
  ```

---

## Summary

| Task | Files | What it does |
|------|-------|-------------|
| 1 | processing_service.py | PIL compositing function |
| 2 | processing.py | POST /api/processing/paint endpoint |
| 3 | api.ts | Frontend paint() upload method |
| 4 | ImageViewer.tsx | Zoom & pan (mousewheel + Shift+drag) |
| 5 | ImageViewer.tsx | Paint canvas overlay + drawing logic |
| 6 | PaintToolbar.tsx | Tool/size/color/save/cancel bar |
| 7 | ImageToolbar.tsx | Paint toggle button |
| 8 | page.tsx | State, handlers, wiring |

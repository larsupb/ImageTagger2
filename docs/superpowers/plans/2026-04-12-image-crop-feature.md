# Image Crop Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add image cropping functionality to the edit page with aspect ratio presets and version backup

**Architecture:** User clicks crop button in toolbar → draws/resizes rectangle on image → Accept sends coordinates to backend → backend creates version backup and crops image

**Tech Stack:** Frontend: React, TypeScript, lucide-react icons | Backend: FastAPI, PIL for image manipulation

---

## File Structure

### Backend
- `backend/app/routers/processing.py` - Add crop endpoint
- `backend/app/services/processing_service.py` - Add crop_image function
- `backend/app/models/schemas.py` - Add CropRequest schema

### Frontend
- `frontend/src/components/edit/ImageToolbar.tsx` - Add crop button
- `frontend/src/components/edit/ImageViewer.tsx` - Add crop overlay with drawing/resize
- `frontend/src/lib/api.ts` - Add crop API call

---

## Task 1: Backend - Add CropRequest Schema

**Files:**
- Modify: `backend/app/models/schemas.py`

- [ ] **Step 1: Read existing schemas file to find the right location**

```bash
# Read the end of the file to find where to add new schema
read backend/app/models/schemas.py offset=1 limit=50
```

- [ ] **Step 2: Add CropRequest schema**

Add after UpscaleRequest or MaskGenerateRequest:

```python
class CropRequest(BaseModel):
    index: int
    x: int
    y: int
    width: int
    height: int
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/models/schemas.py
git commit -m "feat: add CropRequest schema"
```

---

## Task 2: Backend - Add crop_image Service Function

**Files:**
- Modify: `backend/app/services/processing_service.py:100` (append at end)

- [ ] **Step 1: Read processing_service.py to understand patterns**

```bash
read backend/app/services/processing_service.py offset=95
```

- [ ] **Step 2: Add crop_image function at end of file**

```python
def crop_image(session: Session, index: int, x: int, y: int, width: int, height: int):
    from lib.media_cache import generate_thumbnail
    from app.db.repository import ImageRepository

    create_version_backup(session, index, "crop")

    ds = session.dataset
    item = ds.get_item(index)

    with Image.open(item.media_path) as img:
        cropped = img.crop((x, y, x + width, y + height))
        cropped.save(item.media_path)

    item.thumbnail_path = generate_thumbnail(item.media_path)

    rel_path = os.path.relpath(item.media_path, ds.base_dir)
    if session.db:
        ImageRepository.update_metadata(
            session.db,
            ImageRepository.get_by_filename(session.db, rel_path)["id"],
            width=width,
            height=height,
        )
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/services/processing_service.py
git commit -m "feat: add crop_image service function"
```

---

## Task 3: Backend - Add Crop Endpoint

**Files:**
- Modify: `backend/app/routers/processing.py`

- [ ] **Step 1: Read processing.py to find import and add endpoint**

```bash
read backend/app/routers/processing.py offset=1 limit=20
```

- [ ] **Step 2: Add import for CropRequest and add endpoint**

Add to imports:
```python
from app.models.schemas import (
    UpscaleRequest,
    MaskGenerateRequest,
    ImageVersionEntry,
    ComfyUIUpscaleRequest,
    CropRequest,  # Add this
)
```

Add endpoint after generate_mask:
```python
@router.post("/crop")
def crop(req: CropRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    try:
        processing_service.crop_image(
            session, req.index, req.x, req.y, req.width, req.height
        )
        return {"status": "cropped", "index": req.index}
    except Exception as e:
        logger.error("crop failed for index %s: %s", req.index, e, exc_info=True)
        raise HTTPException(500, str(e))
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/routers/processing.py
git commit -m "feat: add POST /api/processing/crop endpoint"
```

---

## Task 4: Frontend - Add Crop API Function

**Files:**
- Modify: `frontend/src/lib/api.ts`

- [ ] **Step 1: Read api.ts to find where to add**

```bash
read frontend/src/lib/api.ts offset=240 limit=30
```

- [ ] **Step 2: Add crop function after existing processing functions**

```typescript
crop: async (index: number, x: number, y: number, width: number, height: number) => {
  return apiFetch(`/api/processing/crop`, {
    method: "POST",
    body: JSON.stringify({ index, x, y, width, height }),
  });
},
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/lib/api.ts
git commit -m "feat: add crop API function"
```

---

## Task 5: Frontend - Add Crop Button to Toolbar

**Files:**
- Modify: `frontend/src/components/edit/ImageToolbar.tsx`

- [ ] **Step 1: Read ImageToolbar.tsx imports and state**

```bash
read frontend/src/components/edit/ImageToolbar.tsx offset=1 limit=40
```

- [ ] **Step 2: Add Crop import from lucide-react**

Add to imports:
```typescript
import { ArrowUpCircle, Eraser, VenetianMask, History, Pencil, Trash2, Eye, EyeOff, Crop } from "lucide-react";
```

- [ ] **Step 3: Add cropMode state and handlers**

Add to ImageToolbarProps:
```typescript
cropMode?: boolean;
setCropMode?: (v: boolean) => void;
```

Add after showMask state (around line 35):
```typescript
const handleCrop = () => {
  if (setCropMode) setCropMode(!cropMode);
};
```

Add disable check for videos and processing:
```typescript
disabled={!!processing || currentItem?.is_video}
```

- [ ] **Step 4: Add crop button in toolbar**

Add after History button (around line 159):
```typescript
<Tooltip>
  <TooltipTrigger
    className="..."
    onClick={handleCrop}
    disabled={!!processing || currentItem?.is_video}
  >
    <Crop className="size-4 text-green-500" />
  </TooltipTrigger>
  <TooltipContent>Crop</TooltipContent>
</Tooltip>
```

Use the same className pattern as other buttons in the file.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/edit/ImageToolbar.tsx
git commit -m "feat: add crop button to ImageToolbar"
```

---

## Task 6: Frontend - Add Crop Overlay to ImageViewer

**Files:**
- Modify: `frontend/src/components/edit/ImageViewer.tsx`

- [ ] **Step 1: Read ImageViewer.tsx**

```bash
read frontend/src/components/edit/ImageViewer.tsx
```

- [ ] **Step 2: Update props to accept cropMode and handlers**

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
}
```

- [ ] **Step 3: Add crop overlay implementation**

This is the complex part. Add state and handlers:

```typescript
const [cropRect, setCropRect] = useState<{ x: number; y: number; width: number; height: number } | null>(null);
const [isDrawing, setIsDrawing] = useState(false);
const [dragStart, setDragStart] = useState<{ x: number; y: number } | null>(null);
const [aspectPreset, setAspectPreset] = useState<string | null>(null);
const imgRef = useRef<HTMLImageElement>(null);

const aspects = [
  { label: "1:1", ratio: 1 },
  { label: "3:2", ratio: 3/2 },
  { label: "2:3", ratio: 2/3 },
  { label: "5:4", ratio: 5/4 },
  { label: "4:5", ratio: 4/5 },
  { label: "Free", ratio: null },
];

const handleMouseDown = (e: React.MouseEvent) => {
  if (!cropMode || !imgRef.current) return;
  const rect = imgRef.current.getBoundingClientRect();
  const x = e.clientX - rect.left;
  const y = e.clientY - rect.top;
  setDragStart({ x, y });
  setIsDrawing(true);
  setCropRect(null);
};

const handleMouseMove = (e: React.MouseEvent) => {
  if (!isDrawing || !dragStart || !imgRef.current) return;
  const rect = imgRef.current.getBoundingClientRect();
  const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width));
  const y = Math.max(0, Math.min(e.clientY - rect.top, rect.height));
  
  let width = x - dragStart.x;
  let height = y - dragStart.y;
  
  if (aspectPreset) {
    const preset = aspects.find(a => a.label === aspectPreset);
    if (preset?.ratio) {
      if (Math.abs(width) > Math.abs(height)) {
        height = width / preset.ratio;
      } else {
        width = height * preset.ratio;
      }
    }
  }
  
  if (width < 0) {
    setCropRect({ x: x, y: dragStart.y, width: -width, height: height });
  } else if (height < 0) {
    setCropRect({ x: dragStart.x, y: y, width: width, height: -height });
  } else {
    setCropRect({ x: dragStart.x, y: dragStart.y, width, height });
  }
};

const handleMouseUp = () => {
  setIsDrawing(false);
  setDragStart(null);
};

const handleAccept = async () => {
  if (!cropRect || !imgRef.current) return;
  const rect = imgRef.current.getBoundingClientRect();
  const naturalWidth = imgRef.current.naturalWidth;
  const naturalHeight = imgRef.current.naturalHeight;
  
  const scaleX = naturalWidth / rect.width;
  const scaleY = naturalHeight / rect.height;
  
  const crop = {
    x: Math.round(cropRect.x * scaleX),
    y: Math.round(cropRect.y * scaleY),
    width: Math.round(cropRect.width * scaleX),
    height: Math.round(cropRect.height * scaleY),
  };
  
  if (crop.width > 10 && crop.height > 10) {
    await onCropComplete?.(crop.x, crop.y, crop.width, crop.height);
    setCropRect(null);
  }
};

const handleCancel = () => {
  setCropRect(null);
  onCropCancel?.();
};
```

- [ ] **Step 4: Add crop UI overlay**

Add after the mask image (before processing div):
```tsx
{cropMode && (
  <div
    className="absolute inset-0 cursor-crosshair"
    onMouseDown={handleMouseDown}
    onMouseMove={handleMouseMove}
    onMouseUp={handleMouseUp}
    onMouseLeave={handleMouseUp}
  >
    {/* Aspect preset buttons */}
    <div className="absolute top-2 left-1/2 -translate-x-1/2 flex gap-1 bg-black/70 rounded p-1">
      {aspects.map(a => (
        <button
          key={a.label}
          className={`px-2 py-1 text-xs rounded ${aspectPreset === a.label ? 'bg-blue-500 text-white' : 'text-white hover:bg-white/20'}`}
          onClick={(e) => { e.stopPropagation(); setAspectPreset(a.label); }}
        >
          {a.label}
        </button>
      ))}
    </div>
    
    {/* Crop rectangle */}
    {cropRect && (
      <div
        className="absolute border-2 border-green-500 bg-green-500/20"
        style={{
          left: cropRect.x,
          top: cropRect.y,
          width: cropRect.width,
          height: cropRect.height,
        }}
      >
        {/* Resize handles */}
        <div className="absolute -top-1 -left-1 w-3 h-3 bg-green-500 cursor-nw-resize" />
        <div className="absolute -top-1 -right-1 w-3 h-3 bg-green-500 cursor-ne-resize" />
        <div className="absolute -bottom-1 -left-1 w-3 h-3 bg-green-500 cursor-sw-resize" />
        <div className="absolute -bottom-1 -right-1 w-3 h-3 bg-green-500 cursor-se-resize" />
        <div className="absolute top-0 -left-2 w-2 h-full bg-green-500 cursor-w-resize" />
        <div className="absolute top-0 -right-2 w-2 h-full bg-green-500 cursor-e-resize" />
        <div className="absolute left-0 -top-2 w-full h-2 bg-green-500 cursor-n-resize" />
        <div className="absolute left-0 -bottom-2 w-full h-2 bg-green-500 cursor-s-resize" />
      </div>
    )}
    
    {/* Accept/Cancel buttons */}
    {cropRect && cropRect.width > 5 && cropRect.height > 5 && (
      <div className="absolute bottom-2 left-1/2 -translate-x-1/2 flex gap-2">
        <button
          className="px-3 py-1.5 bg-green-500 text-white rounded text-sm font-medium hover:bg-green-600"
          onClick={(e) => { e.stopPropagation(); handleAccept(); }}
        >
          Accept
        </button>
        <button
          className="px-3 py-1.5 bg-red-500 text-white rounded text-sm font-medium hover:bg-red-600"
          onClick={(e) => { e.stopPropagation(); handleCancel(); }}
        >
          Cancel
        </button>
      </div>
    )}
  </div>
)}
```

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/edit/ImageViewer.tsx
git commit -m "feat: add crop overlay to ImageViewer"
```

---

## Task 7: Frontend - Connect Crop Between Toolbar and Viewer

**Files:**
- Modify: `frontend/src/app/edit/page.tsx`

- [ ] **Step 1: Read edit page**

```bash
read frontend/src/app/edit/page.tsx offset=130 limit=30
```

- [ ] **Step 2: Add crop state**

Add after showMask state (line 35):
```typescript
const [cropMode, setCropMode] = useState(false);
```

- [ ] **Step 3: Add crop handlers**

Add before the return:
```typescript
const handleCropComplete = async (x: number, y: number, width: number, number) => {
  setProcessing("crop");
  try {
    await api.crop(safeIndex, x, y, width, height);
    setCropMode(false);
    onRefresh();
  } catch (e) {
    toast.error(e instanceof Error ? e.message : "Crop failed");
  } finally {
    setProcessing(null);
  }
};
```

- [ ] **Step 4: Pass props to ImageToolbar**

Update ImageToolbar call (line 137):
```tsx
<ImageToolbar 
  index={safeIndex} 
  onRefresh={() => loadItem(safeIndex)} 
  processing={processing} 
  setProcessing={setProcessing} 
  onMaskGenerated={() => setShowMask(true)} 
  showMask={showMask} 
  setShowMask={setShowMask}
  cropMode={cropMode}
  setCropMode={setCropMode}
/>
```

- [ ] **Step 5: Pass props to ImageViewer**

Update ImageViewer call (line 143):
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
/>
```

- [ ] **Step 6: Commit**

```bash
git add frontend/src/app/edit/page.tsx
git commit -m "feat: connect crop functionality between toolbar and viewer"
```

---

## Task 8: Test and Verify

**Files:**
- Test: Manual browser testing

- [ ] **Step 1: Start backend server**

```bash
cd backend && uvicorn app.main:app --reload --port 8000
```

- [ ] **Step 2: Start frontend server**

```bash
cd frontend && npm run dev
```

- [ ] **Step 3: Test workflow**

1. Open a project and navigate to an image
2. Click the crop button (green scissors icon)
3. Select an aspect ratio preset
4. Draw a rectangle on the image
5. Verify the rectangle can be resized by hovering edges
6. Click Accept - image should crop
7. Verify version is created in Version History dialog

- [ ] **Step 4: Commit final**

```bash
git add -A
git commit -m "feat: add image crop feature with aspect ratio presets and version backup"
```
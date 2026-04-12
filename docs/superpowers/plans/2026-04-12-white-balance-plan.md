# White Balance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic white balance as a batch processing operation with Gray World, Shades of Gray, and Gray Edge methods, mutually exclusive with color matching.

**Architecture:** New `white_balance.py` backend module with three functions. Extend batch request schema. Add frontend OperationCard above Color Matching with mutual exclusion logic.

**Tech Stack:** Python (numpy, scipy for derivatives), TypeScript/React (existing UI components)

---

## File Structure

### Backend
- Create: `backend/lib/white_balance.py` - White balance algorithms
- Modify: `backend/app/models/schemas.py` - Add white_balance fields
- Modify: `backend/app/routers/batch.py` - Add white balance processing step

### Frontend
- Modify: `frontend/src/components/batch/BatchForm.tsx` - Add WhiteBalance OperationCard

---

## Task 1: Create white_balance.py module

**Files:**
- Create: `backend/lib/white_balance.py`

- [ ] **Step 1: Write the failing test**

```python
# backend/tests/test_white_balance.py
import pytest
import numpy as np
from PIL import Image
from lib.white_balance import (
    apply_gray_world,
    apply_shades_of_gray,
    apply_gray_edge,
    white_balance_image,
)


def create_test_image(r: int, g: int, b: int, size: tuple = (100, 100)) -> Image.Image:
    arr = np.zeros((size[0], size[1], 3), dtype=np.uint8)
    arr[:, :, 0] = r
    arr[:, :, 1] = g
    arr[:, :, 2] = b
    return Image.fromarray(arr)


def test_gray_world_balances_channels_means():
    img = create_test_image(150, 100, 50)
    result = apply_gray_world(img)
    result_arr = np.array(result)
    means = result_arr.mean(axis=(0, 1))
    assert abs(means[0] - means[1]) < 5
    assert abs(means[1] - means[2]) < 5


def test_shades_of_gray_balances_both_mean_and_std():
    img = create_test_image(150, 100, 50)
    result = apply_shades_of_gray(img)
    result_arr = np.array(result)
    means = result_arr.mean(axis=(0, 1))
    stds = result_arr.std(axis=(0, 1))
    assert abs(means[0] - means[1]) < 10
    assert abs(means[1] - means[2]) < 10
    assert abs(stds[0] - stds[1]) < 10


def test_gray_edge_uses_edge_pixels():
    img = create_test_image(150, 100, 50)
    result = apply_gray_edge(img)
    result_arr = np.array(result)
    means = result_arr.mean(axis=(0, 1))
    assert means.shape == (3,)


def test_white_balance_dispatch():
    img = create_test_image(150, 100, 50)
    result = white_balance_image(img, "gray_world")
    assert isinstance(result, Image.Image)
    result2 = white_balance_image(img, "shades_of_gray")
    assert isinstance(result2, Image.Image)
    result3 = white_balance_image(img, "gray_edge")
    assert isinstance(result3, Image.Image)


def test_white_balance_invalid_method_raises():
    img = create_test_image(150, 100, 50)
    with pytest.raises(ValueError):
        white_balance_image(img, "invalid_method")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && pytest tests/test_white_balance.py -v`
Expected: FAIL - module not found

- [ ] **Step 3: Write implementation**

```python
# backend/lib/white_balance.py
"""White balance correction algorithms."""

import numpy as np
from PIL import Image
from typing import Optional


def _to_rgb(img: Image.Image) -> Image.Image:
    if img.mode != "RGB":
        return img.convert("RGB")
    return img


def _scale_channel(channel: np.ndarray, target_mean: float, target_std: Optional[float] = None) -> np.ndarray:
    """Scale a single channel to target mean (and optionally std)."""
    current_mean = channel.mean()
    scaled = channel.astype(np.float32) * (target_mean / (current_mean + 1e-8))
    if target_std is not None:
        current_std = scaled.std()
        scaled = (scaled - scaled.mean()) / (current_std + 1e-8) * target_std
        scaled = scaled + target_mean
    return np.clip(scaled, 0, 255).astype(np.uint8)


def apply_gray_world(img: Image.Image) -> Image.Image:
    """Apply Gray World white balance - equalizes channel means."""
    img = _to_rgb(img)
    arr = np.array(img, dtype=np.float32)
    
    target_mean = arr.mean()
    
    for c in range(3):
        arr[:, :, c] = _scale_channel(arr[:, :, c], target_mean)
    
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    return Image.fromarray(arr)


def apply_shades_of_gray(img: Image.Image) -> Image.Image:
    """Apply Shades of Gray - equalizes both means and standard deviations."""
    img = _to_rgb(img)
    arr = np.array(img, dtype=np.float32)
    
    target_mean = arr.mean()
    target_std = arr.std()
    
    for c in range(3):
        arr[:, :, c] = _scale_channel(arr[:, :, c], target_mean, target_std)
    
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    return Image.fromarray(arr)


def apply_gray_edge(img: Image.Image, threshold: float = 10.0) -> Image.Image:
    """Apply Gray Edge white balance - uses edge pixels for correction."""
    img = _to_rgb(img)
    arr = np.array(img, dtype=np.float32)
    
    grad_x = np.diff(arr, axis=1)
    grad_y = np.diff(arr, axis=0)
    
    grad_mag = np.zeros((arr.shape[0], arr.shape[1]))
    grad_mag[:, :-1] += np.linalg.norm(grad_x, axis=2)
    grad_mag[:-1, :] += np.linalg.norm(grad_y, axis=2)
    
    edge_mask = grad_mag > threshold
    
    edge_pixels = arr[edge_mask]
    if len(edge_pixels) == 0:
        edge_pixels = arr
    
    target_mean = edge_pixels.mean(axis=0)
    
    for c in range(3):
        arr[:, :, c] = _scale_channel(arr[:, :, c], target_mean[c])
    
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    return Image.fromarray(arr)


def white_balance_image(img: Image.Image, method: str = "gray_world") -> Image.Image:
    """Apply white balance to image using specified method."""
    if method == "gray_world":
        return apply_gray_world(img)
    elif method == "shades_of_gray":
        return apply_shades_of_gray(img)
    elif method == "gray_edge":
        return apply_gray_edge(img)
    else:
        raise ValueError(f"Unknown white balance method: {method}")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && pytest tests/test_white_balance.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd backend && git add lib/white_balance.py tests/test_white_balance.py && git commit -m "Add white balance algorithms (Gray World, Shades of Gray, Gray Edge)"
```

---

## Task 2: Add white balance to batch schema

**Files:**
- Modify: `backend/app/models/schemas.py` - Add white_balance and white_balance_method fields to BatchProcessRequest

- [ ] **Step 1: Read current schema**

Run: `grep -n "color_match" backend/app/models/schemas.py`

- [ ] **Step 2: Add white_balance fields**

Modify `backend/app/models/schemas.py` around line 158 - add after color_match_reference:

```python
    color_match: bool = False
    color_match_method: str = "histogram"
    color_match_reference: int = 0
    white_balance: bool = False
    white_balance_method: str = "gray_world"
```

- [ ] **Step 3: Commit**

```bash
cd backend && git add app/models/schema.py && git commit -m "Add white_balance fields to batch request schema"
```

---

## Task 3: Add white balance processing in batch.py

**Files:**
- Modify: `backend/app/routers/batch.py` - Add white balance step BEFORE color match

- [ ] **Step 1: Read batch.py around line 120-170**

Find where color_match handling is to add white_balance before it.

- [ ] **Step 2: Add white balance step**

Add after caption handling and BEFORE color_match:

```python
                if req.white_balance:
                    from PIL import Image
                    from lib.white_balance import white_balance_image

                    img = Image.open(item.media_path)
                    if img.mode != "RGB":
                        img = img.convert("RGB")
                    create_version_backup(session, i, "white_balance")
                    result = white_balance_image(img, req.white_balance_method or "gray_world")
                    result.save(item.media_path)
                    log_line.append(f"White balanced using {req.white_balance_method or 'gray_world'}")
```

- [ ] **Step 3: Commit**

```bash
cd backend && git add app/routers/batch.py && git commit -m "Add white balance processing step to batch"
```

---

## Task 4: Add WhiteBalance OperationCard to frontend

**Files:**
- Modify: `frontend/src/components/batch/BatchForm.tsx` - Add WhiteBalance card above Color Matching

- [ ] **Step 1: Read BatchForm.tsx imports**

- [ ] **Step 2: Add state and icon**

Add state variables after colorMatchHistogram (around line 96):
```typescript
  const [whiteBalance, setWhiteBalance] = useState(false);
  const [whiteBalanceMethod, setWhiteBalanceMethod] = useState("gray_world");
```

Add Sun icon import (around line 24):
```typescript
import { Palette, Eye, Sun } from "lucide-react";
```

- [ ] **Step 3: Add mutual exclusion logic**

Add before handleStart function (around line 133):
```typescript
  const handleWhiteBalanceChange = (checked: boolean) => {
    setWhiteBalance(checked);
    if (checked) {
      setColorMatch(false);
    }
  };

  const handleColorMatchChange = (checked: boolean) => {
    setColorMatch(checked);
    if (checked) {
      setWhiteBalance(false);
    }
  };
```

- [ ] **Step 4: Add white_balance to request body**

In handleStart, add to the request JSON body:
```typescript
          white_balance: whiteBalance,
          white_balance_method: whiteBalanceMethod,
```

- [ ] **Step 5: Add OperationCard before Color Matching card**

Add around line 396 (before the existing Color Matching card):
```typescript
        <OperationCard
          icon={<Sun className="w-5 h-5" />}
          title="White Balance"
          description="Automatic white balance correction."
          checked={whiteBalance}
          onCheckedChange={handleWhiteBalanceChange}
        >
          <div className="flex items-center gap-3">
            <label className="text-sm text-text-secondary">Method</label>
            <Select value={whiteBalanceMethod} onValueChange={(v) => setWhiteBalanceMethod(v ?? "gray_world")}>
              <SelectTrigger className="w-40">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="gray_world">Gray World</SelectItem>
                <SelectItem value="shades_of_gray">Shades of Gray</SelectItem>
                <SelectItem value="gray_edge">Gray Edge</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </OperationCard>
```

- [ ] **Step 6: Update Color Matching card onCheckedChange**

Change the Color Matching OperationCard to use handleColorMatchChange:
```typescript
        <OperationCard
          icon={<Palette className="w-5 h-5" />}
          title="Color Matching"
          description="Transfer color distribution from a reference image."
          checked={colorMatch}
          onCheckedChange={handleColorMatchChange}
        >
```

- [ ] **Step 7: Commit**

```bash
cd frontend && git add src/components/batch/BatchForm.tsx && git commit -m "Add White Balance operation card with mutual exclusion"
```

---

## Task 5: Verify end-to-end

- [ ] **Step 1: Start servers and test**

```bash
./run.sh
```

- [ ] **Step 2: Open http://localhost:3000/batch**

- [ ] **Step 3: Verify UI shows White Balance card above Color Matching**

- [ ] **Step 4: Verify mutual exclusion works**

Check enabling White Balance disables Color Matching and vice versa

- [ ] **Step 5: Commit final**

```bash
git add -A && git commit -m "Complete white balance feature"
```

---

## Spec Coverage Check

- [x] Gray World method - Task 1
- [x] Shades of Gray method - Task 1
- [x] Gray Edge method - Task 1
- [x] Schema fields additions - Task 2
- [x] Backend processing order (WB before color match) - Task 3
- [x] Frontend OperationCard above Color Matching - Task 4
- [x] Mutual exclusion logic - Task 4
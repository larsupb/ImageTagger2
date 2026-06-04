# musubi_control Export Format Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `musubi_control` export format that produces a musubi-compatible dataset with images, control images, and a `dataset_config.toml`.

**Architecture:** The `export_dataset()` function in `export_service.py` gets a new format branch. When `format="musubi_control"`, it creates `img/`, `control/`, and `dataset_config.toml` instead of `img/` and `masks/`. The frontend adds one dropdown option. The schema allows the new format name.

**Tech Stack:** Python/FastAPI (backend), React/TypeScript (frontend).

---

### Task 1: Add format validation to schemas

**Files:**
- Modify: `backend/app/models/schemas.py:213-221`

- [ ] **Step 1: Add Literal type for formats and update ExportRequest**

Open `backend/app/models/schemas.py` at line 213. Add a `Literal` import at the top of the file if not present, then change `ExportRequest.format` from `str` to a `Literal["standard", "musubi_control"]`.

Find the `ExportRequest` class (lines 214-221) and change:
```python
class ExportRequest(BaseModel):
    format: str = "standard"
```
to:
```python
class ExportRequest(BaseModel):
    format: Literal["standard", "musubi_control"] = "standard"
```

Also add `Literal` to the import at the top of the file if not already there:
```python
from typing import Literal, Optional
```

Run typecheck (if available):
```bash
cd backend && source .venv/bin/activate && python -c "from app.models.schemas import ExportRequest; print('OK')"
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/models/schemas.py
git commit -m "feat(export): add musubi_control format to schema"
```

---

### Task 2: Add musubi_control export logic

**Files:**
- Modify: `backend/app/services/export_service.py:37-106`

- [ ] **Step 1: Add TOML content constant**

Open `backend/app/services/export_service.py`. Add a constant after the imports (after line 15):

```python
MUSUBI_CONTROL_CONFIG = """[general]
resolution = [1024, 1024]
batch_size = 1

[[datasets]]
image_directory = "img"
caption_extension = ".txt"
control_directory = "control"
"""
```

- [ ] **Step 2: Add musubi_control branch in export_dataset()**

Find the `export_dataset()` function. After the `os.makedirs(masks_dir)` line (line 57), add a condition to create the `control/` directory as well:

Replace lines 53-57:
```python
    output_dir = tempfile.mkdtemp(prefix="imagetagger_export_")
    img_dir = os.path.join(output_dir, "img")
    masks_dir = os.path.join(output_dir, "masks")
    os.makedirs(img_dir)
    os.makedirs(masks_dir)
```
with:
```python
    output_dir = tempfile.mkdtemp(prefix="imagetagger_export_")
    img_dir = os.path.join(output_dir, "img")
    os.makedirs(img_dir)

    if options.format == "musubi_control":
        control_dir = os.path.join(output_dir, "control")
        os.makedirs(control_dir)
    else:
        masks_dir = os.path.join(output_dir, "masks")
        os.makedirs(masks_dir)
```

Then replace the mask export block at lines 101-104:
```python
        if item.mask_path and os.path.exists(item.mask_path):
            mask = Image.open(item.mask_path)
            mask_path = os.path.join(masks_dir, f"{new_filename}.png")
            mask.save(mask_path, format="PNG")
```
with:
```python
        if options.format == "musubi_control":
            if item.mask_path and os.path.exists(item.mask_path):
                mask = Image.open(item.mask_path)
                control_path = os.path.join(control_dir, f"{new_filename}.png")
                mask.save(control_path, format="PNG")
        else:
            if item.mask_path and os.path.exists(item.mask_path):
                mask = Image.open(item.mask_path)
                mask_path = os.path.join(masks_dir, f"{new_filename}.png")
                mask.save(mask_path, format="PNG")
```

Finally, add TOML file writing. Before the `return output_dir` line (line 106), add:

```python
    if options.format == "musubi_control":
        toml_path = os.path.join(output_dir, "dataset_config.toml")
        with open(toml_path, "w", encoding="utf-8") as f:
            f.write(MUSUBI_CONTROL_CONFIG)
```

- [ ] **Step 3: Run verification**

```bash
cd backend && source .venv/bin/activate && python -c "from app.services.export_service import export_dataset, MUSUBI_CONTROL_CONFIG; print('OK'); print(MUSUBI_CONTROL_CONFIG[:50])"
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/services/export_service.py
git commit -m "feat(export): add musubi_control format with dataset_config.toml"
```

---

### Task 3: Add musubi_control to frontend dropdown

**Files:**
- Modify: `frontend/src/components/export/ExportForm.tsx:220-222`

- [ ] **Step 1: Add SelectItem for musubi_control**

Open `frontend/src/components/export/ExportForm.tsx`. Find the `<SelectContent>` block at lines 220-222 and add:

```tsx
              <SelectContent>
                <SelectItem value="standard">Standard</SelectItem>
                <SelectItem value="musubi_control">Musubi Control</SelectItem>
              </SelectContent>
```

- [ ] **Step 2: Run lint**

```bash
cd frontend && npm run lint 2>&1 | head -20
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/components/export/ExportForm.tsx
git commit -m "feat(export): add musubi_control format option"
```

---

### Task 4: Manual integration test

Start the backend and frontend, load a dataset with some images and generated masks, and export with the new `Musubi Control` format. Verify the zip contains `img/`, `control/`, and `dataset_config.toml` with correct contents.
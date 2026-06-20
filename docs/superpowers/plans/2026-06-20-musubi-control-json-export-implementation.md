# Musubi Control JSON Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `musubi_control_json` export format that writes captions as `.json` files instead of `.txt`, suitable for Ideogram-structured captions.

**Architecture:** Extend `export_service.py` with a new format branch, add the format to the schema and frontend dropdown.

**Tech Stack:** Python (backend), TypeScript (frontend dropdown)

---

## File Map

```
backend/app/models/schemas.py              (modify) — add format literal
backend/app/services/export_service.py     (modify) — add format logic + toml config
frontend/src/components/export/ExportForm.tsx  (modify) — add dropdown option
backend/tests/test_batch.py               (modify) — add format test
```

---

## Task 1: Add format literal to schema

**Files:**
- Modify: `backend/app/models/schemas.py:211`

- [ ] **Step 1: Modify ExportRequest.format literal**

Change:
```python
class ExportRequest(BaseModel):
    format: Literal["standard", "musubi_control"] = "standard"
```
To:
```python
class ExportRequest(BaseModel):
    format: Literal["standard", "musubi_control", "musubi_control_json"] = "standard"
```

- [ ] **Step 2: Commit**

```bash
cd /home/lars/PycharmProjects/ImageTagger2/backend && git add app/models/schemas.py && git commit -m "feat(export): add musubi_control_json format to schema"
```

---

## Task 2: Implement export logic

**Files:**
- Modify: `backend/app/services/export_service.py`

- [ ] **Step 1: Add TOML config constant**

Add after `MUSUBI_CONTROL_CONFIG` (after line 25):

```python
MUSUBI_CONTROL_JSON_CONFIG = """[general]
resolution = [1024, 1024]
batch_size = 1

[[datasets]]
image_directory = "img"
caption_directory = "captions"
caption_extension = ".json"
control_directory = "control"
"""
```

- [ ] **Step 2: Add musubi_control_json to format conditions**

In `export_dataset()`, change the condition at line 64:
```python
if options.format == "musubi_control":
```
To:
```python
if options.format in ("musubi_control", "musubi_control_json"):
```

This makes `musubi_control_json` also create the `control/` dir and write masks.

- [ ] **Step 3: Add caption writing for musubi_control_json**

In `export_dataset()`, after the caption reading block (after line 107), change the caption write section. Currently:
```python
caption = caption_service.read_caption(session, i, options.caption_type)
caption_path = os.path.join(img_dir, f"{new_filename}.txt")
with open(caption_path, "w", encoding="utf-8") as f:
    f.write(caption)
```

Change to:
```python
caption = caption_service.read_caption(session, i, options.caption_type)

if options.format == "musubi_control_json":
    captions_dir = os.path.join(output_dir, "captions")
    os.makedirs(captions_dir, exist_ok=True)
    caption_path = os.path.join(captions_dir, f"{new_filename}.json")
    if caption.startswith("{"):
        with open(caption_path, "w", encoding="utf-8") as f:
            f.write(caption)
    else:
        import json as _json
        with open(caption_path, "w", encoding="utf-8") as f:
            _json.dump({"caption": caption}, f, ensure_ascii=False)
else:
    caption_path = os.path.join(img_dir, f"{new_filename}.txt")
    with open(caption_path, "w", encoding="utf-8") as f:
        f.write(caption)
```

- [ ] **Step 4: Add TOML config for musubi_control_json**

After the existing TOML write block (after line 123), change:
```python
if options.format == "musubi_control":
    toml_path = os.path.join(output_dir, "dataset_config.toml")
    with open(toml_path, "w", encoding="utf-8") as f:
        f.write(MUSUBI_CONTROL_CONFIG)
```

To:
```python
if options.format == "musubi_control":
    toml_path = os.path.join(output_dir, "dataset_config.toml")
    with open(toml_path, "w", encoding="utf-8") as f:
        f.write(MUSUBI_CONTROL_CONFIG)
elif options.format == "musubi_control_json":
    toml_path = os.path.join(output_dir, "dataset_config.toml")
    with open(toml_path, "w", encoding="utf-8") as f:
        f.write(MUSUBI_CONTROL_JSON_CONFIG)
```

- [ ] **Step 5: Commit**

```bash
cd /home/lars/PycharmProjects/ImageTagger2/backend && git add app/services/export_service.py && git commit -m "feat(export): implement musubi_control_json format"
```

---

## Task 3: Add frontend dropdown option

**Files:**
- Modify: `frontend/src/components/export/ExportForm.tsx:218`

- [ ] **Step 1: Add SelectItem**

Change:
```tsx
<SelectItem value="musubi_control">Musubi Control</SelectItem>
```
To:
```tsx
<SelectItem value="musubi_control">Musubi Control</SelectItem>
<SelectItem value="musubi_control_json">Musubi Control JSON</SelectItem>
```

- [ ] **Step 2: Commit**

```bash
cd /home/lars/PycharmProjects/ImageTagger2 && git add frontend/src/components/export/ExportForm.tsx && git commit -m "feat(export): add musubi_control_json to frontend dropdown"
```

---

## Task 4: Add test

**Files:**
- Modify: `backend/tests/test_batch.py`

- [ ] **Step 1: Add test**

Look at existing tests in `backend/tests/test_batch.py` to understand the test structure, then add:

```python
def test_export_musubi_control_json_writes_json_files(tmp_path, monkeypatch):
    """musubi_control_json exports captions as .json files with proper toml config."""
    import sys
    import os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

    from app.services.export_service import ExportOptions, export_dataset
    from app.services.export_service import MUSUBI_CONTROL_JSON_CONFIG

    # Create minimal dataset with two captions
    ds_path = tmp_path / "dataset"
    ds_path.mkdir()
    img_dir = ds_path / "img"
    img_dir.mkdir()

    # Create two simple test images
    from PIL import Image
    for i in range(2):
        Image.new("RGB", (512, 512), color="red").save(img_dir / f"img{i:05d}.jpg")

    class FakeDS:
        base_dir = str(ds_path)
        is_initialized = True
        def __len__(self):
            return 2
        def get_item(self, idx):
            class FakeItem:
                media_path = str(img_dir / f"img{idx:05d}.jpg")
                mask_path = None
            return FakeItem()

    class FakeSession:
        dataset = FakeDS()
        db = None

    from app.services import caption_service
    monkeypatch.setattr(caption_service, "read_caption", lambda s, idx, ct: f'{{"high_level_description": "test {idx}"}}')

    options = ExportOptions(format="musubi_control_json", caption_type="tags")
    output_dir = export_dataset(FakeSession(), options)

    # Verify captions dir and .json files
    captions_dir = os.path.join(output_dir, "captions")
    assert os.path.isdir(captions_dir), "captions dir should exist"
    assert os.path.isfile(os.path.join(captions_dir, "00000.json"))
    assert os.path.isfile(os.path.join(captions_dir, "00001.json"))

    # Verify content
    with open(os.path.join(captions_dir, "00000.json")) as f:
        content = f.read()
    import json
    parsed = json.loads(content)
    assert "high_level_description" in parsed

    # Verify dataset_config.toml
    toml_path = os.path.join(output_dir, "dataset_config.toml")
    assert os.path.isfile(toml_path)
    with open(toml_path) as f:
        toml_content = f.read()
    assert 'caption_extension = ".json"' in toml_content
    assert 'caption_directory = "captions"' in toml_content

    # Verify toml matches constant
    assert toml_content == MUSUBI_CONTROL_JSON_CONFIG
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/lars/PycharmProjects/ImageTagger2/backend && python -m pytest tests/test_batch.py::test_export_musubi_control_json_writes_json_files -v 2>&1 | head -20`
Expected: FAIL or ERROR (format not yet registered, or import issues)

- [ ] **Step 3: Run test to verify it passes**

If the test passes after implementing Tasks 1-3, skip to commit. If it fails due to real bugs, fix inline.

- [ ] **Step 4: Commit**

```bash
cd /home/lars/PycharmProjects/ImageTagger2/backend && git add tests/test_batch.py && git commit -m "test(export): add musubi_control_json format test"
```

---

## Self-Review

1. **Spec coverage:** All spec items covered — schema literal (Task 1), export logic (Task 2), frontend dropdown (Task 3), test (Task 4). No gaps.
2. **Placeholder scan:** No TBD/TODO, all code is complete.
3. **Type consistency:** `musubi_control_json` used as format ID consistently in all files. TOML config uses `caption_extension = ".json"` and `caption_directory = "captions"` matching spec.
4. **Spec item check:**
   - [x] Format ID: `musubi_control_json`
   - [x] Output structure: `img/`, `control/`, `captions/`, `dataset_config.toml`
   - [x] Caption as JSON (direct write) or wrapped as `{"caption": "..."}`
   - [x] TOML with `caption_extension = ".json"` and `caption_directory = "captions"`
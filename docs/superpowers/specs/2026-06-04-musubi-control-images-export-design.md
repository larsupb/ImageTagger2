# Musubi Control Images Export Format

## Context

ImageTagger2 already exports images and masks via the standard format. This spec adds a musubi-compatible dataset export format that generates proper control image directories and a `dataset_config.toml`.

The format targets Flux2, Flux Kontext, FramePack, and Wan2.1 training — all of which share the same control image via `control_directory` convention.

## Output Structure

```
output_dir/
  img/
    00000.jpg         # target image
    00000.txt         # caption
    00001.jpg
    00001.txt
    ...
  control/
    00000.png         # control image (RGBA PNG, matching filename)
    00001.png
    ...
  dataset_config.toml
```

## `dataset_config.toml`

```toml
[general]
resolution = [1024, 1024]
batch_size = 1

[[datasets]]
image_directory = "img"
caption_extension = ".txt"
control_directory = "control"
```

## Implementation

### Backend

1. **`backend/app/models/schemas.py`**: Add `"musubi_control"` to `ExportFormat` union.
2. **`backend/app/services/export_service.py`**: Add new branch in `export_dataset()` for `musubi_control`:
   - Create `img/` and `control/` directories inside the output zip.
   - Write images as `.jpg` to `img/`, captions as `.txt` to `img/`.
   - Write control images as `.png` to `control/`.
   - Write `dataset_config.toml` at the root of the zip.
   - Control images are exported even if they don't exist (empty file or skip — musubi expects the directory to exist). Actually, skip files where no mask exists? Or create the directory empty? Musubi will error if referenced files don't exist, so we should only include control images where a mask actually exists.

### Frontend

3. **`frontend/src/components/export/ExportForm.tsx`**: Add `"musubi_control"` to the format dropdown.

## Edge Cases

- Media items without a mask: skip — do not include an entry in `control/` for them.
- Empty export (no masks anywhere): `control/` directory is still created (empty).
- Zip filename: same pattern as existing formats.
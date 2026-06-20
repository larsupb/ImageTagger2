# Musubi Control JSON Export Format

## Overview

Add a new export format `musubi_control_json` that exports captions as `.json` files instead of `.txt` files, alongside images and optional control masks in Musubi format.

## Format ID

`musubi_control_json`

## Output Structure

```
output_dir/
  img/           — images as .jpg
  control/       — mask files as .png (if present, same as musubi_control)
  captions/      — one .json file per image, filename matching img (e.g. 00000.json)
  dataset_config.toml — config with caption_extension = ".json"
```

## Caption File Format

Each `captions/*.json` contains a JSON object:

- If the caption is already valid JSON (e.g. Ideogram structured output), write it directly.
- Otherwise (plain text captions), wrap it: `{"caption": "..."}` to produce valid JSON.

## Files to Change

### `backend/app/models/schemas.py`
- Add `"musubi_control_json"` to `ExportRequest.format` literal

### `backend/app/services/export_service.py`
- Add `caption_extension = ".json"` and `caption_directory = "captions"` to `MUSUBI_CONTROL_JSON_CONFIG`
- Add `musubi_control_json` branch in `export_dataset()`:
  - Create `captions/` dir alongside `img/` and `control/`
  - Write caption as `.json` to `captions/` (not `.txt` to `img/`)
  - Write `dataset_config.toml` with `caption_extension = ".json"` and `caption_directory = "captions"`
- Non-JSON captions wrapped as `{"caption": "..."}`

### `frontend/src/components/export/ExportForm.tsx`
- Add `<SelectItem value="musubi_control_json">Musubi Control JSON</SelectItem>` option

### `backend/tests/test_export.py` (or `tests/test_batch.py`)
- Add test for `musubi_control_json` format: verify captions written as `.json`, dataset_config uses `.json` extension, plain captions wrapped in `{"caption": "..."}`
# Ideogram JSON Tagger Integration Design

## Overview

Add a new "ideogram" tagger method that generates structured Ideogram 4-style JSON captions using an existing VLM endpoint. The output is a JSON string returned to the caller, matching the existing tagger convention.

## Architecture

```
captioning.py (dispatch)
  -> generate_ideogram_caption()     [new]
      -> vlm_endpoint settings       (shared)
      -> VLM API (OpenAI-compatible) [reused client]
      -> parse + normalize JSON
      -> return json.dumps()

ideogram_schema.py                   [new]
  -> default_caption()
  -> normalize_caption()
  -> serialize_caption()
  -> parse_caption_text()
```

## Files

### New: `backend/lib/tagging/ideogram_tagger.py`

Core captioning logic:

- `generate_ideogram_caption(image_path)` — main entry point, returns JSON string
- Reuses `vlm_endpoint` settings from `config.py` (base_url, api_key, model, timeout)
- Encodes image to base64 JPEG (reuse pattern from `openai_tagger.py._encode_image()`)
- Uses built-in prompt constants for the Ideogram JSON schema instructions
- JSON extraction: strip markdown fences, find first `{` / last `}`, parse, validate dict
- On any failure: return empty string (matches existing tagger convention)

Prompt constants (inline, no external files):
- `IMAGE_TO_JSON_SYSTEM` — system prompt instructing model to produce Ideogram JSON
- `IMAGE_TO_JSON_USER` — user request with image attachment
- `JSON_SCHEMA_INSTRUCTIONS` — full schema definition
- `CREATIVE_DIRECTIVE` — creative expansion policy

### New: `backend/lib/tagging/ideogram_schema.py`

Copied from `ideogram_captioner/schema.py`:

- `default_caption()` -> dict with empty schema skeleton
- `normalize_caption(data)` -> validates and normalizes structure
- `serialize_caption(data)` -> compact JSON string
- `parse_caption_text(text)` -> dict from JSON string

### Modified: `backend/app/config.py`

- Add `ideogram_settings` to DEFAULTS:
  ```python
  "ideogram_settings": {
      "prompt": None,  # override built-in prompt, or None for default
  }
  ```
- Add `ideogram_settings(state_dict)` accessor function

### Modified: `backend/lib/captioning.py`

- Add `"ideogram"` to `TAGGERS` list
- Add `elif option == "ideogram"` branch calling `generate_ideogram_caption(path)`

### Optional: Frontend settings UI

- Add ideogram prompt override input in tagger settings, following `florence_settings.prompt` pattern.

## Ideogram JSON Schema

```json
{
  "high_level_description": "string",
  "style_description": {
    "aesthetics": "string",
    "lighting": "string",
    "photo": "string (for photos)",
    "art_style": "string (for artwork)",
    "medium": "string",
    "color_palette": ["#hex"]
  },
  "compositional_deconstruction": {
    "background": "string",
    "elements": [
      {
        "type": "obj | text",
        "desc": "string",
        "bbox": [y1, x1, y2, x2],
        "text": "string (for type=text)",
        "color_palette": ["#hex"]
      }
    ]
  }
}
```

## Error Handling

- API timeout/connection errors: return empty string, log error
- JSON parse failure: return empty string, log error
- Non-dict response: return empty string, log warning

## Testing

- Add `backend/tests/test_ideogram_tagger.py` with mocked VLM responses
- Test JSON parsing, schema normalization, markdown fence stripping
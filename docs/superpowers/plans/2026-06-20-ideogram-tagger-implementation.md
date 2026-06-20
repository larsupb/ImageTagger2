# Ideogram JSON Tagger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new "ideogram" tagger that generates structured Ideogram 4-style JSON captions via the existing vlm_endpoint, returning a JSON string.

**Architecture:** New files `ideogram_schema.py` (schema utils) and `ideogram_tagger.py` (captioning logic), wired into `captioning.py` dispatch and `config.py` settings. Prompts are inline string constants.

**Tech Stack:** Python, openai package (already present), PIL (already present), existing vlm_endpoint settings.

---

## File Map

```
backend/lib/tagging/
  ideogram_schema.py   (new) — schema normalization/serialization
  ideogram_tagger.py   (new) — captioning logic + prompts

backend/app/config.py  (modify) — add ideogram_settings
backend/lib/captioning.py (modify) — add "ideogram" to dispatch
backend/tests/test_ideogram_tagger.py (new) — unit tests
```

---

## Task 1: `ideogram_schema.py`

**Files:**
- Create: `backend/lib/tagging/ideogram_schema.py`
- Test: `backend/tests/test_ideogram_tagger.py`

- [ ] **Step 1: Write the failing tests**

```python
# backend/tests/test_ideogram_tagger.py
import pytest
import json
from lib.tagging.ideogram_schema import (
    default_caption,
    normalize_caption,
    serialize_caption,
    parse_caption_text,
)


def test_default_caption_has_required_keys():
    d = default_caption()
    assert "high_level_description" in d
    assert "style_description" in d
    assert "compositional_deconstruction" in d


def test_normalize_caption_returns_dict():
    result = normalize_caption({"high_level_description": "test"})
    assert isinstance(result, dict)


def test_normalize_caption_defaults_on_non_dict():
    result = normalize_caption("not a dict")
    assert isinstance(result, dict)
    assert result["high_level_description"] == ""


def test_serialize_caption_returns_valid_json():
    d = default_caption()
    d["high_level_description"] = "a test image"
    result = serialize_caption(d)
    parsed = json.loads(result)
    assert parsed["high_level_description"] == "a test image"


def test_parse_caption_text_parses_json_string():
    d = default_caption()
    d["high_level_description"] = "parsed caption"
    text = json.dumps(d)
    result = parse_caption_text(text)
    assert result["high_level_description"] == "parsed caption"


def test_normalize_caption_extracts_style_fields():
    d = {
        "high_level_description": "sunset over mountains",
        "style_description": {
            "aesthetics": "warm, cinematic",
            "lighting": "golden hour",
            "medium": "photograph",
            "photo": "35mm, f/1.8",
            "color_palette": ["#FF6B00", "#FFD700"],
        },
    }
    result = normalize_caption(d)
    assert result["style_description"]["aesthetics"] == "warm, cinematic"
    assert result["style_description"]["lighting"] == "golden hour"
    assert result["style_description"]["photo"] == "35mm, f/1.8"
    assert "color_palette" not in result["style_description"]  # excluded per schema


def test_normalize_caption_extracts_elements():
    d = {
        "high_level_description": "a dog in a park",
        "compositional_deconstruction": {
            "background": "green park",
            "elements": [
                {"type": "obj", "desc": "brown dog"},
                {"type": "text", "text": "hello", "desc": "sign"},
            ]
        }
    }
    result = normalize_caption(d)
    elements = result["compositional_deconstruction"]["elements"]
    assert len(elements) == 2
    assert elements[0]["desc"] == "brown dog"
    assert elements[1]["text"] == "hello"


def test_normalize_caption_normalizes_bbox():
    d = {
        "high_level_description": "image with bboxes",
        "compositional_deconstruction": {
            "background": "",
            "elements": [
                {"type": "obj", "bbox": [100, 200, 500, 600]},
            ]
        }
    }
    result = normalize_caption(d)
    # normalize_bbox swaps to [y1, x1, y2, x2] and sorts
    # [100, 200, 500, 600] -> sorted: y=(100,500), x=(200,600) -> [100, 200, 500, 600]
    # but with top=min, left=min...
    # Actually from schema.py: [y1, x1, y2, x2], top/bottom sorted, left/right sorted
    # So [100, 200, 500, 600] -> top=100, bottom=500, left=200, right=600 -> [100, 200, 500, 600]
    # Wait no - normalize_bbox: y1=100, x1=200, y2=500, x2=600
    # top=min(100,500)=100, bottom=max=500, left=min(200,600)=200, right=max=600
    # return [top, left, bottom, right] = [100, 200, 500, 600]
    element = result["compositional_deconstruction"]["elements"][0]
    assert element.get("bbox") == [100, 200, 500, 600]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/lars/PycharmProjects/ImageTagger2/backend && python -m pytest tests/test_ideogram_tagger.py -v`
Expected: ERROR (cannot import ideogram_schema)

- [ ] **Step 3: Write minimal schema module**

```python
# backend/lib/tagging/ideogram_schema.py
from __future__ import annotations
import json
import re
from copy import deepcopy
from typing import Any

HEX_COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")


def default_caption() -> dict[str, Any]:
    return {
        "high_level_description": "",
        "style_description": {
            "aesthetics": "",
            "lighting": "",
            "photo": "",
            "medium": "photograph",
        },
        "compositional_deconstruction": {
            "background": "",
            "elements": [],
        },
    }


def normalize_palette(value: Any, limit: int) -> list[str]:
    if isinstance(value, str):
        import re as _re
        values: list[str] = []
        for raw in _re.split(r"[,\s]+", value.strip()):
            if not raw:
                continue
            item = raw.upper()
            if HEX_COLOR_RE.match(item) and len(values) < limit:
                values.append(item)
        return values
    if not isinstance(value, list):
        return []
    colors: list[str] = []
    for item in value:
        if not isinstance(item, str):
            continue
        color = item.strip().upper()
        if HEX_COLOR_RE.match(color):
            colors.append(color)
        if len(colors) >= limit:
            break
    return colors


def normalize_bbox(value: Any) -> list[int] | None:
    if not isinstance(value, (list, tuple)) or len(value) != 4:
        return None
    try:
        y1, x1, y2, x2 = [int(round(float(v))) for v in value]
    except (TypeError, ValueError):
        return None
    y1 = max(0, min(1000, y1))
    x1 = max(0, min(1000, x1))
    y2 = max(0, min(1000, y2))
    x2 = max(0, min(1000, x2))
    top, bottom = sorted((y1, y2))
    left, right = sorted((x1, x2))
    if top == bottom or left == right:
        return None
    return [top, left, bottom, right]


def _as_str(value: Any) -> str:
    if value is None:
        return ""
    return str(value)


def normalize_caption(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict):
        return default_caption()

    caption: dict[str, Any] = {}
    caption["high_level_description"] = _as_str(data.get("high_level_description", ""))

    style_in = data.get("style_description")
    if isinstance(style_in, dict):
        has_art = "art_style" in style_in and "photo" not in style_in
        style: dict[str, Any] = {
            "aesthetics": _as_str(style_in.get("aesthetics", "")),
            "lighting": _as_str(style_in.get("lighting", "")),
        }
        if has_art:
            style["medium"] = _as_str(style_in.get("medium", "illustration")) or "illustration"
            style["art_style"] = _as_str(style_in.get("art_style", ""))
        else:
            style["photo"] = _as_str(style_in.get("photo", ""))
            style["medium"] = _as_str(style_in.get("medium", "photograph")) or "photograph"
        caption["style_description"] = style
    else:
        caption["style_description"] = deepcopy(default_caption()["style_description"])

    comp_in = data.get("compositional_deconstruction", {})
    elements_in = comp_in.get("elements", []) if isinstance(comp_in, dict) else []
    elements: list[dict[str, Any]] = []
    if isinstance(elements_in, list):
        for item in elements_in:
            if not isinstance(item, dict):
                continue
            element_type = item.get("type")
            if element_type not in ("obj", "text"):
                element_type = "text" if "text" in item else "obj"
            element: dict[str, Any] = {"type": element_type}
            bbox = normalize_bbox(item.get("bbox"))
            if bbox:
                element["bbox"] = bbox
            if element_type == "text":
                element["text"] = _as_str(item.get("text", ""))
            element["desc"] = _as_str(item.get("desc", item.get("description", "")))
            elements.append(element)

    caption["compositional_deconstruction"] = {
        "background": _as_str(comp_in.get("background", "")) if isinstance(comp_in, dict) else "",
        "elements": elements,
    }
    return caption


def serialize_caption(data: dict[str, Any]) -> str:
    return json.dumps(normalize_caption(data), separators=(",", ":"), ensure_ascii=False)


def parse_caption_text(text: str) -> dict[str, Any]:
    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise ValueError("Caption JSON must be an object.")
    return normalize_caption(parsed)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/lars/PycharmProjects/ImageTagger2/backend && python -m pytest tests/test_ideogram_tagger.py::test_default_caption_has_required_keys tests/test_ideogram_tagger.py::test_normalize_caption_returns_dict tests/test_ideogram_tagger.py::test_normalize_caption_defaults_on_non_dict tests/test_ideogram_tagger.py::test_serialize_caption_returns_valid_json tests/test_ideogram_tagger.py::test_parse_caption_text_parses_json_string -v`
Expected: PASS (all 5 tests)

Run the remaining tests too:
Run: `cd /home/lars/PycharmProjects/ImageTagger2/backend && python -m pytest tests/test_ideogram_tagger.py -v`
Expected: PASS (all 8 tests)

- [ ] **Step 5: Commit**

```bash
cd /home/lars/PycharmProjects/ImageTagger2
git add backend/lib/tagging/ideogram_schema.py backend/tests/test_ideogram_tagger.py
git commit -m "feat(taggers): add ideogram schema utilities"
```

---

## Task 2: `ideogram_tagger.py`

**Files:**
- Create: `backend/lib/tagging/ideogram_tagger.py`
- Test: `backend/tests/test_ideogram_tagger.py`

- [ ] **Step 1: Write the failing tests**

Add these tests to `backend/tests/test_ideogram_tagger.py`:

```python
from lib.tagging.ideogram_tagger import (
    extract_json,
    generate_ideogram_caption,
)


def test_extract_json_strips_markdown_fence():
    raw = '```json\n{"high_level_description": "test"}\n```'
    result = extract_json(raw)
    assert result["high_level_description"] == "test"


def test_extract_json_finds_json_without_fence():
    raw = 'Here is some text before {"high_level_description": "test"} and after'
    result = extract_json(raw)
    assert result["high_level_description"] == "test"


def test_extract_json_finds_nested_braces():
    raw = '{"high_level_description": "test", "nested": {"a": 1}}'
    result = extract_json(raw)
    assert result["nested"]["a"] == 1


def test_extract_json_raises_on_non_dict():
    import pytest
    raw = '"just a string"'
    with pytest.raises(ValueError, match="not an object"):
        extract_json(raw)


def test_extract_json_raises_on_no_json():
    import pytest
    raw = 'no json here at all'
    with pytest.raises(ValueError, match="No JSON object found"):
        extract_json(raw)


def test_generate_ideogram_caption_returns_json_string(tmp_path, mocker):
    from PIL import Image
    from lib.tagging.ideogram_schema import default_caption

    img_path = tmp_path / "test.jpg"
    Image.new("RGB", (10, 10)).save(img_path)

    mock_caption = default_caption()
    mock_caption["high_level_description"] = "a test image"

    mock_settings = {
        "api_key": "test-key",
        "base_url": "http://localhost:8000/v1",
        "model": "qwen2.5-vl-7b",
        "timeout": 60.0,
        "max_retries": 1,
    }

    mocker.patch("lib.tagging.ideogram_tagger.ideogram_settings", return_value={})
    mock_predict = mocker.patch("lib.tagging.ideogram_tagger._predict_ideogram_json", return_value=mock_caption)

    result = generate_ideogram_caption(str(img_path))

    assert result.startswith("{")
    assert "a test image" in result
    mock_predict.assert_called_once()


def test_generate_ideogram_caption_returns_empty_on_error(tmp_path, mocker):
    from PIL import Image

    img_path = tmp_path / "test.jpg"
    Image.new("RGB", (10, 10)).save(img_path)

    mocker.patch("lib.tagging.ideogram_tagger.ideogram_settings", return_value={})
    mocker.patch("lib.tagging.ideogram_tagger._predict_ideogram_json", side_effect=Exception("API error"))

    result = generate_ideogram_caption(str(img_path))

    assert result == ""
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/lars/PycharmProjects/ImageTagger2/backend && python -m pytest tests/test_ideogram_tagger.py::test_extract_json_strips_markdown_fence tests/test_ideogram_tagger.py::test_extract_json_finds_json_without_fence tests/test_ideogram_tagger.py::test_extract_json_finds_nested_braces tests/test_ideogram_tagger.py::test_extract_json_raises_on_non_dict tests/test_ideogram_tagger.py::test_extract_json_raises_on_no_json -v`
Expected: FAIL (functions not defined)

- [ ] **Step 3: Write the tagger module**

```python
# backend/lib/tagging/ideogram_tagger.py
import base64
import io
import json
import logging
import re
from pathlib import Path

import PIL
from PIL import Image
from openai import OpenAI, APITimeoutError, APIConnectionError

from lib.upscaling.util import scale_to_megapixels
from lib.tagging.ideogram_schema import normalize_caption, serialize_caption

logger = logging.getLogger(__name__)

JSON_SCHEMA_INSTRUCTIONS = """
Return exactly one compact valid JSON object. No markdown. No commentary.

Schema:
{
  "high_level_description": "...",
  "style_description": {
    "aesthetics": "...",
    "lighting": "...",
    "photo": "...",
    "medium": "photograph"
  },
  "compositional_deconstruction": {
    "background": "...",
    "elements": [
      {"type": "obj", "desc": "..."},
      {"type": "text", "text": "...", "desc": "..."}
    ]
  }
}

Field guidance:
- high_level_description: one or two sentences summarizing the whole image.
- aesthetics: concise visual style keywords, e.g. "moody, cinematic, desaturated" or "warm, playful, vibrant".
- lighting: concrete light quality, source, and shadow behavior, e.g. "golden hour, rim light, dramatic shadows" or "bright afternoon sunlight, long soft shadows".
- photo: camera, lens, viewpoint, focus, and photographic traits for photos, e.g. "35mm, f/1.4, bokeh", "shallow depth of field, eye-level, 85mm lens", or "wide angle, f/8, long exposure".
- medium: use a compact medium label such as "photograph", "illustration", "3d_render", "painting", or "graphic_design".
- art_style: style and medium traits for non-photo captions, e.g. "flat vector illustration, bold outlines" or "flat vector design, generous whitespace, sans-serif typography".
- background: describe the environment, setting, distant scenery, surfaces, and atmosphere.
- elements desc: describe each subject/object with its visible appearance, clothing/materials, pose/action, and important props.

Rules:
- Include high_level_description, style_description, and compositional_deconstruction.
- compositional_deconstruction must contain background first, then elements.
- Use "photo" for photographic images, or replace it with "art_style" for non-photo artwork.
- Use exactly one of "photo" or "art_style".
- Do not include bbox values. Bboxes are added in a separate pass.
- Do not include color_palette fields.
- type is "obj" for normal subjects/objects and "text" only for literal visible text.
- Text elements must preserve the literal visible text exactly.
- A coherent subject is one element; do not split people, vehicles, plants, buildings, or products into parts.
- Put ground, sky, walls, distant scenery, and ambient environment into background.
- Put people, animals, vehicles, products, furniture, props, signs, and visible text into elements.
- Keep trigger tokens, names, identifiers, and stylized spelling exactly.
""".strip()

IMAGE_TO_JSON_SYSTEM = """
You inspect an image and produce an Ideogram 4 structured JSON caption.
The image is authoritative. Describe only what is visible.
""".strip()

IMAGE_TO_JSON_USER = """
Create an Ideogram 4 structured JSON caption for this image.
Do not reference any existing sidecar caption.
""".strip()

SYSTEM_PROMPT = f"""{IMAGE_TO_JSON_SYSTEM}

{JSON_SCHEMA_INSTRUCTIONS}
"""


def _encode_image(image: Image.Image) -> str:
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=95)
    buffer.seek(0)
    return base64.b64encode(buffer.read()).decode("utf-8")


def extract_json(text: str) -> dict:
    raw = text.strip()
    fence = re.search(r"```(?:json)?\s*(.*?)```", raw, re.DOTALL | re.IGNORECASE)
    if fence:
        raw = fence.group(1).strip()

    start = raw.find("{")
    end = raw.rfind("}")
    if start < 0 or end <= start:
        raise ValueError(f"No JSON object found in model output: {raw[:200]!r}")
    candidate = raw[start : end + 1]
    try:
        parsed = json.loads(candidate)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Could not parse model JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError("Model output JSON root was not an object.")
    return parsed


def ideogram_settings(state_dict=None) -> dict:
    from app.config import read_settings
    settings = read_settings()
    return settings.get("ideogram_settings", {"prompt": None})


def _predict_ideogram_json(
    image_path: str,
    api_key: str,
    base_url: str,
    model: str,
    timeout: float,
) -> dict:
    client = OpenAI(
        api_key=api_key or "dummy",
        base_url=base_url.rstrip("/") + "/",
        timeout=timeout,
        max_retries=1,
    )

    image = Image.open(image_path).convert("RGB")
    image = scale_to_megapixels(image, 0.5)
    base64_image = _encode_image(image)

    response = client.chat.completions.create(
        model=model,
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{base64_image}"}},
                    {"type": "text", "text": IMAGE_TO_JSON_USER},
                ],
            }
        ],
        max_tokens=4096,
        temperature=0.0,
    )

    content = response.choices[0].message.content
    if not content:
        raise ValueError("VLM returned empty response")

    raw = content.strip()
    raw = re.sub(r"<think>.*?</think>", "", raw, flags=re.DOTALL | re.IGNORECASE).strip()
    parsed = extract_json(raw)
    return normalize_caption(parsed)


def generate_ideogram_caption(image_path: str) -> str:
    logger.info(f"Generating Ideogram JSON caption for: {image_path}")
    try:
        from app.config import vlm_endpoint_settings

        settings = vlm_endpoint_settings()
        api_key = settings.get("api_key", "")
        base_url = settings.get("base_url", "http://localhost:11434/v1")
        model = settings.get("model", "qwen2.5-vl-7b")
        timeout = settings.get("timeout", 120.0)

        caption_dict = _predict_ideogram_json(
            image_path=image_path,
            api_key=api_key,
            base_url=base_url,
            model=model,
            timeout=timeout,
        )
        return serialize_caption(caption_dict)

    except APITimeoutError as e:
        logger.error(f"Ideogram API timeout for {image_path}: {e}")
        return ""
    except APIConnectionError as e:
        logger.error(f"Ideogram API connection error for {image_path}: {e}")
        return ""
    except Exception as e:
        logger.error(f"Error generating Ideogram caption for {image_path}: {e}", exc_info=True)
        return ""
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/lars/PycharmProjects/ImageTagger2/backend && python -m pytest tests/test_ideogram_tagger.py -v`
Expected: PASS (all 16 tests)

- [ ] **Step 5: Commit**

```bash
cd /home/lars/PycharmProjects/ImageTagger2
git add backend/lib/tagging/ideogram_tagger.py
git commit -m "feat(taggers): add Ideogram JSON captioning via vlm endpoint"
```

---

## Task 3: Wire into dispatch and config

**Files:**
- Modify: `backend/app/config.py`
- Modify: `backend/lib/captioning.py`

- [ ] **Step 1: Add ideogram_settings to config.py**

Add to `DEFAULTS` dict in `backend/app/config.py` (after line 27):

```python
    "ideogram_settings": {
        "prompt": None,
    },
```

Add this function after `llm_endpoint_settings()`:

```python
def ideogram_settings(state_dict=None) -> dict:
    """Get Ideogram tagger settings."""
    return read_settings().get("ideogram_settings", {"prompt": None})
```

- [ ] **Step 2: Add ideogram to TAGGERS and dispatch in captioning.py**

In `backend/lib/captioning.py`, add `"ideogram"` to the TAGGERS list (line 10):

```python
TAGGERS = ["joytag", "wd14", "florence", "vlm-tagger", "ideogram", "combo"]
```

Add this branch in `generate_caption()` (after line 57):

```python
            elif option == "ideogram":
                from lib.tagging.ideogram_tagger import generate_ideogram_caption

                caption = generate_ideogram_caption(path)
```

- [ ] **Step 3: Run tests**

Run: `cd /home/lars/PycharmProjects/ImageTagger2/backend && python -m pytest tests/test_ideogram_tagger.py -v`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
cd /home/lars/PycharmProjects/ImageTagger2
git add backend/app/config.py backend/lib/captioning.py
git commit -m "feat(taggers): wire ideogram into captioning dispatch and config"
```

---

## Self-Review

1. **Spec coverage:** All spec items covered — schema utils (Task 1), captioning logic (Task 2), config and dispatch wiring (Task 3). No gaps.
2. **Placeholder scan:** No TBD/TODO, no "fill in later", all code is complete and runnable.
3. **Type consistency:** All function names match across tasks — `extract_json`, `generate_ideogram_caption`, `normalize_caption`, `serialize_caption`, `ideogram_settings` used consistently.
4. **Spec item check:**
   - [x] New `ideogram_schema.py` — schema utils from Ideogram-Json-Captioner
   - [x] New `ideogram_tagger.py` — captioning logic, prompt constants, JSON parsing
   - [x] Reuses `vlm_endpoint` settings — uses `vlm_endpoint_settings()` from config.py
   - [x] Returns `json.dumps()` string — via `serialize_caption()`
   - [x] Returns empty string on error — handled with try/except in `generate_ideogram_caption`
   - [x] Added to `TAGGERS` list and dispatch
   - [x] Tests included
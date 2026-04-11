# ComfyUI Upscaling Integration

## Overview

Add ComfyUI as an alternative upscaling method using the official ComfyUI API. This is additive to existing spandrel-based upscaling.

## Configuration

Add to `settings.json` under `comfyui` key:
- `url`: ComfyUI server URL (e.g., `http://localhost:8188`)
- `api_token`: API key for authentication
- `workflow`: Embedded workflow JSON (default SeedVR2)

## Architecture

### New Module: `lib/comfyui/`

#### `lib/comfyui/__init__.py`
- Empty, marks package

#### `lib/comfyui/client.py`
- `ComfyClient` class wrapping HTTP calls
- `upload_image(img: PIL.Image) -> str` — uploads to `/api/upload/image`, returns filename
- `run_workflow(workflow_json: dict, input_image: str) -> str` — POST to `/api/prompt`, returns prompt_id
- `wait_for_completion(prompt_id: str, poll_interval: float = 1.0) -> dict` — polls until done
- `download_output(filename: str) -> bytes` — GET `/api/view?filename=...`
- Auth handled via `ComfyUI-Api-Key` header

#### `lib/comfyui/workflow.py`
- `SEEDVR2_WORKFLOW`: Default SeedVR2 upscaling workflow JSON
- `inject_image(workflow: dict, image_filename: str) -> dict` — helper to set input image node

### Service: `app/services/comfyui_service.py`

```python
def upscale_with_comfyui(session: Session, index: int, target_megapixels: float = 2.0) -> str:
    """Upscale image using ComfyUI workflow."""
    # 1. Load image from dataset
    # 2. Upload to ComfyUI
    # 3. Inject image into workflow
    # 4. Run workflow, wait for completion
    # 5. Download result
    # 6. Scale to target megapixels (same as spandrel)
    # 7. Store in session.upscaled_image
```

### Router: `app/routers/processing.py`

New endpoint:
```
POST /api/processing/upscale-comfyui
Body: {"index": int, "target_megapixels?: float}
Response: {"status": "upscaled", "index": int}
```

### Schema: `app/models/schemas.py`

```python
class ComfyUIUpscaleRequest(BaseModel):
    index: int
    target_megapixels: float | None = 2.0
```

### Config: `app/config.py`

Add to DEFAULTS:
```python
"comfyui": {
    "url": "http://localhost:8188",
    "api_token": "",
    "workflow": SEEDVR2_WORKFLOW  # imported from lib.comfyui.workflow
}
```

## Error Handling

| Error | HTTP Status | Message |
|-------|-------------|---------|
| ComfyUI unreachable | 503 | "ComfyUI not reachable" |
| Invalid API token | 401 | "Invalid ComfyUI API token" |
| Workflow execution fails | 500 | "ComfyUI workflow failed: <error>" |
| Output not found | 404 | "ComfyUI output not found" |

## File Changes Summary

| File | Change |
|------|--------|
| `backend/app/config.py` | Add `comfyui` to DEFAULTS |
| `backend/lib/comfyui/__init__.py` | New |
| `backend/lib/comfyui/client.py` | New |
| `backend/lib/comfyui/workflow.py` | New |
| `backend/app/services/comfyui_service.py` | New |
| `backend/app/routers/processing.py` | Add endpoint |
| `backend/app/models/schemas.py` | Add ComfyUIUpscaleRequest |

## Acceptance Criteria

1. User can configure ComfyUI URL and API token in settings
2. Upscale endpoint triggers ComfyUI workflow execution
3. Image is uploaded to ComfyUI before execution
4. Service blocks until workflow completes (no async)
5. Result is scaled to target megapixels (same as spandrel)
6. Upscaled image is cached in session (same flow as spandrel)
7. Save endpoint works the same way for both upscaling methods
8. Errors are properly surfaced to frontend
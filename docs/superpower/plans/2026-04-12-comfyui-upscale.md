# ComfyUI Upscaling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ComfyUI as an alternative upscaling method using the official ComfyUI API.

**Architecture:** New `lib/comfyui/` module with client + workflow. Service layer handles upload → execute → download → scale. Router adds new endpoint.

**Tech Stack:** Python `requests` library, PIL, existing session management.

---

## File Structure

```
backend/lib/comfyui/
  ├── __init__.py          # Package marker
  ├── client.py           # ComfyClient class for API calls
  └── workflow.py        # Default SeedVR2 workflow JSON

backend/app/services/
  └── comfyui_service.py # upscale_with_comfyui function

backend/app/models/schemas.py     # Add ComfyUIUpscaleRequest
backend/app/config.py             # Add comfyui to DEFAULTS
backend/app/routers/processing.py # Add /upscale-comfyui endpoint
```

---

### Task 1: Create ComfyUI Client Module

**Files:**
- Create: `backend/lib/comfyui/__init__.py`
- Create: `backend/lib/comfyui/client.py`
- Create: `backend/lib/comfyui/workflow.py`

- [ ] **Step 1: Create lib/comfyui/ package**

```python
# backend/lib/comfyui/__init__.py
# Empty - marks package
```

- [ ] **Step 2: Create lib/comfyui/workflow.py with SeedVR2 workflow**

```python
# backend/lib/comfyui/workflow.py
SEEDVR2_WORKFLOW = {
    "last_node_id": 20,
    "last_link_id": 21,
    "nodes": [
        {"id": 1, "type": "LoadImage", "pos": [250, 100], "size": [315, 270], "flags": {}, "order": 0, "mode": 0, "inputs": [{"name": "image", "type": "IMAGE", "link": None}], "outputs": [{"name": "IMAGE", "type": "IMAGE", "links": [21]}, {"name": "MASK", "type": "MASK", "links": None}], "properties": {"Node name for S&R": "LoadImage"}, "widgets_values": ["input_image", "a8f8f8ff-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]},
        {"id": 2, "type": "SeedVR_Pipeline", "pos": [650, 100], "size": [315, 262], "flags": {}, "order": 1, "mode": 0, "inputs": [{"name": "image", "type": "IMAGE", "link": 21}, {"name": "scale", "type": "INT", "link": None, "widget": {"control_name": "scale", "name": "scale", "type": "INT", "value": 4}}, {"name": "seed", "type": "INT", "link": None, "widget": {"control_name": "seed", "name": "seed", "type": "INT", "value": 42}}], "outputs": [{"name": "IMAGE", "type": "IMAGE", "links": [16]}], "property": {}},
        {"id": 3, "type": "SaveImage", "pos": [1050, 100], "size": [315, 270], "flags": {}, "order": 2, "mode": 0, "inputs": [{"name": "images", "type": "IMAGE", "link": 16}, {"name": "filename_prefix", "type": "STRING", "link": None, "widget": {"control_name": "filename_prefix", "name": "filename_prefix", "type": "STRING", "value": "ComfyUI"}}], "outputs": [], "property": {"Node name for S&R": "SaveImage"}, "widgets_values": ["ComfyUI"]}
    ],
    "links": [
        [21, "IMAGE", 1, 0, "IMAGE"]
    ],
    "groups": [],
    "config": {},
    "extra": {"ds": {"scale": 1, "offset": [0, 0]}},
    "version": 0.4
}


def inject_image(workflow: dict, image_filename: str) -> dict:
    """Inject image filename into workflow's LoadImage node."""
    import copy
    wf = copy.deepcopy(workflow)
    for node in wf.get("nodes", []):
        if node.get("type") == "LoadImage":
            if node.get("widgets_values"):
                node["widgets_values"][0] = image_filename
            break
    return wf
```

- [ ] **Step 3: Create lib/comfyui/client.py**

```python
# backend/lib/comfyui/client.py
import io
import time
import requests
from PIL import Image
from typing import Optional


class ComfyClient:
    """Client for ComfyUI API."""
    
    def __init__(self, url: str, api_token: str):
        self.url = url.rstrip("/")
        self.session = requests.Session()
        if api_token:
            self.session.headers.update({"ComfyUI-Api-Key": api_token})
    
    def upload_image(self, img: Image.Image) -> str:
        """Upload image to ComfyUI, return filename."""
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        buf.seek(0)
        files = {"image": ("upload.png", buf, "image/png")}
        resp = self.session.post(f"{self.url}/api/upload/image", files=files)
        resp.raise_for_status()
        data = resp.json()
        return data.get("name", data.get("filename"))
    
    def run_workflow(self, workflow_json: dict) -> str:
        """Submit workflow, return prompt_id."""
        resp = self.session.post(f"{self.url}/api/prompt", json={"prompt": workflow_json})
        resp.raise_for_status()
        data = resp.json()
        return data.get("prompt_id")
    
    def wait_for_completion(self, prompt_id: str, poll_interval: float = 1.0, timeout: float = 300.0) -> dict:
        """Poll until workflow completes, return history entry."""
        start = time.time()
        while time.time() - start < timeout:
            resp = self.session.get(f"{self.url}/api/history_v2/{prompt_id}")
            resp.raise_for_status()
            data = resp.json()
            if prompt_id in data:
                status = data[prompt_id].get("status", {})
                if status.get("completed", False):
                    return data[prompt_id]
            time.sleep(poll_interval)
        raise TimeoutError(f"Workflow {prompt_id} did not complete within {timeout}s")
    
    def download_output(self, filename: str) -> Image.Image:
        """Download output image from ComfyUI."""
        resp = self.session.get(f"{self.url}/api/view", params={"filename": filename})
        resp.raise_for_status()
        return Image.open(io.BytesIO(resp.content))
```

- [ ] **Step 4: Commit**

```bash
git add backend/lib/comfyui/
git commit -m "feat: add ComfyUI client module"
```

---

### Task 2: Add ComfyUI Config to Defaults

**Files:**
- Modify: `backend/app/config.py:1-101`

- [ ] **Step 1: Add comfyui config to DEFAULTS**

Add to DEFAULTS dict around line 7:
```python
    "comfyui": {
        "url": "http://localhost:8188",
        "api_token": "",
    },
```

- [ ] **Step 2: Add helper function**

Add after `combo_taggers()` function around line 99:
```python
def comfyui_settings() -> dict:
    """Get ComfyUI settings."""
    return read_settings().get("comfyui", {"url": "http://localhost:8188", "api_token": ""})
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/config.py
git commit -m "feat: add ComfyUI config defaults"
```

---

### Task 3: Create ComfyUI Service

**Files:**
- Create: `backend/app/services/comfyui_service.py`

- [ ] **Step 1: Create comfyui_service.py**

```python
# backend/app/services/comfyui_service.py
import os
import sys
from io import BytesIO

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from PIL import Image
from app.sessions import Session
from app.config import comfyui_settings
from lib.comfyui.client import ComfyClient
from lib.comfyui.workflow import inject_image, SEEDVR2_WORKFLOW
from lib.upscaling.util import scale_to_megapixels


def upscale_with_comfyui(session: Session, index: int, target_megapixels: float = 2.0) -> str:
    """Upscale image using ComfyUI workflow."""
    settings = comfyui_settings()
    url = settings.get("url", "http://localhost:8188")
    api_token = settings.get("api_token", "")
    
    if not url:
        raise ValueError("ComfyUI URL not configured")
    
    client = ComfyClient(url, api_token)
    
    ds = session.dataset
    item = ds.get_item(index)
    
    img = Image.open(item.media_path)
    if img.mode != "RGB":
        img = img.convert("RGB")
    
    filename = client.upload_image(img)
    
    workflow = inject_image(SEEDVR2_WORKFLOW, filename)
    
    prompt_id = client.run_workflow(workflow)
    
    result = client.wait_for_completion(prompt_id)
    
    outputs = result.get("outputs", {})
    for node_id, node_output in outputs.items():
        if "images" in node_output:
            for img_data in node_output["images"]:
                output_filename = img_data.get("filename")
                if output_filename:
                    upscaled = client.download_output(output_filename)
                    break
            break
    
    if upscaled is None:
        raise ValueError("Could not find output image in ComfyUI result")
    
    upscaled = scale_to_megapixels(upscaled, target_megapixels)
    
    session.upscaled_image = upscaled
    session.upscaled_index = index
    
    return "ok"
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/services/comfyui_service.py
git commit -m "feat: add ComfyUI upscaling service"
```

---

### Task 4: Add Schema and Router Endpoint

**Files:**
- Modify: `backend/app/models/schemas.py:125-135`
- Modify: `backend/app/routers/processing.py:1-82`

- [ ] **Step 1: Add ComfyUIUpscaleRequest to schemas**

Add after line 132 (after MaskGenerateRequest):
```python
class ComfyUIUpscaleRequest(BaseModel):
    index: int
    target_megapixels: Optional[float] = 2.0
```

- [ ] **Step 2: Add router endpoint**

Add to processing.py after line 23 (after upscale endpoint):
```python
@router.post("/upscale-comfyui")
def upscale_comfyui(req: ComfyUIUpscaleRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    try:
        from app.services import comfyui_service
        comfyui_service.upscale_with_comfyui(
            session, req.index, req.target_megapixels
        )
        return {"status": "upscaled", "index": req.index}
    except Exception as e:
        raise HTTPException(500, str(e))
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/models/schemas.py backend/app/routers/processing.py
git commit -m "feat: add ComfyUI upscale endpoint"
```

---

### Task 5: Verify Implementation

**Files:**
- Run: Server startup test

- [ ] **Step 1: Check Python syntax**

Run: `cd backend && python -c "from app.routers.processing import router; print('OK')"`
Expected: Output "OK"

- [ ] **Step 2: Check imports**

Run: `cd backend && python -c "from lib.comfyui.client import ComfyClient; from lib.comfyui.workflow import SEEDVR2_WORKFLOW; from app.services.comfyui_service import upscale_with_comfyui; print('OK')"`
Expected: Output "OK"

- [ ] **Step 3: Commit**

```bash
git status
git commit --amend  # if only verification changes, amend previous commit
```

---
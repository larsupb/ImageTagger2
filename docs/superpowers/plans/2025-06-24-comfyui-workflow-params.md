# ComfyUI Workflow Parameters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable per-workflow parameter configuration for ComfyUI upscalers via an inline settings pane, with values stored in `settings.json`.

**Architecture:** Each ComfyUI upscaler in `upscalers.json` declares a `params` array with `key`, `node_id`, `input_name`, and UI metadata. The `inject_params()` function in `workflow.py` injects these into the workflow nodes at runtime. The frontend renders controls dynamically based on the schema and saves values to `comfyui_fparams` in `settings.json`.

**Tech Stack:** FastAPI backend, Next.js/React frontend, PIL, existing `inject_image()` pattern

---

## File Map

| File | Role |
|---|---|
| `backend/upscalers.json` | Add `params` schema for `comfyui-flux2-edit` |
| `backend/lib/comfyui/workflow.py` | Add `inject_params()`, update `inject_image()` signature |
| `backend/lib/comfyui/client.py` | Pass `params` to `inject_image()` |
| `backend/app/services/comfyui_service.py` | Read `comfyui_fparams` from settings, pass to client |
| `backend/app/config.py` | Add `comfyui_fparams` default to DEFAULTS |
| `frontend/src/lib/types.ts` | Add `WorkflowParam`, update `Upscaler` and `Settings` types |
| `frontend/src/app/settings/page.tsx` | Render dynamic params pane when ComfyUI upscaler selected |
| `backend/tests/test_comfyui.py` | Add tests for `inject_params()` |

---

### Task 1: Add params schema to upscalers.json

**Files:**
- Modify: `backend/upscalers.json`

- [ ] **Step 1: Add params array to comfyui-flux2-edit entry**

Replace the `comfyui-flux2-edit` entry with:

```json
{
  "name": "comfyui-flux2-edit",
  "filename": null,
  "scale_factor": 1,
  "url": null,
  "workflow_file": "lib/comfyui/workflows/image_enhance.json",
  "display_name": "ComfyUI Enhance",
  "params": [
    {
      "key": "denoise",
      "label": "Denoise",
      "type": "float",
      "node_id": "158:77",
      "input_name": "denoise",
      "default": 0.35,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "hint": "Lower = preserve original, higher = more transformation"
    },
    {
      "key": "steps",
      "label": "Steps",
      "type": "int",
      "node_id": "158:77",
      "input_name": "steps",
      "default": 5,
      "min": 1,
      "max": 50
    },
    {
      "key": "seed",
      "label": "Seed",
      "type": "int",
      "node_id": "158:77",
      "input_name": "seed",
      "default": -1,
      "hint": "-1 = random each time"
    },
    {
      "key": "cfg",
      "label": "CFG Scale",
      "type": "float",
      "node_id": "158:77",
      "input_name": "cfg",
      "default": 1.0,
      "min": 0.0,
      "max": 20.0,
      "step": 0.5
    },
    {
      "key": "sampler_name",
      "label": "Sampler",
      "type": "select",
      "node_id": "158:77",
      "input_name": "sampler_name",
      "default": "euler",
      "options": ["euler", "euler_ancestral", "dpmpp_3m_sde", "dpmpp_2m", "dpmpp_2m_sde", "heun", "dpm_2", "dpm_2_ancestral", " LMS", "LMS Karras", "dpm_fast", "dpm_adaptive", "dpmpp_2m_karras", "dpmpp_3m_sde_karras", "unipc", "unipc"]
    },
    {
      "key": "scheduler",
      "label": "Scheduler",
      "type": "select",
      "node_id": "158:77",
      "input_name": "scheduler",
      "default": "simple",
      "options": ["simple", "karras", "exponential", "normal", "exponential_int", "simple_beta", "simple_quad", "simple_cubic", "linear_quad", "normal_beta", "karras_beta", "exponential_beta", "simple_offset_noise", "vp_beta", "sgm_uniform"]
    },
    {
      "key": "enhance_instruction",
      "label": "Enhancement Instruction",
      "type": "text",
      "node_id": "150",
      "input_name": "value",
      "default": "same person and expression, improve lighting"
    },
    {
      "key": "modifications",
      "label": "Modifications",
      "type": "text",
      "node_id": "151",
      "input_name": "value",
      "default": ""
    },
    {
      "key": "quality_tags",
      "label": "Quality Tags",
      "type": "text",
      "node_id": "152",
      "input_name": "value",
      "default": "Subtle high resolution, histogram equalization, color grade, white balance correction, micro-contrast, lens distortion correction, clean digital file, remove blur and noise, remove jpeg artifacts, unsharp mask, neutral and perfectly tuned color, soft studio lighting, subtle background blur"
    }
  ]
}
```

- [ ] **Step 2: Commit**

```bash
cd backend && git add upscalers.json && git commit -m "feat: add params schema for comfyui-flux2-edit"
```

---

### Task 2: Add inject_params() to workflow.py

**Files:**
- Modify: `backend/lib/comfyui/workflow.py`

- [ ] **Step 1: Write failing tests for inject_params**

Add to `backend/tests/test_comfyui.py`:

```python
def test_inject_params():
    """Test that params are injected into the correct workflow nodes."""
    from lib.comfyui.workflow import inject_image, inject_params, get_workflow

    workflow = get_workflow()
    params = {"denoise": 0.5, "steps": 10, "seed": 42}
    result = inject_image(workflow, "test.jpg", target_megapixels=1.0, input_width=512, input_height=512)

    params_result = inject_params(result, params)

    # KSampler node should have denoise=0.5, steps=10, seed=42
    sampler_node = params_result.get("158:77", params_result.get("77"))
    assert sampler_node is not None, "KSampler node not found"
    if sampler_node:
        assert sampler_node["inputs"]["denoise"] == 0.5
        assert sampler_node["inputs"]["steps"] == 10
        assert sampler_node["inputs"]["seed"] == 42


def test_inject_params_text():
    """Test that text params are injected into PrimitiveStringMultiline nodes."""
    from lib.comfyui.workflow import inject_image, inject_params, get_workflow

    workflow = get_workflow("image_enhance.json")
    params = {"enhance_instruction": "enhance details, sharpen features"}
    result = inject_image(workflow, "test.jpg", target_megapixels=1.0, input_width=512, input_height=512)

    params_result = inject_params(result, params)

    assert params_result["150"]["inputs"]["value"] == "enhance details, sharpen features"
```

Run: `cd backend && source .venv/bin/activate && python -m pytest tests/test_comfyui.py::test_inject_params -v`
Expected: FAIL — `inject_params` not defined

- [ ] **Step 2: Implement inject_params()**

After the `inject_image` function in `workflow.py`, add:

```python
def inject_params(workflow: dict, params: dict) -> dict:
    """
    Inject workflow-specific parameters into nodes.

    Args:
        workflow: Workflow dict already processed by inject_image()
        params: Flat dict of {key: value} from settings

    Returns:
        Modified workflow dict with params injected
    """
    result = copy.deepcopy(workflow)

    # Build a reverse lookup: node_id -> {input_name: key}
    # This allows looking up params by the key declared in upscalers.json
    for key, value in params.items():
        if value is None:
            continue

        for node_id, node in result.items():
            if isinstance(node, dict) and "inputs" in node:
                if key in node["inputs"]:
                    node["inputs"][key] = value

    return result
```

Note: the loop over `node["inputs"]` with `key in node["inputs"]` means each param `key` must exactly match the input name. This works because the schema in `upscalers.json` declares `key` values that match the ComfyUI input names (e.g., `key: "denoise"` matches `inputs.denoise`).

Also update `inject_image()` to accept and pass through `params` but not set them itself (keep concerns separated):

```python
def inject_image(
    workflow: dict,
    image_filename: str,
    target_megapixels: float = None,
    input_width: int = None,
    input_height: int = None,
    params: dict = None,
) -> dict:
    result = copy.deepcopy(workflow)

    load_image = _find_node_by_class(result, "LoadImage")
    if load_image:
        node_id, node = load_image
        node["inputs"]["image"] = image_filename

    if target_megapixels and input_width and input_height:
        resolution = calculate_resolution_for_megapixels(
            input_width, input_height, target_megapixels
        )

        img_scale_nodes = _find_nodes_by_class(result, "ImageScaleToTotalPixels")
        if img_scale_nodes:
            for node_id, node in img_scale_nodes:
                if "megapixels" in node["inputs"]:
                    node["inputs"]["megapixels"] = target_megapixels

        resolution_calc_nodes = _find_nodes_by_class(result, "PixelResolutionCalculator")
        if resolution_calc_nodes:
            for node_id, node in resolution_calc_nodes:
                if "megapixels" in node["inputs"]:
                    node["inputs"]["megapixels"] = target_megapixels

        if "1" in result and "inputs" in result["1"]:
            if "resolution" in result["1"]["inputs"]:
                result["1"]["inputs"]["resolution"] = resolution

    if params:
        result = inject_params(result, params)

    return result
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `cd backend && source .venv/bin/activate && python -m pytest tests/test_comfyui.py::test_inject_params tests/test_comfyui.py::test_inject_params_text -v`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
cd backend && git add lib/comfyui/workflow.py tests/test_comfyui.py && git commit -m "feat: add inject_params() for workflow-specific node injection"
```

---

### Task 3: Pass params through client.py

**Files:**
- Modify: `backend/lib/comfyui/client.py`

- [ ] **Step 1: Update run_workflow() signature and body**

Change `run_workflow` from:
```python
def run_workflow(
    self,
    image_filename: str,
    target_megapixels: float = None,
    input_width: int = None,
    input_height: int = None,
    workflow_file: str = None,
) -> str:
    workflow = get_workflow(workflow_file)
    workflow_with_image = inject_image(
        workflow,
        image_filename,
        target_megapixels=target_megapixels,
        input_width=input_width,
        input_height=input_height,
    )
```

To:
```python
def run_workflow(
    self,
    image_filename: str,
    target_megapixels: float = None,
    input_width: int = None,
    input_height: int = None,
    workflow_file: str = None,
    params: dict = None,
) -> str:
    workflow = get_workflow(workflow_file)
    workflow_with_image = inject_image(
        workflow,
        image_filename,
        target_megapixels=target_megapixels,
        input_width=input_width,
        input_height=input_height,
        params=params,
    )
```

- [ ] **Step 2: Commit**

```bash
cd backend && git add lib/comfyui/client.py && git commit -m "feat: pass params through ComfyClient.run_workflow()"
```

---

### Task 4: Read comfyui_fparams and pass to client

**Files:**
- Modify: `backend/app/services/comfyui_service.py`
- Modify: `backend/app/config.py`

- [ ] **Step 1: Add comfyui_fparams to DEFAULTS in config.py**

In `backend/app/config.py`, add to `DEFAULTS`:

```python
"comfyui_fparams": {},
```

- [ ] **Step 2: Update comfyui_service.py to read and pass params**

In `comfyui_service.py`, after resolving `workflow_file`, add:

```python
if workflow_file:
    workflow_file = os.path.join(
        os.path.dirname(__file__), "..", "..", workflow_file
    )

# Load per-workflow params from settings
settings = comfyui_settings()
fparams = settings.get("comfyui_fparams", {})
workflow_params = fparams.get(upscaler_name, {})

client = ComfyClient(url, api_token)
```

Then update the `client.run_workflow()` call:
```python
prompt_id = client.run_workflow(
    filename,
    target_megapixels=target_megapixels,
    input_width=img_width,
    input_height=img_height,
    workflow_file=workflow_file,
    params=workflow_params,
)
```

Note: The function needs `upscaler_name` as a parameter. Update the function signature:
```python
def upscale_with_comfyui(
    session: Session,
    index: int,
    target_megapixels: float = 2.0,
    workflow_file: str = None,
    upscaler_name: str = None,
    cancel_check=None,
) -> str:
```

- [ ] **Step 3: Update processing_service.py to pass upscaler_name**

In `backend/app/services/processing_service.py`, update the call:
```python
return comfyui_service.upscale_with_comfyui(
    session, index, target_mp, workflow_file=workflow_file, upscaler_name=upscaler, cancel_check=cancel_check
)
```

- [ ] **Step 4: Commit**

```bash
cd backend && git add app/services/comfyui_service.py app/services/processing_service.py app/config.py && git commit -m "feat: load comfyui_fparams per upscaler from settings"
```

---

### Task 5: Add frontend types

**Files:**
- Modify: `frontend/src/lib/types.ts`

- [ ] **Step 1: Add WorkflowParam interface and update Upscaler**

Add to `types.ts`:

```ts
export interface WorkflowParam {
  key: string;
  label: string;
  type: "float" | "int" | "select" | "text";
  node_id: string;
  input_name: string;
  default: unknown;
  min?: number;
  max?: number;
  step?: number;
  options?: string[];
  hint?: string;
}
```

Update `Upscaler`:
```ts
export interface Upscaler {
  name: string;
  filename: string | null;
  scale_factor: number;
  url: string | null;
  workflow_file?: string | null;
  display_name?: string | null;
  params?: WorkflowParam[];
}
```

Update `Settings` to add `comfyui_fparams`:
```ts
export interface Settings {
  // ...existing fields...
  comfyui?: {
    url?: string;
    api_token?: string;
    workflow_file?: string;
  };
  comfyui_fparams?: Record<string, Record<string, unknown>>;
}
```

- [ ] **Step 2: Commit**

```bash
cd frontend && git add src/lib/types.ts && git commit -m "feat: add WorkflowParam type and comfyui_fparams to Settings"
```

---

### Task 6: Render dynamic params pane in settings page

**Files:**
- Modify: `frontend/src/app/settings/page.tsx`

- [ ] **Step 1: Add ParamControl helper component**

Add before the `SettingsPage` function:

```tsx
function ParamControl({
  param,
  value,
  onChange,
}: {
  param: WorkflowParam;
  value: unknown;
  onChange: (v: unknown) => void;
}) {
  const id = `param-${param.key}`;

  if (param.type === "float" || param.type === "int") {
    const min = param.min ?? 0;
    const max = param.max ?? 100;
    const step = param.step ?? 1;
    const numValue = Number(value ?? param.default);

    return (
      <div className="flex flex-col gap-1">
        <label className="block text-sm text-text-secondary" htmlFor={id}>
          {param.label}
          {param.hint && (
            <span className="ml-2 text-xs text-text-muted">({param.hint})</span>
          )}
        </label>
        <div className="flex items-center gap-3">
          <input
            type="range"
            id={id}
            min={min}
            max={max}
            step={step}
            value={numValue}
            onChange={(e) => onChange(param.type === "int" ? parseInt(e.target.value) : parseFloat(e.target.value))}
            className="flex-1"
          />
          <input
            type="number"
            min={min}
            max={max}
            step={step}
            value={numValue}
            onChange={(e) => onChange(param.type === "int" ? parseInt(e.target.value) : parseFloat(e.target.value))}
            className="w-20 px-2 py-1 bg-background border border-border rounded text-sm text-text text-right"
          />
        </div>
      </div>
    );
  }

  if (param.type === "select") {
    return (
      <div className="flex flex-col gap-1">
        <label className="block text-sm text-text-secondary" htmlFor={id}>
          {param.label}
        </label>
        <select
          id={id}
          value={String(value ?? param.default)}
          onChange={(e) => onChange(e.target.value)}
          className="w-full px-3 py-1.5 bg-background border border-border rounded text-sm text-text focus:outline-none focus:border-ring"
        >
          {param.options?.map((opt) => (
            <option key={opt} value={opt}>{opt}</option>
          ))}
        </select>
      </div>
    );
  }

  if (param.type === "text") {
    return (
      <div className="flex flex-col gap-1">
        <label className="block text-sm text-text-secondary" htmlFor={id}>
          {param.label}
        </label>
        <textarea
          id={id}
          value={String(value ?? param.default)}
          onChange={(e) => onChange(e.target.value)}
          rows={2}
          className="w-full px-3 py-2 bg-background border border-border rounded text-sm text-text resize-y focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/50 outline-none"
        />
      </div>
    );
  }

  return null;
}
```

- [ ] **Step 2: Add ComfyUI params pane inline under upscaler dropdown**

In the Upscaling `Section`, after the megapixel input, add:

```tsx
{localSettings.upscaler?.startsWith("comfyui-") && (
  upscalers?.find((u) => u.name === localSettings.upscaler)?.params && (
    <div className="mt-4 p-4 bg-surface-raised rounded-lg border border-border flex flex-col gap-4">
      <h4 className="text-sm font-medium text-text">Workflow Parameters</h4>
      {(upscalers?.find((u) => u.name === localSettings.upscaler)?.params ?? []).map((param) => {
        const currentValues = localSettings.comfyui_fparams?.[localSettings.upscaler!] ?? {};
        const value = currentValues[param.key] ?? param.default;

        return (
          <ParamControl
            key={param.key}
            param={param}
            value={value}
            onChange={(newVal) => {
              const nextFparams = {
                ...(localSettings.comfyui_fparams ?? {}),
                [localSettings.upscaler!]: {
                  ...(localSettings.comfyui_fparams?.[localSettings.upscaler!] ?? {}),
                  [param.key]: newVal,
                },
              };
              setLocalSettings({ ...localSettings, comfyui_fparams: nextFparams });
              save("comfyui_fparams", nextFparams);
            }}
          />
        );
      })}
    </div>
  )
)}
```

- [ ] **Step 3: Commit**

```bash
cd frontend && git add src/app/settings/page.tsx && git commit -m "feat: render dynamic workflow params pane in settings"
```

---

### Task 7: Add settings.json default entry

- [ ] **Step 1: Add comfyui_fparams to settings.json**

In `backend/settings.json`, add:

```json
"comfyui_fparams": {}
```

(It's already in memory from DEFAULTS but needs to be in the actual file so it persists.)

Run: `cd backend && source .venv/bin/activate && python -c "from app.config import save_settings; s = __import__('json').load(open('settings.json')); s.setdefault('comfyui_fparams', {}); save_settings(s)"`

- [ ] **Step 2: Commit settings.json**

```bash
cd backend && git add settings.json && git commit -m "chore: add comfyui_fparams key to settings.json"
```

---

## Spec Coverage Check

| Spec section | Tasks |
|---|---|
| Schema in upscalers.json with params array | Task 1 |
| Runtime storage in settings.json (comfyui_fparams) | Tasks 4, 7 |
| inject_params() in workflow.py | Task 2 |
| Pass params through client.py | Task 3 |
| Read comfyui_fparams in comfyui_service.py | Task 4 |
| Frontend WorkflowParam type | Task 5 |
| Dynamic params pane in settings page | Task 6 |
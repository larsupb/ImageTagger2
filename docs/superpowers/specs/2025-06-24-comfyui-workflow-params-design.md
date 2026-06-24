# ComfyUI Workflow Parameters Design

## Context

ImageTagger2 supports ComfyUI-backed upscalers with swappable workflow JSON files. Each workflow exposes node-level parameters (e.g., KSampler denoise, steps, seed) that users may want to tune per workflow. Currently no mechanism exists to expose or persist these per-workflow parameters.

## Storage

### Schema in `upscalers.json`

Each ComfyUI upscaler entry may contain a `params` array:

```json
{
  "name": "comfyui-flux2-edit",
  "workflow_file": "lib/comfyui/workflows/image_enhance.json",
  "display_name": "ComfyUI Enhance",
  "params": [
    {
      "key": "denoise",
      "label": "Denoise",
      "type": "float",
      "node_id": "158:77",
      "input_name": "denoise",
      "default": 0.9,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "key": "enhance_instruction",
      "label": "Enhancement Instruction",
      "type": "text",
      "node_id": "150",
      "input_name": "value",
      "default": "same person and expression, improve lighting"
    }
  ]
}
```

Fields:
- `key`: unique identifier within the workflow, used as the settings key
- `label`: human-readable label for the UI
- `type`: one of `float`, `int`, `select`, `text`
- `node_id`: ComfyUI node ID to inject into
- `input_name`: input field name on that node
- `default`: default value
- `min` / `max` / `step`: for numeric types
- `options`: array of strings, for `select` type
- `hint`: optional tooltip / help text

### Runtime storage in `settings.json`

```json
{
  "comfyui_fparams": {
    "comfyui-flux2-edit": {
      "denoise": 0.35,
      "steps": 5,
      "seed": -1
    },
    "comfyui-seedvr2": {}
  }
}
```

Default values from `upscalers.json` are used when no entry exists.

## Backend

### `workflow.py`

Add `inject_params(params: dict)` function:
- Takes a flat dict of `{ key: value }` (e.g., `{"denoise": 0.35, "seed": 123}`)
- Looks up each key in a node/input mapping derived from the schema
- Deep-copies the workflow and sets `result[node_id]["inputs"][input_name] = value`
- Called after `inject_image()` in `ComfyClient.run_workflow()`

### `comfyui_service.py`

- Read `comfyui_fparams` from settings keyed by upscaler name
- Pass params dict to `client.run_workflow(workflow_file=..., params=...)`
- If a param key is already injected by `inject_image` (e.g., seed from random), params override it

### `client.py`

- `run_workflow()` gains a `params: dict` kwarg
- Passes `params` to `inject_image()` which then calls `inject_params()`

## Frontend

### Types

```ts
interface WorkflowParam {
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

interface Upscaler {
  name: string;
  display_name?: string;
  params?: WorkflowParam[];
}
```

### Settings page

When the upscaler dropdown selects a ComfyUI upscaler (`name.startsWith("comfyui-")`), render an inline parameters pane below the dropdown. Structure:

1. Fetch `upscalers` from `api.getUpscalers()`
2. Find current upscaler's `params` array
3. Read current values from `settings.comfyui_fparams?.[upscalerName]` (merged with schema defaults)
4. Render per param type:
   - **float / int**: label + range slider + number input (linked)
   - **select**: label + `<select>` dropdown
   - **text**: label + `<textarea>`
5. On any change: update local state immediately, debounce save to `api.updateSetting("comfyui_fparams", fullDict)` after 500ms

The pane uses the existing `Section` component with `defaultOpen`. A helper `renderParam(param, value, onChange)` function handles the type switch.

## Scope

This spec covers the `comfyui-flux2-edit` workflow as the first use case. The design is general enough to apply to any ComfyUI upscaler added in the future.
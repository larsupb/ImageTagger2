# Project-Specific Settings — Design

Date: 2026-10-11
Status: approved by user (brainstorm session)

## Problem

All settings are global (`backend/settings.json`). Users want per-project values
for tagging/caption prompts and processing defaults, with globals as the base.
`project.json` already contains an unused `settings_overrides` dict (only
`active_tag_type` is persisted there today); nothing merges it into the
effective settings.

## Decisions (from brainstorm)

- Overridable scope: **tagging/caption prompts** and **processing defaults** only.
  Not tagger/model choices, not generation params (temperature etc.), not endpoints.
- Global settings stay the base; per-field sparse overrides with "reset to global"
  (inheritance, not snapshot).
- Global settings get their own entry point: gear icon in the top toolbar next to
  Jobs, opening a **dialog** with the existing full settings form.
- Left-nav **Settings** page becomes the project-specific settings page.
- Approach A: merge overrides into `session.config` at load time; consumers read
  `session.config`, not `read_settings()`.

## Overridable keys (fixed list)

| Key path | Label |
|---|---|
| `florence_settings.prompt` | Florence prompt |
| `vlm_endpoint.prompt` | VLM prompt |
| `upscaler` | Upscaler |
| `upscale_target_megapixels` | Upscale target megapixels |
| `rembg.model` | Rembg model |

Dropped as dead settings (read by no consumer; global fields exist but have no
effect): `tagger_instruction`, `ideogram_settings.prompt` (the Ideogram tagger
uses a hardcoded SYSTEM_PROMPT). `tagger_instruction` removal may be revisited
if a consumer ever appears.

`active_tag_type` keeps its existing bespoke persistence and UI placement
untouched; it lives in the same `settings_overrides` dict and must be preserved
by read-modify-write.

## Backend

The merge machinery already exists and is applied on project open:
`config.merge_settings/_deep_merge` (recursive) and
`project_service.get_effective_settings(path)`; `routers/projects.py` open/create
already set `session.config = get_effective_settings(path)`, and
`PUT /api/projects/{project_id}/config` already persists `settings_overrides`
and refreshes live sessions. What is missing:

1. **lib helpers ignore project config.** `app/config.py` helpers
   `florence_settings/vlm_endpoint_settings/ideogram_settings` accept but ignore
   `state_dict`; make them use `state_dict["config"]` (a settings dict) when
   present, else `read_settings()`. `tagger_service` (and the batch caption
   fallback) pass `{"dataset": ..., "config": session.config}` as state_dict.
2. **Direct global reads in project flows.** `routers/batch.py:70` (and its
   `vlm_endpoint_settings()` call for vlm captions), `services/processing_service.py:49,102,132`
   switch to `session.config or read_settings()`. `routers/settings.py` and
   `comfyui_service.py` (comfyui url/fparams — global by design) stay global.
3. **No way to read config from the client.** Add
   `GET /api/projects/{project_id}/config` returning the existing
   `ProjectConfigResponse` extended with `settings: {"global": {...},
   "effective": {...}}` — the five dotted key paths flattened by a new
   `config.flatten_overridable(settings) -> dict` helper. The existing PUT
   returns the same shape (full `settings_overrides` replacement semantics;
   client does read-modify-write).

## Frontend

### Toolbar icon

`ProjectTabs.tsx`: gear icon button next to `<JobsIndicator />` (visible always,
like Jobs). Opens a Radix Dialog containing the existing global settings form —
extracted from `app/settings/page.tsx` into `components/settings/GlobalSettingsForm.tsx`
verbatim (the route page is replaced by the project settings content).

### Project settings page

`app/settings/page.tsx` renders the project-scoped page:
- New `api.getProjectConfig(projectId)` / existing `api.updateProjectConfig`;
  reads `settings.global` / `settings.effective` from the response.
- One section per group: "Prompts" (2 textareas), "Processing" (upscaler select
  fed by `/api/settings/upscalers`, megapixels input, rembg select).
- Each field shows the effective value; if inherited shows a muted "global" hint
  with the global value beneath; if overridden shows a "Reset" button (sets the
  key to undefined in the read-modify-write payload).
- No project open: fields disabled, hint "Open a project to edit its settings".
- The PUT payload is the full `settings_overrides` dict (read via GET, mutate the
  five keys, preserve `active_tag_type` and unknown keys verbatim).

## Error handling

- `project.json` missing/corrupt → treated as `{}` overrides (effective = global);
  existing `read_project_config` behavior.
- Unknown `project_id` on GET/PUT config → 404 (existing PUT behavior).
- Project never registered / folder deleted → GET 404; page shows the
  disabled-state hint.

## Testing

- Unit: `flatten_overridable` (nested child merged with global sibling values);
  `florence_settings`/`vlm_endpoint_settings` honor `state_dict["config"]` and
  fall back to globals without it.
- API: `GET /api/projects/{id}/config` returns global/effective flattened five
  keys; PUT with nested override then GET shows it merged (sibling keys intact);
  PUT removing the key restores global.
- Integration: project overrides `vlm_endpoint.prompt`; `/api/tagging/generate`
  with monkeypatched `lib.captioning.generate_caption` receives state_dict whose
  `config["vlm_endpoint"]["prompt"]` is the project value.
- Frontend: `npx tsc --noEmit` clean, eslint clean on changed files.

## Out of scope

- Tagger/model selection, generation params, endpoint URLs/keys per project.
- PromptGen prompts (hardcoded system prompt; not stored settings).
- Editing global + project settings concurrently in two tabs (last write wins).

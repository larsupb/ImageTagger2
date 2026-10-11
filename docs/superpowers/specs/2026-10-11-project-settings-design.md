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
| `tagger_instruction` | Tagger instruction |
| `florence_settings.prompt` | Florence prompt |
| `vlm_endpoint.prompt` | VLM prompt |
| `ideogram_settings.prompt` | Ideogram prompt |
| `upscaler` | Upscaler |
| `upscale_target_megapixels` | Upscale target megapixels |
| `rembg.model` | Rembg model |

`active_tag_type` keeps its existing bespoke persistence and UI placement
untouched; the new GET/PUT must keep returning/accepting it for existing callers.

## Backend

### Merge helper (`app/config.py`)

`merge_overrides(settings: dict, overrides: dict) -> dict`
- One level deep: for each key in overrides, if both sides are dicts, shallow-merge
  the child dicts; else replace. Never mutates inputs.
- Overrides with value `None` at a leaf path remove the override (reset), handled
  at PUT time, not in merge.

### Load path

`dataset_service.load_dataset` (already sets `session.config = read_settings()`):
after reading project config, set
`session.config = merge_overrides(read_settings(), project_config.get("settings_overrides", {}))`.

### Consumers switched from `read_settings()` to `session.config`

- `routers/batch.py:70`
- `services/processing_service.py:49,102,132`
- `services/comfyui_service.py:78`

These all run in a project session context. Where a service lacks the session,
the session/config is threaded in as a parameter — no per-endpoint merging.
`routers/settings.py` keeps using global `read_settings()` (it manages globals).

### API: extend `/api/session/settings`

GET returns:
```json
{
  "global": {"tagger_instruction": "...", "florence_settings.prompt": "...", ...},
  "overrides": {"vlm_endpoint": {"prompt": "..."}},
  "effective": {"...": "merged result"}
}
```
- `global` and `effective` contain the seven flattened dotted key paths plus the
  existing `active_tag_type` (unchanged field); `overrides` is the raw sparse dict.
- PUT body: flat JSON object whose keys are the dotted paths, values are the new
  value or `null` (= remove the override). Backend expands dotted paths into the
  nested sparse dict before persisting.
PUT accepts a flat dict of the seven key paths with values (`null` = remove the
override). PUT: update `settings_overrides` in `project.json` via
`update_project_config`, re-merge into `session.config`, return the same shape.
Validation: reject unknown keys (422).

## Frontend

### Toolbar icon

`ProjectTabs.tsx`: gear icon button next to `<JobsIndicator />` (visible always,
like Jobs). Opens a Radix Dialog containing the existing global settings form —
extracted from `app/settings/page.tsx` into `components/settings/GlobalSettingsForm.tsx`
(page re-renders it so `/settings` deep-links keep working until nav change).

### Project settings page

`app/settings/page.tsx` renders the project-scoped page:
- Uses a new `api.getSessionSettings()` (GET/PUT `/api/session/settings`).
- One section per group: "Prompts" (4 textareas), "Processing" (upscaler select
  fed by `/api/settings/upscalers`, megapixels input, rembg select).
- Each field shows the effective value; if inherited shows a muted "global" hint
  with the global value beneath; if overridden shows a "Reset" button.
- No project open: fields disabled, hint "Open a project to edit its settings".

## Error handling

- `project.json` missing/corrupt → treated as `{}` overrides (effective = global);
  existing `read_project_config` behavior.
- PUT with unknown key → 422 with the key named.
- Session without DB/project (upload-only session) → GET returns global ==
  effective, `overrides: {}`; PUT → 400 "No project open".

## Testing

- Unit: `merge_overrides` (keeps sibling keys, replaces scalars, no mutation).
- API: `/api/session/settings` GET shape; PUT sets nested override, GET shows it
  in overrides/effective; PUT null removes it; unknown key 422.
- Integration: with a project override of the VLM prompt, monkeypatched
  `generate_caption` receives the overridden prompt (attributes classify path).
- Frontend: `npx tsc --noEmit` clean, eslint clean on changed files.

## Out of scope

- Tagger/model selection, generation params, endpoint URLs/keys per project.
- PromptGen prompts (hardcoded system prompt; not stored settings).
- Editing global + project settings concurrently in two tabs (last write wins).

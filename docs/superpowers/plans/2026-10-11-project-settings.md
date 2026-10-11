# Project-Specific Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-project overrides (sparse, inherit-from-global with reset) for Florence/VLM prompts and processing defaults (upscaler, upscale MP, rembg model), editable on the Settings page; global settings move to a toolbar dialog.

**Architecture:** Reuse the existing machinery: `project.json → settings_overrides`, `config.merge_settings/_deep_merge`, `project_service.get_effective_settings` (already applied to `session.config` on project open/create and live-refreshed by `PUT /api/projects/{id}/config`). Add: state_dict-aware config helpers, switch direct `read_settings()` consumers to `session.config`, a GET config endpoint exposing flattened global/effective values, and the frontend (extract global form → dialog; rebuild Settings page as project form).

**Tech Stack:** FastAPI + sqlite/JSON, pytest; Next.js 15 / React 19 / TS strict, Zustand (projectStore), React Query, shadcn Dialog.

**Spec:** `docs/superpowers/specs/2026-10-11-project-settings-design.md`

**Conventions:**
- Backend tests: `cd backend && .venv/bin/python -m pytest -q --ignore=tests/test_openai_tagger.py --ignore=tests/test_ideogram_tagger.py` (baseline: 114 passed + 2 pre-existing white_balance failures).
- Frontend gates: `cd frontend && npx tsc --noEmit` (must be clean); eslint: 2 pre-existing unused-import errors in `src/app/settings/page.tsx` are baseline (may vanish when that file is rewritten).
- Commits inside `backend/` / `frontend/` submodules, then bump pointer from repo root. Branch `feature/project-settings` already exists in all three repos.
- No comments unless non-obvious; no emojis; no `any`.

**Key existing facts (do not re-derive):**
- `backend/app/config.py`: `DEFAULTS`, `read_settings()`, `merge_settings(overrides)`, `_deep_merge` (recursive), `florence_settings/vlm_endpoint_settings/ideogram_settings(state_dict=None)` currently ignore `state_dict` and read globals; `vlm_endpoint_settings()` returns dict with `base_url`, `model`, `prompt`, ...
- `backend/app/services/project_service.py`: `read_project_config(path)`, `update_project_config(path, name=None, settings_overrides=None)` (replaces the whole overrides dict), `find_registry_entry(project_id)`, `get_effective_settings(path)`.
- `backend/app/routers/projects.py` has `PUT /{project_id}/config` (finds entry by looping `get_recent_projects(limit=200)`, refreshes live sessions). It does NOT import `find_registry_entry` yet.
- `backend/app/models/project.py`: `ProjectConfigUpdateRequest {name?, settings_overrides?}`, `ProjectConfigResponse {name, settings_overrides, last_opened, version}`.
- `backend/app/services/tagger_service.py:14`: `state_dict = {"dataset": session.dataset}`.
- `backend/app/routers/batch.py`: line 70 `settings = read_settings()`; line ~214 `vlm_settings = {**vlm_endpoint_settings(), "prompt": prompt}`; line ~226 `gen_caption, i, tagger_name, {"dataset": session.dataset}, prompt`.
- `backend/app/services/processing_service.py`: `read_settings()` in `upscale_image` (~49), `remove_background` (~102), `generate_mask` (~132); all three have `session: Session` first param.
- `lib/captioning.py` passes `state_dict` into `config.florence_settings(state_dict)` / `config.vlm_endpoint_settings(state_dict)`.
- `backend/tests/test_attributes_api.py` has `client` and `dataset` fixtures (create project → upload 3 PNGs 8x8 → rename → close → reopen; yields session headers). Its `dataset` fixture's create/open responses contain `project_id`.
- Frontend: `useProjectStore` keys projects by `session_id` (`activeProjectId` is a session id); each project entry has `project_id`. `api` object in `src/lib/api.ts`; `api.getUpscalers()` exists; shadcn `src/components/ui/dialog.tsx` exists; `ProjectTabs.tsx` renders `<JobsIndicator />` in a `div.shrink-0.pl-2` at the top bar's right end.

**Overridable keys (fixed):** `florence_settings.prompt`, `vlm_endpoint.prompt`, `upscaler`, `upscale_target_megapixels`, `rembg.model`. `active_tag_type` also lives inside `settings_overrides` and MUST be preserved verbatim by any client read-modify-write.

---

### Task 1: Config helpers honor `state_dict["config"]`

**Files:**
- Modify: `backend/app/config.py` (functions `florence_settings`, `vlm_endpoint_settings`, `ideogram_settings`)
- Test: `backend/tests/test_project_settings.py` (create)

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_project_settings.py`:

```python
from app.config import florence_settings, vlm_endpoint_settings


def test_helpers_prefer_state_dict_config():
    cfg = {
        "florence_settings": {"prompt": "proj florence"},
        "vlm_endpoint": {"prompt": "proj vlm", "base_url": "http://proj:1/v1"},
    }
    assert florence_settings({"config": cfg})["prompt"] == "proj florence"
    vlm = vlm_endpoint_settings({"config": cfg})
    assert vlm["prompt"] == "proj vlm"
    assert vlm["base_url"] == "http://proj:1/v1"


def test_helpers_fall_back_to_global_without_config():
    assert vlm_endpoint_settings()["base_url"]
    assert vlm_endpoint_settings({"dataset": None})["base_url"]
    assert florence_settings({})["prompt"]
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && .venv/bin/python -m pytest tests/test_project_settings.py -q`
Expected: FAIL — `KeyError: 'prompt'` (or missing keys) in the first test since helpers ignore `state_dict` and return global values.

- [ ] **Step 3: Implement**

In `backend/app/config.py`, above `florence_settings`, add:

```python
def _settings_source(state_dict: dict = None) -> dict:
    if state_dict:
        config = state_dict.get("config")
        if isinstance(config, dict) and config:
            return config
    return read_settings()
```

and change the three helpers to use it:

```python
def florence_settings(state_dict: dict = None) -> dict:
    return _settings_source(state_dict).get("florence_settings", DEFAULTS["florence_settings"])


def vlm_endpoint_settings(state_dict: dict = None) -> dict:
    return _settings_source(state_dict).get("vlm_endpoint", DEFAULTS["vlm_endpoint"])


def ideogram_settings(state_dict=None) -> dict:
    return _settings_source(state_dict).get("ideogram_settings", {"prompt": None})
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd backend && .venv/bin/python -m pytest tests/test_project_settings.py -q`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
cd backend && git add app/config.py tests/test_project_settings.py && git commit -m "Honor session config in florence/vlm/ideogram settings helpers"
```

---

### Task 2: Route project flows through session config

**Files:**
- Modify: `backend/app/services/tagger_service.py:14`
- Modify: `backend/app/routers/batch.py:70`, `~214`, `~226`
- Modify: `backend/app/services/processing_service.py:49`, `:102`, `:132`
- Test: `backend/tests/test_project_settings.py` (append)

- [ ] **Step 1: Write the failing integration test**

Append to `backend/tests/test_project_settings.py` (copy the two fixtures `client` and `dataset` from `backend/tests/test_attributes_api.py` — copy verbatim, including its imports `io, os, tempfile, pytest, TestClient, Image, app.main app`; capture `project_id` from the create response):

```python
def test_tagging_generate_receives_project_config(client, dataset, monkeypatch):
    captured = {}

    def fake_generate_caption(index, tagger, state_dict, prompt=None):
        captured["state_dict"] = state_dict
        return "a caption"

    monkeypatch.setattr("lib.captioning.generate_caption", fake_generate_caption)
    response = client.put(
        f"/api/projects/{dataset['project_id']}/config",
        json={"settings_overrides": {"vlm_endpoint": {"prompt": "PROJECT PROMPT"}}},
    )
    assert response.status_code == 200
    response = client.post(
        "/api/tagging/generate",
        json={"index": 0, "tagger": "vlm-tagger"},
        headers=dataset["headers"],
    )
    assert response.status_code == 200
    vlm = captured["state_dict"]["config"]["vlm_endpoint"]
    assert vlm["prompt"] == "PROJECT PROMPT"
    assert vlm["base_url"]
```

Note: the `dataset` fixture in `test_attributes_api.py` discards the create response; in the copy, change `response = client.post("/api/projects/create", ...)` handling to also store `project_id = response.json()["project_id"]` and yield it: `"project_id": project_id` in the yielded dict. Also verify the exact request body of `POST /api/tagging/generate` in `backend/app/routers/tagging.py` (it is `{"index", "tagger", "prompt"?}` per `models/schemas.py`) — adjust body keys to match if needed.

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && .venv/bin/python -m pytest tests/test_project_settings.py -q`
Expected: new test FAILS with `KeyError: 'config'` (state_dict carries only `dataset`).

- [ ] **Step 3: Implement**

`backend/app/services/tagger_service.py` line 14:

```python
    state_dict = {"dataset": session.dataset, "config": session.config}
```

`backend/app/routers/batch.py`:
- line 70: `settings = session.config or read_settings()`
- vlm branch (~214): `vlm_settings = {**(session.config.get("vlm_endpoint") or vlm_endpoint_settings()), "prompt": prompt}` (keep the existing `from app.config import vlm_endpoint_settings` import line in place)
- fallback caption call (~226): `{"dataset": session.dataset, "config": session.config}`

`backend/app/services/processing_service.py` — in `upscale_image`, `remove_background`, `generate_mask`, replace `settings = read_settings()` with:

```python
    settings = session.config or read_settings()
```

Do NOT touch `backend/app/routers/settings.py` (global CRUD) or `backend/app/services/comfyui_service.py` (comfyui url/fparams stay global).

- [ ] **Step 4: Run tests**

Run: `cd backend && .venv/bin/python -m pytest tests/test_project_settings.py tests/test_attributes_api.py tests/test_batch_attributes.py -q`
Expected: all pass. Then full suite:
Run: `cd backend && .venv/bin/python -m pytest -q --ignore=tests/test_openai_tagger.py --ignore=tests/test_ideogram_tagger.py`
Expected: only the 2 pre-existing `test_white_balance.py` failures.

- [ ] **Step 5: Commit**

```bash
cd backend && git add app/services/tagger_service.py app/routers/batch.py app/services/processing_service.py tests/test_project_settings.py && git commit -m "Read project settings from session config in tagging, batch and processing flows"
```

---

### Task 3: Flattened settings + GET project config endpoint

**Files:**
- Modify: `backend/app/config.py` (add `OVERRIDABLE_KEYS`, `flatten_overridable`)
- Modify: `backend/app/models/project.py` (`ProjectConfigResponse`)
- Modify: `backend/app/routers/projects.py` (GET route, PUT response, import `find_registry_entry`)
- Test: `backend/tests/test_project_settings.py` (append)

- [ ] **Step 1: Write the failing tests**

Append:

```python
def test_project_config_roundtrip(client, dataset):
    pid = dataset["project_id"]
    base = client.get(f"/api/projects/{pid}/config").json()
    assert base["settings"]["global"]["vlm_endpoint.prompt"] == \
        base["settings"]["effective"]["vlm_endpoint.prompt"]
    for key in ("florence_settings.prompt", "upscaler",
                "upscale_target_megapixels", "rembg.model"):
        assert key in base["settings"]["global"]

    overrides = dict(base["settings_overrides"])
    overrides["vlm_endpoint"] = {"prompt": "PROJ"}
    client.put(f"/api/projects/{pid}/config", json={"settings_overrides": overrides})
    after = client.get(f"/api/projects/{pid}/config").json()
    assert after["settings"]["effective"]["vlm_endpoint.prompt"] == "PROJ"
    assert after["settings"]["effective"]["florence_settings.prompt"] == \
        base["settings"]["global"]["florence_settings.prompt"]

    client.put(f"/api/projects/{pid}/config", json={"settings_overrides": base["settings_overrides"]})
    back = client.get(f"/api/projects/{pid}/config").json()
    assert back["settings"]["effective"] == back["settings"]["global"] or \
        back["settings"]["effective"]["vlm_endpoint.prompt"] == \
        back["settings"]["global"]["vlm_endpoint.prompt"]


def test_project_config_unknown_id_404(client):
    assert client.get("/api/projects/nope-nope/config").status_code == 404
```

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && .venv/bin/python -m pytest tests/test_project_settings.py -q`
Expected: roundtrip test FAILS (`KeyError: 'settings'` / GET returns 405/404), 404 test passes.

- [ ] **Step 3: Implement**

`backend/app/config.py` (after `_deep_merge`):

```python
OVERRIDABLE_KEYS = [
    "florence_settings.prompt",
    "vlm_endpoint.prompt",
    "upscaler",
    "upscale_target_megapixels",
    "rembg.model",
]


def flatten_overridable(settings: dict) -> dict:
    flat = {}
    for path in OVERRIDABLE_KEYS:
        parent, _, leaf = path.partition(".")
        if leaf:
            section = settings.get(parent)
            flat[path] = section.get(leaf) if isinstance(section, dict) else None
        else:
            flat[path] = settings.get(path)
    return flat
```

`backend/app/models/project.py` — extend:

```python
class ProjectConfigResponse(BaseModel):
    name: str
    settings_overrides: dict
    last_opened: str
    version: int
    settings: dict = {}
```

`backend/app/routers/projects.py` — add `find_registry_entry` to the `project_service` import list and `flatten_overridable, read_settings` to config imports (check existing imports; `read_settings` may already be imported). Add helper + route:

```python
def _config_response(path: str) -> ProjectConfigResponse:
    config = read_project_config(path) or {}
    return ProjectConfigResponse(
        name=config.get("name", os.path.basename(path)),
        settings_overrides=config.get("settings_overrides", {}),
        last_opened=config.get("last_opened", ""),
        version=config.get("version", 1),
        settings={
            "global": flatten_overridable(read_settings()),
            "effective": flatten_overridable(get_effective_settings(path)),
        },
    )


@router.get("/{project_id}/config", response_model=ProjectConfigResponse)
def get_project_configuration(project_id: str):
    entry = find_registry_entry(project_id)
    if entry is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return _config_response(entry["path"])
```

and in the existing `update_project_configuration`, replace its manual recent-projects lookup body's final `return ProjectConfigResponse(...)` construction with `return _config_response(project_entry["path"])` (keep the 404 check and session-refresh loop). Note the PUT currently resolves entries via `get_recent_projects(limit=200)`; leave that as is to avoid behavior change.

- [ ] **Step 4: Run tests**

Run: `cd backend && .venv/bin/python -m pytest tests/test_project_settings.py -q` → all pass.
Full suite as in Task 2 Step 4.

- [ ] **Step 5: Commit**

```bash
cd backend && git add app/config.py app/models/project.py app/routers/projects.py tests/test_project_settings.py && git commit -m "Add GET project config with flattened global and effective settings"
```

---

### Task 4: Frontend types + API client

**Files:**
- Modify: `frontend/src/lib/types.ts`
- Modify: `frontend/src/lib/api.ts`

- [ ] **Step 1: Add types**

Append to `frontend/src/lib/types.ts`:

```ts
export type FlattenedSettings = Record<string, string | number | boolean | null>;

export interface ProjectConfigResponse {
  name: string;
  settings_overrides: Record<string, unknown>;
  last_opened: string;
  version: number;
  settings: {
    global: FlattenedSettings;
    effective: FlattenedSettings;
  };
}
```

- [ ] **Step 2: Add api methods**

In `frontend/src/lib/api.ts` next to the other `apiFetch` methods, import `ProjectConfigResponse` from `./types` and add:

```ts
  getProjectConfig: (projectId: string) =>
    apiFetch<ProjectConfigResponse>(`/api/projects/${projectId}/config`),

  updateProjectConfig: (projectId: string, overrides: Record<string, unknown>) =>
    apiFetch<ProjectConfigResponse>(`/api/projects/${projectId}/config`, {
      method: "PUT",
      body: JSON.stringify({ settings_overrides: overrides }),
    }),
```

(If `updateProjectConfig` already exists in some form, adapt to this signature and fix callers.)

- [ ] **Step 3: Typecheck + commit**

```bash
cd frontend && npx tsc --noEmit && git add src/lib/types.ts src/lib/api.ts && git commit -m "Add project config API client"
```

---

### Task 5: Extract global settings form into a dialog behind a toolbar icon

**Files:**
- Create: `frontend/src/components/settings/GlobalSettingsForm.tsx`
- Modify: `frontend/src/components/layout/ProjectTabs.tsx`

- [ ] **Step 1: Move the form verbatim**

Copy `frontend/src/app/settings/page.tsx` (current content, 710 lines: `ParamControl`, `Section`, the page component body with `localSettings`/`save`) to `frontend/src/components/settings/GlobalSettingsForm.tsx`. In the copy: rename the default-exported component to `function GlobalSettingsForm()` with `export default GlobalSettingsForm;`. Keep everything else byte-identical (its `useQuery(["settings"])` + `api.getSettings()` + `api.saveSetting` behavior stays).

- [ ] **Step 2: Add toolbar button + dialog**

`frontend/src/components/layout/ProjectTabs.tsx` — add imports:

```tsx
import { useState } from "react";
import { Settings } from "lucide-react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import GlobalSettingsForm from "@/components/settings/GlobalSettingsForm";
```

(merge `useState` into the existing react import; `lucide-react` icons are already imported there — add `Settings` to that import instead of a new line).

Replace:

```tsx
        <div className="shrink-0 pl-2">
          <JobsIndicator />
        </div>
```

with:

```tsx
        <div className="shrink-0 flex items-center gap-1 pl-2">
          <Dialog>
            <DialogTrigger asChild>
              <button
                className="p-2 rounded-md text-text-secondary hover:text-text hover:bg-surface-raised transition-colors"
                aria-label="Global settings"
                title="Global settings"
              >
                <Settings className="w-4 h-4" />
              </button>
            </DialogTrigger>
            <DialogContent className="max-w-3xl max-h-[85vh] overflow-y-auto">
              <DialogHeader>
                <DialogTitle>Global Settings</DialogTitle>
              </DialogHeader>
              <GlobalSettingsForm />
            </DialogContent>
          </Dialog>
          <JobsIndicator />
        </div>
```

(Verify the exact exported names in `src/components/ui/dialog.tsx` before writing — if there is no `DialogTrigger` or the API differs, match what exists.)

- [ ] **Step 3: Typecheck (page still uses old file, so both must compile)**

Run: `cd frontend && npx tsc --noEmit`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
cd frontend && git add src/components/settings/GlobalSettingsForm.tsx src/components/layout/ProjectTabs.tsx && git commit -m "Add global settings dialog to project toolbar"
```

---

### Task 6: Settings page becomes project settings

**Files:**
- Rewrite: `frontend/src/app/settings/page.tsx`

- [ ] **Step 1: Implement the page**

Replace the entire content of `frontend/src/app/settings/page.tsx` with:

```tsx
"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { useProjectStore } from "@/stores/projectStore";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";
import type { FlattenedSettings } from "@/lib/types";

const OVERRIDABLE_KEYS = [
  "florence_settings.prompt",
  "vlm_endpoint.prompt",
  "upscaler",
  "upscale_target_megapixels",
  "rembg.model",
] as const;

type OverridableKey = (typeof OVERRIDABLE_KEYS)[number];

function setNested(target: Record<string, unknown>, path: string, value: unknown): void {
  const [parent, leaf] = path.includes(".") ? path.split(".") : [path, ""];
  if (!leaf) {
    target[parent] = value;
    return;
  }
  const section = { ...(typeof target[parent] === "object" && target[parent] !== null ? target[parent] as Record<string, unknown> : {}) };
  section[leaf] = value;
  target[parent] = section;
}

function removeNested(target: Record<string, unknown>, path: string): void {
  const [parent, leaf] = path.includes(".") ? path.split(".") : [path, ""];
  if (!leaf) {
    delete target[parent];
    return;
  }
  const section = { ...(typeof target[parent] === "object" && target[parent] !== null ? target[parent] as Record<string, unknown> : {}) };
  delete section[leaf];
  if (Object.keys(section).length === 0) delete target[parent];
  else target[parent] = section;
}

function Field({
  label,
  effective,
  globalValue,
  overridden,
  children,
  onReset,
}: {
  label: string;
  effective: string | number | boolean | null | undefined;
  globalValue: string | number | boolean | null | undefined;
  overridden: boolean;
  children: React.ReactNode;
  onReset: () => void;
}) {
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center justify-between">
        <label className="text-sm text-text-secondary">{label}</label>
        {overridden ? (
          <Button variant="ghost" size="sm" className="h-6 text-xs" onClick={onReset}>
            Reset to global
          </Button>
        ) : (
          <span className="text-xs text-text-muted">global</span>
        )}
      </div>
      {children}
      {overridden && (
        <p className="text-xs text-text-muted truncate">global: {String(globalValue ?? "")}</p>
      )}
      {!overridden && typeof effective === "string" && effective.length > 120 && (
        <p className="text-xs text-text-muted line-clamp-2">{effective}</p>
      )}
    </div>
  );
}

export default function SettingsPage() {
  const projects = useProjectStore((s) => s.projects);
  const activeSessionId = useProjectStore((s) => s.activeProjectId);
  const projectId = projects.find((p) => p.session_id === activeSessionId)?.project_id ?? null;
  const queryClient = useQueryClient();

  const { data: upscalers } = useQuery({ queryKey: ["upscalers"], queryFn: () => api.getUpscalers() });
  const { data: globalSettings } = useQuery({ queryKey: ["settings"], queryFn: () => api.getSettings() });
  const { data: config } = useQuery({
    queryKey: ["project-config", projectId],
    queryFn: () => api.getProjectConfig(projectId as string),
    enabled: projectId !== null,
  });

  const [draft, setDraft] = useState<Record<string, string>>({});

  const disabled = projectId === null;
  const eff: FlattenedSettings = config?.settings.effective ?? {};
  const glob: FlattenedSettings = config?.settings.global ?? {};
  const overrides = config?.settings_overrides ?? {};

  const isOverridden = (key: OverridableKey): boolean => {
    const [parent, leaf] = key.includes(".") ? key.split(".") : [key, ""];
    const section = leaf ? overrides[parent] : undefined;
    return leaf
      ? typeof section === "object" && section !== null && leaf in (section as Record<string, unknown>)
      : parent in overrides;
  };

  const save = async (key: OverridableKey, value: unknown) => {
    if (projectId === null) return;
    const next: Record<string, unknown> = { ...overrides };
    if (value === undefined) removeNested(next, key);
    else setNested(next, key, value);
    try {
      await api.updateProjectConfig(projectId, next);
      queryClient.invalidateQueries({ queryKey: ["project-config", projectId] });
      toast.success("Project setting saved");
    } catch (e) {
      toast.error(`Failed to save: ${e}`);
    }
  };

  const valueOf = (key: OverridableKey): string =>
    draft[key] ?? String(eff[key] ?? "");

  if (disabled) {
    return (
      <div className="p-6">
        <h2 className="text-xl font-semibold text-text mb-2">Project Settings</h2>
        <p className="text-sm text-text-muted">Open a project to edit its settings.</p>
      </div>
    );
  }

  return (
    <div className="p-6 flex flex-col gap-6 max-w-3xl">
      <div>
        <h2 className="text-xl font-semibold text-text">Project Settings</h2>
        <p className="text-sm text-text-muted mt-1">
          Overrides for this project. Unset fields follow global settings.
        </p>
      </div>

      <section className="bg-surface rounded-lg border border-border p-6 flex flex-col gap-4">
        <h3 className="text-base font-medium text-text">Prompts</h3>
        {(["florence_settings.prompt", "vlm_endpoint.prompt"] as const).map((key) => (
          <Field
            key={key}
            label={key === "vlm_endpoint.prompt" ? "VLM caption prompt" : "Florence prompt"}
            effective={eff[key]}
            globalValue={glob[key]}
            overridden={isOverridden(key)}
            onReset={() => save(key, undefined)}
          >
            <textarea
              rows={3}
              disabled={disabled}
              className="w-full px-3 py-2 bg-background border border-border rounded text-sm text-text resize-y focus-visible:border-ring outline-none disabled:opacity-50"
              value={valueOf(key)}
              onChange={(e) => setDraft({ ...draft, [key]: e.target.value })}
              onBlur={() => {
                const v = draft[key];
                if (v !== undefined && v !== String(eff[key] ?? "")) save(key, v);
                setDraft((d) => { const n = { ...d }; delete n[key]; return n; });
              }}
            />
          </Field>
        ))}
      </section>

      <section className="bg-surface rounded-lg border border-border p-6 flex flex-col gap-4">
        <h3 className="text-base font-medium text-text">Processing defaults</h3>
        <Field
          label="Upscaler"
          effective={eff.upscaler}
          globalValue={glob.upscaler}
          overridden={isOverridden("upscaler")}
          onReset={() => save("upscaler", undefined)}
        >
          <select
            className="w-full px-3 py-1.5 bg-background border border-border rounded text-sm text-text focus:outline-none focus:border-ring disabled:opacity-50"
            value={valueOf("upscaler") || undefined}
            disabled={disabled}
            onChange={(e) => { setDraft({ ...draft, upscaler: e.target.value }); save("upscaler", e.target.value); }}
          >
            {(upscalers ?? []).map((u) => (
              <option key={u.name} value={u.name}>{u.name}</option>
            ))}
          </select>
        </Field>
        <Field
          label="Upscale target megapixels"
          effective={eff.upscale_target_megapixels}
          globalValue={glob.upscale_target_megapixels}
          overridden={isOverridden("upscale_target_megapixels")}
          onReset={() => save("upscale_target_megapixels", undefined)}
        >
          <input
            type="number"
            step="0.1"
            min="0.1"
            className="w-32 px-3 py-1.5 bg-background border border-border rounded text-sm text-text focus:outline-none focus:border-ring disabled:opacity-50"
            value={valueOf("upscale_target_megapixels")}
            disabled={disabled}
            onChange={(e) => setDraft({ ...draft, upscale_target_megapixels: e.target.value })}
            onBlur={() => {
              const v = draft.upscale_target_megapixels;
              if (v !== undefined) save("upscale_target_megapixels", parseFloat(v));
              setDraft((d) => { const n = { ...d }; delete n.upscale_target_megapixels; return n; });
            }}
          />
        </Field>
        <Field
          label="Background removal model"
          effective={eff["rembg.model"]}
          globalValue={glob["rembg.model"]}
          overridden={isOverridden("rembg.model")}
          onReset={() => save("rembg.model", undefined)}
        >
          <select
            className="w-full px-3 py-1.5 bg-background border border-border rounded text-sm text-text focus:outline-none focus:border-ring disabled:opacity-50"
            value={valueOf("rembg.model") || undefined}
            disabled={disabled}
            onChange={(e) => save("rembg.model", e.target.value)}
          >
            {["u2net", "u2net_human_seg", "isnet-general-use", "birefnet-portrait"].map((m) => (
              <option key={m} value={m}>{m}</option>
            ))}
          </select>
        </Field>
      </section>
      {globalSettings === undefined && <p className="text-xs text-text-muted">Loading global settings…</p>}
    </div>
  );
}
```

Notes for the implementer:
- Check the real `useProjectStore` selector shape at the top of the file (`projects` items have `session_id` and `project_id`; `activeProjectId` holds the active **session id**) and adjust if the store shape differs.
- Check the rembg model options against what the global settings page used before deletion (search the old file for `u2net`); reuse that exact list.
- If the old `settings/page.tsx` had a `Section`/`ParamControl` used elsewhere, they were copied in Task 5; nothing else may import from the page file.

- [ ] **Step 2: Verify**

```bash
cd frontend && npx tsc --noEmit && npx eslint src/app/settings/page.tsx src/components/settings/GlobalSettingsForm.tsx src/components/layout/ProjectTabs.tsx src/lib/api.ts
```

Expected: tsc clean; eslint no errors on the new/changed files (warnings acceptable).

- [ ] **Step 3: Commit**

```bash
cd frontend && git add src/app/settings/page.tsx && git commit -m "Settings page edits project-scoped overrides with reset-to-global"
```

---

### Task 7: Full verification, live check, PRs

- [ ] **Step 1: Backend suite**

Run: `cd backend && .venv/bin/python -m pytest -q --ignore=tests/test_openai_tagger.py --ignore=tests/test_ideogram_tagger.py`
Expected: only 2 pre-existing white_balance failures.

- [ ] **Step 2: Frontend build gate**

Run: `cd frontend && npx tsc --noEmit && npm run build`
Expected: build succeeds.

- [ ] **Step 3: Live sanity (backend on :8000 with --reload picks this up)**

```bash
SID=$(curl -s -X POST localhost:8000/api/projects/open -H 'Content-Type: application/json' -d '{"path":"/mnt/sd_encrypted/datasets/characters/ashleyt/ashleyt_it2"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["session_id"])')
PID=$(curl -s -H "X-Session-ID: $SID" localhost:8000/api/projects/ | python3 -c 'import json,sys; print(json.load(sys.stdin)["projects"][0]["project_id"])')
curl -s -H "X-Session-ID: $SID" localhost:8000/api/projects/$PID/config | python3 -m json.tool
```

Expected: JSON with `settings.global` / `settings.effective` containing the five keys.

- [ ] **Step 4: Push all three repos, create PRs**

```bash
cd backend && git push -u origin feature/project-settings
cd ../frontend && git push -u origin feature/project-settings
cd .. && git add backend frontend docs && git commit -m "Bump submodules: project settings" && git push -u origin feature/project-settings
gh pr create --base main --title "Project-specific settings" --body "Per-project overrides (prompts, processing defaults) with inherit-from-global + reset; global settings moved to toolbar dialog. Stacked on feature/semantic-search PR."
```

Create PRs in backend and frontend repos too (same base/title style).

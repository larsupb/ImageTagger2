# Create Project Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Create Project" button to the landing page that creates a new empty directory and opens it as a project.

**Architecture:** New `POST /api/projects/create` backend endpoint creates the directory with `os.makedirs` then delegates to the existing open-project logic. Frontend adds `api.createProject`, a matching store action, and a secondary-styled button next to the existing "Open Project" button — both sharing the same path input.

**Tech Stack:** Python/FastAPI (backend), TypeScript/React/Zustand (frontend), Tailwind CSS 4, shadcn Button

---

## File Map

| File | Change |
|---|---|
| `backend/app/models/project.py` | Add `ProjectCreateRequest` model |
| `backend/app/routers/projects.py` | Add `POST /api/projects/create` endpoint |
| `backend/tests/test_projects.py` | New — tests for the create endpoint |
| `frontend/src/lib/api.ts` | Add `createProject` method |
| `frontend/src/stores/projectStore.ts` | Add `createProject` action + interface entry |
| `frontend/src/components/layout/AppLayout.tsx` | Add handler + Create Project button |

---

## Task 1: Install pytest and write failing tests for the create endpoint

No pytest is currently installed in the backend venv. This task installs it and writes tests that will fail until the endpoint exists.

**Files:**
- Create: `backend/tests/test_projects.py`

- [ ] **Step 1: Install pytest into the backend venv**

```bash
cd backend && .venv/bin/pip install pytest
```

Expected output: `Successfully installed pytest-...`

- [ ] **Step 2: Write the test file**

Create `backend/tests/test_projects.py`:

```python
import os
import tempfile
import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_create_project_creates_directory():
    with tempfile.TemporaryDirectory() as parent:
        new_path = os.path.join(parent, "my-dataset")
        response = client.post("/api/projects/create", json={"path": new_path})
        assert response.status_code == 200
        assert os.path.isdir(new_path)


def test_create_project_returns_open_response_shape():
    with tempfile.TemporaryDirectory() as parent:
        new_path = os.path.join(parent, "test-dataset")
        response = client.post("/api/projects/create", json={"path": new_path})
        assert response.status_code == 200
        data = response.json()
        assert "session_id" in data
        assert "project_id" in data
        assert "project_name" in data
        assert data["dataset_info"]["total_items"] == 0


def test_create_project_existing_path_returns_409():
    with tempfile.TemporaryDirectory() as existing_path:
        response = client.post("/api/projects/create", json={"path": existing_path})
        assert response.status_code == 409
        assert "already exists" in response.json()["detail"].lower()


def test_create_project_empty_path_returns_422():
    response = client.post("/api/projects/create", json={})
    assert response.status_code == 422
```

- [ ] **Step 3: Run the tests — expect all to fail with 404 (endpoint not yet defined)**

```bash
cd backend && .venv/bin/python -m pytest tests/test_projects.py -v
```

Expected: 3 failures with `assert 404 == 200` / `assert 404 == 409`, 1 possible pass for 422. That confirms the endpoint is missing and we need to add it.

---

## Task 2: Add `ProjectCreateRequest` model and the create endpoint

**Files:**
- Modify: `backend/app/models/project.py`
- Modify: `backend/app/routers/projects.py`

- [ ] **Step 1: Add `ProjectCreateRequest` to the models file**

In `backend/app/models/project.py`, add after `ProjectOpenRequest`:

```python
class ProjectCreateRequest(BaseModel):
    path: str
```

- [ ] **Step 2: Import `ProjectCreateRequest` in the router**

In `backend/app/routers/projects.py`, change the import from `app.models.project`:

```python
from app.models.project import (
    ProjectOpenRequest,
    ProjectCreateRequest,
    ProjectOpenResponse,
    ProjectDatasetInfo,
    ProjectCloseResponse,
    ActiveProjectInfo,
    ActiveProjectsResponse,
    RecentProjectEntry,
    RecentProjectsResponse,
    ProjectConfigUpdateRequest,
    ProjectConfigResponse,
)
```

- [ ] **Step 3: Add the `create_project` endpoint**

In `backend/app/routers/projects.py`, add this endpoint immediately after the `open_project` function (after line 75, before the `close_project` route):

```python
@router.post("/create", response_model=ProjectOpenResponse)
def create_project(req: ProjectCreateRequest):
    """Create a new empty directory and open it as a project."""
    path = os.path.abspath(req.path)
    if os.path.exists(path):
        raise HTTPException(status_code=409, detail="Path already exists")
    try:
        os.makedirs(path)
    except PermissionError:
        raise HTTPException(status_code=403, detail="Permission denied")
    except OSError as e:
        raise HTTPException(status_code=400, detail=str(e))

    entry = get_or_create_registry_entry(path)
    project_id = entry["project_id"]
    project_name = entry["name"]

    create_or_update_project_config(path, name=project_name)

    session = session_manager.create(project_id=project_id)

    load_dataset(session, path, False, False)

    effective_settings = get_effective_settings(path)
    session.config = effective_settings

    ds = session.dataset
    return ProjectOpenResponse(
        session_id=session.id,
        project_id=project_id,
        project_name=project_name,
        dataset_info=ProjectDatasetInfo(
            total_items=len(ds),
            base_dir=ds._base_dir,
            masks_dir=ds._masks_dir,
        ),
    )
```

- [ ] **Step 4: Run tests — expect all to pass**

```bash
cd backend && .venv/bin/python -m pytest tests/test_projects.py -v
```

Expected:
```
tests/test_projects.py::test_create_project_creates_directory PASSED
tests/test_projects.py::test_create_project_returns_open_response_shape PASSED
tests/test_projects.py::test_create_project_existing_path_returns_409 PASSED
tests/test_projects.py::test_create_project_empty_path_returns_422 PASSED
4 passed
```

- [ ] **Step 5: Commit**

```bash
git add backend/app/models/project.py backend/app/routers/projects.py backend/tests/test_projects.py
git commit -m "feat(backend): add POST /api/projects/create endpoint"
```

---

## Task 3: Add `createProject` to the frontend API client

**Files:**
- Modify: `frontend/src/lib/api.ts`

- [ ] **Step 1: Add `createProject` after `removeRecentProject` in `frontend/src/lib/api.ts`**

Locate the `removeRecentProject` method and add `createProject` immediately after it:

```typescript
  createProject: async (path: string): Promise<ProjectOpenResponse> => {
    const res = await fetch("/api/projects/create", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ path }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(body.detail || "Failed to create project");
    }
    return res.json() as Promise<ProjectOpenResponse>;
  },
```

Note: unlike the other methods in this file, `createProject` parses `body.detail` from error responses so that specific backend messages ("Path already exists", "Permission denied") reach the toast notification.

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd frontend && npm run build 2>&1 | tail -20
```

Expected: build completes with no TypeScript errors related to `api.ts`.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/lib/api.ts
git commit -m "feat(frontend): add createProject API method"
```

---

## Task 4: Add `createProject` action to the project store

**Files:**
- Modify: `frontend/src/stores/projectStore.ts`

- [ ] **Step 1: Add `createProject` to the `ProjectStore` interface**

In `frontend/src/stores/projectStore.ts`, add `createProject` to the interface after `removeRecentProject`:

```typescript
  removeRecentProject: (projectId: string) => Promise<void>;
  createProject: (path: string) => Promise<ProjectOpenResponse>;
  reset: () => void;
```

- [ ] **Step 2: Add the `createProject` implementation**

In the `create<ProjectStore>` body, add `createProject` after `removeRecentProject`:

```typescript
  createProject: async (path) => {
    const result = await api.createProject(path);
    const sessionId = result.session_id;
    setSessionId(sessionId);
    useSessionStore.getState().setDatasetInfo(sessionId, {
      total_items: result.dataset_info.total_items,
      base_dir: result.dataset_info.base_dir,
      masks_dir: result.dataset_info.masks_dir,
    });
    set((state) => ({
      projects: [
        ...state.projects,
        {
          session_id: sessionId,
          project_id: result.project_id,
          project_name: result.project_name,
          path: result.dataset_info.base_dir,
          total_items: result.dataset_info.total_items,
          current_index: 0,
          created_at: Date.now() / 1000,
          last_accessed: Date.now() / 1000,
        },
      ],
      activeProjectId: sessionId,
    }));
    return result;
  },
```

- [ ] **Step 3: Verify TypeScript compiles**

```bash
cd frontend && npm run build 2>&1 | tail -20
```

Expected: no TypeScript errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/stores/projectStore.ts
git commit -m "feat(frontend): add createProject store action"
```

---

## Task 5: Add the Create Project button to the landing page

**Files:**
- Modify: `frontend/src/components/layout/AppLayout.tsx`

- [ ] **Step 1: Destructure `createProject` from the store**

In `frontend/src/components/layout/AppLayout.tsx`, update the destructured store values on the line that starts with `const {`:

```typescript
  const { projects, recentProjects, loadActiveProjects, loadRecentProjects, openProject, removeRecentProject, createProject } = useProjectStore();
```

- [ ] **Step 2: Add the `handleCreateProject` handler**

Add this function immediately after `handleOpenProject` (around line 39):

```typescript
  const handleCreateProject = async () => {
    if (!path.trim()) return;
    try {
      const result = await createProject(path);
      toast.success(`Created ${result.project_name}`);
      setPath("");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to create project");
    }
  };
```

- [ ] **Step 3: Replace the single button with a flex row of two buttons**

Find this block (around line 62):

```tsx
            <Button onClick={handleOpenProject}>Open Project</Button>
```

Replace it with:

```tsx
            <div className="flex gap-2">
              <Button onClick={handleOpenProject}>Open Project</Button>
              <Button
                onClick={handleCreateProject}
                variant="outline"
                className="border-green-700 text-green-400 hover:border-green-500 hover:text-green-300 hover:bg-green-950"
              >
                Create Project
              </Button>
            </div>
```

- [ ] **Step 4: Verify TypeScript compiles**

```bash
cd frontend && npm run build 2>&1 | tail -20
```

Expected: no TypeScript errors.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/layout/AppLayout.tsx
git commit -m "feat(frontend): add Create Project button to landing page"
```

---

## Task 6: Manual smoke test

- [ ] **Step 1: Start the app**

```bash
./run.sh
```

- [ ] **Step 2: Verify the happy path**

1. Open http://localhost:3000 with no projects open.
2. Type a new, non-existent path (e.g. `/tmp/my-test-dataset`) into the path input.
3. Click "Create Project".
4. Confirm: toast says "Created my-test-dataset", app transitions to Browse with "0 items".
5. Confirm the directory was created: `ls /tmp/my-test-dataset` in a terminal.

- [ ] **Step 3: Verify the error path — path already exists**

1. With the app still running, go back to the landing page (close the project or open a new tab).
2. Type the same path (`/tmp/my-test-dataset`) and click "Create Project".
3. Confirm: toast shows "Path already exists".

- [ ] **Step 4: Verify Open Project still works normally**

1. Type an existing dataset path and click "Open Project".
2. Confirm it opens as before.

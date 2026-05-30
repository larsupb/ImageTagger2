# Create Project Feature — Design Spec

**Date:** 2026-05-30

## Overview

Add a "Create Project" button to the landing page that creates a new empty directory on disk and immediately opens it as a project. This lets users start a fresh dataset without leaving the app.

## User Flow

1. User is on the landing page (no open projects).
2. User types the desired new folder path into the existing path input.
3. User clicks "Create Project".
4. The folder is created and opened; the app transitions to the Browse page with an empty dataset (0 items).
5. On error (path already exists, parent missing, permission denied), a toast error is shown with the backend's message.

## Backend

**New endpoint:** `POST /api/projects/create`

**Request model:** `{ path: str }` — no `only_missing_captions` or `include_subdirectories` flags since the folder is guaranteed empty.

**Logic:**
1. Resolve absolute path.
2. Call `os.makedirs(path, exist_ok=False)`. Raise `409` if the path already exists, `400` for invalid path or missing parent, propagate OS permission errors as `403`.
3. Delegate to the existing `open_project` internals: create registry entry, create session, call `load_dataset`, apply effective settings.
4. Return `ProjectOpenResponse` (same model as `POST /api/projects/open`).

No new response model needed.

## Frontend

Three small changes, no new files:

**`src/lib/api.ts`**
- Add `createProject(path: string)` method calling `POST /api/projects/create` with `{ path }`, returning `ProjectOpenResponse`.
- Unlike the existing `openProject` method which throws a generic string, `createProject` must extract `body.detail` from the error response so that specific backend messages ("Path already exists", etc.) reach the toast.

**`src/stores/projectStore.ts`**
- Add `createProject(path: string)` action with identical logic to `openProject`: calls `api.createProject`, registers session in store, sets `activeProjectId`.

**`src/components/layout/AppLayout.tsx`**
- Add `handleCreateProject` handler (same shape as `handleOpenProject`, calls `store.createProject`).
- Add "Create Project" button next to the existing "Open Project" button, sharing the same `path` state input.
- Both buttons are in a `flex` row; "Open Project" is primary (filled blue, existing style); "Create Project" is secondary (outlined, green-tinted — `variant="secondary"` or equivalent).

## Button Layout

```
[ path input                        ]
[ Open Project ]  [ Create Project ]
```

- Open Project: primary button (filled blue) — existing style, no change.
- Create Project: secondary button (outlined green) — signals "new/create", lower visual weight than Open since it is the less frequent action.

## Error Handling

All errors surface via `toast.error` using the message from the backend `HTTPException`. Key cases:

| Condition | HTTP status | Toast message |
|---|---|---|
| Path already exists | 409 | "Path already exists" |
| Parent directory missing | 400 | "Parent directory does not exist" |
| Permission denied | 403 | "Permission denied" |
| No path typed | — | (guarded client-side, button disabled or no-op) |

## What Is Not In Scope

- Copying or moving existing images into the new folder.
- Naming the project separately from the folder name (the folder name becomes the project name, consistent with existing behaviour).
- Any changes to the settings or configuration pages.

# Export Page — Caption Type Selector

## Context

The backend stores multiple caption types per image in `metadata.db`. The existing export feature reads captions from sidecar `.txt` files (`item.caption_path`), which only contain the legacy single-caption format. A new `caption_type` parameter will be added so the export reads from the DB instead, picking the correct caption type.

## UI

Add a third `OperationCard` to `ExportForm.tsx`, placed below Format and above Bucket Resize:

```
[✓] [icon] Caption Type
          Select which caption type to export
          [ Select ▾ ]
```

- Always checked (no toggle, same as the Format card)
- `Select` dropdown populated with available caption types
- Default selection: the currently active caption type from the first image's `captions` array
- If no captions exist: disabled select with placeholder "No caption types available"

## Backend Changes

### ExportRequest schema (`app/models/schemas.py`)
Add `caption_type: str = "tags"` to `ExportRequest`.

### ExportOptions class (`app/services/export_service.py`)
Add `caption_type: str = "tags"` to `ExportOptions.__init__`.

### export_dataset function (`app/services/export_service.py`)
Change caption reading from sidecar file read to `caption_service.read_caption(session, index, caption_type)`. Pass `session` to the function.

### export router (`app/routers/export.py`)
- Change `export_dataset` signature to accept `session` (already available via dependency)
- Pass `req.caption_type` to `ExportOptions`

## Frontend Changes

### ExportForm (`frontend/src/components/export/ExportForm.tsx`)
1. Add state: `captionType: string`
2. Add `useQuery` to fetch available caption types from `/api/captions/types` (returns `string[]`)
3. Add `useQuery` to fetch the first image's `captions` array (e.g. from `/api/dataset/navigation?index=0`) to determine the active caption type for defaulting
4. Add a new `OperationCard` rendering the caption type `Select`
5. Pass `caption_type` in the `api.startExportTask({ ... })` call

### API client (`frontend/src/lib/api.ts`)
Update `startExportTask` to accept and forward `caption_type: string`.

### Types (`frontend/src/lib/types.ts`)
No new types needed.

## Error Handling

- If the selected caption type has no content for a given image: write an empty `.txt` file
- If the captions endpoint returns an error: show toast error, disable export button
- If no caption types exist: disable the select, show "No caption types available"

## Files to Change

| File | Change |
|------|--------|
| `backend/app/models/schemas.py` | Add `caption_type` to `ExportRequest` |
| `backend/app/services/export_service.py` | Add `caption_type` to `ExportOptions`, use `caption_service.read_caption()` instead of sidecar file read |
| `backend/app/routers/export.py` | Pass `caption_type` to `ExportOptions`, ensure `session` is accessible |
| `frontend/src/components/export/ExportForm.tsx` | Add caption type card, state, queries |
| `frontend/src/lib/api.ts` | Forward `caption_type` in `startExportTask` |
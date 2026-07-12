# Browse "Caption selected" Context-Menu Entry

## Summary

Add a "Caption selected" entry to the browse-page image context menu that
batch-captions the currently selected images. It mirrors the existing "Upscale
selected" submenu: the user picks a tagger from a submenu, and every selected
image is captioned with that tagger. The generated caption is written into the
session's active tag type.

## Motivation

Batch upscaling is already available from the browse-page context menu. Batch
captioning currently requires going image-by-image on the edit page. This gives
the user a one-action way to caption a whole selection with a chosen tagger,
matching the interaction they already know from "Upscale selected".

## Scope

Frontend-only, browse page only. No backend changes, no new API-client methods.
Reuses existing endpoints: `api.getTaggers()`, `api.generateCaption()`,
`api.saveCaption()`, `api.getSessionSettings()`.

## UI

- Add a `ContextMenuSub` in `frontend/src/components/browse/GalleryGrid.tsx`,
  immediately after the "Upscale selected" submenu (currently ends line 240) and
  before the `ContextMenuSeparator` at line 241.
- Sub-trigger: label "Caption selected" with a `MessageSquare` (lucide) icon,
  `disabled={selectedCount < 1}` — same disabled rule as "Upscale selected".
- Sub-content: lists `taggers`. When `taggers.length === 0`, render a single
  disabled item "No taggers available" (mirrors the upscaler empty state).
  Otherwise map each tagger to a `ContextMenuItem` keyed by `tagger.id`, showing
  `tagger.name`, whose `onClick` calls `onContextMenuCaption(tagger.id)`.

## State & Data

In the `GalleryGrid` component:

- Fetch taggers: `useQuery({ queryKey: ["taggers"], queryFn: () => api.getTaggers() })`.
  The endpoint returns `{ taggers: Tagger[]; default_tagger: string }`; use
  `data?.taggers ?? []`.
- Fetch session settings for the active tag type:
  `useQuery({ queryKey: ["sessionSettings"], queryFn: () => api.getSessionSettings() })`,
  returning `{ active_tag_type: string | null }`.
- `captionTypes` (from `api.getCaptionTypes()`) already exists in this component
  from the preview tag-type-selector feature; reuse it for the fallback.

Target tag-type resolution when captioning:

```
activeTagType = sessionSettings?.active_tag_type ?? captionTypes[0] ?? "tags"
```

The `"tags"` final fallback matches `api.saveCaption`'s default caption type.

## Behavior

Add a `handleContextMenuCaption` callback modeled on the existing
`handleContextMenuUpscale` (currently lines 913-937):

1. `const indices = Array.from(selectedIndices); if (indices.length === 0) return;`
2. Resolve `targetType` as above.
3. `const toastId = toast.loading(\`Captioning 0/${indices.length}...\`)`.
4. Loop sequentially over `indices`:
   - `const { caption } = await api.generateCaption(idx, tagger);`
   - `await api.saveCaption(idx, caption, targetType);`
   - increment `done`, update the loading toast `Captioning ${done}/${indices.length}...`.
5. On success: `toast.success(\`Captioned ${done} image...\`, { id: toastId })`.
6. On error: `toast.error(\`Captioning failed after ${done}/${indices.length}: ...\`, { id: toastId })`.
7. `finally`: `queryClient.invalidateQueries({ queryKey: ["gallery"] })` so
   caption badges refresh.

Captioning is sequential (one image at a time), matching the upscale flow — VLM
taggers are slow and this keeps load predictable.

## Prop Threading

`GalleryItemCard` renders the context menu but receives its data via props
drilled through `CategorySection`, exactly like `upscalers` and
`onContextMenuUpscale` today. Add two new props following the same path:

- `taggers: Tagger[]`
- `onContextMenuCaption: (tagger: string) => void`

Thread them: `GalleryGrid` → `CategorySection` (add to its props type and its
`GalleryItemCard` render) → `GalleryItemCard` (add to its props type and use in
the submenu). Pass `taggers` and `handleContextMenuCaption` from `GalleryGrid`
wherever `upscalers` and `handleContextMenuUpscale` are already passed.

## Non-Goals (YAGNI)

- No per-run tag-type picker — always writes to the resolved active tag type.
- No parallel captioning.
- No "only missing captions" filter.
- No new backend endpoints or API-client methods.
- No changes to the edit page or the batch page.

## Testing

No frontend test framework is configured (see CLAUDE.md). Manual verification:

1. Open a project, select several images on the browse page.
2. Right-click a selected image; confirm "Caption selected" appears below
   "Upscale selected" and lists the taggers.
3. Confirm it is disabled when nothing is selected.
4. Pick a fast tagger (e.g. WD14); confirm the progress toast counts up and a
   success toast appears.
5. Confirm captions were written into the active tag type (check on the edit
   page) and caption badges refresh in the gallery.
6. Verify with `npx tsc --noEmit` (no new errors in `GalleryGrid.tsx`) and
   `npm run build`.

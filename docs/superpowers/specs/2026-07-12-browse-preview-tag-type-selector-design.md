# Browse Preview Tag-Type Selector

## Summary

On the browse page, add a dropdown next to the "{total} images" count text that
lets the user choose which caption (tag) type is shown in the hover/click image
preview overlay. Currently the preview always shows `captions[0]` regardless of
type.

## Motivation

Images carry captions of multiple types (e.g. `tags`, a VLM description, etc.).
When previewing an image on the browse page, the user cannot control which
caption type they see — it is hard-coded to the first caption in the list. This
feature gives them a per-project selector to pick the type they care about.

## Scope

Display-only, browse page only. No backend changes. No changes to the edit-page
caption editing flow.

## UI

- Add a small shadcn `Select` immediately after the `{total} images` span in
  `frontend/src/components/browse/GalleryGrid.tsx` (currently line 971), inside
  the existing left-hand flex group.
- Size it to match surrounding controls (`text-sm`, `h-7`).
- Options are the caption types returned by `api.getCaptionTypes()`.
- Render the selector only when `captionTypes.length > 0`.

## State & Data

- Fetch caption types with `useQuery(["captionTypes"], () => api.getCaptionTypes())`
  in `GalleryGrid` (same call used by `ExportForm`).
- Hold the selected type in `GalleryGrid` state: `previewCaptionType`.
- **Persistence (per project):** read/write
  `localStorage["browse:previewCaptionType:<projectId>"]`.
- **Initial value resolution** on mount / when data is available:
  1. Stored localStorage value for the active project, if present and still a
     valid caption type.
  2. Else the `is_active` caption type from `api.getItem(0)` (the pattern
     `ExportForm` uses to pick a sensible default).
  3. Else `captionTypes[0]`.
- Writing the selection updates both React state and localStorage.

## Preview Behavior

- Pass `captionType={previewCaptionType}` into the `ImagePreview` component.
- In `ImagePreview`'s existing effect (currently lines 631-636), pick the caption
  whose `caption_type === captionType` instead of `captions[0]`.
- If that type is absent for the image, or its content is blank, call
  `setCaption(null)` — the overlay then shows nothing, matching the current
  empty-caption handling.

## Non-Goals (YAGNI)

- No backend/API changes; reuse existing endpoints.
- No placeholder text or cross-type fallback when the selected type is empty —
  the overlay simply shows nothing.
- No global (cross-project) persistence.
- No changes to the edit page or its caption-type selector.

## Testing

No test framework is configured in this repo yet. Manual verification:

1. Open a project with images that have multiple caption types.
2. Confirm the dropdown appears next to the image count and lists the caption
   types.
3. Select a type, hover/click an image, and confirm the overlay shows that
   type's content.
4. Preview an image lacking the selected type; confirm no overlay text appears.
5. Reload the page; confirm the selection persists for that project.
6. Switch to a different project; confirm the selection is independent.

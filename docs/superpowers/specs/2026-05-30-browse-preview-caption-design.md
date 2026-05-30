# Browse Page: Image Preview Caption

**Date:** 2026-05-30
**Status:** Approved

## Summary

When a user clicks a thumbnail on the Browse page, a large `ImagePreview` popup appears. This spec adds a photo caption bar at the bottom of that popup showing the image's first available caption.

## Context

`GalleryItem` (the type used in the gallery grid) carries only `has_caption: boolean` — no caption text. Full caption data lives on `MediaItem`, returned by `GET /api/dataset/item/{index}`, which includes a `captions: CaptionEntry[]` array. Each `CaptionEntry` has `caption_type`, `content`, and `is_active`. There is no primary caption type concept yet; the first entry in the array is used for now.

## Design

### Data Fetching

`ImagePreview` gains a `useEffect` that calls `api.getItem(item.index)` on mount. The result is stored in local state as `caption: string | null`, initialized to `null`.

Caption selection: `captions[0]?.content ?? null`. If the array is empty or the first entry has no content, nothing is shown.

No loading spinner — the caption bar simply appears once the fetch resolves. The fetch is fast (local API) and the image itself loads in parallel, so the slight delay is not disruptive.

### Rendering

A caption bar is appended inside the preview panel `<div>`, below the `<img>`:

- Only rendered when `caption` is non-null and non-empty
- Styling: `bg-black/70 px-3 py-2 text-sm text-white leading-snug`
- Multi-line wrapping allowed — no truncation, no max-height
- The preview panel already has `maxWidth: 800, maxHeight: 800` constraints, so the image size naturally bounds the overall panel height

### Component Scope

All changes are contained in the `ImagePreview` component (`GalleryGrid.tsx`, lines 556–591). No changes to:
- Parent components (`GalleryGrid`, `CategorySection`, `GalleryThumbnail`)
- Backend API
- Type definitions
- Query keys or cache

## Non-goals

- Choosing a "primary" caption type — deferred
- Editing the caption from the preview
- Showing multiple caption types
- Truncation or scrollable caption area

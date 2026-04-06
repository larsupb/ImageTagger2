# Caption Type Selector Design Spec

## Context

The backend now stores multiple caption types per image (tags, natural_language, danbooru, custom) in `metadata.db`. The `MediaItem` API response already includes a `captions: CaptionEntry[]` array. The frontend currently ignores this array and only uses the single `caption: string` field. This spec adds a type selector to the `CaptionEditor` so users can view, edit, and create caption types per image.

## UI Layout

Option B was chosen: caption type dropdown inline in the existing toolbar row, leftmost position.

```
[type dropdown ▾] ──────────── [tagger dropdown ▾] [Generate] [Save Caption]
```

The caption type dropdown uses the existing `Select` component (same as the tagger selector). At the bottom of the dropdown options, a divider separates a special `"+ New type…"` item.

## CaptionEditor Component Changes

**New prop:** `captions: CaptionEntry[]`

**New internal state:**
- `activeType: string` — initialized from the `is_active: true` entry in the `captions` array; falls back to `"tags"` if none is active

**Textarea content** is driven by `activeType`. When the component mounts or `captions` prop changes, `text` is set to the content of the active type's entry (or `""` if not found).

**Type switching:**
1. If `text !== savedText` (dirty), auto-save current content: `api.saveCaption(index, text, activeType)`
2. Set `activeType` to the selected type
3. Set `text` to the new type's content from `captions` prop (or `""` if no entry exists yet)
4. Notify parent via `onCaptionChange(newText)` so the edit page stays in sync

**Saving:** `api.saveCaption(index, text, activeType)` — `activeType` is passed explicitly. The `onCaptionChange(text)` callback fires after save. The edit page re-fetches the item to refresh the `captions` array.

**Dirty tracking:** unchanged — `text !== savedCaption` where `savedCaption` is the last saved/confirmed value for the currently active type.

## "New Type" Flow

Selecting `"+ New type…"` from the dropdown opens a `Popover` anchored to the dropdown trigger containing:
- A text `Input` for the type name
- A "Create" confirm button (disabled if input is empty)

On confirm:
- Close popover
- Switch `activeType` to the new name
- Set `text` to `""`
- The new type is **not** persisted until the user saves — no API call on creation

The new type name appears in the dropdown immediately, derived from component state merged with the `captions` prop.

## Edit Page Changes (`edit/page.tsx`)

- Pass `captions={currentItem.captions ?? []}` to `CaptionEditor`
- After any caption save, re-fetch `api.getItem(index)` to refresh `currentItem` (including updated `captions` array) so the dropdown reflects newly created types

## Scope

- Dataset-local: caption types exist only within the current dataset's DB
- No global type registry
- No changes to the captions bulk-operations page (tag cloud, search-replace, etc.) — those continue operating on `caption_type="tags"` by default

## Files to Change

| File | Change |
|------|--------|
| `frontend/src/components/edit/CaptionEditor.tsx` | Add `captions` prop, type dropdown, new-type popover, auto-save on switch |
| `frontend/src/app/edit/page.tsx` | Pass `captions` prop, re-fetch item after save |

## Verification

1. Open a dataset with existing `.txt` captions — type dropdown shows `"tags"` as the only option
2. Switch to a different type (e.g. add a `natural_language` caption via curl) — dropdown shows both, switching loads correct content
3. Select `"+ New type…"`, type `"danbooru"`, confirm — textarea empties, saves correctly with `caption_type="danbooru"`
4. Edit a caption while dirty, switch type — content auto-saves before switching
5. New type persists after navigating to next image and back

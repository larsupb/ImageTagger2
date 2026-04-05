# Design: Caption Dirty Navigation Guard

## Purpose

Prevent accidental loss of unsaved caption edits when the user navigates away from the current image on the Edit page.

## Trigger

Dirty state = `textarea text !== saved caption (currentItem.caption)`. This means the caption differs from what's currently stored server-side, not from the original caption when the image was first loaded.

## Architecture

### CaptionEditor.tsx

- Add `savedCaption: string` prop — the caption as last saved (from `currentItem.caption`)
- Add `onDirtyChange?: (dirty: boolean) =>` callback
- Add `getUnsavedText?: () => string` callback — returns current textarea text (so EditPage can save it without lifting state)
- Compute dirty via `useEffect` on `[text, savedCaption]`, calls callback when dirty state changes
- When dirty: "Save Caption" button switches to `variant="default"` with blue accent (primary action style)
- When clean: "Save Caption" button stays `variant="secondary"`

### edit/page.tsx

- Track `captionDirty` in `useState(false)`
- Wrap `loadItem` with `handleNavigate(index)` that checks dirty first:
  - If not dirty: call `loadItem(index)` directly
  - If dirty: open ConfirmDialog with 3 options
- ConfirmDialog content:
  - Title: "Unsaved Caption Changes"
  - Message: "The caption for this image has been modified. What would you like to do?"
  - Actions: **Save & Go** (primary), **Discard** (destructive), **Cancel** (secondary)
  - On Save: call `api.saveCaption(index, text)`, then `loadItem(index)`, then close dialog
  - On Discard: call `loadItem(index)`, then close dialog
  - On Cancel: close dialog, stay on current image
- Add `beforeunload` listener for browser/tab close — sets `e.returnValue` when dirty
- Store a ref to `getUnsavedText` from CaptionEditor to retrieve current text for saving
- Pass `savedCaption={currentItem.caption}`, `onDirtyChange`, and `getUnsavedText` to CaptionEditor

### ConfirmDialog

The existing ConfirmDialog supports onConfirm/onCancel with a single confirm action. We need 3 actions. Options:
- Extend ConfirmDialog to support a `secondaryAction` prop (label + handler + variant)
- Or inline a small Dialog with 3 buttons directly in EditPage

**Decision**: Inline a Dialog in EditPage. The 3-action pattern is specific enough that extending ConfirmDialog would add complexity for a single use case. We'll use shadcn Dialog primitives directly.

## Navigation Coverage

| Trigger | Guarded? | Mechanism |
|---------|----------|-----------|
| Prev/Next buttons (NavigationBar) | Yes | `handleNavigate` wrapper |
| Range slider (NavigationBar) | Yes | `handleNavigate` wrapper |
| Keyboard arrows | Yes | `handleNavigate` wrapper |
| Tab/window close | Yes | `beforeunload` event |
| Sidebar nav (route change) | No | SPA limitation — known trade-off |
| ImageToolbar actions (delete, rename, etc.) | No | These refresh in-place, don't navigate |

## Data Flow

```
CaptionEditor (text state)
  └─ useEffect([text, savedCaption]) → onDirtyChange(dirty)
       └─ EditPage (captionDirty state)
            ├─ handleNavigate(index) checks dirty
            │    ├─ dirty → open 3-action dialog
            │    └─ clean → loadItem(index)
            └─ beforeunload sets e.returnValue if dirty
```

## Visual: Save Button Highlight

- Clean state: `variant="secondary"` (muted/gray)
- Dirty state: `variant="default"` (blue/primary) — visually signals "you should save"
- The button is already the right component; only the variant prop changes based on `dirty`

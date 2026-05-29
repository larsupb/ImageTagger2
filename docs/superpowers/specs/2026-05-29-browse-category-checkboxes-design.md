# Browse Page — Category Checkboxes

**Date:** 2026-05-29  
**Branch:** feature/export-category-filter  
**Status:** Approved

## Overview

Add a checkbox to the left of each category expander header on the Browse page. Checking selects all images in that category; unchecking deselects all images in that category. An indeterminate state is shown when only some images in the category are selected.

## Scope

- `frontend/src/components/ui/checkbox.tsx` — extend with indeterminate support
- `frontend/src/components/browse/GalleryGrid.tsx` — restructure `CategorySection` header and add selection handler in `GalleryGrid`

No backend changes. No new state beyond what already exists (`selectedIndices: Set<number>`).

## Checkbox Component Extension

**File:** `frontend/src/components/ui/checkbox.tsx`

Add an `indeterminate` prop to the `Checkbox` wrapper. Pass it through to `CheckboxPrimitive.Root` (base-ui supports this natively; it sets `data-indeterminate` on the element and treats the checked value as `"mixed"`). Inside `CheckboxPrimitive.Indicator`, render a `Minus` icon (from lucide-react) when `indeterminate` is true, and the existing `CheckIcon` otherwise.

The prop type is `boolean | undefined`; it is optional and defaults to `false`.

## CategorySection Header Restructure

**Current:** A single `<button>` containing `[ChevronRight] [name] [count] [line]`.

**New:** A flex row with two independent interactive elements:

```
[ Checkbox ]  [ ChevronRight  Name  Count  ─────── ]
               ↑ existing collapse button, unchanged
```

- The `Checkbox` is a sibling of the collapse button, not nested inside it — no accessibility violation.
- The checkbox is only rendered when `showHeader` is `true` (i.e., when categories exist in the dataset).
- Clicking the checkbox calls `onSelectCategory(select: boolean)`. It does **not** toggle the collapse state.

Two new props added to `CategorySection`:

| Prop | Type | Description |
|---|---|---|
| `categoryCheckState` | `'checked' \| 'indeterminate' \| 'unchecked'` | Drives checkbox visual state |
| `onSelectCategory` | `(select: boolean) => void` | Called when checkbox is clicked |

### Checkbox state derivation

Computed in `GalleryGrid` per category at render time (no new `useState`):

- All items selected → `'checked'`
- No items selected → `'unchecked'`
- Some items selected → `'indeterminate'`

## GalleryGrid Handler

A new `handleSelectCategory(items: GalleryItem[], select: boolean)` callback:

- `select = true`: adds all `item.index` values from `items` into `selectedIndices` (merged with any existing selection from other categories)
- `select = false`: removes all `item.index` values from `items` from `selectedIndices`

The handler is memoized with `useCallback` and depends on `setSelectedIndices`.

## Toggle Behavior

| Current state | User action | Result |
|---|---|---|
| Unchecked | Click | All items in category added to selection |
| Indeterminate | Click | All items in category added to selection |
| Checked | Click | All items in category removed from selection |

## What Is Not Changing

- The collapse/expand behavior of the category header is unchanged.
- Individual image selection (Ctrl+click, shift-click) continues to work and will update the category checkbox state reactively.
- The "Select all" / "Deselect all" global buttons remain unchanged.
- No backend API changes.

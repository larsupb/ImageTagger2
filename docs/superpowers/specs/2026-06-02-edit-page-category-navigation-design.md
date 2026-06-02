# Edit Page Category-Aware Navigation

**Date:** 2026-06-02  
**Status:** Approved

## Problem

When the user clicks Edit on an image in the Browse gallery, the Edit page navigates through all images by absolute index. The user expects navigation to stay within the same category as the image they opened.

## Decision

Navigation context is derived from the **current item's category** (not from any Browse filter state). If image X belongs to category "Portraits", Edit always navigates through Portraits — regardless of what the Browse page was showing when the user clicked Edit.

Uncategorized items (`category === null`) form their own navigation context.

## Architecture

### What changes

**`src/app/edit/page.tsx`**

- Add `useQuery` with key `["gallery", "all", total]` and `enabled: !!datasetInfo` to read the gallery cache.
- Derive `navItems: { index: number }[]` by filtering gallery items to those whose `category` strictly equals `currentItem.category`, sorted by index.
- Fallback: if gallery data is absent (cold cache / direct deep-link), `navItems` is the full range `[0, 1, ..., total-1]` mapped to `{ index }` objects — preserving current behavior.
- Derive `positionInNav`, `prevIndex`, `nextIndex` from `navItems` and `currentIndex`.
- Update keyboard arrow-key handler to use `prevIndex` / `nextIndex` instead of `currentIndex ± 1`.
- Pass `navItems` as a new prop to `NavigationBar`.

**`src/components/edit/NavigationBar.tsx`**

- Add `navItems: { index: number }[]` to `NavigationBarProps`.
- Derive `positionInNav = navItems.findIndex(i => i.index === currentIndex)`.
- **Prev button**: disabled when `positionInNav <= 0`; calls `onNavigate(navItems[positionInNav - 1].index)`.
- **Next button**: disabled when `positionInNav >= navItems.length - 1`; calls `onNavigate(navItems[positionInNav + 1].index)`.
- **Slider**: `min=0`, `max=navItems.length - 1`, `value=positionInNav`; `onChange` maps slider value `v` → `onNavigate(navItems[v].index)`.
- **Counter**: displays `positionInNav + 1 / navItems.length`.

### What does not change

- `loadItem(index)` — still takes an absolute index and fetches from the backend unchanged.
- `currentIndex` in the session store — remains an absolute index throughout.
- Session store schema — no new fields.
- Backend — no new endpoints.
- Browse page — unaffected.

## Data Flow

```
Browse (warm cache: ["gallery", "all", total])
  → user clicks Edit on item at absolute index I, category C
  → router.push("/edit")

Edit page
  → reads gallery cache (no network request, cache is warm)
  → filters: navItems = galleryItems.filter(i => i.category === C).sort(by index)
  → positionInNav = navItems.findIndex(i => i.index === currentIndex)
  → passes navItems to NavigationBar
  → keyboard/slider/buttons navigate within navItems
  → loadItem(navItems[pos].index) fetches by absolute index as before
```

## Fallback Behavior

If the gallery query data is not in cache (user deep-linked directly to `/edit`):

- `navItems` = `Array.from({ length: total }, (_, i) => ({ index: i }))`
- Navigation behaves identically to the current implementation (all items, sequential).

## Constraints

- No backend changes.
- No session store schema changes.
- No changes to any page other than Edit.
- The `useQuery` call on Edit page uses `staleTime: Infinity` to avoid triggering a refetch when the cache is already populated.

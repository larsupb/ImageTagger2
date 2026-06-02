# Edit Page Category-Aware Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Edit page navigate prev/next within the current item's category instead of across all items globally.

**Architecture:** `EditPage` reads the gallery cache (already populated by Browse) via `useQuery`, filters to the current item's category to build a `navItems` list, and passes it to `NavigationBar`. `NavigationBar` maps slider/buttons through `navItems` indices instead of raw absolute indices.

**Tech Stack:** Next.js 15, React 19, TypeScript, @tanstack/react-query, Zustand

---

## File Map

| File | Change |
|---|---|
| `frontend/src/app/edit/page.tsx` | Add gallery `useQuery`, derive `navItems`, update keyboard handler, pass prop to `NavigationBar` |
| `frontend/src/components/edit/NavigationBar.tsx` | Accept `navItems` prop, rewrite slider/buttons/counter to navigate within it |

No other files change. No backend changes. No session store schema changes.

---

### Task 1: Derive `navItems` in EditPage and update keyboard navigation

**Files:**
- Modify: `frontend/src/app/edit/page.tsx`

- [ ] **Step 1: Add `useQuery` and `useMemo` imports**

In `frontend/src/app/edit/page.tsx`, the import on line 3 currently reads:
```typescript
import { useEffect, useCallback, useState, useRef } from "react";
```
Change it to:
```typescript
import { useEffect, useCallback, useState, useRef, useMemo } from "react";
```

The import on line 4 currently reads:
```typescript
import { useQueryClient } from "@tanstack/react-query";
```
Change it to:
```typescript
import { useQuery, useQueryClient } from "@tanstack/react-query";
```

- [ ] **Step 2: Add the gallery query and `navItems` derivation**

After the line `const { currentIndex, currentItem, datasetInfo } = session ?? {};` (currently line 32), add:

```typescript
  const { data: galleryData } = useQuery({
    queryKey: ["gallery", "all", datasetInfo?.total_items ?? 0],
    queryFn: () => api.getGallery(0, datasetInfo!.total_items),
    enabled: !!datasetInfo && (datasetInfo.total_items > 0),
    staleTime: Infinity,
  });

  const navItems = useMemo<{ index: number }[]>(() => {
    if (!currentItem) return [];
    if (galleryData?.items) {
      return galleryData.items
        .filter((i) => i.category === currentItem.category)
        .sort((a, b) => a.index - b.index)
        .map((i) => ({ index: i.index }));
    }
    const total = datasetInfo?.total_items ?? 0;
    return Array.from({ length: total }, (_, i) => ({ index: i }));
  }, [galleryData?.items, currentItem, datasetInfo?.total_items]);

  const positionInNav = navItems.findIndex((i) => i.index === (currentIndex ?? 0));
```

- [ ] **Step 3: Update keyboard arrow-key handler**

Find the `useEffect` that adds the keyboard handler (currently lines 116–126). Replace it entirely with:

```typescript
  useEffect(() => {
    if (!activeProjectId) return;
    const handler = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLTextAreaElement || e.target instanceof HTMLInputElement) return;
      if (e.key === "ArrowLeft") {
        const prev = navItems[positionInNav - 1];
        if (prev) handleNavigate(prev.index);
      }
      if (e.key === "ArrowRight") {
        const next = navItems[positionInNav + 1];
        if (next) handleNavigate(next.index);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [navItems, positionInNav, handleNavigate, activeProjectId]);
```

- [ ] **Step 4: Pass `navItems` to `NavigationBar`**

Find the `<NavigationBar onNavigate={handleNavigate} />` line (currently line 203). Replace it with:

```tsx
      <NavigationBar onNavigate={handleNavigate} navItems={navItems} />
```

- [ ] **Step 5: Verify TypeScript compiles**

```bash
cd frontend && npm run build 2>&1 | tail -20
```

Expected: build succeeds (or only pre-existing errors, none new).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/app/edit/page.tsx
git commit -m "feat: derive category-scoped navItems in EditPage"
```

---

### Task 2: Update NavigationBar to use `navItems`

**Files:**
- Modify: `frontend/src/components/edit/NavigationBar.tsx`

- [ ] **Step 1: Add `navItems` to the props interface**

Replace the current interface (lines 10–12):
```typescript
interface NavigationBarProps {
  onNavigate: (index: number) => void;
}
```
With:
```typescript
interface NavigationBarProps {
  onNavigate: (index: number) => void;
  navItems: { index: number }[];
}
```

- [ ] **Step 2: Destructure `navItems` from props and remove `total` from session**

Replace the current function signature and session reads (lines 14–21):
```typescript
export default function NavigationBar({ onNavigate }: NavigationBarProps) {
  const activeProjectId = useProjectStore((s) => s.activeProjectId);
  const session = activeProjectId
    ? useSessionStore((s) => s.getProjectSession(activeProjectId))
    : null;
  const currentIndex = session?.currentIndex ?? 0;
  const currentItem = session?.currentItem;
  const datasetInfo = session?.datasetInfo;
  const total = datasetInfo?.total_items ?? 0;
```
With:
```typescript
export default function NavigationBar({ onNavigate, navItems }: NavigationBarProps) {
  const activeProjectId = useProjectStore((s) => s.activeProjectId);
  const session = activeProjectId
    ? useSessionStore((s) => s.getProjectSession(activeProjectId))
    : null;
  const currentIndex = session?.currentIndex ?? 0;
  const currentItem = session?.currentItem;

  const positionInNav = navItems.findIndex((i) => i.index === currentIndex);
  const safePosition = Math.max(0, positionInNav);
  const total = navItems.length;
```

- [ ] **Step 3: Rewrite the prev button**

Replace:
```tsx
      <Button
        variant="outline"
        size="icon"
        onClick={() => onNavigate(Math.max(0, currentIndex - 1))}
        disabled={currentIndex <= 0}
      >
        <ChevronLeft className="size-4" />
      </Button>
```
With:
```tsx
      <Button
        variant="outline"
        size="icon"
        onClick={() => {
          const prev = navItems[positionInNav - 1];
          if (prev) onNavigate(prev.index);
        }}
        disabled={positionInNav <= 0}
      >
        <ChevronLeft className="size-4" />
      </Button>
```

- [ ] **Step 4: Rewrite the slider**

Replace:
```tsx
      <input
        type="range"
        min={0}
        max={Math.max(0, total - 1)}
        value={currentIndex}
        onChange={(e) => onNavigate(Number(e.target.value))}
        className="flex-1 accent-bg-primary"
        style={{ accentColor: "var(--color-primary, #3b82f6)" }}
      />
```
With:
```tsx
      <input
        type="range"
        min={0}
        max={Math.max(0, total - 1)}
        value={safePosition}
        onChange={(e) => {
          const item = navItems[Number(e.target.value)];
          if (item) onNavigate(item.index);
        }}
        className="flex-1 accent-bg-primary"
        style={{ accentColor: "var(--color-primary, #3b82f6)" }}
      />
```

- [ ] **Step 5: Rewrite the counter**

Replace:
```tsx
      <span className="text-sm text-text-muted min-w-[80px] text-center">
        {currentIndex + 1} / {total}
      </span>
```
With:
```tsx
      <span className="text-sm text-text-muted min-w-[80px] text-center">
        {safePosition + 1} / {total}
      </span>
```

- [ ] **Step 6: Rewrite the next button**

Replace:
```tsx
      <Button
        variant="outline"
        size="icon"
        onClick={() => onNavigate(Math.min(total - 1, currentIndex + 1))}
        disabled={currentIndex >= total - 1}
      >
        <ChevronRight className="size-4" />
      </Button>
```
With:
```tsx
      <Button
        variant="outline"
        size="icon"
        onClick={() => {
          const next = navItems[positionInNav + 1];
          if (next) onNavigate(next.index);
        }}
        disabled={positionInNav >= total - 1}
      >
        <ChevronRight className="size-4" />
      </Button>
```

- [ ] **Step 7: Verify TypeScript compiles**

```bash
cd frontend && npm run build 2>&1 | tail -20
```

Expected: build succeeds with no new errors.

- [ ] **Step 8: Manual verification**

Start the dev server:
```bash
./run.sh
```

Open http://localhost:3000 and:
1. Open a project that has images in at least two categories.
2. Go to Browse — note which images are in category "A" and their absolute indices.
3. Click Edit on the first image in category "A".
4. Verify the counter shows e.g. "1 / 5" (position within category, not global position).
5. Press the Next button or ArrowRight — verify it jumps to the next image in category "A" (may not be absolute index + 1).
6. Press the Prev button or ArrowLeft — verify it returns to the previous image in category "A".
7. Drag the slider to the end — verify it lands on the last image in category "A", not the last global image.
8. Open Edit on an uncategorized image — verify the counter and navigation are scoped to uncategorized images only.
9. Open Edit directly (navigate to http://localhost:3000/edit without coming from Browse) — verify navigation falls back to all items sequentially with no crash.

- [ ] **Step 9: Commit**

```bash
git add frontend/src/components/edit/NavigationBar.tsx
git commit -m "feat: navigate within image category on Edit page"
```

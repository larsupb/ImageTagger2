# Browse Page — Category Checkboxes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-category checkboxes to the Browse page that select/deselect all images in a category, fix the broken Shift+Click range selection, and support an indeterminate state when a category is partially selected.

**Architecture:** Two files change — `checkbox.tsx` gets an `indeterminate` prop extension, and `GalleryGrid.tsx` gets a one-line bug fix, two new props on `CategorySection`, a new `handleSelectCategory` handler, and a header restructure that places a `Checkbox` beside the existing collapse button. No backend changes, no new state.

**Tech Stack:** Next.js 15, React 19, TypeScript, base-ui (`@base-ui/react/checkbox`), lucide-react, Tailwind CSS 4

---

## File Map

| File | Change |
|---|---|
| `frontend/src/components/ui/checkbox.tsx` | Add `indeterminate` prop; render `Minus` icon when set |
| `frontend/src/components/browse/GalleryGrid.tsx` | Fix Shift+Click gate; add `categoryCheckState` + `onSelectCategory` props to `CategorySection`; add `handleSelectCategory` in `GalleryGrid`; restructure `CategorySection` header |

---

## Task 1: Fix Shift+Click Range Selection Bug

**Files:**
- Modify: `frontend/src/components/browse/GalleryGrid.tsx` (line ~102)

- [ ] **Step 1: Open GalleryGrid.tsx and locate the onClick handler in GalleryThumbnail**

The handler is inside the `GalleryThumbnail` component, on the `<div role="button">` that wraps the thumbnail image. It currently reads:

```typescript
onClick={(e) => {
  if (e.ctrlKey || e.metaKey) {
    onToggleSelect(item.index, e.shiftKey);
  } else {
    onPreview(item, e.clientX, e.clientY);
  }
}}
```

- [ ] **Step 2: Add `|| e.shiftKey` to the condition**

Replace the `onClick` handler with:

```typescript
onClick={(e) => {
  if (e.ctrlKey || e.metaKey || e.shiftKey) {
    onToggleSelect(item.index, e.shiftKey);
  } else {
    onPreview(item, e.clientX, e.clientY);
  }
}}
```

- [ ] **Step 3: Verify manually**

1. Start the dev server: `cd frontend && npm run dev`
2. Open a project with multiple images in the Browse page
3. Ctrl+Click one image — it should become selected (blue ring)
4. Shift+Click another image — all images between the two should become selected
5. Plain Click an image (no modifier keys) — the image preview should open as before

- [ ] **Step 4: Commit**

```bash
git add frontend/src/components/browse/GalleryGrid.tsx
git commit -m "fix(browse): include shiftKey in thumbnail click selection gate"
```

---

## Task 2: Extend Checkbox Component with Indeterminate Support

**Files:**
- Modify: `frontend/src/components/ui/checkbox.tsx`

- [ ] **Step 1: Add Minus import**

The current imports in `checkbox.tsx`:

```typescript
import { CheckIcon } from "lucide-react"
```

Replace with:

```typescript
import { CheckIcon, Minus } from "lucide-react"
```

- [ ] **Step 2: Destructure `indeterminate` from props and update the component**

Replace the entire `Checkbox` function with:

```typescript
function Checkbox({ className, indeterminate, ...props }: CheckboxPrimitive.Root.Props) {
  return (
    <CheckboxPrimitive.Root
      data-slot="checkbox"
      indeterminate={indeterminate}
      className={cn(
        "peer relative flex size-4 shrink-0 items-center justify-center rounded-[4px] border border-input transition-colors outline-none group-has-disabled/field:opacity-50 after:absolute after:-inset-x-3 after:-inset-y-2 focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 aria-invalid:aria-checked:border-primary dark:bg-input/30 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40 data-checked:border-primary data-checked:bg-primary data-checked:text-primary-foreground dark:data-checked:bg-primary",
        className
      )}
      {...props}
    >
      <CheckboxPrimitive.Indicator
        data-slot="checkbox-indicator"
        className="grid place-content-center text-current transition-none [&>svg]:size-3.5"
      >
        {indeterminate ? <Minus /> : <CheckIcon />}
      </CheckboxPrimitive.Indicator>
    </CheckboxPrimitive.Root>
  )
}
```

- [ ] **Step 3: Verify TypeScript compiles cleanly**

```bash
cd frontend && npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/components/ui/checkbox.tsx
git commit -m "feat(ui): add indeterminate prop to Checkbox component"
```

---

## Task 3: Add Category Selection Handler and Props to GalleryGrid

**Files:**
- Modify: `frontend/src/components/browse/GalleryGrid.tsx`

This task adds:
- `categoryCheckState` and `onSelectCategory` to `CategorySection`'s prop types
- `handleSelectCategory` callback in `GalleryGrid`
- Per-category `categoryCheckState` computation in the render loop
- Wires both into the existing `CategorySection` JSX

- [ ] **Step 1: Add two new props to the CategorySection props interface**

Find the `CategorySection` function signature (around line 196). The props destructuring currently ends with `onContextMenuAssign`. Add two new props:

```typescript
function CategorySection({
  name,
  items,
  showHeader,
  collapsed,
  onToggleCollapse,
  selectedIndices,
  thumbDeleteState,
  categories,
  onToggleSelect,
  onPreview,
  onEdit,
  onDelete,
  onCategoryDrop,
  onContextMenuAssign,
  categoryCheckState,
  onSelectCategory,
}: {
  name: string | null;
  items: GalleryItem[];
  showHeader: boolean;
  collapsed: boolean;
  onToggleCollapse: () => void;
  selectedIndices: Set<number>;
  thumbDeleteState: { v: number; fromIndex: number } | null;
  categories: string[];
  onToggleSelect: (index: number, shiftKey: boolean) => void;
  onPreview: (item: GalleryItem, x: number, y: number) => void;
  onEdit: (item: GalleryItem) => void;
  onDelete: (item: GalleryItem) => void;
  onCategoryDrop: (index: number, category: string | null) => void;
  onContextMenuAssign: (itemIndex: number, category: string | null) => void;
  categoryCheckState: 'checked' | 'indeterminate' | 'unchecked';
  onSelectCategory: (select: boolean) => void;
}) {
```

- [ ] **Step 2: Add handleSelectCategory to GalleryGrid**

In `GalleryGrid`, after the existing `clearSelection` callback (around line 632), add:

```typescript
const handleSelectCategory = useCallback((items: GalleryItem[], select: boolean) => {
  setSelectedIndices((prev) => {
    const next = new Set(prev);
    if (select) {
      for (const item of items) next.add(item.index);
    } else {
      for (const item of items) next.delete(item.index);
    }
    return next;
  });
}, []);
```

- [ ] **Step 3: Compute categoryCheckState and wire props in the render loop**

Find the `grouped.map` block in `GalleryGrid`'s return (around line 810). Replace it with:

```typescript
{grouped.map(([category, items]) => {
  const categoryKey = category ?? "__uncategorized__";
  const selectedCount = items.filter((item) => selectedIndices.has(item.index)).length;
  const categoryCheckState =
    selectedCount === 0
      ? 'unchecked'
      : selectedCount === items.length
      ? 'checked'
      : 'indeterminate';
  return (
    <CategorySection
      key={categoryKey}
      name={category}
      items={items}
      showHeader={hasCategories}
      collapsed={hasCategories && collapsedCategories.has(categoryKey)}
      onToggleCollapse={() => handleToggleCollapse(categoryKey)}
      selectedIndices={selectedIndices}
      thumbDeleteState={thumbDeleteRef.current}
      categories={categoryNames}
      onToggleSelect={toggleSelect}
      onPreview={handlePreview}
      onEdit={handleEdit}
      onDelete={setPendingDeleteItem}
      onCategoryDrop={handleCategoryDrop}
      onContextMenuAssign={handleContextMenuAssign}
      categoryCheckState={categoryCheckState}
      onSelectCategory={(select) => handleSelectCategory(items, select)}
    />
  );
})}
```

- [ ] **Step 4: Verify TypeScript compiles cleanly**

```bash
cd frontend && npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/browse/GalleryGrid.tsx
git commit -m "feat(browse): add category selection handler and props to CategorySection"
```

---

## Task 4: Restructure CategorySection Header with Checkbox

**Files:**
- Modify: `frontend/src/components/browse/GalleryGrid.tsx`
- Uses: `frontend/src/components/ui/checkbox.tsx` (already extended in Task 2)

- [ ] **Step 1: Add Checkbox import to GalleryGrid.tsx**

Find the existing import block at the top of `GalleryGrid.tsx`. Add `Checkbox` to the UI component imports:

```typescript
import { Checkbox } from "@/components/ui/checkbox";
```

- [ ] **Step 2: Replace the CategorySection header button with a split layout**

Find the `{showHeader && (...)}` block inside `CategorySection` (currently a single `<button>`). Replace it with:

```typescript
{showHeader && (
  <div className="flex items-center gap-2 mb-3">
    <Checkbox
      checked={categoryCheckState === 'checked'}
      indeterminate={categoryCheckState === 'indeterminate'}
      onCheckedChange={() => onSelectCategory(categoryCheckState !== 'checked')}
      onClick={(e: React.MouseEvent) => e.stopPropagation()}
    />
    <button
      className="flex items-center gap-2 w-full text-left group/header"
      onClick={onToggleCollapse}
    >
      <ChevronRight
        className={`w-3.5 h-3.5 text-text-secondary transition-transform duration-150 ${
          collapsed ? "" : "rotate-90"
        }`}
      />
      <h2 className="text-sm font-semibold text-text group-hover/header:text-text-secondary transition-colors">
        {name ?? "Uncategorized"}
      </h2>
      <span className="text-xs text-text-secondary">{items.length}</span>
      <div className="flex-1 h-px bg-border" />
    </button>
  </div>
)}
```

- [ ] **Step 3: Verify TypeScript compiles cleanly**

```bash
cd frontend && npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 4: Manual verification**

1. Open the Browse page with a project that has multiple categories
2. Confirm each category header now shows a checkbox to the left of the chevron
3. Check that clicking the chevron/name still collapses/expands the category
4. Check that clicking the checkbox (with no images selected) selects all images in that category (blue ring on all thumbs)
5. Check that the checkbox shows indeterminate (minus icon) when some — but not all — images in the category are individually selected
6. Check that clicking a checked (all-selected) category checkbox deselects all images in that category
7. Check that selecting a category does not affect selection in other categories
8. Check that the "Select all" / "Deselect all" global buttons still work correctly

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/browse/GalleryGrid.tsx
git commit -m "feat(browse): add category checkboxes with indeterminate state to gallery header"
```

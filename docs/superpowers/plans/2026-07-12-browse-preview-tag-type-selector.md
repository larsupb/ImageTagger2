# Browse Preview Tag-Type Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dropdown next to the browse-page image count that selects which caption (tag) type is shown in the image preview overlay, persisted per project.

**Architecture:** Two frontend-only changes in `GalleryGrid.tsx`. First, make the existing `ImagePreview` component select its overlay caption by a passed-in `caption_type` instead of always using `captions[0]`. Second, add a caption-types dropdown + per-project persisted selection in `GalleryGrid`, and pass the selection into `ImagePreview`. No backend changes — everything reuses existing endpoints (`api.getCaptionTypes`, `api.getItem`).

**Tech Stack:** Next.js 15 / React 19 / TypeScript, TanStack Query, shadcn `Select`, browser `localStorage`.

**Testing note:** This repo has no frontend test framework configured (see CLAUDE.md). Tasks use manual verification in the running dev server (`npm run dev` in `frontend/`) plus `npm run build` / `npx tsc --noEmit` for type safety, matching the repo's existing practice. Pre-existing type errors in `src/app/edit/page.tsx` are unrelated — ignore them; only new errors in `GalleryGrid.tsx` matter.

---

### Task 1: Select the preview caption by type in `ImagePreview`

Make `ImagePreview` accept an optional `captionType` prop and show the caption matching that type. When the prop is absent, behavior is unchanged (first caption) so the build stays green before Task 2 wires it up. When the prop is present but the image has no such type (or it is blank), the overlay shows nothing.

**Files:**
- Modify: `frontend/src/components/browse/GalleryGrid.tsx` (the `ImagePreview` function, currently lines 609-658)

- [ ] **Step 1: Add the `captionType` prop to the component signature**

Replace the current `ImagePreview` signature/props (lines 609-619):

```tsx
function ImagePreview({
  item,
  x,
  y,
  onClose,
}: {
  item: GalleryItem;
  x: number;
  y: number;
  onClose: () => void;
}) {
```

with:

```tsx
function ImagePreview({
  item,
  x,
  y,
  captionType,
  onClose,
}: {
  item: GalleryItem;
  x: number;
  y: number;
  captionType?: string;
  onClose: () => void;
}) {
```

- [ ] **Step 2: Select the caption by type in the fetch effect**

Replace the existing effect (currently lines 631-636):

```tsx
  useEffect(() => {
    api.getItem(item.index).then((mediaItem) => {
      const first = mediaItem.captions[0]?.content ?? null;
      setCaption(first && first.trim() ? first : null);
    });
  }, [item.index]);
```

with:

```tsx
  useEffect(() => {
    api.getItem(item.index).then((mediaItem) => {
      const entry = captionType
        ? mediaItem.captions.find((c) => c.caption_type === captionType)
        : mediaItem.captions[0];
      const content = entry?.content ?? null;
      setCaption(content && content.trim() ? content : null);
    });
  }, [item.index, captionType]);
```

- [ ] **Step 3: Verify types and build**

Run: `cd frontend && npx tsc --noEmit 2>&1 | grep GalleryGrid`
Expected: no output (no new errors in `GalleryGrid.tsx`).

- [ ] **Step 4: Manual verification (unchanged behavior)**

With `npm run dev` running, open a project on the browse page and hover an image. Expected: the preview overlay still shows the first caption exactly as before (no `captionType` is passed yet).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/browse/GalleryGrid.tsx
git commit -m "Select browse preview caption by type in ImagePreview"
```

---

### Task 2: Add the caption-type dropdown with per-project persistence

Add a caption-types query, a `previewCaptionType` state persisted per project in `localStorage`, a shadcn `Select` next to the `{total} images` text, and pass the selection into `ImagePreview`.

**Files:**
- Modify: `frontend/src/components/browse/GalleryGrid.tsx` (imports, `GalleryGrid` component body ~lines 660-680, count row ~line 971, `ImagePreview` render call ~lines 1062-1067)

- [ ] **Step 1: Import the shadcn Select components**

The file already imports `Input` from `@/components/ui/input` (line 15). Directly after that import line, add:

```tsx
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
```

- [ ] **Step 2: Add the caption-types query and selection state**

In the `GalleryGrid` component, just after the existing line:

```tsx
  const total = session?.datasetInfo?.total_items ?? 0;
```

add:

```tsx
  const storageKey = activeProjectId
    ? `browse:previewCaptionType:${activeProjectId}`
    : null;

  const { data: captionTypes = [] } = useQuery({
    queryKey: ["captionTypes"],
    queryFn: () => api.getCaptionTypes(),
  });

  const { data: firstItem } = useQuery({
    queryKey: ["previewDefaultCaptionType"],
    queryFn: () => api.getItem(0),
    enabled: captionTypes.length > 0 && total > 0,
  });

  const [previewCaptionType, setPreviewCaptionType] = useState<string | null>(null);

  useEffect(() => {
    if (previewCaptionType || captionTypes.length === 0) return;

    const stored = storageKey ? localStorage.getItem(storageKey) : null;
    if (stored && captionTypes.includes(stored)) {
      setPreviewCaptionType(stored);
      return;
    }

    const active = firstItem?.captions.find((c) => c.is_active)?.caption_type;
    setPreviewCaptionType(
      active && captionTypes.includes(active) ? active : captionTypes[0]
    );
  }, [captionTypes, firstItem, storageKey, previewCaptionType]);

  const handlePreviewTypeChange = useCallback(
    (value: string) => {
      setPreviewCaptionType(value);
      if (storageKey) localStorage.setItem(storageKey, value);
    },
    [storageKey]
  );
```

Note: `useState`, `useEffect`, `useCallback`, and `useQuery` are already imported (lines 3 and 5). `activeProjectId` is already defined at the top of the component (`const activeProjectId = useProjectStore((s) => s.activeProjectId);`).

- [ ] **Step 3: Render the dropdown next to the image count**

Replace the count line (currently line 971):

```tsx
          <span className="text-sm text-text-secondary">{total} images</span>
```

with:

```tsx
          <span className="text-sm text-text-secondary">{total} images</span>
          {captionTypes.length > 0 && previewCaptionType && (
            <Select value={previewCaptionType} onValueChange={handlePreviewTypeChange}>
              <SelectTrigger className="h-7 w-[140px] text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {captionTypes.map((type) => (
                  <SelectItem key={type} value={type}>
                    {type}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
```

- [ ] **Step 4: Pass the selected type into `ImagePreview`**

Replace the `ImagePreview` render call (currently lines 1062-1067):

```tsx
        <ImagePreview
          item={previewState.item}
          x={previewState.x}
          y={previewState.y}
          onClose={closePreview}
        />
```

with:

```tsx
        <ImagePreview
          item={previewState.item}
          x={previewState.x}
          y={previewState.y}
          captionType={previewCaptionType ?? undefined}
          onClose={closePreview}
        />
```

- [ ] **Step 5: Verify types and build**

Run: `cd frontend && npx tsc --noEmit 2>&1 | grep GalleryGrid`
Expected: no output.
Run: `cd frontend && npm run build`
Expected: build succeeds (ignore any pre-existing unrelated warnings).

- [ ] **Step 6: Manual verification**

With `npm run dev` running and a project open that has multiple caption types:
1. Confirm the dropdown appears next to the image count and lists the caption types.
2. Select a type, hover/click an image — overlay shows that type's content.
3. Preview an image lacking the selected type — no overlay text appears.
4. Reload the page — the selection persists for that project.
5. Switch to a different project — the selection is independent (its own stored value or default).

- [ ] **Step 7: Commit**

```bash
git add frontend/src/components/browse/GalleryGrid.tsx
git commit -m "Add per-project preview tag-type dropdown to browse page"
```

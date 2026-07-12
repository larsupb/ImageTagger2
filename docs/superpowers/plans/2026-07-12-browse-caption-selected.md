# Browse "Caption selected" Context-Menu Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Caption selected" submenu to the browse-page context menu that batch-captions the selected images with a chosen tagger, writing into the session's active tag type.

**Architecture:** Frontend-only changes in `frontend/src/components/browse/GalleryGrid.tsx`, mirroring the existing "Upscale selected" submenu exactly. Add a taggers query and a session-settings query in `GalleryGrid`, a `handleContextMenuCaption` callback that loops selected images calling `api.generateCaption` then `api.saveCaption`, a new `ContextMenuSub` in `GalleryThumbnail`, and prop-drilling (`taggers`, `onContextMenuCaption`) through `CategorySection`. No backend or API-client changes.

**Tech Stack:** Next.js 15 / React 19 / TypeScript, TanStack Query, shadcn `ContextMenu`, sonner toasts, lucide-react icons.

**Testing note:** This repo has no frontend test framework (see CLAUDE.md). Verification is `npx tsc --noEmit` (no new errors in `GalleryGrid.tsx`), `npm run build`, and manual checks in the dev server. Pre-existing type errors in `src/app/edit/page.tsx` (around `session.activeTagType`) are unrelated — ignore them.

---

### Task 1: Add imports, queries, and the caption handler in `GalleryGrid`

Wire up the data and the batch-caption callback in the top-level `GalleryGrid` component and its two imports, without yet rendering any UI. The build stays green because nothing consumes the new callback until Task 2/3.

**Files:**
- Modify: `frontend/src/components/browse/GalleryGrid.tsx` (imports line 6 and line 30; `GalleryGrid` body around lines 729-732 and 913-937)

- [ ] **Step 1: Add the `MessageSquare` icon import**

Replace the lucide import (line 6):

```tsx
import { Star, AlertTriangle, Pencil, Plus, Tag, ChevronRight, Upload, Trash2, Expand } from "lucide-react";
```

with:

```tsx
import { Star, AlertTriangle, Pencil, Plus, Tag, ChevronRight, Upload, Trash2, Expand, MessageSquare } from "lucide-react";
```

- [ ] **Step 2: Add the `Tagger` type import**

Replace the types import (line 30):

```tsx
import type { GalleryItem, GalleryResponse, Upscaler } from "@/lib/types";
```

with:

```tsx
import type { GalleryItem, GalleryResponse, Upscaler, Tagger } from "@/lib/types";
```

- [ ] **Step 3: Add the taggers and session-settings queries**

Immediately after the existing upscalers query (lines 729-732):

```tsx
  const { data: upscalers = [] } = useQuery({
    queryKey: ["upscalers"],
    queryFn: () => api.getUpscalers(),
  });
```

add:

```tsx
  const { data: taggersResponse } = useQuery({
    queryKey: ["taggers"],
    queryFn: () => api.getTaggers(),
  });
  const taggers = taggersResponse?.taggers ?? [];

  const { data: sessionSettings } = useQuery({
    queryKey: ["sessionSettings"],
    queryFn: () => api.getSessionSettings(),
  });
```

Note: `useQuery`, `useCallback`, `api`, `toast`, and `queryClient` are already in scope. `captionTypes` is already defined earlier in this component (from the preview tag-type feature).

- [ ] **Step 4: Add the `handleContextMenuCaption` callback**

Immediately after the existing `handleContextMenuUpscale` callback (which ends at line 937 with `);`), add:

```tsx
  const handleContextMenuCaption = useCallback(
    async (tagger: string) => {
      const indices = Array.from(selectedIndices);
      if (indices.length === 0) return;
      const targetType =
        sessionSettings?.active_tag_type ?? captionTypes[0] ?? "tags";
      const toastId = toast.loading(`Captioning 0/${indices.length}...`);
      let done = 0;
      try {
        for (const idx of indices) {
          const { caption } = await api.generateCaption(idx, tagger);
          await api.saveCaption(idx, caption, targetType);
          done++;
          toast.loading(`Captioning ${done}/${indices.length}...`, { id: toastId });
        }
        toast.success(
          `Captioned ${done} image${done === 1 ? "" : "s"} into "${targetType}"`,
          { id: toastId }
        );
      } catch (err) {
        toast.error(
          `Captioning failed after ${done}/${indices.length}: ${err instanceof Error ? err.message : "error"}`,
          { id: toastId }
        );
      } finally {
        queryClient.invalidateQueries({ queryKey: ["gallery"] });
      }
    },
    [selectedIndices, sessionSettings, captionTypes, queryClient]
  );
```

- [ ] **Step 5: Verify types**

Run: `cd frontend && npx tsc --noEmit 2>&1 | grep GalleryGrid`
Expected: no output (unused `taggers`/`handleContextMenuCaption` do not error under this config; if a no-unused-vars error appears, it will be resolved in Task 3 when they are consumed — proceed).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/components/browse/GalleryGrid.tsx
git commit -m "Add taggers query and batch-caption handler to browse GalleryGrid"
```

---

### Task 2: Thread the new props through `CategorySection` to `GalleryThumbnail`

Add `taggers` and `onContextMenuCaption` to both component prop interfaces and pass them down, mirroring `upscalers` / `onContextMenuUpscale`. Still no visible UI change.

**Files:**
- Modify: `frontend/src/components/browse/GalleryGrid.tsx` (`GalleryThumbnail` props ~lines 72-90; `CategorySection` props ~lines 270-297 and its `GalleryThumbnail` render ~lines 384-386; `GalleryGrid`'s `CategorySection` render ~lines 1108-1110)

- [ ] **Step 1: Add props to `GalleryThumbnail` destructure**

Replace (lines 72-74):

```tsx
  upscalers,
  selectedCount,
  onContextMenuUpscale,
```

with:

```tsx
  upscalers,
  taggers,
  selectedCount,
  onContextMenuUpscale,
  onContextMenuCaption,
```

- [ ] **Step 2: Add props to `GalleryThumbnail` props type**

Replace (lines 88-90):

```tsx
  upscalers: Upscaler[];
  selectedCount: number;
  onContextMenuUpscale: (upscaler: string) => void;
```

with:

```tsx
  upscalers: Upscaler[];
  taggers: Tagger[];
  selectedCount: number;
  onContextMenuUpscale: (upscaler: string) => void;
  onContextMenuCaption: (tagger: string) => void;
```

- [ ] **Step 3: Add props to `CategorySection` destructure**

Replace (lines 270-272):

```tsx
  upscalers,
  selectedCount,
  onContextMenuUpscale,
```

with:

```tsx
  upscalers,
  taggers,
  selectedCount,
  onContextMenuUpscale,
  onContextMenuCaption,
```

- [ ] **Step 4: Add props to `CategorySection` props type**

Replace (lines 295-297):

```tsx
  upscalers: Upscaler[];
  selectedCount: number;
  onContextMenuUpscale: (upscaler: string) => void;
```

with:

```tsx
  upscalers: Upscaler[];
  taggers: Tagger[];
  selectedCount: number;
  onContextMenuUpscale: (upscaler: string) => void;
  onContextMenuCaption: (tagger: string) => void;
```

- [ ] **Step 5: Pass props into the `GalleryThumbnail` render inside `CategorySection`**

Replace (lines 384-386):

```tsx
              upscalers={upscalers}
              selectedCount={selectedCount}
              onContextMenuUpscale={onContextMenuUpscale}
```

with:

```tsx
              upscalers={upscalers}
              taggers={taggers}
              selectedCount={selectedCount}
              onContextMenuUpscale={onContextMenuUpscale}
              onContextMenuCaption={onContextMenuCaption}
```

- [ ] **Step 6: Pass props into the `CategorySection` render inside `GalleryGrid`**

Replace (lines 1108-1110):

```tsx
                upscalers={upscalers}
                selectedCount={selectionCount}
                onContextMenuUpscale={handleContextMenuUpscale}
```

with:

```tsx
                upscalers={upscalers}
                taggers={taggers}
                selectedCount={selectionCount}
                onContextMenuUpscale={handleContextMenuUpscale}
                onContextMenuCaption={handleContextMenuCaption}
```

- [ ] **Step 7: Verify types**

Run: `cd frontend && npx tsc --noEmit 2>&1 | grep GalleryGrid`
Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add frontend/src/components/browse/GalleryGrid.tsx
git commit -m "Thread taggers and caption handler props through browse gallery"
```

---

### Task 3: Render the "Caption selected" submenu

Add the `ContextMenuSub` in `GalleryThumbnail`, directly below "Upscale selected".

**Files:**
- Modify: `frontend/src/components/browse/GalleryGrid.tsx` (`GalleryThumbnail` context menu, insert after line 240)

- [ ] **Step 1: Insert the caption submenu**

After the closing `</ContextMenuSub>` of the "Upscale selected" block (line 240) and before the `<ContextMenuSeparator />` (line 241), insert:

```tsx
        <ContextMenuSub>
          <ContextMenuSubTrigger disabled={selectedCount < 1}>
            <MessageSquare className="w-3.5 h-3.5" />
            Caption selected
          </ContextMenuSubTrigger>
          <ContextMenuSubContent>
            {taggers.length === 0 ? (
              <ContextMenuItem disabled>
                <span className="text-text-muted">No taggers available</span>
              </ContextMenuItem>
            ) : (
              taggers.map((t) => (
                <ContextMenuItem
                  key={t.id}
                  onClick={() => onContextMenuCaption(t.id)}
                >
                  {t.name}
                </ContextMenuItem>
              ))
            )}
          </ContextMenuSubContent>
        </ContextMenuSub>
```

`ContextMenuSub`, `ContextMenuSubTrigger`, `ContextMenuSubContent`, and `ContextMenuItem` are already imported and used by the "Upscale selected" block just above.

- [ ] **Step 2: Verify types and build**

Run: `cd frontend && npx tsc --noEmit 2>&1 | grep GalleryGrid`
Expected: no output.
Run: `cd frontend && npm run build`
Expected: build succeeds (ignore pre-existing unrelated warnings/errors outside `GalleryGrid.tsx`).

- [ ] **Step 3: Manual verification**

With `npm run dev` running and a project open:
1. Select several images (ctrl/shift-click), right-click a selected one.
2. Confirm "Caption selected" appears directly below "Upscale selected" and lists the taggers by name.
3. Confirm the submenu trigger is disabled when nothing is selected.
4. Pick a fast tagger (e.g. WD14); confirm the toast counts up `Captioning n/N...` and ends with a success toast naming the target tag type.
5. On the edit page, confirm the captions were written into the active tag type, and that caption badges refreshed in the gallery.
6. Force an error path if convenient (e.g. VLM tagger with no endpoint configured) and confirm the error toast reports how many completed.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/components/browse/GalleryGrid.tsx
git commit -m "Add Caption selected submenu to browse context menu"
```

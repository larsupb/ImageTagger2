# Browse Page Image Preview Caption — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the first available caption as a photo caption bar at the bottom of the `ImagePreview` popup on the Browse page.

**Architecture:** `ImagePreview` fetches the full `MediaItem` on mount via `api.getItem(index)`, reads `captions[0].content`, and renders it as a caption bar below the image. All changes are contained in one component in one file.

**Tech Stack:** React 19, Next.js 15, TypeScript, Tailwind CSS 4, `@tanstack/react-query` (not used here — local state only)

---

### Task 1: Add caption bar to `ImagePreview`

**Files:**
- Modify: `frontend/src/components/browse/GalleryGrid.tsx:1,556-591`

> No test framework is configured (see CLAUDE.md). Manual verification steps are provided instead.

- [ ] **Step 1: Add `useEffect` to the React import**

Open `frontend/src/components/browse/GalleryGrid.tsx`. Line 3 currently reads:

```ts
import { useState, useCallback, useRef, useMemo } from "react";
```

Change it to:

```ts
import { useState, useCallback, useRef, useMemo, useEffect } from "react";
```

- [ ] **Step 2: Replace the `ImagePreview` function**

Find the `ImagePreview` function (starts at line 556, ends at line 591). Replace the entire function with:

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
  const PAD = 16;
  const MAX = 800;
  let left = x + PAD;
  let top = y + PAD;
  if (left + MAX > window.innerWidth) left = x - MAX - PAD;
  if (top + MAX > window.innerHeight) top = y - MAX - PAD;
  left = Math.max(PAD, left);
  top = Math.max(PAD, top);

  const [caption, setCaption] = useState<string | null>(null);

  useEffect(() => {
    api.getItem(item.index).then((mediaItem) => {
      const first = mediaItem.captions[0]?.content ?? null;
      setCaption(first && first.trim() ? first : null);
    });
  }, [item.index]);

  return (
    <div className="fixed inset-0 z-50" onClick={onClose}>
      <div
        className="absolute rounded-lg overflow-hidden shadow-2xl border border-border bg-surface"
        style={{ left, top, maxWidth: MAX, maxHeight: MAX }}
        onClick={(e) => e.stopPropagation()}
      >
        <img
          src={getMediaUrl(item.index)}
          alt={item.filename}
          style={{ maxWidth: MAX, maxHeight: MAX, display: "block" }}
        />
        {caption && (
          <div className="bg-black/70 px-3 py-2 text-sm text-white leading-snug">
            {caption}
          </div>
        )}
      </div>
    </div>
  );
}
```

All imports used here (`api`, `getMediaUrl`, `GalleryItem`) are already present in the file.

- [ ] **Step 3: Type-check**

```bash
cd frontend && npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 4: Manual verification**

Start the dev servers:
```bash
./run.sh
```

Open the Browse page in the browser (`http://localhost:3000/browse`).

Verify:
1. Click a thumbnail for an image **with** a caption → preview opens, caption text appears below the image in a dark bar.
2. The caption wraps naturally if it is long (no truncation).
3. Click a thumbnail for an image **without** a caption → preview opens, no caption bar is shown.
4. Close the preview by clicking outside → reopens cleanly on next click.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/browse/GalleryGrid.tsx
git commit -m "feat(browse): show first caption in image preview"
```

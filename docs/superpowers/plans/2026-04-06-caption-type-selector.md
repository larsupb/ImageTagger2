# Caption Type Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a caption type dropdown to CaptionEditor so users can view, edit, and create multiple caption types per image.

**Architecture:** Inline dropdown in CaptionEditor's toolbar row, backed by the existing `captions: CaptionEntry[]` prop from MediaItem. A Popover for the "+ New type…" flow. Type switching auto-saves dirty content before switching.

**Tech Stack:** React 19, TypeScript, Next.js 15, @base-ui/react Select, @radix-ui/react-popover (new dependency), Tailwind CSS 4, Zustand

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `frontend/src/components/edit/CaptionEditor.tsx` | Modify | Add `captions` prop, type dropdown, new-type popover, auto-save on switch |
| `frontend/src/app/edit/page.tsx` | Modify | Pass `captions` prop, re-fetch item after save |
| `frontend/package.json` | Modify | Add `@radix-ui/react-popover` dependency |

---

### Task 1: Add Popover dependency

**Files:**
- Modify: `frontend/package.json`

- [ ] **Step 1: Install @radix-ui/react-popover**

Run in `frontend/`:
```bash
npm install @radix-ui/react-popover
```

Verify it appears in package.json dependencies.

- [ ] **Step 2: Create Popover component**

Create `frontend/src/components/ui/popover.tsx`:

```tsx
"use client"

import * as React from "react"
import * as PopoverPrimitive from "@radix-ui/react-popover"

import { cn } from "@/lib/utils"

const Popover = PopoverPrimitive.Root
const PopoverTrigger = PopoverPrimitive.Trigger
const PopoverAnchor = PopoverPrimitive.Anchor

function PopoverContent({
  className,
  align = "center",
  sideOffset = 4,
  children,
  ...props
}: React.ComponentProps<typeof PopoverPrimitive.Content>) {
  return (
    <PopoverPrimitive.Portal>
      <PopoverPrimitive.Content
        data-slot="popover-content"
        align={align}
        sideOffset={sideOffset}
        className={cn(
          "z-50 w-72 rounded-lg border bg-popover p-4 text-popover-foreground shadow-md outline-hidden data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2",
          className
        )}
        {...props}
      >
        {children}
      </PopoverPrimitive.Content>
    </PopoverPrimitive.Portal>
  )
}

export { Popover, PopoverTrigger, PopoverContent, PopoverAnchor }
```

- [ ] **Step 3: Verify build**

Run in `frontend/`:
```bash
npm run build
```
Expected: Build succeeds with no type errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/package.json frontend/package-lock.json frontend/src/components/ui/popover.tsx
git commit -m "add popover component for caption type selector"
```

---

### Task 2: Add caption type dropdown to CaptionEditor

**Files:**
- Modify: `frontend/src/components/edit/CaptionEditor.tsx`

- [ ] **Step 1: Update imports and props**

Add imports for Popover, Input, Separator. Add `captions` prop and update the interface:

```tsx
"use client";

import { useState, useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { Button } from "@/components/ui/button";
import type { Tagger, CaptionEntry } from "@/lib/types";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  SelectSeparator,
} from "@/components/ui/select";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Input } from "@/components/ui/input";
import { Loader2, Plus } from "lucide-react";

interface CaptionEditorProps {
  caption: string;
  index: number;
  savedCaption: string;
  captions?: CaptionEntry[];
  onCaptionChange: (caption: string) => void;
  onDirtyChange?: (dirty: boolean) => void;
  getUnsavedText?: (getter: () => string) => void;
}
```

- [ ] **Step 2: Add new state and initialization logic**

Add to the component body (after existing state declarations):

```tsx
  const [activeType, setActiveType] = useState("tags");
  const [newTypeInput, setNewTypeInput] = useState("");
  const [newTypeOpen, setNewTypeOpen] = useState(false);

  // Initialize activeType from captions prop
  useEffect(() => {
    if (captions && captions.length > 0) {
      const active = captions.find((c) => c.is_active);
      setActiveType(active?.caption_type ?? "tags");
    } else {
      setActiveType("tags");
    }
  }, [captions]);

  // Initialize text from active caption type
  useEffect(() => {
    if (captions) {
      const entry = captions.find((c) => c.caption_type === activeType);
      setText(entry?.content ?? "");
    }
  }, [captions, activeType]);
```

- [ ] **Step 3: Add type switching with auto-save**

Add this function before `handleSave`:

```tsx
  const handleTypeChange = async (type: string) => {
    if (type === "__new__") {
      setNewTypeOpen(true);
      return;
    }
    if (text !== savedCaption) {
      await api.saveCaption(index, text, activeType);
    }
    setActiveType(type);
    const entry = captions?.find((c) => c.caption_type === type);
    const newContent = entry?.content ?? "";
    setText(newContent);
    onCaptionChange(newContent);
  };
```

- [ ] **Step 4: Add new type creation handler**

Add this function after `handleTypeChange`:

```tsx
  const handleCreateNewType = () => {
    const trimmed = newTypeInput.trim();
    if (!trimmed) return;
    setNewTypeOpen(false);
    setNewTypeInput("");
    setActiveType(trimmed);
    setText("");
    onCaptionChange("");
  };
```

- [ ] **Step 5: Update handleSave to use activeType**

Change the existing `handleSave`:

```tsx
  const handleSave = async () => {
    await api.saveCaption(index, text, activeType);
    onCaptionChange(text);
  };
```

- [ ] **Step 6: Update handleGenerate to use activeType**

Change the existing `handleGenerate`:

```tsx
  const handleGenerate = async () => {
    setGenerating(true);
    try {
      const result = await api.generateCaption(index, tagger);
      setText(result.caption);
    } finally {
      setGenerating(false);
    }
  };
```

Note: `generateCaption` saves to the active type via the backend's default behavior. The generated text goes into the textarea which is tied to `activeType`.

- [ ] **Step 7: Replace the JSX with the new layout**

Replace the entire return block:

```tsx
  const dirty = text !== savedCaption;

  const existingTypes = captions?.map((c) => c.caption_type) ?? [];
  const allTypes = [...new Set([...existingTypes, activeType])];

  return (
    <div className="bg-surface rounded-lg border border-border p-4 flex flex-col gap-3">
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        rows={4}
        className="w-full px-3 py-2 bg-background border border-border rounded text-sm text-text resize-y focus:outline-none focus:border-ring focus:ring-2 focus:ring-ring/50 placeholder:text-text-muted"
        placeholder="Caption text..."
      />

      <div className="flex items-center gap-2">
        <Select value={activeType} onValueChange={handleTypeChange}>
          <SelectTrigger className="w-[180px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {allTypes.map((type) => (
              <SelectItem key={type} value={type}>
                {type}
              </SelectItem>
            ))}
            <SelectSeparator />
            <SelectItem value="__new__">
              <span className="flex items-center gap-1.5 text-muted-foreground">
                <Plus className="w-3.5 h-3.5" />
                New type…
              </span>
            </SelectItem>
          </SelectContent>
        </Select>

        <Popover open={newTypeOpen} onOpenChange={setNewTypeOpen}>
          <PopoverTrigger asChild>
            <div className="hidden" />
          </PopoverTrigger>
          <PopoverContent className="w-72" align="start">
            <div className="flex flex-col gap-3">
              <h4 className="text-sm font-medium">New caption type</h4>
              <Input
                value={newTypeInput}
                onChange={(e) => setNewTypeInput(e.target.value)}
                placeholder="Type name (e.g. danbooru)"
                onKeyDown={(e) => {
                  if (e.key === "Enter" && newTypeInput.trim()) {
                    handleCreateNewType();
                  }
                }}
                autoFocus
              />
              <div className="flex justify-end gap-2">
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => {
                    setNewTypeOpen(false);
                    setNewTypeInput("");
                  }}
                >
                  Cancel
                </Button>
                <Button
                  size="sm"
                  disabled={!newTypeInput.trim()}
                  onClick={handleCreateNewType}
                >
                  Create
                </Button>
              </div>
            </div>
          </PopoverContent>
        </Popover>

        <Select value={tagger} onValueChange={(value) => value && setTagger(value)}>
          <SelectTrigger className="w-[180px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {taggersResponse?.taggers.map((t: Tagger) => (
              <SelectItem key={t.id} value={t.id}>
                {t.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <Button
          onClick={handleGenerate}
          disabled={generating}
        >
          {generating && <Loader2 className="w-4 h-4 mr-1.5 animate-spin" />}
          {generating ? "Generating..." : "Generate"}
        </Button>

        <Button
          variant={dirty ? "default" : "secondary"}
          onClick={handleSave}
          className={dirty ? "bg-orange-500 hover:bg-orange-600 text-white font-bold shadow-lg shadow-orange-500/40 ring-2 ring-orange-400/50" : ""}
        >
          Save Caption
          {dirty && <span className="ml-1.5 inline-flex items-center justify-center w-5 h-5 text-[10px] font-bold bg-white/20 rounded-full">*</span>}
        </Button>
      </div>
    </div>
  );
```

- [ ] **Step 8: Verify build**

Run in `frontend/`:
```bash
npm run build
```
Expected: Build succeeds with no type errors.

- [ ] **Step 9: Commit**

```bash
git add frontend/src/components/edit/CaptionEditor.tsx
git commit -m "add caption type selector with new type popover to CaptionEditor"
```

---

### Task 3: Update edit page to pass captions and re-fetch after save

**Files:**
- Modify: `frontend/src/app/edit/page.tsx`

- [ ] **Step 1: Pass captions prop to CaptionEditor**

Change the CaptionEditor usage:

```tsx
      <CaptionEditor
        caption={currentItem.caption}
        index={safeIndex}
        savedCaption={currentItem.caption}
        captions={currentItem.captions ?? []}
        onCaptionChange={(caption) =>
          setCurrentItem(activeProjectId, { ...currentItem, caption })
        }
        onDirtyChange={setCaptionDirty}
        getUnsavedText={(getter) => {
          getUnsavedTextRef.current = getter;
        }}
      />
```

- [ ] **Step 2: Re-fetch item after caption save in handleSaveAndGo**

Change the `handleSaveAndGo` function to re-fetch the item after saving, so the `captions` array is refreshed:

```tsx
  const handleSaveAndGo = async () => {
    const text = getUnsavedTextRef.current?.() ?? "";
    const saveIndex = currentIndex ?? 0;
    await api.saveCaption(saveIndex, text);
    setShowDirtyDialog(false);
    if (pendingNavigation.current !== null) {
      await loadItem(pendingNavigation.current);
      pendingNavigation.current = null;
    }
  };
```

Note: `loadItem` already calls `api.getItem` which returns the full `MediaItem` including the updated `captions` array.

- [ ] **Step 3: Add re-fetch after inline save**

The `onCaptionChange` callback currently only updates the caption string in the store. To refresh the `captions` array after a save, update the `onCaptionChange` handler:

```tsx
        onCaptionChange={async (caption) => {
          setCurrentItem(activeProjectId, { ...currentItem, caption });
          await loadItem(safeIndex);
        }}
```

This ensures the `captions` array is refreshed after every save, reflecting newly created types.

- [ ] **Step 4: Verify build**

Run in `frontend/`:
```bash
npm run build
```
Expected: Build succeeds with no type errors.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/app/edit/page.tsx
git commit -m "pass captions prop to CaptionEditor and re-fetch after save"
```

---

### Task 4: Manual verification

**Files:** None

- [ ] **Step 1: Start the application**

Run from project root:
```bash
./run.sh
```

- [ ] **Step 2: Verify test cases from spec**

1. Open a dataset with existing `.txt` captions — type dropdown shows `"tags"` as the only option
2. Switch to a different type (e.g. add a `natural_language` caption via curl) — dropdown shows both, switching loads correct content
3. Select `"+ New type…"`, type `"danbooru"`, confirm — textarea empties, saves correctly with `caption_type="danbooru"`
4. Edit a caption while dirty, switch type — content auto-saves before switching
5. New type persists after navigating to next image and back

- [ ] **Step 5: Run lint**

Run in `frontend/`:
```bash
npm run lint
```
Expected: No lint errors.

---

## Self-Review

**1. Spec coverage:**
- UI Layout (Option B, dropdown inline in toolbar) — Task 2, Step 7 ✓
- CaptionEditor changes (captions prop, activeType state, type switching, auto-save) — Task 2, Steps 1-7 ✓
- "New Type" Flow (Popover, Input, Create button, lazy persistence) — Task 1 Step 2, Task 2 Steps 4, 7 ✓
- Edit Page changes (pass captions prop, re-fetch after save) — Task 3 ✓
- Scope (dataset-local, no global registry, no captions page changes) — No changes to captions page ✓

**2. Placeholder scan:** No TBD, TODO, or vague steps. All code is complete.

**3. Type consistency:** 
- `CaptionEntry` type matches `types.ts` definition
- `captions` prop is `CaptionEntry[] | undefined` with `?? []` fallback
- `activeType` is `string`, matches `Select` value type
- `api.saveCaption` signature already accepts `(index, caption, captionType)` — no changes needed
- All method signatures match existing patterns

# Frontend Redesign & Multi-Project UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the ImageTagger2 frontend into a modern dashboard with expanded sidebar, project tabs, shadcn/ui components, Lucide icons, page-specific headers, and multi-project support.

**Architecture:** Replace the current minimal layout (48px emoji sidebar + global DatasetHeader) with a structured dashboard: horizontal project tabs, expanded 240px sidebar with Lucide icons + text labels, page-specific headers, and a multi-project Zustand store. All pages redesigned using shadcn/ui components and a unified dark slate theme.

**Tech Stack:** Next.js 15, React 19, TypeScript, Tailwind CSS v4, shadcn/ui, Lucide React, Zustand, React Query, Sonner

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `frontend/src/lib/utils.ts` | Create | `cn()` utility (clsx + tailwind-merge) |
| `frontend/src/app/globals.css` | Modify | Theme tokens via Tailwind v4 `@theme` |
| `frontend/src/lib/types.ts` | Modify | Add Project, RecentProject, ProjectOpenResponse types |
| `frontend/src/lib/api.ts` | Modify | Multi-project API calls, per-project session management |
| `frontend/src/stores/projectStore.ts` | Create | Multi-project state management |
| `frontend/src/stores/session.ts` | Modify | Refactor to per-project session state |
| `frontend/src/components/ui/*` | Create | shadcn/ui components (button, dialog, dropdown-menu, input, tooltip, toast, select, checkbox, badge, progress, separator, scroll-area) |
| `frontend/src/components/layout/AppLayout.tsx` | Create | Main layout shell (tabs + sidebar + content) |
| `frontend/src/components/layout/ProjectTabs.tsx` | Create | Project tab bar with dropdown actions |
| `frontend/src/components/layout/Sidebar.tsx` | Replace | Expanded nav with Lucide icons + text labels |
| `frontend/src/components/layout/DatasetHeader.tsx` | Delete | Replaced by page-specific headers |
| `frontend/src/components/layout/QueryProvider.tsx` | Keep | Unchanged |
| `frontend/src/components/shared/EmptyState.tsx` | Create | Reusable empty state component |
| `frontend/src/components/shared/LoadingSkeleton.tsx` | Create | Skeleton loaders |
| `frontend/src/components/shared/ConfirmDialog.tsx` | Modify | Refactored to use shadcn dialog |
| `frontend/src/app/layout.tsx` | Modify | Use AppLayout shell |
| `frontend/src/app/page.tsx` | Modify | Redirect logic based on project state |
| `frontend/src/app/browse/page.tsx` | Modify | Add page header, use new components |
| `frontend/src/app/edit/page.tsx` | Modify | Two-column layout, new components |
| `frontend/src/app/captions/page.tsx` | Modify | Two-column layout, new components |
| `frontend/src/app/batch/page.tsx` | Modify | Card-based operation selector, new components |
| `frontend/src/app/tools/page.tsx` | Modify | Card-based layout |
| `frontend/src/app/validation/page.tsx` | Modify | Visual distribution, new components |
| `frontend/src/app/settings/page.tsx` | Modify | Grouped sections, collapsible |
| `frontend/src/components/browse/GalleryGrid.tsx` | Modify | Card-style thumbnails, hover effects |
| `frontend/src/components/edit/ImageViewer.tsx` | Modify | Zoom controls, overlay arrows |
| `frontend/src/components/edit/ImageToolbar.tsx` | Modify | Icon buttons with tooltips |
| `frontend/src/components/edit/NavigationBar.tsx` | Modify | Compact navigation |
| `frontend/src/components/batch/BatchForm.tsx` | Modify | Card-based form |
| `frontend/src/components/captions/TagCloud.tsx` | Modify | Searchable, frequency badges |

---

### Task 1: Install Dependencies

**Files:**
- Modify: `frontend/package.json`

- [ ] **Step 1: Install new dependencies**

Run in `frontend/`:

```bash
npm install lucide-react clsx tailwind-merge sonner class-variance-authority @radix-ui/react-slot @radix-ui/react-dialog @radix-ui/react-dropdown-menu @radix-ui/react-tooltip @radix-ui/react-select @radix-ui/react-checkbox @radix-ui/react-scroll-area @radix-ui/react-separator
```

- [ ] **Step 2: Verify install succeeded**

```bash
cd frontend && npm ls lucide-react clsx tailwind-merge sonner
```

Expected: All packages listed with versions.

- [ ] **Step 3: Commit**

```bash
cd frontend && git add package.json package-lock.json
git commit -m "chore: install shadcn/ui, lucide-react, sonner dependencies"
```

---

### Task 2: Theme Tokens and Utility

**Files:**
- Modify: `frontend/src/app/globals.css`
- Create: `frontend/src/lib/utils.ts`

- [ ] **Step 1: Update globals.css with theme tokens**

Replace the entire `globals.css` with:

```css
@import "tailwindcss";
@source "../**/*.{ts,tsx}";

@theme {
  --color-background: #0f172a;
  --color-surface: #1e293b;
  --color-surface-raised: #334155;
  --color-border: #334155;
  --color-border-subtle: #475569;

  --color-primary: #3b82f6;
  --color-primary-hover: #2563eb;
  --color-primary-foreground: #ffffff;

  --color-success: #22c55e;
  --color-success-hover: #16a34a;
  --color-warning: #f59e0b;
  --color-warning-hover: #d97706;
  --color-danger: #ef4444;
  --color-danger-hover: #dc2626;

  --color-text: #f8fafc;
  --color-text-secondary: #94a3b8;
  --color-text-muted: #64748b;
}

@layer base {
  * {
    @apply border-border;
  }
  body {
    @apply bg-background text-text antialiased;
  }
}

/* Custom scrollbar */
::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}
::-webkit-scrollbar-track {
  background: #1e293b;
}
::-webkit-scrollbar-thumb {
  background: #475569;
  border-radius: 4px;
}
::-webkit-scrollbar-thumb:hover {
  background: #64748b;
}
```

- [ ] **Step 2: Create cn() utility**

Create `frontend/src/lib/utils.ts`:

```typescript
import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

- [ ] **Step 3: Commit**

```bash
cd frontend && git add src/app/globals.css src/lib/utils.ts
git commit -m "feat: add theme tokens and cn() utility"
```

---

### Task 3: Install shadcn/ui Components

**Files:**
- Create: `frontend/src/components/ui/button.tsx`
- Create: `frontend/src/components/ui/dialog.tsx`
- Create: `frontend/src/components/ui/dropdown-menu.tsx`
- Create: `frontend/src/components/ui/input.tsx`
- Create: `frontend/src/components/ui/tooltip.tsx`
- Create: `frontend/src/components/ui/select.tsx`
- Create: `frontend/src/components/ui/checkbox.tsx`
- Create: `frontend/src/components/ui/badge.tsx`
- Create: `frontend/src/components/ui/progress.tsx`
- Create: `frontend/src/components/ui/separator.tsx`
- Create: `frontend/src/components/ui/scroll-area.tsx`
- Create: `frontend/src/components/ui/toast.tsx`
- Create: `frontend/components.json` (shadcn/ui config)

- [ ] **Step 1: Initialize shadcn/ui**

Run in `frontend/`:

```bash
npx shadcn@latest init
```

When prompted:
- Style: **New York**
- Base color: **Slate**
- CSS variables: **Yes**
- Tailwind config: **No** (using v4 CSS-first config)

- [ ] **Step 2: Install required components**

```bash
npx shadcn@latest add button dialog dropdown-menu input tooltip select checkbox badge progress separator scroll-area
```

- [ ] **Step 3: Add Sonner toast provider**

Add `<Toaster />` to `frontend/src/app/layout.tsx` inside the `<body>`:

```tsx
import { Toaster } from "sonner";
// ... inside body:
<Toaster theme="dark" position="top-right" />
```

- [ ] **Step 4: Commit**

```bash
cd frontend && git add src/components/ui/ components.json src/app/layout.tsx
git commit -m "feat: install shadcn/ui components and Sonner toast"
```

---

### Task 4: Multi-Project Store and Types

**Files:**
- Modify: `frontend/src/lib/types.ts`
- Create: `frontend/src/stores/projectStore.ts`
- Modify: `frontend/src/stores/session.ts`

- [ ] **Step 1: Add project types to types.ts**

Append to `frontend/src/lib/types.ts`:

```typescript
export interface Project {
  session_id: string;
  project_id: string;
  project_name: string;
  path: string;
  total_items: number;
  current_index: number;
  created_at: number;
  last_accessed: number;
}

export interface RecentProject {
  project_id: string;
  name: string;
  path: string;
  last_opened: string;
  open_count: number;
  is_active: boolean;
}

export interface ProjectOpenResponse {
  session_id: string;
  project_id: string;
  project_name: string;
  dataset_info: {
    total_items: number;
    base_dir: string;
    masks_dir: string | null;
  };
}

export interface ActiveProjectsResponse {
  projects: Project[];
}

export interface RecentProjectsResponse {
  projects: RecentProject[];
}
```

- [ ] **Step 2: Create project store**

Create `frontend/src/stores/projectStore.ts`:

```typescript
import { create } from "zustand";
import type { Project, RecentProject, ProjectOpenResponse } from "@/lib/types";
import { api } from "@/lib/api";

interface ProjectStore {
  projects: Project[];
  activeProjectId: string | null;
  recentProjects: RecentProject[];
  isLoading: boolean;

  openProject: (
    path: string,
    masksPath?: string,
    onlyMissing?: boolean,
    subdirs?: boolean
  ) => Promise<ProjectOpenResponse>;
  closeProject: (sessionId: string) => Promise<void>;
  switchProject: (sessionId: string) => void;
  loadActiveProjects: () => Promise<void>;
  loadRecentProjects: () => Promise<void>;
  reset: () => void;
}

export const useProjectStore = create<ProjectStore>((set, get) => ({
  projects: [],
  activeProjectId: null,
  recentProjects: [],
  isLoading: false,

  openProject: async (path, masksPath, onlyMissing, subdirs) => {
    const result = await api.openProject(path, masksPath, onlyMissing, subdirs);
    set((state) => ({
      projects: [
        ...state.projects,
        {
          session_id: result.session_id,
          project_id: result.project_id,
          project_name: result.project_name,
          path: result.dataset_info.base_dir,
          total_items: result.dataset_info.total_items,
          current_index: 0,
          created_at: Date.now() / 1000,
          last_accessed: Date.now() / 1000,
        },
      ],
      activeProjectId: result.session_id,
    }));
    return result;
  },

  closeProject: async (sessionId) => {
    await api.closeProject(sessionId);
    set((state) => {
      const remaining = state.projects.filter((p) => p.session_id !== sessionId);
      return {
        projects: remaining,
        activeProjectId:
          state.activeProjectId === sessionId
            ? remaining.length > 0
              ? remaining[remaining.length - 1].session_id
              : null
            : state.activeProjectId,
      };
    });
  },

  switchProject: (sessionId) => {
    set({ activeProjectId: sessionId });
  },

  loadActiveProjects: async () => {
    const response = await api.getActiveProjects();
    set({ projects: response.projects });
    if (response.projects.length > 0) {
      set({ activeProjectId: response.projects[0].session_id });
    }
  },

  loadRecentProjects: async () => {
    const response = await api.getRecentProjects();
    set({ recentProjects: response.projects });
  },

  reset: () => {
    set({ projects: [], activeProjectId: null, recentProjects: [], isLoading: false });
  },
}));
```

- [ ] **Step 3: Refactor session store for multi-project**

Replace `frontend/src/stores/session.ts`:

```typescript
import { create } from "zustand";
import type { DatasetInfo, MediaItem } from "@/lib/types";

interface PerProjectSession {
  datasetInfo: DatasetInfo | null;
  currentIndex: number;
  currentItem: MediaItem | null;
  isLoading: boolean;
  error: string | null;
}

interface SessionState {
  sessions: Map<string, PerProjectSession>;

  getProjectSession: (projectId: string) => PerProjectSession;
  setDatasetInfo: (projectId: string, info: DatasetInfo | null) => void;
  setCurrentIndex: (projectId: string, index: number) => void;
  setCurrentItem: (projectId: string, item: MediaItem | null) => void;
  setLoading: (projectId: string, loading: boolean) => void;
  setError: (projectId: string, error: string | null) => void;
  clearProjectSession: (projectId: string) => void;
}

const defaultSession = (): PerProjectSession => ({
  datasetInfo: null,
  currentIndex: 0,
  currentItem: null,
  isLoading: false,
  error: null,
});

export const useSessionStore = create<SessionState>((set, get) => ({
  sessions: new Map(),

  getProjectSession: (projectId) => {
    const state = get();
    if (!state.sessions.has(projectId)) {
      set((s) => {
        const next = new Map(s.sessions);
        next.set(projectId, defaultSession());
        return { sessions: next };
      });
      return defaultSession();
    }
    return state.sessions.get(projectId)!;
  },

  setDatasetInfo: (projectId, info) =>
    set((state) => {
      const next = new Map(state.sessions);
      const session = next.get(projectId) || defaultSession();
      next.set(projectId, { ...session, datasetInfo: info });
      return { sessions: next };
    }),

  setCurrentIndex: (projectId, index) =>
    set((state) => {
      const next = new Map(state.sessions);
      const session = next.get(projectId) || defaultSession();
      next.set(projectId, { ...session, currentIndex: index });
      return { sessions: next };
    }),

  setCurrentItem: (projectId, item) =>
    set((state) => {
      const next = new Map(state.sessions);
      const session = next.get(projectId) || defaultSession();
      next.set(projectId, { ...session, currentItem: item });
      return { sessions: next };
    }),

  setLoading: (projectId, loading) =>
    set((state) => {
      const next = new Map(state.sessions);
      const session = next.get(projectId) || defaultSession();
      next.set(projectId, { ...session, isLoading: loading });
      return { sessions: next };
    }),

  setError: (projectId, error) =>
    set((state) => {
      const next = new Map(state.sessions);
      const session = next.get(projectId) || defaultSession();
      next.set(projectId, { ...session, error });
      return { sessions: next };
    }),

  clearProjectSession: (projectId) =>
    set((state) => {
      const next = new Map(state.sessions);
      next.delete(projectId);
      return { sessions: next };
    }),
}));
```

- [ ] **Step 4: Commit**

```bash
cd frontend && git add src/lib/types.ts src/stores/projectStore.ts src/stores/session.ts
git commit -m "feat: add multi-project store and refactor session store"
```

---

### Task 5: Update API Client for Multi-Project

**Files:**
- Modify: `frontend/src/lib/api.ts`

- [ ] **Step 1: Rewrite api.ts for multi-project**

Replace `frontend/src/lib/api.ts`:

```typescript
import type {
  DatasetInfo,
  MediaItem,
  GalleryResponse,
  TagCloudEntry,
  SearchReplacePreview,
  Settings,
  Tagger,
  Upscaler,
  BucketResult,
  ProjectOpenResponse,
  ActiveProjectsResponse,
  RecentProjectsResponse,
} from "./types";

let sessionId: string | null = null;

export function setSessionId(id: string | null) {
  sessionId = id;
}

export function getCurrentSessionId(): string | null {
  return sessionId;
}

export async function getSessionId(): Promise<string> {
  if (sessionId) return sessionId;
  const res = await fetch("/api/dataset/session", { method: "POST" });
  const data = await res.json();
  sessionId = data.session_id;
  return sessionId!;
}

export function getMediaUrl(index: number): string {
  return `/api/media/file/${index}?session_id=${sessionId}`;
}

export function getThumbnailUrl(index: number): string {
  return `/api/media/thumbnail/${index}?session_id=${sessionId}`;
}

async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const sid = await getSessionId();
  const res = await fetch(path, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "X-Session-ID": sid,
      ...options.headers,
    },
  });
  if (!res.ok) {
    const error = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(error.detail || "API error");
  }
  return res.json();
}

export const api = {
  // Project management
  openProject: (
    path: string,
    masksPath?: string,
    onlyMissing = false,
    subdirs = false
  ) =>
    fetch("/api/projects/open", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        path,
        masks_path: masksPath,
        only_missing_captions: onlyMissing,
        include_subdirectories: subdirs,
      }),
    }).then((res) => {
      if (!res.ok) throw new Error("Failed to open project");
      return res.json() as Promise<ProjectOpenResponse>;
    }),

  closeProject: (sessionId: string) =>
    fetch(`/api/projects/${sessionId}`, { method: "DELETE" }).then((res) => {
      if (!res.ok) throw new Error("Failed to close project");
      return res.json();
    }),

  getActiveProjects: () =>
    fetch("/api/projects/").then((res) => {
      if (!res.ok) throw new Error("Failed to get active projects");
      return res.json() as Promise<ActiveProjectsResponse>;
    }),

  getRecentProjects: (limit = 10) =>
    fetch(`/api/projects/recent?limit=${limit}`).then((res) => {
      if (!res.ok) throw new Error("Failed to get recent projects");
      return res.json() as Promise<RecentProjectsResponse>;
    }),

  // Dataset (backward compatible)
  loadDataset: (path: string, masksPath?: string, onlyMissing = false, subdirs = false) =>
    apiFetch<DatasetInfo>("/api/dataset/load", {
      method: "POST",
      body: JSON.stringify({
        path,
        masks_path: masksPath,
        only_missing_captions: onlyMissing,
        include_subdirectories: subdirs,
      }),
    }),

  getItem: (index: number) => apiFetch<MediaItem>(`/api/dataset/item/${index}`),

  getGallery: (page = 0, pageSize = 50) =>
    apiFetch<GalleryResponse>(`/api/dataset/gallery?page=${page}&page_size=${pageSize}`),

  toggleBookmark: (index: number) =>
    apiFetch<{ is_bookmarked: boolean }>(`/api/dataset/bookmark/${index}`, { method: "POST" }),

  deleteItem: (index: number) =>
    apiFetch<{ total_items: number }>(`/api/dataset/item/${index}`, { method: "DELETE" }),

  renameItem: (index: number, newName: string) =>
    apiFetch<MediaItem>(`/api/dataset/item/${index}/rename?new_name=${encodeURIComponent(newName)}`, {
      method: "PUT",
    }),

  // Captions
  saveCaption: (index: number, caption: string) =>
    apiFetch("/api/captions/save", {
      method: "PUT",
      body: JSON.stringify({ index, caption }),
    }),

  getTagCloud: (sortBy = "frequency") =>
    apiFetch<TagCloudEntry[]>(`/api/captions/tags?sort_by=${sortBy}`),

  removeTags: (tags: string[]) =>
    apiFetch("/api/captions/tags/remove", { method: "POST", body: JSON.stringify({ tags }) }),

  appendTag: (tag: string) =>
    apiFetch("/api/captions/tags/append", { method: "POST", body: JSON.stringify({ tag }) }),

  prependTag: (tag: string) =>
    apiFetch("/api/captions/tags/prepend", { method: "POST", body: JSON.stringify({ tag }) }),

  cleanupTags: () => apiFetch("/api/captions/tags/cleanup", { method: "POST" }),

  replaceUnderscores: () =>
    apiFetch("/api/captions/tags/replace-underscores", { method: "POST" }),

  searchReplacePreview: (search: string, replace: string) =>
    apiFetch<SearchReplacePreview>("/api/captions/search-replace/preview", {
      method: "POST",
      body: JSON.stringify({ search, replace }),
    }),

  searchReplaceApply: (search: string, replace: string) =>
    apiFetch("/api/captions/search-replace/apply", {
      method: "POST",
      body: JSON.stringify({ search, replace }),
    }),

  exportJsonl: () =>
    apiFetch<{ path: string; count: number }>("/api/captions/export", { method: "POST" }),

  moveToSubdir: (tags: string[], inverse: boolean, subdirectoryName: string) =>
    apiFetch("/api/captions/move-to-subdir", {
      method: "POST",
      body: JSON.stringify({ tags, inverse, subdirectory_name: subdirectoryName }),
    }),

  // Tagging
  generateCaption: (index: number, tagger: string) =>
    apiFetch<{ caption: string }>("/api/tagging/generate", {
      method: "POST",
      body: JSON.stringify({ index, tagger }),
    }),

  // Processing
  upscale: (index: number, upscaler?: string, targetMp?: number) =>
    apiFetch("/api/processing/upscale", {
      method: "POST",
      body: JSON.stringify({ index, upscaler, target_megapixels: targetMp }),
    }),

  saveUpscaled: (index: number) =>
    apiFetch("/api/processing/upscale/save?index=" + index, { method: "POST" }),

  removeBackground: (index: number) =>
    apiFetch("/api/processing/remove-background?index=" + index, { method: "POST" }),

  generateMask: (index: number) =>
    apiFetch("/api/processing/mask/generate", {
      method: "POST",
      body: JSON.stringify({ index }),
    }),

  // Batch
  batchProcess: (options: Record<string, unknown>) => {
    return getSessionId().then((sid) => {
      const params = new URLSearchParams();
      Object.entries(options).forEach(([k, v]) => {
        if (v !== undefined) params.set(k, String(v));
      });
      const source = new EventSource(`/api/batch/process?session_id=${sid}&${params.toString()}`);
      return source;
    });
  },

  analyzeBuckets: (resolution = 1024, step = 64, maxSteps = 4) =>
    apiFetch<BucketResult>("/api/batch/analyze-buckets", {
      method: "POST",
      body: JSON.stringify({ resolution, step, max_steps: maxSteps }),
    }),

  // Settings
  getSettings: () => apiFetch<Settings>("/api/settings/"),
  updateSetting: (key: string, value: unknown) =>
    apiFetch("/api/settings/", { method: "PUT", body: JSON.stringify({ key, value }) }),
  getUpscalers: () => apiFetch<Upscaler[]>("/api/settings/upscalers"),
  getTaggers: () => apiFetch<Tagger[]>("/api/settings/taggers"),

  // Tools
  copyImages: (targetDir: string, option: string) =>
    apiFetch("/api/settings/tools/copy", {
      method: "POST",
      body: JSON.stringify({ target_directory: targetDir, copy_option: option }),
    }),

  // Validation
  validate: () => apiFetch("/api/settings/validation"),

  // Media URLs
  mediaUrl: getMediaUrl,
  thumbnailUrl: getThumbnailUrl,
};
```

- [ ] **Step 2: Commit**

```bash
cd frontend && git add src/lib/api.ts
git commit -m "feat: update API client for multi-project support"
```

---

### Task 6: Layout Shell — AppLayout, Sidebar, ProjectTabs

**Files:**
- Create: `frontend/src/components/layout/AppLayout.tsx`
- Create: `frontend/src/components/layout/ProjectTabs.tsx`
- Replace: `frontend/src/components/layout/Sidebar.tsx`
- Modify: `frontend/src/app/layout.tsx`

- [ ] **Step 1: Create expanded Sidebar with Lucide icons**

Replace `frontend/src/components/layout/Sidebar.tsx`:

```tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Image,
  Pencil,
  Tags,
  Layers,
  Wrench,
  CheckCircle,
  Settings,
} from "lucide-react";

const navItems = [
  { href: "/browse", label: "Browse", icon: Image },
  { href: "/edit", label: "Edit", icon: Pencil },
  { href: "/captions", label: "Captions", icon: Tags },
  { href: "/batch", label: "Batch", icon: Layers },
  { href: "/tools", label: "Tools", icon: Wrench },
  { href: "/validation", label: "Validation", icon: CheckCircle },
  { href: "/settings", label: "Settings", icon: Settings },
];

export default function Sidebar() {
  const pathname = usePathname();

  return (
    <nav className="w-60 shrink-0 border-r border-border bg-surface flex flex-col">
      <div className="p-4 border-b border-border">
        <h1 className="text-lg font-bold text-text">ImageTagger</h1>
      </div>
      <ul className="flex-1 py-2">
        {navItems.map((item) => {
          const isActive = pathname.startsWith(item.href);
          const Icon = item.icon;
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                className={`flex items-center gap-3 px-4 py-2.5 text-sm transition-colors ${
                  isActive
                    ? "bg-primary/10 text-primary font-medium"
                    : "text-text-secondary hover:text-text hover:bg-surface-raised"
                }`}
              >
                <Icon className="w-4 h-4" />
                {item.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
```

- [ ] **Step 2: Create ProjectTabs component**

Create `frontend/src/components/layout/ProjectTabs.tsx`:

```tsx
"use client";

import { FolderOpen, X, ChevronDown, Plus } from "lucide-react";
import { useProjectStore } from "@/stores/projectStore";
import { useSessionStore } from "@/stores/session";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useState } from "react";
import { toast } from "sonner";

export default function ProjectTabs() {
  const { projects, activeProjectId, closeProject, switchProject } = useProjectStore();
  const [showOpenDialog, setShowOpenDialog] = useState(false);

  const handleOpenProject = () => {
    setShowOpenDialog(true);
  };

  const handleCloseProject = async (sessionId: string, e: React.MouseEvent) => {
    e.stopPropagation();
    try {
      await closeProject(sessionId);
      toast.success("Project closed");
    } catch {
      toast.error("Failed to close project");
    }
  };

  if (projects.length === 0) {
    return (
      <div className="flex items-center gap-2 px-4 py-2 border-b border-border bg-surface">
        <Button
          variant="outline"
          size="sm"
          className="gap-2"
          onClick={handleOpenProject}
        >
          <FolderOpen className="w-4 h-4" />
          Open Project
        </Button>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-1 px-2 py-1.5 border-b border-border bg-surface overflow-x-auto">
      {projects.map((project) => {
        const isActive = project.session_id === activeProjectId;
        return (
          <div
            key={project.session_id}
            className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-sm cursor-pointer transition-colors max-w-48 ${
              isActive
                ? "bg-primary/10 text-primary"
                : "text-text-secondary hover:bg-surface-raised hover:text-text"
            }`}
            onClick={() => switchProject(project.session_id)}
          >
            <FolderOpen className="w-3.5 h-3.5 shrink-0" />
            <span className="truncate">{project.project_name}</span>
            <button
              onClick={(e) => handleCloseProject(project.session_id, e)}
              className="shrink-0 opacity-60 hover:opacity-100 transition-opacity"
            >
              <X className="w-3 h-3" />
            </button>
          </div>
        );
      })}
      <Button
        variant="ghost"
        size="icon"
        className="w-7 h-7 shrink-0"
        onClick={handleOpenProject}
      >
        <Plus className="w-4 h-4" />
      </Button>
    </div>
  );
}
```

- [ ] **Step 3: Create AppLayout shell**

Create `frontend/src/components/layout/AppLayout.tsx`:

```tsx
"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";
import Sidebar from "./Sidebar";
import ProjectTabs from "./ProjectTabs";
import { useProjectStore } from "@/stores/projectStore";
import { useSessionStore } from "@/stores/session";
import EmptyState from "@/components/shared/EmptyState";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { projects, activeProjectId, loadActiveProjects } = useProjectStore();
  const { getProjectSession } = useSessionStore();

  useEffect(() => {
    loadActiveProjects();
  }, []);

  const hasProjects = projects.length > 0;

  if (!hasProjects && pathname !== "/") {
    return (
      <div className="flex h-screen">
        <Sidebar />
        <div className="flex-1 flex items-center justify-center">
          <EmptyState
            title="No projects open"
            description="Open a dataset to get started"
            actionLabel="Open Project"
            onAction={() => {}}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-screen">
      <Sidebar />
      <div className="flex flex-col flex-1 overflow-hidden">
        <ProjectTabs />
        <main className="flex-1 overflow-auto p-4 bg-background">
          {children}
        </main>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Update root layout to use AppLayout**

Modify `frontend/src/app/layout.tsx`:

```tsx
import type { Metadata } from "next";
import "./globals.css";
import { QueryProvider } from "@/components/layout/QueryProvider";
import AppLayout from "@/components/layout/AppLayout";
import { Toaster } from "sonner";

export const metadata: Metadata = {
  title: "ImageTagger",
  description: "AI-powered image tagging and dataset management",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className="antialiased">
        <QueryProvider>
          <AppLayout>{children}</AppLayout>
        </QueryProvider>
        <Toaster theme="dark" position="top-right" />
      </body>
    </html>
  );
}
```

- [ ] **Step 5: Delete old DatasetHeader**

```bash
rm frontend/src/components/layout/DatasetHeader.tsx
```

- [ ] **Step 6: Commit**

```bash
cd frontend && git add src/components/layout/ src/app/layout.tsx
git commit -m "feat: create new layout shell with project tabs and expanded sidebar"
```

---

### Task 7: Shared Components — EmptyState, LoadingSkeleton, ConfirmDialog

**Files:**
- Create: `frontend/src/components/shared/EmptyState.tsx`
- Create: `frontend/src/components/shared/LoadingSkeleton.tsx`
- Modify: `frontend/src/components/shared/ConfirmDialog.tsx`

- [ ] **Step 1: Create EmptyState component**

Create `frontend/src/components/shared/EmptyState.tsx`:

```tsx
"use client";

import { Button } from "@/components/ui/button";
import { LucideIcon } from "lucide-react";

interface EmptyStateProps {
  title: string;
  description: string;
  actionLabel?: string;
  onAction?: () => void;
  icon?: LucideIcon;
}

export default function EmptyState({
  title,
  description,
  actionLabel,
  onAction,
  icon: Icon,
}: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-center">
      {Icon && <Icon className="w-12 h-12 text-text-muted mb-4" />}
      <h3 className="text-lg font-medium text-text mb-1">{title}</h3>
      <p className="text-sm text-text-secondary mb-4 max-w-sm">{description}</p>
      {actionLabel && onAction && (
        <Button onClick={onAction}>{actionLabel}</Button>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Create LoadingSkeleton component**

Create `frontend/src/components/shared/LoadingSkeleton.tsx`:

```tsx
"use client";

import { cn } from "@/lib/utils";

interface SkeletonProps {
  className?: string;
  count?: number;
}

export function Skeleton({ className, count = 1 }: SkeletonProps) {
  return (
    <>
      {Array.from({ length: count }).map((_, i) => (
        <div
          key={i}
          className={cn(
            "animate-pulse rounded-md bg-surface-raised",
            className
          )}
        />
      ))}
    </>
  );
}

export function GallerySkeleton({ count = 12 }: { count?: number }) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-3">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="aspect-square rounded-lg bg-surface-raised animate-pulse" />
      ))}
    </div>
  );
}

export function EditPageSkeleton() {
  return (
    <div className="flex gap-4 h-full">
      <div className="flex-1 rounded-lg bg-surface-raised animate-pulse" />
      <div className="w-80 flex flex-col gap-3">
        <div className="h-32 rounded-lg bg-surface-raised animate-pulse" />
        <div className="flex-1 rounded-lg bg-surface-raised animate-pulse" />
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Refactor ConfirmDialog to use shadcn**

Read the existing `ConfirmDialog.tsx` and replace with:

```tsx
"use client";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";

interface ConfirmDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description: string;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: "default" | "destructive";
  onConfirm: () => void;
}

export default function ConfirmDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel = "Confirm",
  cancelLabel = "Cancel",
  variant = "default",
  onConfirm,
}: ConfirmDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            {cancelLabel}
          </Button>
          <Button
            variant={variant === "destructive" ? "destructive" : "default"}
            onClick={() => {
              onConfirm();
              onOpenChange(false);
            }}
          >
            {confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 4: Commit**

```bash
cd frontend && git add src/components/shared/
git commit -m "feat: add EmptyState, LoadingSkeleton, refactor ConfirmDialog"
```

---

### Task 8: Browse Page Redesign

**Files:**
- Modify: `frontend/src/app/browse/page.tsx`
- Modify: `frontend/src/components/browse/GalleryGrid.tsx`

- [ ] **Step 1: Update GalleryGrid with card-style thumbnails**

Read existing `GalleryGrid.tsx` and update to use new theme classes, card-style thumbnails with hover effects, loading skeletons, and proper pagination. Key changes:
- Replace `bg-zinc-900` with `bg-surface`
- Replace `border-zinc-700` with `border-border`
- Add hover effect: `hover:shadow-lg hover:shadow-primary/5 hover:-translate-y-0.5 transition-all`
- Add rounded corners: `rounded-lg`
- Replace "Loading..." text with `<GallerySkeleton />`
- Update bookmark star to use Lucide `Star` icon
- Pagination footer uses `Button` components

- [ ] **Step 2: Update browse page**

Update `frontend/src/app/browse/page.tsx` to check project state and show EmptyState when no project is loaded.

- [ ] **Step 3: Commit**

```bash
cd frontend && git add src/app/browse/ src/components/browse/
git commit -m "feat: redesign browse page with card-style gallery"
```

---

### Task 9: Edit Page Redesign

**Files:**
- Modify: `frontend/src/app/edit/page.tsx`
- Modify: `frontend/src/components/edit/ImageViewer.tsx`
- Modify: `frontend/src/components/edit/ImageToolbar.tsx`
- Modify: `frontend/src/components/edit/NavigationBar.tsx`
- Modify: `frontend/src/components/edit/CaptionEditor.tsx`

- [ ] **Step 1: Redesign EditPage with two-column layout**

Update `EditPage` to use a two-column layout: media viewer (~60%) on the left, caption editor + metadata on the right. Use `EditPageSkeleton` for loading state. Replace empty state with `EmptyState` component. Use theme tokens for all colors.

- [ ] **Step 2: Update ImageViewer with zoom controls**

Add zoom in/out buttons using Lucide `ZoomIn`/`ZoomOut` icons. Center the image with `object-contain`. Add overlay prev/next arrows using Lucide `ChevronLeft`/`ChevronRight`.

- [ ] **Step 3: Update ImageToolbar with icon buttons**

Replace text buttons with icon buttons using shadcn `Button` with `variant="outline"` and `size="icon"`. Add `Tooltip` wrappers for each action. Use semantic colors: `variant="destructive"` for delete.

- [ ] **Step 4: Update NavigationBar**

Make it compact: prev/next icon buttons + position indicator + range slider. Use `Slider` or range input with theme styling.

- [ ] **Step 5: Update CaptionEditor**

Wrap in a card-style container (`bg-surface rounded-lg border border-border p-4`). Use shadcn `Select` for tagger selector. Use shadcn `Button` for Generate/Save.

- [ ] **Step 6: Commit**

```bash
cd frontend && git add src/app/edit/ src/components/edit/
git commit -m "feat: redesign edit page with two-column layout"
```

---

### Task 10: Captions Page Redesign

**Files:**
- Modify: `frontend/src/app/captions/page.tsx`
- Modify: `frontend/src/components/captions/TagCloud.tsx`
- Modify: `frontend/src/components/captions/TagOperations.tsx`
- Modify: `frontend/src/components/captions/SearchReplace.tsx`

- [ ] **Step 1: Redesign captions page with two-column layout**

Tag cloud on left, operations panel on right. Use `bg-surface` cards for each operation section. Use `Badge` components for tag frequency display. Use `ScrollArea` for the tag cloud container.

- [ ] **Step 2: Update TagCloud**

Add search input at top. Use `Badge` for each tag with frequency count. Selected tags use `bg-primary` badge. Add "Select All" / "Clear" buttons using shadcn `Button variant="ghost"`.

- [ ] **Step 3: Update TagOperations**

Each operation in its own card section. Use shadcn `Button` variants. Show selection count in sticky footer with "Apply to X tags" button.

- [ ] **Step 4: Update SearchReplace**

Live preview using a table or list showing before/after diff. Use `Badge` for matched text highlighting. Apply button uses `variant="default"`.

- [ ] **Step 5: Commit**

```bash
cd frontend && git add src/app/captions/ src/components/captions/
git commit -m "feat: redesign captions page with two-column layout"
```

---

### Task 11: Batch Page Redesign

**Files:**
- Modify: `frontend/src/app/batch/page.tsx`
- Modify: `frontend/src/components/batch/BatchForm.tsx`
- Modify: `frontend/src/components/batch/ProgressLog.tsx`

- [ ] **Step 1: Redesign batch page with card-based operation selector**

Display operations as a grid of cards (Rename, Upscale, Bucket Resize, Masks, Captions). Each card has an icon, title, and description. Clicking selects the operation and reveals its configuration form below.

- [ ] **Step 2: Update BatchForm**

Use shadcn `Checkbox`, `Input`, `Select` for form fields. "Run Batch" button prominent at bottom. Use `toast` for success/error messages instead of inline text.

- [ ] **Step 3: Update ProgressLog**

Use shadcn `Progress` for the progress bar. Expandable log panel using a collapsible section. Results summary card after completion.

- [ ] **Step 4: Commit**

```bash
cd frontend && git add src/app/batch/ src/components/batch/
git commit -m "feat: redesign batch page with card-based operation selector"
```

---

### Task 12: Tools, Validation, Settings Pages Redesign

**Files:**
- Modify: `frontend/src/app/tools/page.tsx`
- Modify: `frontend/src/app/validation/page.tsx`
- Modify: `frontend/src/app/settings/page.tsx`

- [ ] **Step 1: Redesign tools page**

Card-based layout per tool. Copy Images tool: target directory input with shadcn `Input`, scope selector with shadcn `Select`, progress with `Progress`.

- [ ] **Step 2: Redesign validation page**

Visual distribution chart for resolution buckets (bar chart using divs with heights proportional to counts). Run analysis button with progress indicator. Actionable recommendations as a list.

- [ ] **Step 3: Redesign settings page**

Grouped sections (Upscaler, Tagger, Background Removal, API Config) using collapsible cards. Auto-save indicators with `toast`. Form validation feedback. Use shadcn `Input`, `Select`, `Checkbox` throughout.

- [ ] **Step 4: Commit**

```bash
cd frontend && git add src/app/tools/ src/app/validation/ src/app/settings/
git commit -m "feat: redesign tools, validation, and settings pages"
```

---

### Task 13: Update Home Page and Clean Up

**Files:**
- Modify: `frontend/src/app/page.tsx`
- Delete: old unused components

- [ ] **Step 1: Update home page**

Update `frontend/src/app/page.tsx` to check if there are active projects. If yes, redirect to `/browse`. If no, show a welcome screen with "Open Project" button and recent projects list.

- [ ] **Step 2: Run lint and build**

```bash
cd frontend && npm run lint
cd frontend && npm run build
```

Fix any TypeScript errors, unused imports, or missing types.

- [ ] **Step 3: Final commit**

```bash
cd frontend && git add -A
git commit -m "feat: complete frontend redesign with multi-project support"
```

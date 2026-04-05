# Frontend Redesign & Multi-Project Support — Design Spec

## Overview

Redesign the ImageTagger2 frontend from a minimal zinc-dark shell into a modern dashboard-style application with multi-project support, shadcn/ui components, Lucide icons, and a structured layout system. All pages redesigned simultaneously.

## Design Decisions

| Decision | Choice |
|----------|--------|
| Design direction | Modern Dashboard (slate palette, blue accents, card-based) |
| Icon library | Lucide React |
| Accent colors | Single accent palette with semantic variants (blue/green/amber/red) |
| Sidebar | Expanded text + icons (~240px) |
| UI components | shadcn/ui |
| Dataset header | Page-specific headers, project tabs replace global header |
| Multi-project | Full multi-project (backend + frontend) |
| Project UI | Project tabs pattern |
| Implementation | Structured Redesign (all pages together, clean architecture) |

## Architecture

### Layout Structure

```
┌─────────────────────────────────────────────────────────────┐
│  Project Tabs Bar                                           │
│  [📁 Dataset A ▼] [📁 Dataset B ▼] [+]                     │
├──────────┬──────────────────────────────────────────────────┤
│          │  Page Header (contextual per page)               │
│ Sidebar  │  ┌────────────────────────────────────────────┐  │
│          │  │ Page-specific controls                     │  │
│  📁 Proj │  └────────────────────────────────────────────┘  │
│  🖼 Browse│                                                  │
│  ✏️ Edit │  Main Content Area                             │
│  🏷 Tags  │  ┌────────────────────────────────────────────┐ │
│  📦 Batch│  │                                            │ │
│  🛠 Tools │  │  Page-specific content                     │ │
│  ✅ Valid│  │                                            │ │
│  ⚙ Set'gs│  └────────────────────────────────────────────┘ │
├──────────┴──────────────────────────────────────────────────┤
│  Status Bar (optional)                                     │
└─────────────────────────────────────────────────────────────┘
```

### Component Structure

```
frontend/src/
├── app/
│   ├── layout.tsx              # Root: providers, dark mode, AppLayout
│   ├── page.tsx                # Redirect to /browse or show project picker
│   ├── browse/page.tsx
│   ├── edit/page.tsx
│   ├── captions/page.tsx
│   ├── batch/page.tsx
│   ├── tools/page.tsx
│   ├── validation/page.tsx
│   └── settings/page.tsx
├── components/
│   ├── layout/
│   │   ├── AppLayout.tsx       # Main shell: tabs + sidebar + content area
│   │   ├── ProjectTabs.tsx     # Tab bar with dropdown actions
│   │   ├── Sidebar.tsx         # Expanded nav with icons + labels
│   │   ├── PageHeader.tsx      # Contextual page header wrapper
│   │   └── StatusBar.tsx       # Optional bottom status bar
│   ├── ui/                     # shadcn/ui components (auto-generated)
│   │   ├── button.tsx
│   │   ├── dialog.tsx
│   │   ├── dropdown-menu.tsx
│   │   ├── input.tsx
│   │   ├── tabs.tsx
│   │   ├── tooltip.tsx
│   │   ├── toast.tsx
│   │   ├── select.tsx
│   │   ├── checkbox.tsx
│   │   ├── badge.tsx
│   │   ├── progress.tsx
│   │   ├── separator.tsx
│   │   └── scroll-area.tsx
│   ├── shared/
│   │   ├── ConfirmDialog.tsx   # Refactored to use shadcn dialog
│   │   ├── EmptyState.tsx      # Reusable empty state component
│   │   └── LoadingSkeleton.tsx # Skeleton loaders
│   ├── browse/
│   │   ├── GalleryGrid.tsx
│   │   └── GalleryFilters.tsx
│   ├── edit/
│   │   ├── ImageViewer.tsx
│   │   ├── VideoPlayer.tsx
│   │   ├── CaptionEditor.tsx
│   │   ├── ImageToolbar.tsx
│   │   └── NavigationBar.tsx
│   ├── batch/
│   │   ├── BatchForm.tsx
│   │   └── ProgressLog.tsx
│   ├── captions/
│   │   ├── TagCloud.tsx
│   │   ├── TagOperations.tsx
│   │   └── SearchReplace.tsx
│   ├── tools/
│   │   └── CopyImagesTool.tsx
│   ├── validation/
│   │   └── ValidationResults.tsx
│   └── settings/
│       └── SettingsForm.tsx
├── stores/
│   ├── useProjectStore.ts      # Multi-project state management
│   └── useSessionStore.ts      # Per-project session state (refactored)
├── lib/
│   ├── api.ts                  # Updated for multi-project sessions
│   ├── types.ts                # Extended with Project interface
│   └── utils.ts                # cn() utility for shadcn/ui
└── styles/
    └── globals.css             # Theme tokens via Tailwind v4 @theme
```

## Multi-Project State Management

### Backend Changes

1. **Session Manager** (`backend/app/sessions.py`): Support multiple concurrent dataset sessions. Each session has its own state (dataset path, masks path, current index, filters).

2. **New API Endpoints**:
   - `POST /api/projects/open` — Open a dataset, returns session ID
   - `DELETE /api/projects/{session_id}` — Close a project session
   - `GET /api/projects` — List all active project sessions
   - `GET /api/projects/{session_id}/info` — Get project info

3. **Existing Endpoints**: Continue to work within a project context via `X-Session-ID` header. No changes to endpoint signatures needed.

### Frontend State

**Project Store** (`useProjectStore`):
```typescript
interface Project {
  id: string;
  name: string;
  path: string;
  masksPath?: string;
  currentIndex: number;
  currentItem: MediaItem | null;
  isLoading: boolean;
  error: string | null;
}

interface ProjectState {
  projects: Project[];
  activeProjectId: string | null;
  openProject: (path: string, masksPath?: string) => Promise<string>;
  closeProject: (id: string) => void;
  switchProject: (id: string) => void;
}
```

**Per-Project Session State** (refactored from existing `useSessionStore`):
- Each project maintains its own `currentIndex`, `currentItem`, `isLoading`, `error`
- Switching projects updates the active context without losing state
- All API calls use the `activeProjectId` as the `X-Session-ID` header

### Project Tab Behavior

- Opening a project calls `POST /api/projects/open`, creates a new session, adds tab
- Tab displays dataset name (truncated if long) with close button
- Click tab switches context — all page content reflects that project
- Closing last project shows empty state with "Open Project" prompt
- Each tab maintains independent navigation position and filters
- Dropdown on tab: Close, Close Others, Close All, Open Location

## Design System

### Theme Tokens (Tailwind v4 `@theme`)

```css
@theme {
  --color-background: #0f172a;
  --color-surface: #1e293b;
  --color-surface-raised: #334155;
  --color-border: #334155;
  --color-border-subtle: #475569;
  --color-primary: #3b82f6;
  --color-primary-hover: #2563eb;
  --color-success: #22c55e;
  --color-warning: #f59e0b;
  --color-danger: #ef4444;
  --color-text: #f8fafc;
  --color-text-secondary: #94a3b8;
  --color-text-muted: #64748b;
}
```

### shadcn/ui Components

Install: `button`, `dialog`, `dropdown-menu`, `input`, `tabs`, `tooltip`, `toast` (sonner), `select`, `checkbox`, `badge`, `progress`, `separator`, `scroll-area`.

### Dependencies Added

- `lucide-react` — Icon library
- `shadcn/ui` components — UI component primitives
- `clsx` + `tailwind-merge` — Class name utilities (`cn()` helper)
- `sonner` — Toast notifications
- `class-variance-authority` — shadcn/ui dependency for button variants

## Page Specifications

### Browse Page

- Card-style thumbnail grid with hover lift effect
- Top bar: search/filter input, sort dropdown, view toggle (grid/list)
- Bookmark star badge on cards
- Loading skeletons replacing "Loading..." text
- Pagination footer with page numbers
- Empty state with "Open Dataset" CTA

### Edit Page

- Two-column layout: media viewer (~60%) + caption editor & metadata
- Media viewer: centered with zoom controls, prev/next overlay arrows
- Caption editor: card-style panel with tagger selector, generate/save
- Image info bar: filename, dimensions, quick action icon buttons with tooltips
- Navigation: compact prev/next + position indicator in page header
- Bookmark toggle as prominent icon button

### Captions Page

- Two-column layout: tag cloud (left) + operations panel (right)
- Tag cloud: searchable, frequency badges, selection highlights
- Operations: card-based sections (Remove, Cleanup, Export, Append/Prepend, Move)
- Search & replace: dedicated section with live before/after diff preview
- Selection count and "Apply to X tags" button in sticky footer

### Batch Page

- Operation selector as card grid (Rename, Upscale, Bucket Resize, Masks, Captions)
- Selecting operation reveals configuration form in slide-down panel
- "Run Batch" prominent button
- Full-width progress bar + expandable log panel
- Results summary card after completion
- Bucket analysis as collapsible section with visual distribution

### Tools Page

- Card-based layout per tool with description and action buttons
- Copy Images tool: target directory input, scope selector (all/bookmarked), progress

### Validation Page

- Visual distribution chart for resolution buckets
- Actionable recommendations
- Run analysis button with progress indicator

### Settings Page

- Grouped sections (Upscaler, Tagger, Background Removal, API Config)
- Collapsible sections
- Auto-save indicators
- Form validation feedback

## Error Handling

- Toast notifications for errors (replacing inline text messages)
- Page-level error boundaries with retry option
- Loading states: skeletons for content areas, spinners for actions
- Empty states with contextual CTAs
- Network error handling with retry logic in React Query

## Migration Strategy

1. Install dependencies (lucide-react, shadcn/ui, sonner, clsx, tailwind-merge)
2. Set up theme tokens in `globals.css`
3. Create `cn()` utility and shadcn/ui component base
4. Build layout shell (AppLayout, ProjectTabs, Sidebar, PageHeader)
5. Implement multi-project store and backend endpoints
6. Redesign each page using new components and layout
7. Replace ConfirmDialog with shadcn dialog
8. Add toast notifications, loading skeletons, empty states
9. Remove old layout components and unused code

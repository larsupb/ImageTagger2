# AGENTS.md — ImageTagger2

AI-powered image tagging and dataset management tool. FastAPI backend + Next.js 15 frontend.

## Quick Start

```bash
./run.sh        # starts backend :8000 + frontend :3000
./shutdown.sh   # stops both
```

## Project Structure

```
ImageTagger2/
├── backend/              # Python 3.12+ / FastAPI
│   ├── app/
│   │   ├── routers/      # API endpoints (dataset, media, captions, processing, tagging, batch, settings)
│   │   ├── services/     # Business logic (caption, dataset, processing, tagger)
│   │   ├── models/       # Pydantic schemas
│   │   ├── config.py     # Settings management (settings.json)
│   │   ├── sessions.py   # Session manager + get_session dependency
│   │   └── main.py       # FastAPI app entry
│   └── lib/              # Shared utilities (tagging, upscaling, bucketing, image_dataset)
├── frontend/             # Next.js 15 / React 19 / TypeScript
│   └── src/
│       ├── app/          # App router pages (browse, edit, captions, batch, tools, validation, settings)
│       ├── components/   # Feature-scoped component dirs + shared/
│       ├── lib/          # API client (api.ts), types (types.ts)
│       └── stores/       # Zustand session store
└── run.sh                # Starts both servers
```

## Build / Lint / Test Commands

### Backend (Python / FastAPI)

```bash
cd backend

# Install dependencies
pip install -r requirements.txt

# Run dev server
uvicorn app.main:app --reload --port 8000

# No linter/formatter configured yet. Use ruff or black if adding linting:
# pip install ruff
# ruff check .
# ruff format .
```

### Frontend (Next.js / TypeScript)

```bash
cd frontend

# Install dependencies
npm install

# Dev server
npm run dev

# Production build
npm run build

# Start production server
npm start

# Lint (ESLint via Next.js)
npm run lint
```

### Running Both

```bash
./run.sh
```

### Running a Single Test

No test framework is currently configured. When adding tests:

- **Backend**: Use `pytest`. Run single test: `pytest tests/test_file.py::test_function -v`
- **Frontend**: Use `jest` or `vitest`. Run single test: `npm test -- --testPathPattern=file.test.ts`

## Code Style & Conventions

### Python (Backend)

- **Formatting**: 4-space indentation, double quotes preferred
- **Imports**: Standard library → third-party → local. Group with blank line between groups
- **Types**: Use type hints on all function signatures. Pydantic v2 for request/response schemas
- **Naming**: `snake_case` for functions/variables, `PascalCase` for classes
- **Error handling**: Raise `HTTPException(status_code, detail)` for API errors. Use `try/except` with specific exception types
- **Routers**: Define in `app/routers/`. Use `APIRouter` with prefix (e.g., `prefix="/api/dataset"`)
- **Services**: Business logic in `app/services/`. Routers thin, delegating to services
- **Settings**: Stored in `backend/settings.json`. Use `app.config` functions (`read_settings`, `save_settings`, `update_setting`, `get_setting`)

### TypeScript (Frontend)

- **Strict mode**: `strict: true` in tsconfig.json. No `any` types
- **Imports**: Use `@/` path alias for `src/` imports (e.g., `@/lib/api`, `@/components/shared/...`)
- **Components**: `.tsx` files. Use functional components with hooks. PascalCase filenames
- **Pages**: App router convention. Directory = route segment, `page.tsx` = route handler
- **State**: Zustand for global session state. React Query (`@tanstack/react-query`) for server state
- **API calls**: Use `@/lib/api` client. All requests include `X-Session-ID` header from session store
- **Styling**: Tailwind CSS 4. Use utility classes. Avoid inline styles
- **Naming**: `camelCase` for variables/functions, `PascalCase` for components, `kebab-case` for CSS classes (if any)
- **Error handling**: Use try/catch with user-facing error messages. Leverage React Query error states

### General

- **No emojis** in code or UI
- **No comments** unless explaining non-obvious behavior
- **Commit messages**: Present tense, imperative mood (e.g., "Add batch export feature")
- **Architecture**: Frontend proxies `/api/:path*` to FastAPI via Next.js rewrites (no CORS in dev)
- **Sessions**: In-memory. Each session holds an `ImageDataSet`. All endpoints (except `/health`) require `X-Session-ID` header
- **Batch progress**: SSE streaming on `/api/batch/process` — use `EventSource` client-side
- **Git**: Repo with submodules (`backend/` and `frontend/`). Use `git clone --recursive` or `git submodule update --init` after clone

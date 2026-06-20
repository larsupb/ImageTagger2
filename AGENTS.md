# AGENTS.md — ImageTagger2

AI-powered image tagging and dataset management tool. FastAPI backend + Next.js 15 frontend.

## Quick Start

```bash
./run.sh        # starts backend :8000 + frontend :3000
./shutdown.sh   # stops both
```

## Project Structure

```
backend/              # Python 3.12+ / FastAPI
├── app/
│   ├── main.py       # FastAPI entry point
│   ├── config.py     # Settings (backend/settings.json)
│   ├── sessions.py   # Session manager + get_session dependency
│   ├── routers/      # Thin HTTP layer → services (dataset, media, captions, processing, tagging, batch, settings, projects)
│   ├── services/     # Business logic (caption_service, processing_service, etc.)
│   └── models/       # Pydantic schemas
└── lib/              # Tagging (JoyTag, WD14, Florence-2, Qwen2-VL, VLM), upscaling (Spandrel), bucketing, masking

frontend/             # Next.js 15 / React 19 / TypeScript
└── src/
    ├── app/          # Pages: browse, edit, captions, batch, tools, validation, settings
    ├── components/   # shadcn (Radix) + @base-ui components
    ├── lib/          # api.ts, types.ts
    └── stores/       # Zustand (session.ts, projectStore.ts) + React Query for server state
```

## Developer Commands

### Backend

```bash
cd backend
source .venv/bin/activate              # activates venv (required — run.sh does this too)
uvicorn app.main:app --reload --port 8000
pip install -r requirements.txt       # install deps
pytest                                 # run all tests
pytest tests/test_file.py::test_name   # run single test
```

### Frontend

```bash
cd frontend
npm install
npm run dev      # dev server :3000
npm run build    # production build
npm run lint     # ESLint
```

## Key Conventions

- **No emojis** in code or UI
- **No comments** unless explaining non-obvious behavior
- **Routers thin**: delegate logic to services
- **No `any` types** in TypeScript (strict mode)

### API Proxy
Next.js rewrites `/api/:path*` → `http://localhost:8000/api/:path*` (next.config.ts). No CORS config needed in dev.

### Sessions
All endpoints (except `/health`) require `X-Session-ID` header. Media endpoints also accept `session_id` query param.

### Batch Progress
SSE streaming on `/api/batch/process` — use `EventSource` client-side.

### Settings
Stored in `backend/settings.json`. Use `app.config` functions (`read_settings`, `save_settings`, `update_setting`, `get_setting`).
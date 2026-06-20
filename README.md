# ImageTagger 2

AI-powered image tagging and dataset management tool. Rebuilt as a modern Next.js + FastAPI application.

## Architecture

```
ImageTagger2/
├── backend/          # FastAPI REST API
│   ├── app/
│   │   ├── routers/  # API endpoints (dataset, media, captions, processing, tagging, batch, settings)
│   │   ├── services/ # Business logic
│   │   ├── models/   # Pydantic schemas
│   │   ├── sessions.py
│   │   ├── config.py
│   │   └── main.py
│   └── lib/          # Copied from original ImageTagger (tagging, upscaling, bucketing, etc.)
├── frontend/         # Next.js 15 + Tailwind CSS 4
│   └── src/
│       ├── app/      # Pages (browse, edit, captions, batch, tools, validation, settings)
│       ├── components/
│       ├── lib/      # API client, types
│       └── stores/   # Zustand session store
└── run.sh            # Convenience startup script
```

## Features

- **Browse** — Paginated gallery view with thumbnails and bookmark indicators
- **Edit** — Full image viewer with keyboard navigation, caption editor, AI tagger integration, upscaling, background removal, mask generation
- **Captions** — Tag cloud with frequency/alphabetical sorting, bulk tag operations (remove, append, prepend, cleanup), search & replace with preview, JSONL export, move to subdirectory
- **Batch** — Process entire datasets with rename, upscale, bucket resize, mask generation, and captioning. SSE-based progress streaming
- **Tools** — Copy images (all or bookmarked) to target directory
- **Validation** — Dataset validation with bucket distribution analysis
- **Settings** — Configure upscaler, taggers, Florence prompt, rembg model, VLM Tagger API (Ollama, etc.), models directory

## Supported Taggers

| Tagger | Description |
|--------|-------------|
| JoyTag | Vision model-based tag generation |
| WD14 | Waifu Diffusion 14 ONNX tagger |
| Florence-2 | Detailed caption generation with configurable prompts |
| Qwen2-VL | Alibaba's vision-language model |
| VLM Tagger | API-based (Ollama, LM Studio, etc.) |
| Ideogram | Structured JSON captioning via VLM API — outputs scene, style, color, and subject fields |
| Combo | Combination of selected taggers |

## Quick Start

### Prerequisites

- Python 3.12+
- Node.js 18+
- npm

### Backend

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

### Frontend

```bash
cd frontend
npm install
npm run dev
```

Or use the convenience script:

```bash
./run.sh
```

Open http://localhost:3000 (or your configured port).

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/dataset/session` | Create a new session |
| POST | `/api/dataset/load` | Load a dataset from directory |
| GET | `/api/dataset/gallery` | Get paginated gallery |
| GET | `/api/dataset/item/{index}` | Get item details |
| POST | `/api/dataset/bookmark/{index}` | Toggle bookmark |
| DELETE | `/api/dataset/item/{index}` | Delete item |
| PUT | `/api/dataset/item/{index}/rename` | Rename item |
| GET | `/api/media/file/{index}` | Serve media file |
| GET | `/api/media/thumbnail/{index}` | Serve thumbnail |
| GET | `/api/media/mask/{index}` | Serve mask |
| PUT | `/api/captions/save` | Save caption |
| GET | `/api/captions/tags` | Get tag cloud |
| POST | `/api/captions/tags/remove` | Remove tags |
| POST | `/api/captions/tags/append` | Append tag |
| POST | `/api/captions/tags/prepend` | Prepend tag |
| POST | `/api/captions/tags/cleanup` | Cleanup tags |
| POST | `/api/captions/search-replace/preview` | Preview search & replace |
| POST | `/api/captions/search-replace/apply` | Apply search & replace |
| POST | `/api/captions/export` | Export captions as JSONL |
| POST | `/api/captions/move-to-subdir` | Move images to subdirectory |
| POST | `/api/tagging/generate` | Generate caption with tagger |
| POST | `/api/processing/upscale` | Upscale image |
| POST | `/api/processing/upscale/save` | Save upscaled image |
| POST | `/api/processing/remove-background` | Remove background |
| POST | `/api/processing/mask/generate` | Generate mask |
| POST | `/api/batch/process` | Batch process (SSE) |
| POST | `/api/batch/analyze-buckets` | Analyze bucket distribution |
| GET | `/api/settings/` | Get settings |
| PUT | `/api/settings/` | Update setting |
| GET | `/api/settings/upscalers` | List available upscalers |
| GET | `/api/settings/taggers` | List available taggers |
| POST | `/api/settings/tools/copy` | Copy images |
| GET | `/api/settings/validation` | Validate dataset |

## Session Management

All API calls (except health check) require a session ID via the `X-Session-ID` header. Media endpoints also accept `session_id` as a query parameter for `<img>` and `<video>` tags.

```bash
# Create session
curl -X POST http://localhost:8000/api/dataset/session
# → {"session_id": "uuid..."}

# Use session
curl -H "X-Session-ID: uuid..." http://localhost:8000/api/dataset/gallery
```

## Configuration

Settings are stored in `backend/settings.json`. Defaults:

```json
{
  "models_dir": "models",
  "upscaler": "NMKD_Siax_200k_4x",
  "upscale_target_megapixels": 2.0,
  "combo_taggers": ["florence", "wd14"],
  "florence_settings": { "prompt": "<DETAILED_CAPTION>" },
  "rembg": { "model": "u2net_human_seg" },
  "openai_settings": {
    "base_url": "http://localhost:11434/v1",
    "model": "qwen3:32b",
    "prompt": "Describe the image in continuous text."
  }
}
```

## Changelog

### 2026-06-20

- **Ideogram tagger** — New structured JSON captioning tagger that calls a VLM API (Ollama, LM Studio, etc.) and returns a rich schema: high-level description, style, color palette, subject, and mood fields. Output is serialized into a single caption string compatible with the rest of the pipeline.
- **musubi_control / musubi_control_json export** — Two new export formats targeting the Musubi Tuner training framework. `musubi_control` exports image–caption pairs in the expected directory layout; `musubi_control_json` produces a JSON manifest with per-image metadata.
- **Mask edit mode** — Paint directly on the generated mask in the Edit page to refine segmentation results before saving.
- **Paint mode** — Free-hand paint overlay on images in the Edit page (pencil and eraser tools, configurable brush size and color).
- **Category-aware Edit navigation** — Prev/next buttons, arrow keys, and the slider on the Edit page now navigate within the current image's category. The counter shows position within the category (e.g. "3 / 8"). Falls back to global navigation when gallery data is not cached.

## License

MIT

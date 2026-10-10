# Semantic Search via Caption Embeddings — Design

Date: 2026-10-11
Status: approved by user (verbally), pending spec review

## Problem

Datasets contain free-text VLM captions plus 10 categorical attributes, but
browsing is limited to exact attribute/category filters and filename guessing.
Users want to find images "like *person looking over shoulder in warm evening
light*" — things not captured by the controlled vocabularies.

## Solution

Per-dataset vector store of caption embeddings. Captions are embedded with a
remote OpenAI-compatible embedding endpoint; queries are embedded with the
same model and ranked by cosine similarity. Search is exposed as a search box
in the browse grid and as an HTTP API. Indexing is an on-demand job plus an
opt-in hook into the batch captioning run.

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| What to embed | Captions only (no image/CLIP embeddings) |
| Where to embed | Remote OpenAI-compatible `/v1/embeddings` endpoint |
| Where exposed | Search box in browse grid + HTTP API |
| When to index | On-demand index job + hook in batch captioning |
| Storage/retrieval | sqlite BLOB + in-memory numpy brute force (approach A) |

## Data model

New table inside the existing per-dataset `.imagetagger/metadata.db`, created
`IF NOT EXISTS` at project open (same zero-migration pattern as attributes):

```sql
CREATE TABLE IF NOT EXISTS caption_vectors (
    image_id   INTEGER PRIMARY KEY REFERENCES images(id) ON DELETE CASCADE,
    model      TEXT    NOT NULL,
    dim        INTEGER NOT NULL,
    embedding  BLOB    NOT NULL,           -- float32 little-endian, normalized at write time
    text_hash  TEXT    NOT NULL,           -- sha256 hex of the embedded caption text
    updated_at TEXT    NOT NULL
);
```

- One row per image: the embedding of its **active caption** (the
  `captions` table row with `is_active = 1` — whatever type the user has
  selected, typically the generated description).
- Staleness is derived, never tracked separately: an image needs (re-)indexing
  when it has an active caption and **no row**, or `text_hash` differs from
  `sha256(active caption)`, or `model` differs from the configured model.
- Deleting an image removes its vector via FK cascade. Caption edits/regenerations
  need no bookkeeping — the hash mismatch marks them at the next index run.

## Embedding endpoint configuration

New `settings.json` key `embedding_endpoint`, mirroring the shape of
`vlm_endpoint`:

```json
{"base_url": "...", "api_key": "...", "model": "qwen3-embedding-8b", "timeout": 120}
```

Defaults seeded from the existing `llm_endpoint` values (same host/key,
`qwen3-embedding-8b`). Editable on the Settings page. Changing `model` marks
every vector stale (re-embed all).

## Backend service

`app/services/embedding_service.py`:

- `embed_texts(texts: list[str], settings) -> np.ndarray (n, dim)` —
  `POST {base_url}/embeddings` with the batch as `input`, API-key header,
  timeout from settings, **one retry** on empty/malformed response (the
  remote endpoint is known to intermittently return 200 with empty bodies).
  Batch size 32 to keep payloads small and retries cheap.
- `index_dataset(session, task_id)` — background job through `task_service`
  (progress/pause/cancel semantics identical to attribute classification):
  select stale images (active caption read via `CaptionRepository.get_active`), embed in
  batches of 32, normalize, store float32 BLOB + `text_hash` + `model` +
  `updated_at` (`INSERT OR REPLACE`), and delete orphaned rows (image without
  a non-empty active caption). Task completes
  with an error count for images whose embedding failed, same convention as
  attributes.
- `search(session, query, limit, min_score)` — embed the query once, cosine
  similarity against the in-memory matrix, return ranked
  `(index, filename, score)` above `min_score`.
- In-memory matrix cache: built lazily per session on first search
  (`np.frombuffer` over the whole table, rows already L2-normalized so cosine
  is a dot product); invalidated when `COUNT(*)` or `MAX(updated_at)` of the
  table changes. `ponytail:` brute force O(n·d) is ~µs–ms up to ~50k images
  per dataset; upgrade path is sqlite-vec or a real ANN index.

## HTTP API

New thin router `app/routers/search.py` (session-guarded like all others):

- `GET /api/search?q=&limit=200&min_score=0.0`
  → `{results: [{index, filename, score}], indexed: int, pending: int, model: str}`
  `pending` = count of stale/new images (drives the UI affordance). `q` empty
  or missing → `results: []` (no implicit "show all").
  If **no** vectors exist yet and `q` is present → 400 `"search index is empty, index captions first"`.
- `POST /api/search/index` → `{task_id}` via `task_service`, name
  "Caption embedding index".

## Batch captioning integration

`BatchProcessRequest.embed_captions: bool = False` (UI checkbox
"Make captions searchable", default checked, placed with the existing
"Detect image attributes" checkbox). When set, after each caption is generated
in the batch loop, embed that single caption immediately and upsert the vector
row. Embedding failure logs `embedding: error` for that image and continues —
never aborts the run (identical error policy to `classify_attributes`).

## Frontend

- **Browse toolbar**: search input beside the `Filters` chip. Search fires on
  Enter and on 500 ms debounce after the user stops typing (remote call per
  search — no keystroke-per-request). Active search: grid shows only search
  results in score order, each tile with a small score badge; a clear (x)
  button restores normal browsing. Existing attribute/category filters
  intersect client-side over the current result set (same pattern as the
  attribute filters).
- **Staleness hint**: when `pending > 0`, a small "Index N captions" button
  next to the search box starts `POST /api/search/index`; progress visible in
  the existing Jobs drawer.
- **Settings page**: `embedding_endpoint` section — base URL, API key
  (masked), model name.

## Error handling

- Embedding endpoint unreachable/erroring: index job ends `failed` with the
  API error text in `error`; search returns 502 with a clear detail; the UI
  shows a toast. Nothing crashes, no partial-state writes (a failed batch of
  32 writes nothing; per-image rows upsert atomically).
- Zero vectors + non-empty `q` → 400 (above). Zero vectors + index job →
  completes with 0 processed.
- Caption deleted (or emptied): the stale vector keeps matching until the
  next index run, which deletes rows whose image has no non-empty active
  caption. No live bookkeeping.

## Testing

Fake the embeddings HTTP call (no network in tests, same style as the
attribute tests monkeypatching `lib.captioning.generate_caption`):

- `tests/test_embeddings.py` — `embed_texts` batching, retry-on-empty,
  normalization, error propagation.
- `tests/test_search_api.py` — index job indexes new, re-indexes changed
  captions and model-changed rows, skips fresh rows; `pending` counts;
  search returns nearest-first ranking with expected scores; `min_score`
  filtering; 400 on empty index; matrix cache invalidation after a re-index.
- Batch hook — `embed_captions=true` upserts a vector after a generated
  caption; embedding failure does not abort the run; `embed_captions=false`
  (default) writes no vectors.

## Out of scope

- Image/CLIP embeddings, hybrid (text+image) search.
- Cross-dataset/project-wide search.
- Similarity threshold tuning UI beyond a plain `min_score` API param.
- Embedding caption history (only the active caption is ever embedded).

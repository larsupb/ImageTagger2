# Image Attributes Design

## Overview

Add per-image categorical attributes (shot type, framing, camera angle, pose, ...) stored in the dataset's SQLite DB, classified automatically by a VLM with manual override in the UI. Two consumers:

1. **UI**: filter and curate images by attribute while working a dataset.
2. **Agent**: build balanced LoRA training sets by reading the dataset footprint, querying images by attribute, and pulling files by id — the selection logic stays agent-side; the server has no sampling opinion.

## Data Model

Zero migration. Attributes reuse the dormant `metadata` table (`backend/app/db/schema.py`):

- One row per set attribute: `(image_id, key=<attribute name>, value=<snake_case value>)`, `INSERT OR REPLACE` on set, `DELETE` to unset. Cascades with the image row.
- Absent row = not classified or not applicable (single state in v1).
- Values validated app-side against the vocabulary; no DB CHECK constraints.

## Vocabulary (`backend/app/attributes.py`)

Single Python dict `{attribute: {applies_to, values}}` serving validation, API docs, UI dropdowns and the classifier prompt. All attributes single-valued. `applies_to: "all" | "person"`; person-only attributes are never expected on images without a person (classifier returns null, UI hides them).

| attribute | applies_to | values |
|---|---|---|
| `shot_type` | all | selfie, headshot, upper_body_portrait, full_body_portrait, environmental_portrait, lifestyle, candid_street, group_shot, couple_shot, landscape, aerial, macro, architecture, interior, product, still_life, food, animal, sports_action, event |
| `framing` | all | extreme_close_up, close_up, medium_close_up, medium_shot, cowboy_shot, medium_wide, full_shot, wide_shot, extreme_wide |
| `camera_angle` | person | eye_level, low_angle, high_angle, birds_eye, worms_eye, dutch_angle, pov, over_the_shoulder |
| `subject_orientation` | person | frontal_looking_at_camera, frontal_looking_away, three_quarter, profile, back_view |
| `pose` | person | standing, walking, running_jumping, sitting, sitting_on_floor, kneeling, crouching, lying_reclining, leaning, dancing |
| `medium` | all | photo, illustration_anime, 3d_render, screenshot |
| `setting` | all | studio_plain, indoor_home, indoor_public, urban_outdoor, nature_outdoor, beach_water, snow |
| `lighting` | all | natural_soft, direct_sunlight, golden_hour, blue_hour, overcast, window_light, studio_strobe, flash, backlit_rim, night_low_light, neon |
| `expression` | person | neutral, smile, laugh, serious, surprised, sad, angry |
| `quality_flags` | all | sharp, blurry, watermarked, text_overlay, very_low_res |

`quality_flags` follows the single-value rule: the most important defect wins (`sharp` = no defect); an image that is blurry and watermarked stores `blurry`.

Vocabularies validated against StudioBinder/Adobe (framing, angles), PPA/Digital Photography School (lighting), standard portrait-genre and pose references. Deliberate exclusions: glamour/editorial/fashion (intent, not visually classifiable), studio lighting patterns (Rembrandt/butterfly — setup terms a VLM would guess), hand gestures (arms crossed etc. co-occur with any base pose, violating single-value; they live in caption tags).

New attributes in the future = dict entry only, never a DB change.

## Classification

`POST /api/attributes/classify {tagger, only_missing?: bool}` → task-service job (progress, pause, cancel, SSE via existing jobs UI). Per image:

1. One call to `lib.captioning.generate_caption(index, tagger, ...)` with a fixed prompt embedding the vocabularies (person-only lists omitted when the VLM itself reports no person in the same response) and demanding one flat JSON object: `{"shot_type": "...", ..., "has_person": true}`.
2. Lenient parse: extract first `{...}` block, coerce/clamp each value into its vocabulary (case-insensitive, spaces→underscores), unknown or unparsable value → attribute left unset.
3. Persist via `AttributeRepository` (mirrors `ImageRepository` style).

`only_missing=true` leaves already-set attributes untouched so manual corrections survive reruns; default re-classify overwrites. A per-image parse failure writes nothing and is counted in the job result, never aborts the job.

## API

All endpoints session-scoped (`X-Session-ID`), mounted under `/api/attributes` plus media additions.

- `GET /api/attributes/schema` — the vocabulary dict + applicability. Read first by UI and agents.
- `GET /api/attributes/footprint` — dataset footprint: `{"shot_type": {"selfie": 10, ..., "_unset": 12}, ..., "_total": 500}`. Counts per attribute per value, `_unset` = images without a row for that attribute (person-only attributes count non-person images here).
- `GET /api/attributes/query` — filtered listing: query params are attributes (`?shot_type=selfie&pose=walking`), values AND across attributes, `|` means OR within one attribute, literal `unset` matches missing rows. Params `limit` (default 100, max 500), `offset`. Response `{total, items: [{id, index, filename, width, height, is_bookmarked, category, attributes: {...}, captions: {<caption_type>: content}}]}` — `id` = DB row id, `index` = current dataset index (so existing `/api/media/file/{index}` works unchanged), `captions` = all caption types for the image.
- `PUT /api/attributes {filename, attributes}` — manual set/unset; `null` value deletes a row; unknown attribute or out-of-vocabulary value → 422; person-only attributes accepted on any image (manual override beats heuristics).
- `POST /api/attributes/classify` — starts the job, returns task id.
- `GET /api/media/by-id/{id}` and `GET /api/media/thumbnail-by-id/{id}` — thin wrappers resolving DB id → filename → path, reusing the serving code of `media.py:24`; unknown id → 404.

Agent loop: `schema` → `footprint` → `query` per planned bucket (paginated via `total`/`offset`) → files via `index` or id.

## Frontend

- `src/lib/api.ts` + `types.ts`: schema/footprint/query/classify/put calls and types (no `any`).
- **Edit view**: attribute panel — one select per schema entry, humanized labels, "unset" option, only `applies_to: all` plus attributes set on the image, save on change via PUT.
- **Browse**: attribute filter dropdowns (server-side — `attributes` param on the items endpoint filtering via the existing DB enrichment join) and compact value badges on cards.
- **Jobs page**: classify job appears automatically (task-service).
- Deferred as YAGNI: footprint visualization, server-side sampling.

## Error Handling

- Out-of-vocabulary PUT values → 422 with the offending value named.
- VLM prose-wrapped or truncated JSON → lenient parse, unset what cannot be mapped; job reports per-image failure count.
- Query with unknown attribute name → 422 (prevents silent `?shot_typ=...` returning everything).
- DB absent (session without project) → attributes endpoints 400, same as other DB-backed routes.

## Testing

- `AttributeRepository` set/get/unset/cascade round trip; PUT validation rejects unknown values.
- footprint counts match fixture data incl. `_unset` arithmetic.
- query: AND across attributes, OR via `|`, `unset` matching, pagination totals.
- Classifier parse robustness: fenced JSON, prose-wrapped JSON, out-of-vocab values, no-JSON response; `only_missing` semantics — with a stubbed caption generator (matches existing fake-tagger test style; real VLM untested).

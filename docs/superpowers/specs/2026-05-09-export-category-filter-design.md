# Export Category Filter Design

## Overview

Add category-based filtering to the export functionality, allowing users to select which image categories to include in the exported dataset.

## Frontend Changes

### File: `frontend/src/components/export/ExportForm.tsx`

**New state:**
- `categories: string[]` — list of all available category names (fetched from API)
- `selectedCategories: Set<string>` — set of selected category names for export

**UI Section (added below caption type selection):**

```
Categories
─────────────────────────────────────────
[ ] category_1   [ ] category_2   [ ] category_3
[ ] category_4   [ ] Uncategorized

[Select All]  [Deselect All]
─────────────────────────────────────────
```

**Behavior:**
- Fetch categories from `GET /api/categories/` on mount
- All categories + "Uncategorized" checked by default
- Select All: sets `selectedCategories` to full set of all categories + "Uncategorized"
- Deselect All: sets `selectedCategories` to empty set
- Individual toggle: add/remove from `selectedCategories` Set

**API Request:**
Add `categories: string[]` field to `ExportRequest` sent to `POST /api/export`:
```typescript
{
  format: "standard",
  caption_type: "tags",
  bucket_resize: false,
  categories: Array.from(selectedCategories) // ["cat1", "cat2", "Uncategorized"]
}
```

### File: `frontend/src/lib/api.ts`

No changes needed — existing `exportDataset` function accepts `ExportOptions` which can be extended.

## Backend Changes

### File: `backend/app/models/schemas.py`

Add to `ExportRequest`:
```python
categories: list[str] | None = None  # None = export all categories
```

### File: `backend/app/services/export_service.py`

In the export loop, filter images by selected categories:
```python
image_categories = self._get_image_categories(image_index)
if request.categories is not None:
    category_to_check = image_categories[0] if image_categories else None
    if category_to_check not in request.categories and (category_to_check is None and "Uncategorized" not in request.categories):
        continue  # skip this image
```

The filtering logic:
- If `categories` is `None`: export all images (existing behavior)
- If `categories` is provided: only export images where `category in categories` OR `category is None and "Uncategorized" in categories`

## API Endpoints

### POST `/api/export`

**Request Body:**
```json
{
  "format": "standard",
  "caption_type": "tags",
  "bucket_resize": false,
  "categories": ["nature", "portrait", "Uncategorized"]
}
```

**`categories` field:**
- `null` or omitted: export all categories (backward compatible)
- `string[]`: list of category names to include; "Uncategorized" represents images with no category

### GET `/api/categories/`

No changes. Returns:
```json
["nature", "portrait", "landscape"]
```

## Files to Modify

1. `frontend/src/components/export/ExportForm.tsx` — add category selection UI
2. `backend/app/models/schemas.py` — add `categories` field to `ExportRequest`
3. `backend/app/services/export_service.py` — filter images by selected categories

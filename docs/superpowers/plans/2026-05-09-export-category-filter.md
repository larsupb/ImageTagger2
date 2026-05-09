# Export Category Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to filter exported images by category, with UI for multi-select, select all, and deselect all.

**Architecture:** Frontend adds category multi-select UI to ExportForm. Backend filters images by category during export. "Uncategorized" is a special filter value representing images with no category.

**Tech Stack:** React 19, TypeScript (frontend), FastAPI, Pydantic, Python (backend), SQLite (categories via `category_id` on images table).

---

### Task 1: Backend - Add `categories` field to schemas

**Files:**
- Modify: `backend/app/models/schemas.py:212-218`

- [ ] **Step 1: Add `categories` field to `ExportRequest`**

Edit `backend/app/models/schemas.py`, replace lines 212-218:
```python
class ExportRequest(BaseModel):
    format: str = "standard"
    caption_type: str = "tags"
    bucket_resize: bool = False
    bucket_resolution: int = 1024
    bucket_step: int = 128
    bucket_max_steps: int = 2
    categories: list[str] | None = None
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/models/schemas.py
git commit -m "feat(export): add categories field to ExportRequest schema"
```

---

### Task 2: Backend - Filter images by category in export

**Files:**
- Modify: `backend/app/services/export_service.py:16-31` and `:65-68`

- [ ] **Step 1: Add `categories` to `ExportOptions`**

Edit `backend/app/services/export_service.py`, replace the `ExportOptions.__init__` method (lines 16-31):
```python
class ExportOptions:
    def __init__(
        self,
        format: str = "standard",
        caption_type: str = "tags",
        bucket_resize: bool = False,
        bucket_resolution: int = 1024,
        bucket_step: int = 128,
        bucket_max_steps: int = 2,
        categories: list[str] | None = None,
    ):
        self.format = format
        self.caption_type = caption_type
        self.bucket_resize = bucket_resize
        self.bucket_resolution = bucket_resolution
        self.bucket_step = bucket_step
        self.bucket_max_steps = bucket_max_steps
        self.categories = categories
```

- [ ] **Step 2: Add category filtering logic in export loop**

Edit `backend/app/services/export_service.py`, replace the export loop (lines 64-68):
```python
    total = len(ds)
    exported_count = 0
    for i in range(total):
        item = ds.get_item(i)
        if item is None:
            continue

        if options.categories is not None:
            category = item.category
            if category not in options.categories:
                if category is None and "Uncategorized" not in options.categories:
                    continue
                elif category is not None:
                    continue
```

- [ ] **Step 3: Update progress counting in export router**

Edit `backend/app/routers/export.py`, replace the `ExportOptions` creation (lines 33-40):
```python
                options = export_service.ExportOptions(
                    format=req.format,
                    caption_type=req.caption_type,
                    bucket_resize=req.bucket_resize,
                    bucket_resolution=req.bucket_resolution,
                    bucket_step=req.bucket_step,
                    bucket_max_steps=req.bucket_max_steps,
                    categories=req.categories,
                )
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/services/export_service.py backend/app/routers/export.py
git commit -m "feat(export): filter images by selected categories during export"
```

---

### Task 3: Frontend - Add category selection UI

**Files:**
- Modify: `frontend/src/components/export/ExportForm.tsx:50-320`

- [ ] **Step 1: Add state and fetch categories**

Edit `frontend/src/components/export/ExportForm.tsx`, add after line 60:
```typescript
  const [selectedCategories, setSelectedCategories] = useState<Set<string>>(new Set());

  const { data: allCategories = [] } = useQuery({
    queryKey: ["categories"],
    queryFn: () => api.getCategories(),
  });

  useEffect(() => {
    const cats = new Set(allCategories);
    cats.add("Uncategorized");
    setSelectedCategories(cats);
  }, [allCategories]);
```

- [ ] **Step 2: Add select all / deselect all handlers**

Add after the `handleAnalyzeBuckets` function (after line 164):
```typescript
  const handleSelectAllCategories = () => {
    const cats = new Set(allCategories);
    cats.add("Uncategorized");
    setSelectedCategories(cats);
  };

  const handleDeselectAllCategories = () => {
    setSelectedCategories(new Set());
  };

  const toggleCategory = (cat: string) => {
    setSelectedCategories((prev) => {
      const next = new Set(prev);
      if (next.has(cat)) next.delete(cat);
      else next.add(cat);
      return next;
    });
  };
```

- [ ] **Step 3: Add categories section to the UI**

Add after the Caption Type `OperationCard` (after line 220, before the Bucket Resize card):
```typescript
        <div className="bg-surface rounded-lg border border-border p-4">
          <div className="flex items-start gap-3">
            <div className="text-text-muted"><Tag className="w-5 h-5" /></div>
            <div className="flex-1">
              <label className="text-sm font-medium cursor-pointer">
                Categories
              </label>
              <p className="text-xs text-text-muted mt-0.5">Select which categories to export</p>
            </div>
          </div>
          <div className="mt-4 pt-4 border-t border-border">
            <div className="flex flex-wrap gap-2">
              {[...allCategories, "Uncategorized"].map((cat) => (
                <label key={cat} className="flex items-center gap-1.5 text-sm cursor-pointer">
                  <Checkbox
                    checked={selectedCategories.has(cat)}
                    onCheckedChange={() => toggleCategory(cat)}
                  />
                  {cat}
                </label>
              ))}
            </div>
            <div className="flex gap-2 mt-3">
              <Button variant="outline" size="sm" onClick={handleSelectAllCategories}>
                Select All
              </Button>
              <Button variant="outline" size="sm" onClick={handleDeselectAllCategories}>
                Deselect All
              </Button>
            </div>
          </div>
        </div>
```

- [ ] **Step 4: Pass categories in export request**

Edit `handleExport` in `ExportForm.tsx`, replace lines 117-134:
```typescript
  const handleExport = async () => {
    setIsExporting(true);
    setLogEntry(null);
    try {
      const result = await api.startExportTask({
        format,
        caption_type: captionType,
        bucket_resize: bucketResize,
        bucket_resolution: resolution,
        bucket_step: step,
        bucket_max_steps: maxSteps,
        categories: Array.from(selectedCategories),
      });
      setCurrentTaskId(result.task_id);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to start export");
      setIsExporting(false);
    }
  };
```

- [ ] **Step 5: Move Tag import to top of icon imports (it is already imported)**

No change needed — Tag is already imported at line 16.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/components/export/ExportForm.tsx
git commit -m "feat(export): add category multi-select filter to export UI"
```

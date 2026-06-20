# White Balance Default Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a White Balance section to the Settings page for managing the default white balance method, and use it in the Batch Form.

**Architecture:** Add `white_balance_method` to settings.json, expose via Settings interface, add UI section in settings page, wire up BatchForm to use the setting as default.

**Tech Stack:** Python/FastAPI backend, Next.js/React frontend, existing Select component

---

### Task 1: Add default to settings.json

**Files:**
- Modify: `backend/settings.json`

- [ ] **Step 1: Add default value**

Add `"white_balance_method": "gray_world"` to settings.json (after `rembg` section):

```json
"rembg": {
  "model": "u2net_human_seg"
},
"white_balance_method": "gray_world",
```

- [ ] **Step 2: Commit**

```bash
git add backend/settings.json
git commit -m "feat: add default white_balance_method setting"
```

---

### Task 2: Add type to Settings interface

**Files:**
- Modify: `frontend/src/lib/types.ts:82-102`

- [ ] **Step 1: Add white_balance_method to Settings interface**

In the Settings interface, add after `rembg`:

```typescript
rembg: { model: string };
white_balance_method?: string;
```

- [ ] **Step 2: Commit**

```bash
git add frontend/src/lib/types.ts
git commit -m "feat: add white_balance_method to Settings type"
```

---

### Task 3: Add White Balance section to Settings page

**Files:**
- Modify: `frontend/src/app/settings/page.tsx:225-248`

- [ ] **Step 1: Add White Balance Section**

Add new Section after "Background Removal" section (line ~225), before "VLM Endpoint":

```tsx
<Section title="White Balance">
  <div>
    <label className="block text-sm text-text-secondary mb-1">Default Method</label>
    <Select
      value={localSettings.white_balance_method || "gray_world"}
      onValueChange={(v) => {
        if (v) {
          setLocalSettings({ ...localSettings, white_balance_method: v });
          save("white_balance_method", v);
        }
      }}
    >
      <SelectTrigger className="w-48">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="gray_world">Gray World</SelectItem>
        <SelectItem value="shades_of_gray">Shades of Gray</SelectItem>
        <SelectItem value="gray_edge">Gray Edge</SelectItem>
      </SelectContent>
    </Select>
  </div>
</Section>
```

- [ ] **Step 2: Commit**

```bash
git add frontend/src/app/settings/page.tsx
git commit -m "feat: add White Balance section to settings page"
```

---

### Task 4: Wire up BatchForm to use the setting

**Files:**
- Modify: `frontend/src/components/batch/BatchForm.tsx:98-99`

- [ ] **Step 1: Update whiteBalanceMethod to read from settings**

The BatchForm already fetches settings via useQuery. Need to get the value and use it as initial state:

Add after line 97 (after colorMatchHistogram state):

```typescript
const { data: settings } = useQuery({
  queryKey: ["settings"],
  queryFn: () => api.getSettings(),
});
```

Change line 99 from:
```typescript
const [whiteBalanceMethod, setWhiteBalanceMethod] = useState("gray_world");
```

To:
```typescript
const [whiteBalanceMethod, setWhiteBalanceMethod] = useState(
  settings?.white_balance_method || "gray_world"
);
```

- [ ] **Step 2: Commit**

```bash
git add frontend/src/components/batch/BatchForm.tsx
git commit -m "feat: use default white_balance_method from settings in BatchForm"
```

---

### Verification

- [ ] Navigate to Settings page, verify White Balance section appears with dropdown
- [ ] Select different method, verify it saves
- [ ] Go to Batch page, verify white balance dropdown shows the saved default
- [ ] Run `npm run lint` in frontend to check for errors
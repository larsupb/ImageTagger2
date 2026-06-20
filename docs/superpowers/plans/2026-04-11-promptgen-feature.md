# PromptGen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a new PromptGen page on the frontend that uses OpenAI API to generate image prompts descriptions based on existing caption/tag examples from the dataset.

**Architecture:** Backend provides a new `/api/promptgen/generate` endpoint that retrieves random caption examples from the database, formats them, and call OpenAI API with a system prompt. Frontend displays a form with caption type selector, example count, optional user prompt, and shows the generated result with copy button.

**Tech Stack:** FastAPI (backend), Next.js 15 + React 19 + TypeScript (frontend), OpenAI API (existing settings)

---

### File Structure

**Backend (new files):**
- `backend/app/routers/promptgen.py` - New API router for prompt generation
- `backend/app/services/promptgen_service.py` - Business logic for prompt generation

**Backend (modify):**
- `backend/app/main.py` - Register new router

**Frontend (new files):**
- `frontend/src/app/promptgen/page.tsx` - New PromptGen page

**Frontend (modify):**
- `frontend/src/lib/api.ts` - Add API method for prompt generation

---

### Task 1: Create Backend Service

**Files:**
- Create: `backend/app/services/promptgen_service.py`

- [ ] **Step 1: Write the service module**

```python
import logging
import random
from openai import OpenAI

from app.sessions import Session
from app.db.repository import CaptionRepository
from app.config import openai_settings

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are an expert at creating detailed image generation prompts. 
Based on the following example descriptions, create a new prompt that captures the 
same style, mood, and visual element patterns. The prompt should be suitable for 
AI image generation models like Midjourney, Stable Diffusion, etc.

Examples:
{examples}

Create a single, detailed prompt that follows the same pattern:"""


def generate_prompt(session: Session, caption_type: str, example_count: int, user_prompt: str) -> str:
    """Generate an image prompt based on caption examples.
    
    Args:
        session: Current session
        caption_type: The caption type to fetch examples from
        example_count: Number of examples to use
        user_prompt: Additional user instructions
        
    Returns:
        Generated prompt string
    """
    rows = CaptionRepository.get_all_by_type(session.db, caption_type)
    
    # Filter out empty captions
    non_empty = [r for r in rows if r.get("content")]
    if not non_empty:
        raise ValueError(f"No captions found for type: {caption_type}")
    
    # Sample examples
    examples = random.sample(non_empty, min(example_count, len(non_empty)))
    formatted_examples = "\n".join(f"- {r['content']}" for r in examples)
    
    # Build full prompt
    system_msg = SYSTEM_PROMPT.format(examples=formatted_example)
    user_msg = user_prompt.strip() if user_prompt.strip() else "Create a prompt in the same style."
    
    # Call OpenAI
    settings = openai_settings()
    client = OpenAI(
        api_key=settings.get("api_key", "") or "ollama",
        base_url=settings.get("base_url", "http://localhost:11434/v1"),
        timeout=settings.get("timeout", 120.0),
        max_retries=settings.get("max_retries", 2)
    )
    
    response = client.chat.completions.create(
        model=settings.get("model", "gpt-4o"),
        messages=[
            {"role": "system", "content": system_msg},
            {"role": "user", "content": user_msg}
        ],
        max_tokens=1024
    )
    
    if not response.choices:
        raise ValueError("Empty response from OpenAI")
    
    return response.choices[0].message.content or ""
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/services/promptgen_service.py
git commit -m "feat: add promptgen service"
```

---

### Task 2: Create Backend Router

**Files:**
- Create: `backend/app/routers/promptgen.py`
- Modify: `backend/app/main.py:1-30` (register router)

- [ ] **Step 1: Write the router module**

```python
from fastapi import APIRouter, Depends, HTTPException

from app.sessions import Session, get_session
from app.services import promptgen_service
from pydantic import BaseModel

router = APIRouter(prefix="/api/promptgen", tag=["promptgen"])


class GenerateRequest(BaseModel):
    caption_type: str
    example_count: int = 20
    user_prompt: str = ""


class GenerateResponse(BaseModel):
    prompt: str


@router.post("/generate", response_model=GenerateResponse)
def generate_prompt(req: GenerateRequest, session: Session = Depends(get_session)):
    if session.dataset is None:
        raise HTTPException(400, "No dataset loaded")
    
    try:
        prompt = promptgen_service.generate_prompt(
            session,
            req.caption_type,
            req.example_count,
            req.user_prompt
        )
        return GenerateResponse(prompt=prompt)
    except ValueError as e:
        raise HTTPException(400, str(e))
    except Exception as e:
        logger = promptgen_service.logger
        logger.error(f"Error generating prompt: {e}")
        raise HTTPException(500, f"Failed to generate prompt: {str(e)}")
```

- [ ] **Step 2: Register router in main.py**

Open `backend/app/main.py` and find where other routers imports are, add:

```python
from app.routers import promptgen
```

Then find where routers are included (e.g., `app.include_router(...)` calls) and add:

```python
app.include_router(promptgen.router)
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/routers/promptgen.py backend/app/main.py
git commit -m "feat: add promptgen router endpoint"
```

---

### Task 3: Add Frontend API Method

**Files:**
- Modify: `frontend/src/lib/api.ts:280-290` (add method)

- [ ] **Step 1: Add API method to api.ts**

Add after line 283 (before the last closing brace):

```typescript
  // PromptGen
  generatePrompt: (captionType: string, exampleCount: number, userPrompt: string) =>
    apiFetch<{ prompt: string }>("/api/promptgen/generate", {
      method: "POST",
      body: JSON.stringify({
        caption_type: captionType,
        example_count: exampleCount,
        user_prompt: userPrompt
      }),
    }),
```

- [ ] **Step 2: Commit**

```bash
git add frontend/src/lib/api.ts
git commit -m "feat: add generatePrompt API method"
```

---

### Task 4: Create Frontend PromptGen Page

**Files:**
- Create: `frontend/src/app/promptgen/page.tsx`

- [ ] **Step 1: Write the page component**

```tsx
"use client";

import { useState, useEffect } from "react";
import { useProjectStore } from "@/stores/projectStore";
import { useSessionStore } from "@/stores/session";
import { api } from "@/lib/api";
import EmptyState from "@/components/shared/EmptyState";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Wand2, Copy, Check } from "lucide-react";
import { toast } from "sonner";

export default function PromptGenPage() {
  const activeProjectId = useProjectStore((s) => s.activeProjectId);
  const session = activeProjectId
    ? useSessionStore((s) => s.getProjectSession(activeProjectId))
    : undefined;

  const [captionTypes, setCaptionTypes] = useState<string[]>([]);
  const [selectedType, setSelectedType] = useState("tags");
  const [exampleCount, setExampleCount] = useState(20);
  const [userPrompt, setUserPrompt] = useState("");
  const [generatedPrompt, setGeneratedPrompt] = useState("");
  const [isGenerating, setIsGenerating] = useState(false);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!activeProjectId) return;
    api.getCaptionType().then(setCaptionTypes).catch(console.error);
  }, [activeProjectId]);

  if (!activeProjectId) {
    return (
      <EmptyState
        icon={Wand2}
        title="No project open"
        description="Open a project to access PromptGen."
      />
    );
  }

  const handleGenerate = async () => {
    setIsGenerating(true);
    setGeneratedPrompt("");
    try {
      const result = await api.generatePrompt(selectedType, exampleCount, userPrompt);
      setGeneratedPrompt(result.prompt);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to generate prompt");
    } finally {
      setIsGenerating(false);
    }
  };

  const handleCopy = async () => {
    if (!generatedPrompt) return;
    await navigator.clipboard.writeText(generatedPrompt);
    setCopied(true);
    toast.success("Copied to clipboard");
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="max-w-xl flex flex-col gap-6">
      <div className="bg-surface rounded-lg border border-border p-6">
        <div className="flex items-center gap-2 mb-4">
          <Wand2 className="w-5 h-5 text-text-secondary" />
          <h2 className="text-lg font-medium text-text">PromptGen</h2>
        </div>

        <div className="flex flex-col gap-4">
          <div>
            <label className="block text-sm text-text-secondary mb-1">Caption Type</label>
            <Select value={selectedType} onValueChange={(v) => v && setSelectedType(v)}>
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {captionTypes.map((type) => (
                  <SelectItem key={type} value={type}>
                    {type}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div>
            <label className="block text-sm text-text-secondary mb-1">
              Example Count
            </label>
            <Input
              type="number"
              min={5}
              max={100}
              value={exampleCount}
              onChange={(e) => setExampleCount(Number(e.target.value))}
            />
          </div>

          <div>
            <label className="block text-sm text-text-secondary mb-1">
              User Prompt (optional)
            </label>
            <Textarea
              value={userPrompt}
              onChange={(e) => setUserPrompt(e.target.value)}
              placeholder="Additional instructions for the prompt..."
              rows={3}
            />
          </div>

          <Button
            onClick={handleGenerate}
            disabled={isGenerating || !selectedType}
          >
            <Wand2 className="w-4 h-4 mr-2" />
            {isGenerating ? "Generating..." : "Generate Prompt"}
          </Button>
        </div>
      </div>

      {generatedPrompt && (
        <div className="bg-surface rounded-lg border border-border p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-text-secondary">Generated Prompt</h3>
            <Button variant="ghost" size="sm" onClick={handleCopy}>
              {copied ? (
                <Check className="w-4 h-4 mr-1" />
              ) : (
                <Copy className="w-4 h-4 mr-1" />
              )}
              {copied ? "Copied" : "Copy"}
            </Button>
          </div>
          <p className="text-text whitespace-pre-wrap">{generatedPrompt}</p>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Check if Textarea exists**

The page uses `Textarea` component. Check if it exists:

```bash
ls frontend/src/components/ui/textarea.tsx
```

If not found, create it based on the Input pattern (check `input.tsx` for reference).

- [ ] **Step 3: Commit**

```bash
git add frontend/src/app/promptgen/page.tsx
git commit -m "feat: add PromptGen page"
```

---

### Task 5: Verify Build

**Files:**
- Run: Backend lint (if configured)
- Run: Frontend build

- [ ] **Step 1: Run frontend build**

```bash
cd frontend && npm run build
```

- [ ] **Step 2: Commit any fixes**

If there are errors, fix them and commit.

---

### Plan Coverage

- [x] New backend router for prompt generation
- [x] Backend service with OpenAI API call
- [x] Frontend page with form inputs
- [x] Caption type selection from dataset
- [x] Example count configuration
- [x] User prompt textarea
- [x] Generated prompt display + copy
- [x] Error handling with toasts

---

**Plan complete and saved to `docs/superpower/plans/2026-04-11-promptgen-feature.md`. Two execution options:**

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
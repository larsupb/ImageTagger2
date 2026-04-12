# Auto White Balance Design

## Overview

Add automatic white balance correction as a batch processing operation, appearing above the existing Color Matching card. The two features are mutually exclusive.

## Methods

Three white balance algorithms:

1. **Gray World** - Assumes average of all channels means equals. Scales each channel so mean(R) = mean(G) = mean(B).

2. **Shades of Gray** - Extends Gray World by also equalizing standard deviations across channels means and stds.

3. **Gray Edge** - Uses first-order derivatives at edges pixels (gradient magnitude > threshold), computes mean of those pixels per channel, and equalizes.

## Mutual Exclusion

Frontend logic:
- Enabling White Balance unchecks Color Matching
- Enabling Color Matching unchecks White Balance

This ensures only one of the two runs in a batch.

## Files to Modify

### Backend
- `backend/lib/white_balance.py` - New module with functions implementations
- `backend/app/models/schemas.py` - Add `white_balance: bool`, `white_balance_method: str`
- `backend/app/routers/batch.py` - Add white balance step BEFORE color match

### Frontend
- `frontend/src/components/batch/BatchForm.tsx` - Add WhiteBalance OperationCard above Color Matching

## Processing Order (existing + new)

1. Rename → Upscale → Bucket Resize → Mask → Caption → **White Balance** → **Color Matching**

White balance runs after caption (existing order), before color matching (existing).

## UI Layout

```
[OperationCard: White Balance]
  - Checkbox + Icon + Title + Description
  - Expanded content:
    - Method dropdown (Gray World, Shades of Gray, Gray Edge)

[OperationCard: Color Matching]
  - (existing)
```

## Acceptance Criteria

1. Checkbox toggles enable white balance
2. Method dropdown selects algorithm (default: Gray World)
3. Enabling White Balance disables Color Matching and vice versa
4. Batch processes images with selected white balance method before color matching runs
5. Reference image for color matching is NOT white balanced (when both somehow run)
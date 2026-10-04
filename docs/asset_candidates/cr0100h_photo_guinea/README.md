# CR-0100H Photo-Referenced Guinea Pig

The user approved the fox and requested a guinea pig based on their supplied
photo (`full.jpeg`). The new design preserves a low oval body, short feet,
small dark eyes, sideways rounded ears, golden fur and a white facial blaze.
The reference photo is not bundled in the app.

`guinea_pig_master_v1.png` is generated reference-based artwork. The eight
`*_source.png` variants change facial expression. Production images use the
existing fixed-body, feathered-face compositor, not whole-body frame swapping.
There is no claim of phoneme-level lip sync.

## Reproduce

```sh
python3 scripts/build_cat_inspired_pet_assets.py --skin guinea_pig --source docs/asset_candidates/cr0100h_photo_guinea --face-ellipse 850 650 230 235 --install
```

Only the 15 guinea pig production images are installed. Fox images are unchanged.
`prepared/` is disposable output; `review.png` shows all eight main states.

## Validation

- Compositor: identical alpha silhouette in every state; no changed visible
  pixels outside the feathered facial mask.
- Targeted Flutter suite: 56 passed (asset pack, avatar, skin picker, subtitle,
  store readiness).
- Visual review: the eight-state montage was inspected on a light background.
- iPhone 14 Plus: production-backend Profile build installed without uninstalling;
  independent launch via devicectl succeeded and Runner was still present on a
  later process check. Personal-team preview hides Apple sign-in only through a
  build define; the Release entitlement remains unchanged. Interactive voice,
  subtitle and final appearance acceptance still require the user's inspection.
- Device inspection and formal App Store signing are separate release gates;
  automated tests do not certify final review readiness.

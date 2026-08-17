# CR-0100A Pet Visual Asset Candidates

This note records the first candidate outputs for the pet visual style A/B work.
These images are reference sheets only and are not wired into the Flutter app.

## Candidate Sheets

| Candidate | File | State order |
| --- | --- | --- |
| Dog cute / Q style | `docs/asset_candidates/cr0100a/dog_cute_state_sheet_v1.png` | top-left normal, top-right happy, bottom-left caring, bottom-right sad |
| Dog semi-realistic style | `docs/asset_candidates/cr0100a/dog_realistic_state_sheet_v1.png` | top-left normal, top-right happy, bottom-left caring, bottom-right sad |
| Dog semi-realistic clean sheet | `docs/asset_candidates/cr0100a/dog_realistic_clean_state_sheet_v1.png` | top-left normal, top-right happy, bottom-left caring, bottom-right sad |
| Dog semi-realistic natural proportion sheet | `docs/asset_candidates/cr0100a/dog_realistic_natural_proportion_sheet_v1.png` | top-left normal, top-right happy, bottom-left caring, bottom-right sad |

## Split State Outputs

These files are cropped from `dog_realistic_state_sheet_v1.png`.
They keep the selected first-sheet proportions and should be treated as candidate outputs, not final bundled app assets yet.

| State | File | Size |
| --- | --- | --- |
| normal | `docs/asset_candidates/cr0100a/split/dog_realistic_normal_v1.png` | 627 x 627 |
| happy | `docs/asset_candidates/cr0100a/split/dog_realistic_happy_v1.png` | 627 x 627 |
| caring | `docs/asset_candidates/cr0100a/split/dog_realistic_caring_v1.png` | 627 x 627 |
| sad | `docs/asset_candidates/cr0100a/split/dog_realistic_sad_v1.png` | 627 x 627 |

## Transparent Candidate Outputs

The normalized alpha files are the recommended handoff candidates for app integration review.
They use a consistent transparent canvas so state changes should not resize the pet unexpectedly.

| State | Recommended file | Size | Channels |
| --- | --- | --- | --- |
| normal | `docs/asset_candidates/cr0100a/transparent_normalized/dog_realistic_normal_alpha_1400_v1.png` | 1400 x 1400 | sRGBA |
| happy | `docs/asset_candidates/cr0100a/transparent_normalized/dog_realistic_happy_alpha_1400_v1.png` | 1400 x 1400 | sRGBA |
| caring | `docs/asset_candidates/cr0100a/transparent_normalized/dog_realistic_caring_alpha_1400_v1.png` | 1400 x 1400 | sRGBA |
| sad | `docs/asset_candidates/cr0100a/transparent_normalized/dog_realistic_sad_alpha_1400_v1.png` | 1400 x 1400 | sRGBA |

Notes:

- `docs/asset_candidates/cr0100a/transparent/dog_realistic_sad_alpha_candidate_v1.png` is rejected because it baked a checkerboard background into the image and has no alpha channel.
- The normalized files are still candidate assets under `docs/`. Move selected finals into the app asset tree only after visual QA.

## Visual QA

QA previews:

| Check | File | Result |
| --- | --- | --- |
| Background contrast | `docs/asset_candidates/cr0100a/qa/dog_realistic_background_qa_sheet_v1.png` | Pass |
| Small-size readability | `docs/asset_candidates/cr0100a/qa/dog_realistic_small_size_qa_sheet_v1.png` | Pass with notes |

Findings:

- The normalized transparent files render correctly on warm cream, soft green, and dark backgrounds.
- At home-screen scale, all four states are recognizable and visually warm.
- At very small icon sizes around 80 px, `normal` and `caring` become visually closer, while `happy` and `sad` remain clear.
- The `caring` state has a larger head tilt than the other states. Use a crossfade or animated transition if it is switched live during conversation.
- The files are suitable for integration as a candidate semi-realistic pet style after a final product review.

## Flutter v2 Asset Handoff

The reviewed transparent candidates have been converted to 1024 x 1024 PNGs and placed in the v2 app asset tree:

| State | App asset |
| --- | --- |
| normal | `assets/pets/v2/realistic/adult/dog/states/normal.png` |
| happy | `assets/pets/v2/realistic/adult/dog/states/happy.png` |
| caring | `assets/pets/v2/realistic/adult/dog/states/caring.png` |
| sad | `assets/pets/v2/realistic/adult/dog/states/sad.png` |

Current app integration status:

- `AssetPaths.stateImageForStyle(...)` can resolve these v2 dog realistic adult state assets.
- The realistic dog now has all eight static states: `normal`, `happy`, `caring`, `sad`, `excited`, `hungry`, `thirsty`, and `sleepy`.
- `AssetPaths.listeningForStyle(...)` can resolve the v2 dog realistic adult listening asset.
- `talk` and `rest` now have a minimal v2 animation set so realistic dog no longer falls back to Q版 during speaking or idle states.
- Do not expose a broad realistic-style UI toggle for every pet. Only dog / realistic / adult currently has reviewed v2 state assets.

Extended state QA:

| Check | File | Result |
| --- | --- | --- |
| Eight states + listening contrast | `docs/asset_candidates/cr0100_realistic_dog_extended/qa/dog_realistic_extended_state_qa_sheet_v1.png` | Pass with notes |
| Minimal rest/talk animation | `docs/asset_candidates/cr0100_realistic_dog_extended/qa/dog_realistic_animation_minimal_qa_sheet_v1.png` | Pass with notes |

Notes:

- The green-background candidates were converted with local chroma-key removal. A first pass left visible green fringing on dark backgrounds, so the alpha extraction was tightened before writing the final app assets.
- Current app assets are suitable on the warm/light home background. Very dark backgrounds may still reveal a very thin edge on some green-screen-derived states.
- `excited` has a larger pose change than the other static states, so it is best used for reward/celebration moments rather than idle state switching.
- `rest` currently uses a safe 3-frame blink loop: `normal`, `sleepy`, `normal`.
- `talk` currently uses a safe 6-frame open/closed-mouth loop based on `normal` and `happy`. This prevents Q版 fallback during voice playback, but a future polish pass should replace it with true mouth-shape frames.

## Production Direction

- Keep the cute / Q style close to the current app illustration language, because it is the safest immediate continuation from the existing dog pet.
- Use the semi-realistic dog as the first A/B comparison candidate. It should still feel gentle and companion-like, not photo-realistic or uncanny.
- Treat `dog_realistic_state_sheet_v1.png` as the preferred source sheet for the semi-realistic dog direction. It has the strongest warmth, companion feeling, and elderly-friendly cuteness even though its proportions are more stylized.
- Keep `dog_realistic_clean_state_sheet_v1.png` as a cleanup reference only. It should not replace the preferred source unless the final asset needs cleaner spacing for cutout work.
- Keep `dog_realistic_natural_proportion_sheet_v1.png` as a rejected direction reference. Its anatomy is more realistic, but the result feels less like the selected companion pet identity.
- Do not use runtime AI image generation in the production app. All selected pet states should be reviewed, exported, bundled, versioned, and tested as static assets.
- Before app integration, split selected sheets into individual transparent PNG state assets and run visual QA on device.

## Next Required Work

1. Pick one cute dog direction and one semi-realistic dog direction.
2. Review the split white-background PNGs for state clarity and identity consistency.
3. Review the normalized transparent PNGs for state clarity, edge quality, and identity consistency.
4. Move reviewed finals into the Flutter app asset tree.
5. Add asset manifest entries only after the selected files are production-ready.
6. Add visual regression checks for size, transparency, and non-empty render.
7. Design the in-app Q/real preference UI so it only exposes complete, reviewed options.

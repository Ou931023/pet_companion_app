# CR-0100 Non-Dog Realistic Pet Candidates

> Superseded direction: these candidates are kept only as historical references.
> They should **not** be integrated into the production app. The current preferred
> direction is `../cr0100_elder_top5_q_consistency/`, which prioritizes obvious
> species traits and older-adult appeal over semi-realistic redesign.

Generated on 2026-08-21 as candidate mother sheets for future realistic visual
style expansion. These are **not** integrated into the production app yet.

## Candidate Sheets

| Pet | File | Status |
| --- | --- | --- |
| Fox | `fox_realistic_state_sheet_v1.png` | Superseded; do not integrate |
| Guinea pig | `guinea_pig_realistic_state_sheet_v1.png` | Superseded; do not integrate |
| Mochi | `mochi_realistic_state_sheet_v1.png` | Superseded; do not integrate |

## QA Notes

- All three sheets follow the dog realistic reference direction: warm cream
  background, soft semi-realistic rendering, blue scarf, and 2x2 states.
- Fox is the strongest candidate: clear species identity, full paws, consistent
  scale, and readable tail.
- Guinea pig is usable as a first candidate: strong senior-friendly softness and
  clear paws, but needs transparent cutout QA because the body is very round.
- Mochi is usable as a soft mascot candidate, but it visually leans toward a
  white puppy. Before integration, decide whether Mochi should remain mascot-like
  or become an explicit animal.

## Production Integration Gate

Do not expose realistic style for these pets in the app until all items below
are complete:

- Split the four states into independent transparent PNG files.
- Extend from four states to the full production state set:
  `normal`, `happy`, `caring`, `sad`, `excited`, `hungry`, `thirsty`, `sleepy`.
- Add a `listening` image.
- Add minimal `rest` and `talk` frames so voice interaction does not fall back to
  Q版 assets while speaking or idling.
- Add the final asset paths to `AssetPaths.productionProfiles`.
- Add tests that every referenced asset file exists.
- Verify small-size readability on mobile home screen.

Until then, `AssetPaths.availableVisualStyles(...)` should continue to expose
`真實版` only for dog.

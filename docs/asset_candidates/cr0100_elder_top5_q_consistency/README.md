# CR-0100 Elder-Friendly Pet Q-Style Candidates

Generated on 2026-08-21 as candidate mother sheets for pets likely to be
friendly and familiar to older adults.

## Important Scope

The repo does not currently contain the formal survey table for "top 10 pets
older adults want". Until the survey source is added, this folder keeps four
elder-friendly candidate directions:

1. Dog
2. Cat
3. Rabbit
4. Bird

Replace this list when the actual survey result is available.

## Direction Update

The goal is **not strict old-character matching**. The production goal is:

- Each pet must have obvious species traits at first glance.
- Each pet must feel warm, friendly, and easy for older adults to like.
- The app should keep a coherent Q-style visual language: big eyes, rounded
  shapes, gentle expressions, clear silhouettes, and soft colors.
- Do not over-realize the pets. They should still feel like companion app
  characters, not animal photos.

## Candidate Sheets

| Pet | File | First-pass note |
| --- | --- | --- |
| Dog | `dog_q_elder_top5_state_sheet_v1.png` | Strong; closest to current app dog and clearly friendly. |
| Cat | `cat_q_elder_top5_state_sheet_v1.png` | Strong; tabby markings and white paws make the pet identity clear. |
| Rabbit | `rabbit_q_elder_top5_state_sheet_v1.png` | Good; species is clear, but sad state changes ears to lop style and should be corrected before integration. |
| Bird | `bird_q_elder_top5_state_sheet_v1.png` | Strong; simple, readable, and warm. |

## Production Gate

These are candidate mother sheets only. Do not integrate them into the app until:

- The actual survey ranking is confirmed or this candidate set is accepted.
- Each selected sheet is split into independent transparent PNG state assets.
- The full app state set is complete: `normal`, `happy`, `caring`, `sad`,
  `excited`, `hungry`, `thirsty`, `sleepy`.
- Listening, rest, and talk frames are added.
- Small-screen readability is checked on the home screen.
- `AssetPaths` and tests are updated only after the asset set is complete.

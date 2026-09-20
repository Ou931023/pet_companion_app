# CR-0100G: Cat-Inspired Fox and Guinea Pig

## Scope and status

User requested fox and guinea pig redesign using the existing cat's silhouette
and illustration style. Original masters remain here for reproducibility;
the cleaned expression packs are now installed in `assets/pets`.
The cat reference is `assets/pets/states/mochi_normal.png`.

| Candidate | Direction | PNG |
| --- | --- | --- |
| `fox_master_v1.png` | Natural seated quadruped, amber eyes, pointed ears, white chest, full white-tipped tail | 1254 x 1254, RGBA |
| `guinea_pig_master_v1.png` | Low rounded body, short legs, folded ears, ivory/caramel short fur, no tail | 1254 x 1254, RGBA |

Generated with the built-in imagegen tool, then processed locally with explicit
user approval. Source files in this directory are not bundled. All 33 production
fox/guinea-pig state, listening, rest and talk images were replaced together.

## Prompt set

Shared: use the cat reference for balanced head/body composition, warm attentive
eyes, fine clean painted lines and soft fur shading; a friendly companion for
older adults; full body, transparent background, no clothes, props or text.

Fox: natural seated pose with front paws on the ground, modest pointed muzzle,
russet coat, white muzzle/chest, darker lower legs, thick white-tipped tail curled
beside feet. Preserve recognizable fox anatomy, avoid biped mascot proportions.

Guinea pig: low compact rounded body, very short legs, rounded folded ears,
blunt broad muzzle, ivory and caramel coat, no tail or exposed teeth. Borrow the
cat's expression and composition without copying its long legs or pointed ears.

Expression edits: preserve body, framing, silhouette, markings and feet baseline;
change only eyes and mouth for happy, caring, sad, sleepy, excited, hungry,
thirsty and listening states. Require real alpha, not a painted checkerboard.

## Verification

- Both masters have genuine alpha and fully transparent corners.
- Some expression edits have a baked checkerboard and no alpha. Repeated
  generation did not fix this reliably; batch generation was stopped.
- User approved deterministic local processing. The pipeline protects the opaque
  body interior, removes saturated red/yellow fringe only at the outer edge, and
  composes feathered face patches onto a single canonical body per species.
- Generated checkerboard backgrounds are never used: only inner-face pixels
  from expression sources are composited, constrained to the opaque body area.
- All nine states per species have identical alpha hashes; every visible pixel
  outside the face patch remains unchanged. The build fails before installation
  if either invariant is broken.
- Prepared images are 1024 x 1024 RGBA; light-background 220px and dark-background
  120px previews were inspected. `new_pets_preview.png` shows both masters.
- Production footprint: 33 PNGs, 21.95 MiB (previously 18.38 MiB).
- Flutter targeted suite: 56 passed, including asset alpha consistency, avatar,
  picker, subtitles and store readiness. Targeted Flutter analysis: no issues.
- Run `bash scripts/check_pet_asset_alpha.sh <files...>` for structural checks;
  passing this command does not certify visual quality or emotion consistency.

## Rebuild

`python3 scripts/build_cat_inspired_pet_assets.py` builds candidates and checks
body/alpha invariants. Add `--install` only after visual review to replace the
two complete production packs using their existing asset paths.

`prepared/` is reproducible build output and is ignored by Git. The source
masters and expression sources remain versioned for future regeneration.

iPhone transition/voice smoke and user preference validation remain pending;
automated image invariants do not establish that all older adults prefer these
designs or that live voice playback is perfectly synchronized.

The production renderer already uses continuous motion for rest/talking instead
of rapidly swapping full-body frames. Retain that behavior during integration.

# Design QA

## Scope

- Product: 삐약과학 native Flutter/Flame Android game
- Device: Samsung Galaxy A16 (`SM_A165N`, serial `RF9Y101ZZPB`)
- Implementation viewport: 2340×1080 landscape; game canvas remains 1600×900 with fitted side gutters
- State: Korean locale, release build, edit/selected/clear states exercised by ADB touch gestures

## Reference directions

The visual review covered three product directions: chain reaction guidance,
predict-then-test interaction, and the three-star mastery challenge.

## Implementation evidence

- Chain reaction: `C:\workAndroid\PiyakScience\tmp\fun-pass-a16\08_chain_stage.png`
- Prediction choice and placement: `C:\workAndroid\PiyakScience\tmp\fun-pass-a16\05_prediction_placed.png`
- Star challenge and collectible: `C:\workAndroid\PiyakScience\tmp\fun-pass-a16\09_star_challenge.png`
- Final 3-star result after spacing fix: `C:\workAndroid\PiyakScience\tmp\fun-pass-a16\11_prediction_clear_fixed.png`
- Legacy clear migrated to filled stars: `C:\workAndroid\PiyakScience\tmp\fun-pass-a16\10_home_migrated.png`
- Retry after result-card fix: `C:\workAndroid\PiyakScience\tmp\fun-pass-a16\12_retry_after_overlay_fix.png`

## Combined comparison inputs

- Full screens: `C:\workAndroid\PiyakScience\tmp\design-qa\full_comparison.png`
- Focused UI regions: `C:\workAndroid\PiyakScience\tmp\design-qa\focused_comparison.png`

Both files place the source and A16 implementation in one image. They were opened and visually inspected after capture.

## Findings and history

| Priority | Finding | Resolution |
|---|---|---|
| P0 | None | — |
| P1 | The first prediction clear capture showed the science sentence touching the retry/next button cards. | Moved the prediction science line upward and action buttons downward. Rebuilt and recaptured; the final clear screen has clean vertical separation and the drifted retry gesture still works. |
| P2 | Old `cleared_v1` records initially rendered as empty stars because no historical mastery record existed. | Added a 3-star legacy fallback and verified the old cleared tile and world chip both render filled 3-star progress on A16. |

## Visual judgment

- The chain ribbon preserves the source's ball→mechanism→goal sequence, using the shipped part art and the existing cocoa/cream sticker treatment.
- The prediction card keeps the two real ball sprites and a clear selected state. It is intentionally at the top because the existing bottom tray is interactive; this is a layout adaptation, not a loss of the source interaction.
- The challenge ribbon and in-world mint star reproduce the source's optional mastery cue without blocking the base goal. The collectible has a real transparent raster asset rather than a placeholder or code-drawn substitute.
- No cropped labels, HUD overlap, broken aspect ratio, stray dark silhouettes, or undersized primary touch targets were found in the final A16 captures.

## Tutorial extension QA

### Target and normalization

- Source visual truth: `C:\workAndroid\PiyakScience\store\screenshots\02_stage.png` (2340×1080, Android density 3; normalized to 780×360).
- Implementation: `C:\workAndroid\PiyakScience\tmp\tutorial_01_goal.png` (780×360, Flutter code-rendered view at devicePixelRatio 1).
- State: Korean locale, world 1 stage 1, first-visit tutorial step 1 over the live game screen.
- Typeface normalization: the render harness loaded Malgun Gothic and the real Material Icons font so Korean copy and icons could be inspected. Production continues to use the Android system Korean font shown in the source capture; the family difference is capture-environment-only.

### Comparison evidence

- Full view, source and implementation in one image: `C:\workAndroid\PiyakScience\tmp\tutorial-design-qa\full_comparison.png`.
- Focused flow with all four interaction states: `C:\workAndroid\PiyakScience\tmp\tutorial-design-qa\tutorial_flow.png`.
- Post-fix alternate-goal evidence: `C:\workAndroid\PiyakScience\tmp\tutorial_button_goal.png`.

All three comparison inputs were opened and inspected. The source and implementation use the same normalized 780×360 content viewport; no device frame or browser chrome is included.

### Required fidelity surfaces

- Fonts and typography: 22/23px heavy headings and 13/15px supporting copy preserve the existing app hierarchy. Korean copy fits without clipping or awkward truncation across all four pages.
- Spacing and layout rhythm: the 720×326 card keeps 12px outer safety margins, a stable 240px illustration column, 18px content gap, and 48px minimum action heights. No control collision was found at 780×360.
- Colors and tokens: cream surface, cocoa outline, candy gold progress/next state, and green start state reuse the production tokens rather than introducing a second visual system.
- Image quality and asset fidelity: mascot, balls, basket, button, plank, and collectible star are the shipped raster assets with correct aspect ratios and transparent edges. Gesture/action symbols use the shipped Material icon font; there are no emoji, placeholders, handcrafted SVGs, or substitute drawings.
- Copy and content: each page asks for one concrete action. Skip, back, next, and start wording is short and standalone in Korean and English.
- Accessibility and interaction: help is semantically labeled, persistent help and all tutorial actions meet the 48px mobile target, and automated tests cover first-visit display, skip/finish persistence, replay, page navigation, and goal-specific imagery.

### Tutorial comparison history

| Priority | Earlier finding | Fix and post-fix evidence |
|---|---|---|
| P0 | None | — |
| P1 | None | — |
| P2 | The first draft always illustrated ball→basket, which would teach the wrong goal when help was reopened on button, balloon, or domino stages. | Passed the current `GoalType` into the overlay and render goal-specific shipped sprites. `tutorial_button_goal.png` shows the post-fix metal-ball→button state; the widget test also asserts the basket asset is absent in that state. |

No actionable P0/P1/P2 difference remains. A physical-device screenshot is still desirable as a release-install check, but it is not needed to resolve a visual mismatch because the same 780×360 app viewport is fully rendered and compared here.

## Final result

passed

# Gate Test Report v2 - fresh-agent asset from brand-guidelines.md alone

Asset: [gate-test-asset-v2.html](gate-test-asset-v2.html), rendered to [gate-test-asset-v2.png](gate-test-asset-v2.png) (headless Chrome, 1080x1350).
Evaluated 2026-08-01 against brand-guidelines.md, positioning.md, and naming-decision.md.

## Verdict: FAIL

The copy and styling are on-brand, but the rendered card has a hard layout failure: the content stack overflows the fixed 1350px canvas and `overflow: hidden` clips the always-in-viewport proof line mid-sentence ("Unlimited free" is the last visible text; "workouts, no account required." is cut) and the entire canonical legal line is invisible.
A pre-launch asset that ships without its legal line violates §2, and a Hero A asset that truncates its proof line violates §9.
The blind agent's spec text described the legal line as placed; only rendering revealed it was clipped, which is itself a gap the guidelines did not guard against (no "render and verify fit" rule existed).
Verified by a second capture at 1080x1800: the clip is the canvas's own `overflow: hidden` at 1350px, not the screenshot window.

## What the asset got right

- Hero A headline verbatim, sentence case, periods kept (§9, §5).
- Subhead correctly applies the §9 scope note, replacing "no questions" with "nothing to answer between open and Start".
- Palette: Paper background, Ink headline, Slate secondary, Moss as the single accent, no Clay, no gradients, no pure white/black (§4).
- Ready Mark built exactly to the §3 reference SVG, both in the wordmark and as the large hero visual; wordmark gap and cap-height ratios correct.
- Type scale at 2x per §5 fixed-canvas rule: Display 112/120, Body 34/52, Small 28/40, Micro 24/32; 96px margins.
- Voice: declarative, identity-framed, no questions, no hype, no bro-fitness register, no streak/XP language, no health claims, no discipline surface word (§7, §8, §11).
- Truth policy: zero invented proof; the proof line states only verifiable mechanics; the overline states beta status factually (§7 rules 11-14, §11).
- Correct canonical legal line text (§2), plain "Rep Today" name, no dead "Rest Tomorrow" suffix, no em dashes anywhere.

## What the asset got wrong

1. **Overflow clipping (hard failure, described above).** Root cause: wordmark + 216px hero mark + overline + 3-line Display headline + 5-line subhead + 2-line proof + legal exceeds 1350px; the flex spacer collapses but text blocks cannot, so the bottom is silently clipped.
2. **Proof line weight 500** where the §5 scale specifies Small at weight 400 (minor; emphasis via weight was an unguided guess).
3. **The subhead's appended beta sentence** ("The first TestFlight builds go out soon.") modified an approved-verbatim block with no rule permitting it (judged acceptable in intent; now explicitly permitted, see edit 3).

## Evaluation of the reported gaps

- **Gap 1 (no beta/TestFlight guidance): REAL.** The guidelines had no announcement pattern, no CTA convention, and no ruling on whether "opening soon" is an urgency mechanic. The agent's judgment (factual status, no CTA without a real link) was correct but should not have required judgment.
- **Gap 2 (UI-forward with no real screenshot): REAL.** §10 called UI the safest asset while §7 rule 14 forbids invention, with no stated fallback; the Ready Mark fallback was the right call but was improvised. The "Screen images simulated" disclosure was indeed specified only for video end cards.
- **Gap 3 (truncated in transmission): the agent's report was cut off mid-sentence, so its remaining ambiguities are unknown.** The two found independently by this evaluation (fixed-canvas fit verification, proof-line weight) are covered by edits 4 and the note above.

## Guideline edits made to close the gaps

1. **§2 (name usage / disclosures):** the "Screen images simulated. App is pre-release." disclosure now applies to any asset, static or video, that depicts a simulated or staged screen; on static assets it is appended after the legal line. Closes the disclosure half of Gap 2.
2. **§10 (imagery):** new "Pre-launch UI stand-in" bullet: never mock a fictional Ready Screen with invented content; the Ready Mark at display scale is the approved stand-in until real build screenshots exist; any staged screen shows only shipped mechanics and carries the disclosure. Closes the visual half of Gap 2.
3. **§9 (approved copy):** new "Beta / TestFlight announcements (pre-launch)" block: approved status line "TestFlight beta for iOS - opening soon."; status lines state facts, never countdowns, uncommitted dates, or scarcity; no CTA until a real link exists, then the one CTA is "Join the beta"; one appended beta sentence on a hero subhead is explicitly permitted. Closes Gap 1.
4. **§5 (typography):** new "Fit before ship (fixed canvases)" rule: render at final pixel size and verify everything fits; clipping any required line is a hard failure; cut optional content first, never the proof or legal lines, never shrink below scale. Closes the unreported gap that produced this asset's failure.

## Disposition

The asset fails as shipped and should be regenerated after the guideline edits (shrink or drop the 216px hero mark, or trim the optional beta sentence, until the legal line renders inside the canvas).
The gate test did its job: all three reported gaps plus one unreported layout gap are now closed in brand-guidelines.md.

## Round 2 (2026-08-01): PASS

A second fresh agent, again restricted to brand-guidelines.md alone, regenerated the asset against the amended guidelines and self-verified fit before finishing (the new §5 rule).
The orchestrator independently viewed the rendered PNG: wordmark and mark correct, Moss overline uses the approved beta status line, Hero A headline and subhead verbatim with the permitted appended beta sentence, Ready Mark used as the pre-launch visual stand-in (no staged UI, so no simulated-screen disclosure required), proof line present, legal line last and fully inside the canvas with margins intact.
No clipping, no fabricated proof, no em dash, no CTA (no public link exists).
Residual gaps the blind agent reported are composition-level (no explicit social-card layout template; proof line has no assigned type style) and were judged acceptable improvisation surface rather than guideline defects: the composed result stayed on-brand twice under two different agents.
Verdict: the guidelines pass the fresh-agent gate as amended.
The shipped artifacts are gate-test-asset-v2.html / gate-test-asset-v2.png (round-2 version) plus this report covering both rounds.

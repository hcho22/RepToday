# Brand Guidelines Gate Test - Report

**Gate (from the master prompt):** a fresh agent that has read *only* `brand-guidelines.md` must produce a new on-brand asset with zero further input.

**Test run 2026-07-15.**
A fresh agent, restricted to the guidelines file alone (no repo access, no web), was asked to produce a 1080x1350 coming-soon social card with at least one newly written copy line.

**Result: PASS.**
The asset ([gate-test-asset.html](gate-test-asset.html), screenshot [gate-test-asset.png](gate-test-asset.png)) came back on-brand:
Paper background, Ink/Slate text, Moss-only accent, the Ready Mark built to the construction spec, sentence-case headline with periods, digits kept as digits, the required clearance line present, no urgency mechanics, no social proof, no questions asked of the reader.
Its new copy lines ("It launches the way it opens: ready." and the no-waitlist body line) pass all ten voice rules.

**Gaps the test surfaced (all fixed in the guidelines the same day):**

1. No fixed-canvas scaling rule for social-size assets - added (design at 2x the 16px scale; 80px margin at 1080 wide).
2. Wordmark name-to-mark size ratio unspecified - added (cap height = 2/3 mark height).
3. Uppercase overlines could mangle proper names ("IOS") - added a rule.
4. Ambiguity on Moss for non-body text - clarified (overlines/labels/stat callouts may be Moss; body never).
5. Weight 650 is a variable-font trap - H2 changed to 600.
6. Legal-line placement unspecified - added (last, Small, Slate/Mist, >= 24px at 1080 wide).
7. Card shadow vs "no glows" contradiction - reconciled with an explicit exception.
8. (No approved "coming soon" line existed; the test's new line is now precedent rather than canon - future assets may write their own to the voice rules, which is the intended behavior.)

The test asset is kept in the package unmodified, as evidence of what the guidelines alone produce.

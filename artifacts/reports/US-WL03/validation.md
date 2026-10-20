# US-WL03 validation: page copy and consistency across both pages

Date: 2026-10-20.
Spec: `.claude/agent/tasks/prd-waitlist_261019.md`, US-WL03.
Site copy and a static check only; nothing deployed.
No email address appears in this record; the check's tests assemble every address from parts and its findings never repeat one.

## What landed

- The closing band's lead ends "no date to announce yet, no spam, one launch email, plus a beta invitation only if you ask for one." on both pages; "one message" is gone.
- The FAQ "Is my data sold?" clause is Appendix B's sentence: the waitlist "keeps your email, your answers to its form, which Rep Today link brought you, if any, and the date you joined; the Privacy Policy's waitlist section says why and for how long".
  "When does it launch?" is unchanged and still agrees with the call to action.
- The hero's "Rep Today is pre-launch and not yet on the App Store." sits above the card (landed with US-WL02), and the `<noscript>` mailbox join is gone from all four placements, so no placement offers a second way to join; the only address left on the site is the policy's published contact address.
- `tools/waitlist/check-site.py`: the static check, run in CI's `waitlist` job (Ubuntu, no Xcode, no network).
  Rules: `placement-count`, `placement-drift`, `approved-string`, `form-fields`, `one-message`, `mailto-join`, `ask-guard`, `script`, `stray-address`.
  Findings print `rule  file:line  what` and never a value.
- `tools/waitlist/test-check-site.py`: 16 tests, each breaking a copy of the real site one way.
- `DEPLOY.md` and `_headers` notes: the Kit embed script is gone and a future CSP needs `connect-src` and `frame-src` for Kit and the event sink (still a follow-up, as the PRD's non-goals say).

## Validation Test

1. `python3 tools/waitlist/check-site.py` printed `check-site: ok`, exit 0.
2. In a browser at true 390 px and 1440 px on `/` and `/index-b`: `document.body.innerText.includes('one message')` was `false` and `...includes('one launch email, plus a beta invitation only if you ask for one')` was `true` on all four; no horizontal scroll; no `mailto:` link on the page.
3. The "mailbox line in all four placements" sabotage (a `<noscript>` line with a `mailto:` link to the published contact address, identical in every placement, so neither the drift rule nor the stray-address rule can fire) failed with only `mailto-join`, four findings, each naming file and line.
   That is `test_a_mailbox_join_line_in_every_placement_fails_only_the_mailto_rule`.
4. Changing one label in the closing band only failed with `placement-drift` naming `index.html:<line>`, "the closing placement of index.html" (`test_one_placement_that_differs_is_named`; the reference is the form most placements share, so the odd placement is the one named).
5. FAQ at both widths: `index-faq-390.png`, `index-faq-1440.png`, `index-b-faq-390.png`, `index-b-faq-1440.png`.
   The FAQ now names what the form keeps and points to the policy for why and for how long; it no longer says "nothing more".

Other sabotage covered by the tests: a missing or altered approved string, a missing promise phrase on a page, the old wording in any case, a fourth input or a wrongly named field, a download/follow/share word, a stray address in a text file (the finding names the file and line, not the address), the published contact address alone (allowed), a binary file holding address-shaped bytes (skipped), the script not posting the contract's field names, a page without the script, and a third placement.

## A/B comparison

`ab-diff.txt`: with the waitlist blocks and the named sentences (the hero lead-in, the FAQ clause, the closing promise, the form styles and the script tag) normalized away, `index.html` versus `index-b.html` differs by the same 57 diff lines before and after this story and the previous one (checked against the commit before the form landed, `27dd55e`), so the running A/B comparison is undisturbed.

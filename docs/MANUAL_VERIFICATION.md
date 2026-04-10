# Manual verification checklist

This document covers the three end-to-end verification flows that can't be
automated in CI because they require a live Claude Code session to load and
execute skills. Every other code path in phlexed is covered by the automated
regression suites at `scripts/test-adapters.sh` (60 assertions) and
`scripts/test-installer.sh` (24 assertions).

Work through the flows below after any material change to a skill file or
adapter. Capture the requested artifacts on any failure so bugs can be
reproduced in a follow-up Ralph loop.

---

## Prerequisites

One-time setup before running any of the three flows:

1. **Install phlexed globally** from a clean checkout:
   ```bash
   git clone git@github.com:theinventor/phlexed.git ~/.claude/skills/phlexed
   cd ~/.claude/skills/phlexed
   ./setup
   ./setup --check    # should report "symlinked to this repo"
   ```
2. **Verify the automated suites pass** before manual work:
   ```bash
   ./scripts/test-adapters.sh --quick   # 42/42 offline
   ./scripts/test-installer.sh          # 24/24 installer
   ```
   If either fails, fix the automated regression before running manual tests
   — live-session bugs are hard to distinguish from bin-script bugs otherwise.
3. **Install the sample app's gems** if you plan to run `phlexed-registry`
   end-to-end. The sample declares `ruby "3.3.0"` and `gem "phlexy_ui"`:
   ```bash
   cd sample
   bundle install         # needs ruby 3.3+ available via rbenv/rvm/etc.
   bundle show phlexy_ui  # should print a path — that's what phlexed-registry calls
   ```
   If bundle install is too slow or the environment doesn't have ruby 3.3,
   you can skip this and rely on the adapter-against-real-source verification
   already covered by `test-adapters.sh` (the online tests). The manual
   flows below do NOT strictly require a fully-bundled sample.

---

## Flow 1 — `/phlexed-setup` + `/phlexed-build`

**Covers:** Phase 2 fix_plan item — "Test skills end-to-end: run
/phlexed-setup in sample app, then /phlexed-build to generate a page"

### Steps

1. **Open Claude Code in the sample app root:**
   ```bash
   cd sample
   claude
   ```
2. **Invoke `/phlexed-setup`:**
   ```
   /phlexed-setup
   ```
   **Expected output:**
   - Preamble bash runs, reports `HAS_GEMFILE=1`, `HAS_PHLEX=1`,
     `DETECTED_LIBRARY=phlexy_ui`, `HAS_REGISTRY=0`, `HAS_ROUTING=0`,
     `HAS_PACKAGE_JSON=1`, `HAS_CURSOR=no` (sample doesn't use Cursor)
   - Step 4 runs `phlexed-registry`, writes `.phlexed/registry.json`
     with ~35 components (bundle-install required) OR reports that
     `bundle show phlexy_ui` failed (acceptable if gems aren't installed —
     the rest of the flow still works for the style registry)
   - As of v0.2, the registry has `source` tags per component and
     `local_components` metadata. If the sample has any local Phlex files
     (`app/views/base.rb`, `profile/show_view.rb`), they should appear as
     `source: "local"` in the merged output.
   - Step 4b runs `phlexed-style-scan`, writes `.phlexed/style-registry.json`
     reporting `design_system: daisyui`, `version: 4.12.10`,
     `active: phlexed-brand`, `5 themes`
   - Step 5 appends routing rules + styling rules to `CLAUDE.md`
     (creating the file if absent) between
     `<!-- phlexed skill routing -->` markers
   - Step 6 adds `.phlexed/` to `.gitignore` (already present in sample,
     should be a no-op)
   - Step 7 reports setup complete with library + design system summary.
     As of v0.2, if `local_components.conflicts > 0`, a "⚠ Name conflicts
     detected" block lists every conflicting local component and suggests
     renaming. The sample has no intentional conflicts so this block
     should NOT appear — if it does, something inadvertently added a
     local component whose name collides with a library name.
   - Step 8 (v0.2): since `HAS_CURSOR=no`, this step should be skipped
     entirely and not mentioned in the report. If the step runs anyway,
     the `HAS_CURSOR` detection logic is buggy.
3. **Invoke `/phlexed-build`:**
   ```
   > build me an account settings page where users can change their
   > email, password, and notification preferences
   ```
   **Expected behavior:**
   - Loads `.phlexed/registry.json` (warns if stale)
   - Preamble reports `LIBRARY_COUNT`, `LOCAL_COUNT`, `CONFLICT_COUNT`
     (v0.2). For the sample with real phlexy_ui installed, expect
     `LIBRARY_COUNT=35`, `LOCAL_COUNT=2` (Views::Base + Profile::ShowView),
     `CONFLICT_COUNT=0`.
   - Plans the page structure using registered PhlexyUI components
     (Card, FormControl, Input, Button, Toggle, etc.)
   - As of v0.2: the composition tree annotates each node with
     `[library: PhlexyUI::X]` or `[local: app/components/x.rb]` so the
     library/local split is visible before any files are written
   - Generates a Phlex view class at `app/views/account/settings_view.rb`
     that inherits from `Views::Base` and uses `render PhlexyUI::Card.new(...)`
     style composition
   - Does NOT emit inline Tailwind/DaisyUI class strings (the whole point
     of phlexed)
   - Wires the controller if needed (creates or updates `account_controller.rb`)
   - Final report (v0.2): "Components used:" section groups by source,
     listing library components first. If the sample has no local
     components used, it shows a flat list. Report does NOT include the
     ⚠ conflict warning unless the user's prompt explicitly targeted a
     conflicted name (sample has none).

### Pass criteria

- `.phlexed/registry.json` exists and contains 20+ components (or, without
  bundle install, contains phlexed-registry's error message as part of the
  skill's graceful-degrade path)
- `.phlexed/style-registry.json` exists with 18 DaisyUI component classes
  catalogued
- `CLAUDE.md` contains a "phlexed skill routing" section
- The generated Phlex view uses `render PhlexyUI::X.new(...)` composition,
  not `div(class: "card card-bordered")` inlining
- The view compiles with `ruby -c app/views/account/settings_view.rb` (even
  if it can't actually render without the full Rails boot)

### Sub-flow: Cursor rules generation (v0.2 Step 8)

`/phlexed-setup`'s Step 8 only runs when the project uses Cursor. The sample
doesn't, so this sub-flow requires a separate one-off test. **Before Flow 1's
main steps**, create a dummy Cursor marker:

```bash
cd sample
touch .cursorrules   # or: mkdir .cursor
```

Then run `/phlexed-setup` and verify:

- Preamble reports `HAS_CURSOR=yes`
- Step 8 fires an `AskUserQuestion` with 3 options (generate, preview, skip)
- Picking "generate" runs `phlexed-render-cursorrules` and writes the
  phlexed section into `.cursorrules`. If the file existed with markers
  (from a prior run), only the phlexed section is replaced. If it had user
  content, that content is preserved.
- Picking "preview" runs `--check` mode and prints to stdout without
  modifying the file
- Picking "skip" makes no changes and adds no line to the report
- After generate/preview, the Step 7 report gains a "Cursor rules:" line

**Cleanup after sub-flow:**
```bash
rm -rf sample/.cursorrules sample/.cursor
```

### If it fails

Capture these and file as a follow-up:
- The exact user prompt you sent to Claude Code
- `cat .phlexed/registry.json | head -50`
- `cat .phlexed/style-registry.json | head -50`
- The generated Phlex view file contents
- Any error output from the skill preamble or body
- The relevant section of `CLAUDE.md` after the skill ran

Common failure modes:
- **Registry build fails**: `bundle show phlexy_ui` returned nothing.
  Confirmed real failure mode — needs `bundle install` in the sample first.
- **Inline classes in generated output**: the skill's "use registered
  components" invariant was skipped. Check whether the styling rules got
  correctly appended to `CLAUDE.md`.
- **Wrong base class**: the generated view extends `Phlex::HTML` directly
  instead of `Views::Base`. The preamble's `BASE_CLASS` detection failed —
  check the sample's `app/views/base.rb` and confirm the grep in the
  preamble still matches.

**If the flow also exercises `/phlexed-component`** (which it will if
`/phlexed-build` decides it needs a new component): as of v0.2 the
component skill uses `generic.rb --append <file.rb>` in Step 6 for
incremental registry updates instead of a full rebuild. Verify:
- The new component appears in `.phlexed/registry.json` after the skill
  finishes (grep for the component name)
- The new component has `"source": "local"` tagged on it
- The full library component list is UNCHANGED from before the
  component was created (the append step shouldn't touch library
  entries). Compare counts: `jq '.components | map(select(.source == "library")) | length' .phlexed/registry.json` before and after should match.
- If the new component's short name collides with a library component,
  it should have `"conflict": true` in its JSON entry, and the skill's
  final report should explicitly mention the conflict.

---

## Flow 2 — `/phlexed-retrofit` against sample ERB views

**Covers:** Phase 2.5 fix_plan item — "Test retrofit against sample app:
add some ERB views to sample/, run /phlexed-retrofit, verify it audits
correctly, generates the plan, and the Ralph loop converts views one by one"

The sample app already has 7 convertible ERB templates committed, so you
don't need to add any — `sample/app/views/home/index.html.erb`,
`settings/index.html.erb`, `dashboard/show.html.erb`, plus the 3 shared
partials in `shared/` and a layout in `layouts/application.html.erb`.

### Steps

1. **Work on a throwaway branch** so the retrofit's atomic commits are easy
   to discard or inspect:
   ```bash
   cd sample
   git checkout -b retrofit-verification-$(date +%s)
   ```
2. **Ensure `/phlexed-setup` has run successfully** (from Flow 1 above).
   The retrofit skill's preamble checks for `.phlexed/registry.json` and
   `HAS_REGISTRY=1` — it hard-blocks without it.
3. **Invoke `/phlexed-retrofit`:**
   ```
   /phlexed-retrofit
   ```
4. **Phase 1 (Audit):** the skill should run `phlexed-audit`, produce
   `.phlexed/retrofit-audit.json`, and report:
   - 7 convertible templates, 2 already-phlex (`base.rb`, `profile/show_view.rb`)
   - 3 new components needed: `Flash`, `Footer`, `TopNav` (synthesized from
     the shared partials)
   - 4 batches (Shared partials → Layouts → Simple pages → Medium pages)
5. **Phase 2 (Present Plan):** the skill should show an `AskUserQuestion`
   with 5 options (A: everything, B: easy only, C: specific batches, D:
   plan-only, E: cancel). Pick **A** (everything).
6. **Phase 3 (Generate Ralph Loop):** the skill writes
   `.phlexed/retrofit/PROMPT.md`, `.phlexed/retrofit/fix_plan.md`, and
   `.phlexed/retrofit/.ralphrc`. Open each and verify:
   - `PROMPT.md` has the 11-step per-iteration workflow and conversion rules
   - `fix_plan.md` lists one task per view, ordered by batch
   - `.ralphrc` has scoped permissions (no `git push`, no `rm -rf`)
7. **Phase 4 (Execute):** accept the approval prompt. This fires
   `ralph -p .phlexed/retrofit/PROMPT.md` from the sample root. Each
   iteration should:
   - Pick the next unconverted view from fix_plan.md
   - Create the Phlex component class
   - Rename the old template to `.pre-phlex`
   - Commit atomically with message like
     `retrofit: convert shared/_flash to Phlex Shared::Flash`

### Pass criteria

- Audit finds 7 convertible templates with correct complexity classification
  (3 simple, some medium based on the partial references)
- Plan synthesizes the 3 shared-partial-derived new components (Flash, Footer,
  TopNav) with inferred props
- Each Ralph iteration produces exactly one atomic commit
- After the loop completes, `ls sample/app/views/**/*.pre-phlex` shows the
  old templates preserved as backups
- The git log on the branch shows 10+ commits (7 view conversions + 3 new
  component creations), each with a clear message
- No `.pre-phlex` files are deleted by the retrofit (cleanup is a manual
  final pass per the design doc)

### If it fails

Capture:
- `cat .phlexed/retrofit-audit.json`
- `cat .phlexed/retrofit/PROMPT.md`
- `cat .phlexed/retrofit/fix_plan.md`
- `git log --oneline` on the branch (to see how far the loop got)
- The last iteration's error message if the loop stopped early

Common failure modes:
- **"3 consecutive failures" stop rule fires**: the loop hit a view
  conversion it can't handle automatically. Read the last 3 iterations'
  output in `.phlexed/retrofit/logs/` to see why. Usually a sign that the
  sample needs a helper method added (e.g., `current_user`) to match a
  real project's conventions.
- **Converted views don't render**: the retrofit preserved behavior in
  theory but missed a detail. Compare the `.pre-phlex` backup to the new
  Phlex file and look for missing `render` calls or `yield`s.
- **New components aren't registered**: the skill was supposed to rebuild
  the registry after each new component. Check
  `.phlexed/registry.json` mtime — it should be updated during the loop.

**After verification, abandon the branch:**
```bash
git checkout main
git branch -D retrofit-verification-<timestamp>
rm -rf .phlexed/retrofit/ .phlexed/retrofit-audit.json .phlexed/retrofit-plan.json
```

---

## Flow 3 — `/phlexed-theme` mode verification

**Covers:** Phase 2.75 fix_plan item — "Test: verify style-registry.json is
accurate for sample app, verify /phlexed-theme can switch DaisyUI themes
correctly"

### Steps

1. **Ensure `/phlexed-setup` has run** (Flow 1) — `.phlexed/style-registry.json`
   must exist. The preamble's `HAS_STYLE_REGISTRY` check hard-blocks without it.
2. **Confirm the initial state:**
   ```bash
   grep data-theme sample/app/views/layouts/application.html.erb
   # Expected: data-theme="phlexed-brand"
   ```
3. **Invoke `/phlexed-theme` in switch mode:**
   ```
   > /phlexed-theme switch to dark
   ```
   **Expected:**
   - Preamble reports 11 state vars populated (`DESIGN_SYSTEM=daisyui`,
     `DS_VERSION=4.12.10`, `ACTIVE_THEME=phlexed-brand`, `THEME_COUNT=5`,
     etc.)
   - Skill routes to Switch mode (S1-S5 sub-workflow)
   - Updates `data-theme="dark"` in `app/views/layouts/application.html.erb`
   - Updates `daisyui.themes` in `tailwind.config.js` if needed (dark is
     already in the list so this may be a no-op)
   - Rebuilds `.phlexed/style-registry.json` — `active_theme` should now be
     `"dark"`
4. **Invoke `/phlexed-theme` in custom mode:**
   ```
   > /phlexed-theme create a custom theme called "sunset" with coral primary,
   > teal secondary, and a warm cream background
   ```
   **Expected:**
   - Skill routes to Custom mode (C1-C5 sub-workflow)
   - Writes a new theme object to `tailwind.config.js` with ALL 11 required
     semantic keys (primary, primary-content, secondary, secondary-content,
     accent, neutral, base-100, info, success, warning, error)
   - Derives `-content` colors from base lightness (white-on-dark or
     black-on-light)
   - Updates `data-theme="sunset"` in the layout
   - Rebuilds the style registry — `custom_themes` now includes `sunset`
5. **Invoke `/phlexed-theme` in audit mode:**
   ```
   > /phlexed-theme audit
   ```
   **Expected:**
   - Skill routes to Audit mode (A1-A5 sub-workflow, read-only)
   - Scans for anti-patterns: inline styles, hardcoded hex colors, raw
     Tailwind color utilities, custom CSS files
   - Produces a report — the sample intentionally has
     `settings/index.html.erb` with hardcoded DaisyUI class strings (the
     "before" example). Audit should flag that.
   - Does NOT auto-fix anything

### Pass criteria

- Switch mode updates both the layout AND tailwind.config.js atomically,
  no partial state
- Custom mode writes all 11 semantic keys (verify with
  `grep -E "primary|secondary|accent|neutral|base-100|info|success|warning|error" sample/tailwind.config.js`
  — should see all 11 for the new theme)
- Style registry rebuild reflects the new active theme
- Audit mode produces a report without modifying any files

### If it fails

Capture:
- Before and after diffs of `tailwind.config.js` and the layout file
- `cat .phlexed/style-registry.json | head -50` before and after
- The AskUserQuestion prompt text from the skill invocation

Common failure modes:
- **Missing semantic keys in custom theme**: the custom mode forgot to
  generate one of the 11 required keys. DaisyUI emits a warning at build
  time that's easy to miss. Check the generated theme object against the
  full list.
- **Raw class strings emitted instead of prop updates**: restyle mode is
  supposed to refuse this. If it happened, check that the preamble
  correctly loaded `.phlexed/registry.json` so the skill knows which
  components + props exist.
- **Switch mode doesn't update the layout**: the layout file detection
  may have failed. The preamble's `LAYOUT_FILE` var should be set to
  `app/views/layouts/application.html.erb` for the sample. If it's
  empty, check the file discovery glob in the skill preamble.

**After verification, reset the sample to a clean state:**
```bash
cd sample
git checkout app/views/layouts/application.html.erb tailwind.config.js
rm -rf .phlexed/
```

---

## Reporting results

After running any of these flows, update the relevant fix_plan.md item:

- **Flow 1 passes** → mark Phase 2 `[ ] Test skills end-to-end` as done,
  add a note with the date and any quirks observed
- **Flow 2 passes** → mark Phase 2.5 `[ ] Test retrofit against sample
  app` as done
- **Flow 3 passes** → mark Phase 2.75 `[ ] Test: verify style-registry.json
  is accurate for sample app, verify /phlexed-theme can switch DaisyUI
  themes correctly` as done

If any flow fails, file the captured artifacts as a follow-up task in
fix_plan.md under a new "Manual verification findings" section so the
next Ralph loop can pick it up and fix the underlying bug.

## Frequency

These flows are worth running:
- Before tagging a release (all three)
- After any change to a SKILL.md file (just the affected flow)
- After any change to the corresponding bin script (just the affected flow)
- As part of onboarding a new contributor to the project (all three, as a
  learning exercise)

For day-to-day development, the automated suites at `./scripts/test-adapters.sh`
and `./scripts/test-installer.sh` cover enough of the surface that manual
verification is only needed at the boundaries above.

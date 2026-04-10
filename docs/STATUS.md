# Project status

Last updated: 2026-04-10

**phlexed is feature-complete for v0.1 and v0.2.** Every concrete, non-speculative
feature from the design doc's roadmap is built, tested, and integrated. Remaining
work is either (a) live-Claude-Code manual verification or (b) user-initiated
release actions (git tags, publishing to phlexed.com).

## What's shipped

### Core skill system (v0.1)

- **5 skills** at `skill/`:
  - `/phlexed-setup` — detect library, build registries, configure CLAUDE.md (v0.2)
  - `/phlexed-build` — page/feature generation from registered components (v0.2)
  - `/phlexed-component` — new component creation matching library conventions (v0.2)
  - `/phlexed-retrofit` — 4-phase ERB/HAML/Slim → Phlex migration engine (v0.1)
  - `/phlexed-theme` — 4-mode theme switching + restyling + audit (v0.1)
- **6 bin scripts** at `skill/bin/`:
  - `phlexed-detect` — Gemfile.lock → library name
  - `phlexed-registry` — library adapter + generic merge → `.phlexed/registry.json`
  - `phlexed-audit` — template scanner → `.phlexed/retrofit-audit.json`
  - `phlexed-retrofit-plan` — audit → batched conversion plan
  - `phlexed-style-scan` — DaisyUI/Tailwind config → `.phlexed/style-registry.json`
  - `phlexed-render-cursorrules` — registries → `.cursorrules` (v0.2)
- **3 adapters** at `skill/adapters/`: `phlexy_ui.rb`, `shadcn_phlexcomponents.rb`,
  `generic.rb` (fallback with `--append <file>` incremental mode, v0.2)
- **Templates** at `skill/templates/`: claude-md-rules, 3 component-patterns,
  retrofit-prompt, retrofit-ralphrc.template

### v0.2 features

All 3 non-speculative v0.2 items from the design doc's Known Incompleteness
section are shipped:

1. **Cursor support** — `phlexed-render-cursorrules` bin script + auto-offer
   in `/phlexed-setup` Step 8 when `.cursor/` or existing `.cursorrules` is
   detected.
2. **Merged multi-adapter registries** — `phlexed-registry` now runs both
   library adapter AND `generic.rb` on every invocation, merging outputs
   with `source` tags (`"library"` / `"local"`), `has_local_components`
   metadata, and name conflict detection. `--library-only` opt-out.
3. **Incremental component-registry rebuild** — `generic.rb --append <file.rb>`
   parses one new Phlex class and merges it into the existing registry
   without re-scanning everything. Called by `/phlexed-component` Step 6.

### SKILL.md integrations

Every v0.2 bin feature has a corresponding skill integration. 3 of 5 skills
bumped to version 0.2.0:

- `phlexed-setup` (0.2.0): conflict surfacing in Step 7 report, Cursor
  detection + auto-offer in new Step 8
- `phlexed-component` (0.2.0): Step 6 uses `generic.rb --append`, not full
  rebuild; surfaces conflict warnings
- `phlexed-build` (0.2.0): library-first preference, source-annotated
  composition tree, grouped-by-source final report, conflict warnings
- `phlexed-retrofit` (0.1.0): no v0.2 dependencies
- `phlexed-theme` (0.1.0): no v0.2 dependencies

### Installer + sample + website + docs

- **`setup` script** at repo root with 5 modes (`--copy`, `--force`,
  `--uninstall`, `--check`, `--help`), TTY-aware colors, idempotent,
  verified against fake HOME via `scripts/test-installer.sh`
- **Sample Rails app** at `sample/` — hand-crafted fixture with PhlexyUI
  in Gemfile, custom DaisyUI theme, intentional ERB/Phlex mix for retrofit
  testing, 7 convertible ERB templates + 2 already-Phlex files
- **Landing page** at `site/index.html` — 1017-line single-file static site
  with dogfooded DaisyUI theming, hero before/after, 3-example tabbed
  gallery, skills grid, install instructions, CI badge
- **Docs** at `docs/MANUAL_VERIFICATION.md` — step-by-step checklist for
  the 3 live-Claude-Code verification flows
- **README.md, CHANGELOG.md, LICENSE (MIT)** — all in place and current

## Automated test coverage

**151 CI assertions** across 3 suites + shellcheck lint, all passing:

| Suite | Assertions | Scope |
|---|---|---|
| `test-adapters.sh --quick` (CI mode) | 127 | Offline: shellcheck lint, detect, audit, retrofit-plan, style-scan, generic adapter, cursorrules render, SKILL.md frontmatter, merged-registry pipeline with fake-bundle shim, HAML+Slim synthetic fixture with prop inference + complexity classification, ERB prop inference scope tracking |
| `test-adapters.sh` (full mode, local) | 145 | Above + online: real phlexy_ui + shadcn_phlexcomponents cloned from GitHub, adapters run against real upstream source, 9 bug-fix guards |
| `test-installer.sh` | 24 | Installer lifecycle: clean state, symlink install, bin scripts through install, idempotent re-run, --copy --force, --force symlink restore, --uninstall, argument parsing |

Plus a dedicated `shellcheck` step in the CI workflow that runs against all
5 shell scripts on every push/PR. Zero warnings across `setup`, `phlexed-detect`,
`phlexed-registry`, `test-adapters.sh`, `test-installer.sh`.

**GitHub Actions CI** (`.github/workflows/test.yml`) runs the quick adapter
suite + the installer suite on every push and pull request.

## What's NOT yet automatically tested

Three flows require a live Claude Code session to exercise the SKILL.md
instructions end-to-end. Documented in `docs/MANUAL_VERIFICATION.md`:

1. **`/phlexed-setup` + `/phlexed-build`** — full setup + page generation
   in the sample app (Phase 2 fix_plan item)
2. **`/phlexed-retrofit`** — 4-phase retrofit against sample ERB views on a
   throwaway branch (Phase 2.5)
3. **`/phlexed-theme`** — switch/custom/restyle/audit modes (Phase 2.75)

The bin scripts these skills invoke are covered by automated tests; what's
NOT covered is Claude Code loading the skills, reading the instructions,
and following them at runtime. That gap is intrinsic to skill-file-based
systems — automated tests can verify the scripts, not the instruction
interpretation.

## Known limitations

All documented in `CHANGELOG.md` and `docs/MANUAL_VERIFICATION.md`:

- **Retrofit not tested on a real Rails app.** Only the hand-crafted
  `sample/` fixture. Use on a branch with `.pre-phlex` backups as the
  rollback path.
- **Slim/HAML prop inference handles line-start `= expr` and `#{interp}`
  but NOT `%tag= expr` (HAML sigil) or bare `tag= expr` (Slim without
  sigil).** Users must write the expression on its own indented line for
  inference to work. Workaround: indent each output expression, or accept
  that `%h2= title` forms will produce empty `suggested_props` requiring
  manual fixup. Documented in fix_plan.md's deferred list.
- **Library version upgrades require full `phlexed-registry` rerun** —
  the `--append` incremental mode only handles local component additions.
- **Cursor support** is via `.cursorrules` plain-text file. No structured
  Cursor-native features (if Cursor adds them).
- **Dynamic component learning** (Approach C from the design doc) is the
  only v0.2 roadmap item still open. Deferred because it's open-ended
  research rather than a concrete feature.

## Release readiness

**v0.1.0 is ready to tag** after manual verification of the 3 flows above.
The CHANGELOG currently has the v0.1 content under `[0.1.0] — Unreleased`
which should become `[0.1.0] — YYYY-MM-DD` once tagged.

**v0.2.0 is ready to tag** after the same manual verification. The
`[Unreleased]` section of the CHANGELOG has 4 v0.2 entries (`Added` +
`Changed` + `Fixed`) plus a `### Added` for HAML+Slim test coverage that
should move into a new `[0.2.0] — YYYY-MM-DD` section.

Recommended release sequence:

1. Work through `docs/MANUAL_VERIFICATION.md` Flow 1 (setup + build) in
   the sample app. Fix any runtime bugs surfaced. Re-run the test suites
   to confirm no regression.
2. Flow 2 (retrofit) — likely surfaces the most bugs since it's the most
   complex skill.
3. Flow 3 (theme) — quickest flow, 4 mode checks.
4. Commit the Ralph-session work. Suggested single commit:
   `feat: v0.1 + v0.2 skill system, merge registries, incremental rebuild, Cursor support`
5. Tag `v0.1.0`, update CHANGELOG `[0.1.0] — <date>`, push tag.
6. Tag `v0.2.0`, update CHANGELOG `[0.2.0] — <date>`, push tag.
7. Deploy `site/index.html` to phlexed.com (static file, any host works).
8. Announce — the before/after story from the landing page is the hook.

## File manifest

Top-level:

```
CHANGELOG.md          — v0.1 + v0.2 release notes
LICENSE               — MIT
README.md             — project README with CI badge + install
setup                 — installer script
site/index.html       — phlexed.com landing page (1017 lines, 3-example gallery)
sample/               — hand-crafted Rails 8 fixture
scripts/
  test-adapters.sh    — 117 offline + 18 online assertions
  test-installer.sh   — 24 installer-lifecycle assertions
skill/                — the skill system (SKILL.md + 4 sub-skills + bin + adapters + templates)
.github/workflows/
  test.yml            — CI: quick adapter suite + installer suite on every PR
docs/
  MANUAL_VERIFICATION.md — 3 live-Claude-Code flows with expected outputs
  STATUS.md           — you are here
```

## Further reading

- **Design doc:** `~/.gstack/projects/phlexed/troy-unknown-design-20260410-120216.md`
- **Ralph session notes:** `.ralph/fix_plan.md` — comprehensive per-loop notes
  covering every decision, bug, and rationale
- **Landing page copy:** `site/index.html` is both the marketing story and a
  working demo of DaisyUI + custom theme

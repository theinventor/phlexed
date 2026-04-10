# Changelog

All notable changes to phlexed are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **HAML/Slim complexity signals.** `phlexed-audit`'s `COMPLEXITY_SIGNALS`
  list now has 4 HAML/Slim-specific patterns alongside the existing
  ERB-centric ones: `^\s*=\s*raw` (raw HTML output, +3),
  `^\s*-\s*case` (case statement, +2), `^\s*-\s*if` (conditional, +1),
  and `^\s*-.*\b(each|map|select|reject)\b\s+do` (iteration, +1). All
  line-anchored so they don't double-count ERB content (ERB `<%= raw`
  stays in the ERB signal group). The existing signals are now organized
  into three comment-grouped sections (engine-agnostic, ERB-specific,
  HAML/Slim-specific) so future contributors can extend without
  duplication. Previously, a genuinely complex HAML template with case
  statements + iteration + raw output would score 0-2 points and
  misclassify as simple/medium. Now it scores 7+ and correctly lands in
  the complex batch for manual review. Verified with a synthetic
  `admin/dashboard.html.haml` fixture that triggers all 4 new signals
  plus the engine-agnostic content_for + render signals for a total
  score of 9, correctly classified as "complex". Regression guarded:
  the existing HAML `home/index.html.haml` still classifies as
  "medium" (not over-scored by the new signals).
- **shellcheck CI + local integration.** `.github/workflows/test.yml` gained
  a new "Lint shell scripts (shellcheck)" step that runs shellcheck across
  the 5 shell scripts in the repo (`setup`, `phlexed-detect`,
  `phlexed-registry`, `test-adapters.sh`, `test-installer.sh`) on every
  push/PR. Positioned before the test suites so CI fails fast on shell
  bugs. Ubuntu runners ship shellcheck by default so no setup step needed.
  `test-adapters.sh` also gained a conditional shellcheck subsection
  (skipped when the binary isn't on PATH) so local dev runs get the same
  feedback. Cleaned up 5 pre-existing warnings surfaced during integration:
  `ls | xargs basename` in phlexed-registry replaced with `find -exec`
  (SC2011 — filename-safety); unused `YELLOW` + `subsection` in
  test-installer.sh deleted; unused `copy_output`/`force_output` captures
  in test-installer.sh dropped. Intentional exemptions (SC2059 for printf-
  color idioms, SC2329 for trap-invoked cleanup, SC2016 for single-quoted
  Ruby heredocs) declared via file-level `# shellcheck disable=CODE`
  comments with rationale.
- **HAML + Slim regression coverage** — `scripts/test-adapters.sh` now builds
  a synthetic multi-engine project in the test workdir and runs the full
  audit + retrofit-plan pipeline against it, adding 12 new assertions covering
  HAML and Slim code paths that the ERB-only sample doesn't exercise: engine
  detection for both suffixes, render tracing via the HAML/Slim `= render`
  prefix syntax, partial resolution for non-`.erb` extensions, component-
  match extraction from HAML/Slim class syntax (`%section.hero`, `.card`),
  and new-component name derivation (`_footer.html.haml` → `Footer`,
  `_reviews.html.slim` → `Reviews`).

### Fixed

- **`phlexed-retrofit-plan` prop inference now handles HAML and Slim syntax.**
  Previously the inference engine scanned `<%= foo %>` regex only, which
  doesn't match HAML `= foo` / Slim `= foo` output expressions or
  `#{foo}` string interpolation — meaning HAML/Slim projects silently got
  empty `suggested_props` on every component during retrofit. The engine
  now has three extraction patterns (ERB `<%=`, HAML/Slim line-start `=`,
  shared `#{...}` interpolation) plus a new scope-local detection pattern
  for HAML/Slim statement-form assignments (`- foo = ...` at line start).
  Verified against a synthetic fixture: ProductCard (HAML) correctly
  extracts `['description', 'price', 'title']` and ReviewCard (Slim)
  correctly extracts `['author', 'content', 'review', 'timestamp']`.
  Known limitation (documented in fix_plan): HAML `%tag= expr` with a
  sigil+tag prefix and Slim bare `tag= expr` aren't handled — users must
  write `= expr` on its own indented line for inference to work. No
  regression on the 3 pinned ERB assertions (Flash/Footer/TopNav all
  still `[]`).
- **`phlexed-retrofit-plan` prop inference no longer extracts block-scoped
  iteration variables as component props.** Previously, converting
  `_flash.html.erb` to a Phlex component would suggest
  `initialize(message:, variant:)` because the inference engine naively
  picked up `<%= message %>` and `<%= variant %>` from inside
  `flash.each do |type, message|` + `<% variant = ... %>`. The engine now
  tracks two kinds of scope-introducing constructs and excludes their
  bindings:
  1. Block parameters — `|a, b, c|`, `|*rest|`, `|a = default|`, `|&blk|`
  2. Top-level ERB local assignments — `<% foo = ... %>` and `<% foo, bar = ... %>`
  The same-loop regression test was tightened from the lenient "at least 1
  new_component has suggested_props" to three pinned assertions (`Flash == []`,
  `Footer == []`, `TopNav == []`) so any future change to the inference
  engine has to intentionally update the expected shape.

### Added

- **Incremental registry rebuild via `generic.rb --append <file.rb>`** — the
  generic adapter now supports an incremental mode that parses one Phlex class
  and merges it into an existing `.phlexed/registry.json` without re-scanning
  the whole project. Intended to be called by `/phlexed-component` after
  creating a new Phlex class, avoiding a full-rebuild roundtrip for projects
  with many components. Features: dedup by file path (re-appending the same
  file updates in place, so repeated calls are idempotent), conflict detection
  against existing library components (flags the new local component with
  `conflict: true`), `local_components` metadata auto-update in merged v0.2
  registries, clear error for non-Phlex files (exit 1), and path-resolution
  fix so `output_path` resolves relative to `project_root` (not shell CWD).
- **13 new append regression assertions** in `scripts/test-adapters.sh`
  covering 4 scenarios: append to an empty flat v0.1 registry, idempotent
  re-append of the same file, append to a merged v0.2 registry with a
  library-colliding name (conflict flag + metadata update + "library wins"
  invariant), and non-Phlex file rejection.

### Changed

- **`/phlexed-build` now uses the merged registry's `source` field.** Four
  updates to make the skill source-field-aware:
  1. **Preamble** gained three new state vars — `LIBRARY_COUNT`, `LOCAL_COUNT`,
     `CONFLICT_COUNT` — computed from the registry via inline Ruby.
  2. **Step 3 (Load the registry)** now explains the merged registry structure
     (library + local with source tags), documents the library-first preference
     for ambiguous matches, and specifies conflict handling (never silently
     use a `conflict: true` local component).
  3. **Step 4 (Plan composition)** annotates the component tree with
     `[library: <full_class>]` or `[local: <file_path>]` on every node so the
     library/local split is visible before any files are written.
  4. **Step 7 (Report)** groups "Components used:" by source (library first,
     then local). Only shows the grouping when local components are involved —
     library-only projects still get the flat v0.1 output. Adds a ⚠ conflict
     warning block when the user's prompt targeted a component name shared
     between library and local registries.
  5. **Invariants** section adds two new hard rules: "Library wins by default
     when both sources have the same name" and "Never silently use a
     `conflict: true` component." Skill frontmatter bumped to version 0.2.0
     (third skill to move off 0.1.0 — setup + component + build all on 0.2.0
     now). Description expanded to 605 chars.
- **`/phlexed-setup` now surfaces name conflicts and offers Cursor rules
  generation.** Two integration updates to the setup skill:
  1. **Step 7 report** now reads `local_components.conflicts` from the merged
     registry and prints a `⚠ Name conflicts detected` block listing every
     conflicting local component with rename guidance. The Components line
     also breaks down `(N library + N local)` when local components exist.
     Below-zero-conflict case is omitted for terse output.
  2. **New Step 8 — Cursor rules generation offer.** Preamble gained a
     `HAS_CURSOR` check (true if `.cursor/` or `.cursorrules` exists). When
     true, Step 8 fires an `AskUserQuestion` with 3 options: generate via
     `phlexed-render-cursorrules`, preview via `--check`, or skip. When
     false, Step 8 is skipped entirely. The re-run Step 2 option D also
     eligible for Step 8 since style registry changes can affect the
     rendered cursorrules styling section.
  Skill frontmatter bumped to version 0.2.0. Description expanded to 748
  chars mentioning merged registry + Cursor integration.
- **`/phlexed-component` now uses `generic.rb --append` for incremental registry
  rebuild.** Step 6 of the skill previously ran a full `phlexed-registry`
  rebuild after creating every new component. It now calls
  `generic.rb --append <file.rb>` which parses just the new Ruby file and
  merges it into the existing registry in place. Faster, idempotent, and
  preserves library-sourced entries untouched. Documents 3 fallback conditions
  (missing registry, library gem upgrade, deleted component) where a full
  rebuild is still the right move. Surfaces conflict warnings in the final
  report when `--append` flags a name collision with a library component.
  Skill frontmatter bumped to version 0.2.0 to reflect that it now depends
  on the v0.2 append mode.
- **`phlexed-render-cursorrules` partitions components by source** when the
  registry has library + local components merged (v0.2 registries). The output
  now has two sub-sections under "Available components": `### From library
  (<name>)` and `### Project-local (app/components, app/views)`. Name conflicts
  from the merge step are surfaced with a callout at the top of the project-
  local section (`"1 component conflict with library names — consider renaming
  to disambiguate"`) AND an inline `⚠ name conflict` warning on each affected
  component line. Backward-compatible: v0.1 registries without `source` tags
  still render as a single flat listing. 7 new regression assertions in
  `test-adapters.sh` covering the partitioned path + the "library wins in
  conflicts" invariant (library components never get warnings, even when a
  local component shares their name).

### Added

- **Merged multi-adapter registries** — `phlexed-registry` now runs both the
  library adapter (PhlexyUI / shadcn_phlexcomponents) AND the generic adapter
  against `app/components/` + `app/views/` on every invocation, merging the
  outputs into one `.phlexed/registry.json`. Each component is tagged with a
  `source` field (`"library"` or `"local"`) and local components with names
  that collide with the library get a `conflict: true` flag so `/phlexed-build`
  can warn the user to rename. New registry fields: `has_local_components`
  (bool) and `local_components` (metadata hash with `count` and `conflicts`).
  The schema is backward-compatible — existing consumers that only read
  `components[]` see a superset of what they got before. Pass `--library-only`
  to `phlexed-registry` to skip the local scan (still produces the tagged
  schema for consistency, just with zero local components). Closes the v0.2
  "merged multi-adapter registries" item from the design doc's Known
  Incompleteness section.
- **16 new merge regression assertions** in `scripts/test-adapters.sh`. Builds
  a synthetic `phlexy_ui`-like gem + a fake `bundle show` shim + a project
  with 2 local components (one of which conflicts with a library component),
  runs the full phlexed-registry pipeline end-to-end, and verifies: merged
  file exists, library name/version, source tagging, local count, conflict
  detection on the colliding Card component, absence of conflict flag on
  the non-colliding UserBadge, intermediate-file cleanup, and `--library-only`
  schema consistency.
- **`phlexed-render-cursorrules`** — new bin script that reads `.phlexed/registry.json`
  and `.phlexed/style-registry.json` and writes a `.cursorrules` file at the project
  root, making the same phlexed context available to Cursor that `/phlexed-setup`
  injects into `CLAUDE.md` for Claude Code. Uses `# phlexed BEGIN` / `# phlexed END`
  marker comments so re-runs preserve any user-authored content outside the managed
  section. Supports `--project`, `--output`, `--check`, `--help`. Closes the v0.2
  "Cursor support" item from the design doc's Known Incompleteness section.
- **12 new cursorrules regression assertions** in `scripts/test-adapters.sh`,
  covering the render pipeline (file write, BEGIN/END markers, library name +
  version, component line formatting, design system info, active theme, anti-
  patterns) plus idempotent re-inject (user content preservation, single-marker-pair
  invariant) plus `--check` mode (stdout output, file mtime unchanged).

## [0.1.0] — Unreleased

Initial release. Everything below is part of v0.1 and ships together.

### Added — Skills

- **`/phlexed-setup`** — one-time-per-project configuration. Detects the installed
  Phlex component library from `Gemfile.lock`, runs the matching adapter to build
  `.phlexed/registry.json`, scans `package.json` and `tailwind.config.js` to build
  `.phlexed/style-registry.json`, and appends routing + styling rules to `CLAUDE.md`.
  Re-run handling covers fresh/stale/missing registries with explicit user prompts.
- **`/phlexed-build`** — page/feature generation. Loads the component registry,
  plans a layout using registered components, and generates composed Phlex view
  classes. Auto-invokes `/phlexed-component` as a sub-skill when a planned element
  has no registry match. Stops and asks for clarification when 3+ new components
  are needed.
- **`/phlexed-component`** — component creation following library conventions.
  Reads existing components for pattern consistency, generates the class with props
  and variants, writes tests (RSpec if `spec/` exists, Minitest otherwise), and
  rebuilds the registry so the new component is immediately available to `/phlexed-build`.
- **`/phlexed-retrofit`** — 4-phase ERB-to-Phlex migration engine. Audits `app/views/`,
  batches by dependency (shared partials → layouts → simple → medium → complex),
  synthesizes new components from shared partials, generates a Ralph loop
  (`PROMPT.md` + `fix_plan.md` + `.ralphrc`), and executes the conversion with atomic
  commits per view. Old templates preserved as `.pre-phlex` backups. 3-consecutive-
  failures stop rule.
- **`/phlexed-theme`** — 4-mode styling skill (switch / custom / restyle / audit).
  Switch mode updates `data-theme` + `tailwind.config.js` themes array. Custom mode
  generates DaisyUI theme objects with all 11 required semantic keys. Restyle mode
  adjusts component props (never raw classes); refuses raw-class workarounds and
  presents proper alternatives. Audit mode is read-only anti-pattern scanning.

### Added — Bin scripts

- **`phlexed-detect`** — reads `Gemfile.lock` and identifies the installed Phlex
  library. Priority order: `phlexy_ui` > `shadcn_phlexcomponents` > `protos` >
  `ruby_ui` > custom > none.
- **`phlexed-registry`** — orchestrates detection + adapter to produce
  `.phlexed/registry.json`. Staleness detection via `Gemfile.lock` mtime comparison.
  `--check` mode for read-only status.
- **`phlexed-audit`** — Ruby scanner for `app/views/` templates. Classifies complexity
  via 18 regex signals with additive weights, maps component matches against the
  registry via 35+ regex hints, traces shared-partial dependencies across ERB/HAML/
  Slim `render` calls, flags already-Phlex files. Outputs `.phlexed/retrofit-audit.json`.
- **`phlexed-retrofit-plan`** — reads the audit JSON and groups views into 5 batches
  (shared partials → layouts → simple pages → medium → complex). Synthesizes
  `new_components_needed` from unregistered shared partials with inferred props from
  `@ivars`, local-var references, and `locals:` hash keys at render call sites.
- **`phlexed-style-scan`** — detects DaisyUI / Tailwind / none from `package.json`,
  parses `tailwind.config.js` for themes + custom themes + `theme.extend` (nested-
  brace-aware walker, not regex), hardcodes DaisyUI component vocabulary (18
  components) + 20 CSS variables + utility class guidance + 9 anti-patterns. Detects
  active `data-theme` from layout files across .erb / .haml / .slim / .rb. Three
  output modes (daisyui / tailwind / none).

### Added — Adapters

- **`adapters/phlexy_ui.rb`** — parses PhlexyUI gem source. Extracts class name,
  `register_modifiers` variants/sizes (split by matching `xs|sm|md|lg|xl`),
  `component_html_class:`, and `initialize` kwargs. Outputs the structured registry
  schema.
- **`adapters/shadcn_phlexcomponents.rb`** — parses `class_variants(variant: {...},
  size: {...})` DSL plus subcomponent factory methods (`def trigger(**, &)`, etc.).
  Tailwind-native vocabulary.
- **`adapters/generic.rb`** — fallback. Scans `app/components/`, `app/views/components/`,
  and `app/views/layouts/` for any class inheriting from `Phlex::HTML`, `Views::Base`,
  `ApplicationView`, or `ApplicationComponent`. Extracts props from `initialize`
  kwargs and slots from `renders_one` / `renders_many`.

### Added — Templates

- **`templates/claude-md-rules.md`** — CLAUDE.md routing rules template. HTML comment
  markers (`<!-- phlexed skill routing -->`) enable clean removal and re-injection
  on re-runs. Includes all three sections: skill routing, Phlex conventions, styling
  rules.
- **`templates/component-patterns/phlexy-ui.md`** — 604-line PhlexyUI prompt patterns
  across 10 sections: Core conventions, Layout, Forms, Actions, Feedback, Navigation,
  Data display, Full page examples, Anti-patterns, "When a pattern isn't here". Two
  full page examples (settings, pricing).
- **`templates/component-patterns/shadcn-phlexcomponents.md`** — 838-line shadcn
  template with the same 10 sections adapted for Tailwind-native `class_variants` DSL.
  Documents both subcomponent patterns (sibling classes vs factory methods) with
  explicit anti-patterns to prevent cross-contamination.
- **`templates/component-patterns/styling-rules.md`** — 300-line authoritative
  rulebook with 6-step decision ladder, 9 hard rules (each with bad/good pairs),
  6 common scenarios with correct answers, and explicit escape hatches.
- **`templates/retrofit-prompt.md`** — Ralph PROMPT.md template with 11-step per-
  iteration workflow, conversion rules (atomic commits, preserve behavior, `.pre-phlex`
  backups), 3-failures-in-a-row stop rule, and end-of-loop summary report.
- **`templates/retrofit-ralphrc.template`** — scoped `.ralphrc` with explicit allow
  lists (git commit but not push, bundle exec, rspec/rails test, phlexed-registry,
  mv for .pre-phlex renames) and explicit deny lists (git reset --hard, push --force,
  rm -rf, hook bypasses, edits to Gemfile.lock/config/credentials/.env).

### Added — Installer

- **`setup`** script at repo root. Default mode symlinks `skill/` to
  `~/.claude/skills/phlexed/` so `git pull` picks up updates without re-install.
  `--copy` vendors a snapshot instead. `--force` replaces existing installs. `--uninstall`
  removes. `--check` reports install state without modifications. `--help` shows usage.
  Verifies Ruby 3.0+ (warns on older versions, hard-blocks only on missing Ruby).
  TTY-aware ANSI colors. Four install states detected: missing / symlink_correct /
  symlink_wrong:<target> / directory.

### Added — Sample Rails app

- Hand-crafted Rails 8 fixture at `sample/` with PhlexyUI in `Gemfile.lock`, DaisyUI
  + Tailwind config, 7 ERB templates (layout, 3 shared partials, home, dashboard,
  settings) intentionally awaiting retrofit, and 2 already-Phlex files
  (`app/views/base.rb` + `profile/show_view.rb`) representing the target state.
- Custom `phlexed-brand` DaisyUI theme with all 11 required semantic keys in
  `tailwind.config.js` to exercise the style scanner's custom-theme extraction.
- Layout uses `data-theme="phlexed-brand"` so active-theme detection picks up the
  custom theme rather than a built-in.
- `settings/index.html.erb` is the intentional "before" (60+ lines of inline DaisyUI
  classes) for before/after comparison on the landing page and in the README.

### Added — Website

- **`site/index.html`** — single-file static landing page for phlexed.com. 1017 lines.
  Dogfoods DaisyUI with a custom `phlexed-dark` theme (violet / cyan / pink). Sections:
  sticky nav, hero with install quick-command, hero before/after (settings form),
  component gallery with 3 tabbed examples (pricing, dashboard, navbar), "why it
  works" 3-card explanation, 5-skill grid, how-it-works 4-step process, install
  instructions with GitHub CTA, footer.
- Gallery tab switching is 100% CSS via radio inputs + adjacent-sibling selectors.
  Zero JavaScript for interactive elements. Only runtime JS is Prism.js autoloader
  for syntax highlighting.
- All CDN dependencies: Tailwind Play CDN, DaisyUI v4.12.10, Prism.js v1.29.0, Google
  Fonts (Inter + JetBrains Mono). No build step, no npm, no bundler. Preview with
  `open site/index.html` or `python3 -m http.server -d site 8080`.

### Added — Project docs

- **`README.md`** — 342 lines, 11 sections: lede, problem statement, before/after
  teaser, install, 5-skill detail, architecture diagram, supported libraries table,
  repo layout, FAQ (6 questions), contributing, credits, license.
- **`LICENSE`** — standard MIT text. Copyright 2026 Troy Anderson and phlexed
  contributors.

### Known limitations (v0.1)

- **One active adapter at a time.** If a project has a library-specific adapter
  (PhlexyUI, shadcn_phlexcomponents) plus custom components in `app/components/`,
  only the library components are indexed. `/phlexed-component` documents this and
  suggests `--adapter generic` as a follow-up. Merged registries deferred to v0.2.
- **End-to-end testing with real `bundle install`** — all bin scripts are smoke-
  tested against synthetic fixtures and the hand-crafted `sample/` app, but
  `phlexed-registry` has not been exercised against a real `bundle show phlexy_ui`
  invocation. Requires a working Ruby + Bundler environment.
- **Retrofit not yet tested on a real Rails app.** The retrofit skill and its Ralph
  loop scaffolding are built and smoke-tested against the `sample/` fixture, but
  have not been run against a production Rails application with a real test suite.
  Use on a branch with `git revert` as the rollback path. `.pre-phlex` backups are
  preserved automatically.
- **Cursor / Copilot / other AI tools** are not supported. v0.1 targets Claude Code
  only. The registry files are plain JSON so other tools can read them directly; a
  `.cursorrules` generator is deferred to v0.2.
- **No incremental registry rebuild.** `/phlexed-component` always rebuilds the full
  registry after creating a new component. Fast enough for typical component counts;
  incremental add deferred if this becomes a bottleneck.

[0.1.0]: https://github.com/theinventor/phlexed/releases/tag/v0.1.0

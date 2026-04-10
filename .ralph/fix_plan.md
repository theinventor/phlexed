# Phlexed Fix Plan

## Phase 1: Foundation (High Priority)

- [ ] Create monorepo directory structure (skill/, sample/, site/)
- [ ] Build `skill/bin/phlexed-detect` — shell script that reads Gemfile.lock and identifies installed Phlex component library (phlexy_ui, shadcn_phlexcomponents, protos, ruby_ui, or custom)
- [ ] Build `skill/adapters/phlexy_ui.rb` — Ruby script that scans PhlexyUI gem source, extracts component classes, props, variants, and generates registry JSON
- [ ] Build `skill/adapters/shadcn_phlexcomponents.rb` — same for shadcn_phlexcomponents
- [ ] Build `skill/adapters/generic.rb` — fallback adapter that scans app/views/components/ and app/components/ for any Phlex::HTML subclass
- [ ] Build `skill/bin/phlexed-registry` — shell script that orchestrates detection + adapter to produce .phlexed/registry.json
- [ ] Test detect + registry against sample Rails app

## Phase 2: Core Skills (High Priority)

- [ ] Write `skill/SKILL.md` — root skill definition (phlexed-setup workflow: detect library, build registry, append CLAUDE.md rules)
- [ ] Write `skill/templates/claude-md-rules.md` — CLAUDE.md routing rules template
- [ ] Write `skill/templates/component-patterns/phlexy-ui.md` — prompt patterns teaching Claude how to use PhlexyUI components correctly
- [ ] Write `skill/templates/component-patterns/shadcn-phlexcomponents.md` — same for shadcn_phlexcomponents
- [ ] Write `skill/phlexed-build/SKILL.md` — page/feature generation skill (loads registry, plans layout, generates Phlex views)
- [ ] Write `skill/phlexed-component/SKILL.md` — component creation skill (reads patterns, generates component + tests, rebuilds registry)
- [ ] Test skills end-to-end: run /phlexed-setup in sample app, then /phlexed-build to generate a page

## Phase 2.5: Retrofit Skill (High Priority)

- [ ] Build `skill/bin/phlexed-audit` — shell/Ruby script that scans app/views/ for all templates (.erb, .haml, .slim), assesses complexity (simple/medium/complex), maps component matches against registry, identifies shared partial dependencies, and outputs .phlexed/retrofit-audit.json
- [ ] Build `skill/bin/phlexed-retrofit-plan` — reads the audit JSON, groups views into batches (shared partials first, then layouts, then pages by complexity), identifies new components needed, outputs a structured conversion plan
- [ ] Build `skill/templates/retrofit-prompt.md` — Ralph PROMPT.md template for retrofit loops. Includes conversion rules: one view per iteration, preserve all behavior, use registered components, rename old templates to .pre-phlex, atomic commits, skip on test failure
- [ ] Build `skill/templates/retrofit-ralphrc.template` — .ralphrc template with project-appropriate tool permissions for the retrofit loop
- [ ] Write `skill/phlexed-retrofit/SKILL.md` — the retrofit skill definition with 4 phases: audit, present plan (AskUserQuestion with approve/modify/exclude/report-only), generate Ralph loop (.phlexed/retrofit/ with PROMPT.md + fix_plan.md + .ralphrc), execute with user approval (ralph -p .phlexed/retrofit/PROMPT.md)
- [ ] Test retrofit against sample app: add some ERB views to sample/, run /phlexed-retrofit, verify it audits correctly, generates the plan, and the Ralph loop converts views one by one

## Phase 2.75: Theme/Styling Skill (High Priority)

- [ ] Build `skill/bin/phlexed-style-scan` — scans package.json for DaisyUI version, reads tailwind.config.js for active themes/custom themes/extensions, cross-references PhlexyUI component prop-to-class mappings with DaisyUI's class vocabulary. Outputs .phlexed/style-registry.json
- [ ] Extend `skill/bin/phlexed-registry` to also build style-registry.json during setup (calls phlexed-style-scan)
- [ ] Write `skill/templates/component-patterns/styling-rules.md` — the styling rules that get injected into CLAUDE.md. Anti-patterns list: no inline styles, no hardcoded colors, no raw Tailwind when DaisyUI class exists, no custom CSS when design system handles it
- [ ] Write `skill/phlexed-theme/SKILL.md` — theme/restyle skill: loads both registries, handles theme switching (update data-theme + tailwind.config), custom theming (generate DaisyUI theme definitions), component restyling (use props not classes). Rebuilds style registry after changes.
- [ ] Update `skill/SKILL.md` (phlexed-setup) to build style-registry.json alongside component registry
- [ ] Update `skill/templates/claude-md-rules.md` to include styling rules section
- [ ] Test: verify style-registry.json is accurate for sample app, verify /phlexed-theme can switch DaisyUI themes correctly

## Phase 3: Sample App (Medium Priority)

- [ ] Create minimal Rails 8 app in sample/ with PhlexyUI installed
- [ ] Add 2-3 example pages built with Phlex components (dashboard, settings, profile)
- [ ] Verify phlexed-detect correctly identifies PhlexyUI in sample app
- [ ] Verify phlexed-registry produces correct registry.json from sample app
- [ ] Create a "before" example: raw AI-generated Phlex without phlexed (for website comparison)

## Phase 4: Installer (Medium Priority)

- [ ] Write `setup` script at repo root — copies skill/ to ~/.claude/skills/phlexed/, verifies Ruby, prints instructions
- [ ] Make setup idempotent (safe to re-run)
- [ ] Test full install flow: clone repo, run setup, go to sample app, run /phlexed-setup

## Phase 5: Website (Lower Priority)

- [ ] Create phlexed.com landing page in site/ — hero with before/after AI output comparison
- [ ] Add install instructions section
- [ ] Add component gallery showing phlexed-powered AI output examples
- [ ] Add link to GitHub repo

## Phase 6: Polish (Lower Priority)

- [ ] Write comprehensive README.md with install instructions, usage, and screenshots
- [ ] Add CHANGELOG.md
- [ ] Add LICENSE (MIT)
- [ ] Test full flow from fresh clone to working skill system

## Completed

- [x] Project initialization
- [x] Design doc created and approved

## Notes

- Study `~/.claude/skills/gstack/` for how real skills are structured (SKILL.md format, bin scripts, preambles)
- The design doc is at ~/.gstack/projects/phlexed/troy-unknown-design-20260410-120216.md
- PhlexyUI docs: https://phlexyui.com/
- shadcn_phlexcomponents: https://github.com/sean-yeoh/shadcn_phlexcomponents
- Primary audience: solo AI-assisted Rails developers using Claude Code
- Component registry is the core innovation — everything depends on it being accurate

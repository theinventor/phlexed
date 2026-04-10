# Phlexed Fix Plan

## Phase 1: Foundation (High Priority)

- [ ] Create monorepo directory structure (skill/, sample/, site/)
- [ ] Build `skill/bin/phlexed-detect` — shell script that reads Gemfile.lock and identifies installed Phlex component library (phlexy_ui, shadcn_phlexcomponents, protos, ruby_ui, or custom)
- [ ] Build `skill/adapters/phlexy_ui.rb` — Ruby script that scans PhlexyUI gem source, extracts component classes, props, variants, and generates registry JSON
- [ ] Build `skill/adapters/shadcn_phlexcomponents.rb` — same for shadcn_phlexcomponents
- [ ] Build `skill/adapters/generic.rb` — fallback adapter that scans app/views/components/ and app/components/ for any Phlex::HTML subclass
- [ ] Build `skill/bin/phlexed-registry` — shell script that orchestrates detection + adapter to produce .phlexed/registry.json
- [ ] Test detect + registry against sample Rails app

## Phase 2: Skills (High Priority)

- [ ] Write `skill/SKILL.md` — root skill definition (phlexed-setup workflow: detect library, build registry, append CLAUDE.md rules)
- [ ] Write `skill/templates/claude-md-rules.md` — CLAUDE.md routing rules template
- [ ] Write `skill/templates/component-patterns/phlexy-ui.md` — prompt patterns teaching Claude how to use PhlexyUI components correctly
- [ ] Write `skill/templates/component-patterns/shadcn-phlexcomponents.md` — same for shadcn_phlexcomponents
- [ ] Write `skill/phlexed-build/SKILL.md` — page/feature generation skill (loads registry, plans layout, generates Phlex views)
- [ ] Write `skill/phlexed-component/SKILL.md` — component creation skill (reads patterns, generates component + tests, rebuilds registry)
- [ ] Test skills end-to-end: run /phlexed-setup in sample app, then /phlexed-build to generate a page

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

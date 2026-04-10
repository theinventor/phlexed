# Phlexed — Agent Build Instructions

## Project Overview

Phlexed is an AI skill system for Phlex UI development in Rails. It's a monorepo containing:
- `skill/` — Claude Code skills (the main product)
- `sample/` — Minimal Rails 8 app for testing
- `site/` — phlexed.com landing page
- `setup` — Installer script

## Tech Stack

- **Skills:** Bash scripts (bin/), Ruby scripts (adapters/), Markdown (SKILL.md files)
- **Sample app:** Rails 8, Ruby 3.3+, PhlexyUI, Tailwind CSS
- **Website:** Static HTML/CSS/JS (or simple Rails app)

## Prerequisites

```bash
ruby --version    # 3.3+
rails --version   # 8.0+
bundle --version  # Bundler 2+
```

## Project Setup

```bash
# From repo root — nothing to install at the top level.
# The skill system is plain Bash/Ruby scripts with no dependencies.

# For the sample Rails app:
cd sample
bundle install
bin/rails db:create db:migrate
```

## Running Tests

```bash
# Test phlexed-detect (from repo root)
cd sample && ../skill/bin/phlexed-detect

# Test phlexed-registry (from sample app)
cd sample && ../skill/bin/phlexed-registry --adapter phlexy_ui

# Test the full setup flow
cd sample && claude --skill ../skill/SKILL.md  # or install globally first
```

## Build Commands

```bash
# No build step needed for skills (they're interpreted scripts)

# Sample Rails app
cd sample && bin/rails server

# Website
cd site && open index.html  # or whatever serves it
```

## Key Learnings

- Study `~/.claude/skills/gstack/` for real Claude Code skill patterns
- PhlexyUI components live in the gem's lib directory (find via `bundle show phlexy_ui`)
- Phlex components inherit from Phlex::HTML
- Registry JSON must be valid and complete for skills to produce good output
- SKILL.md files use YAML frontmatter + Markdown with embedded bash

## Skill Reference

The best reference for how Claude Code skills work is the gstack skill system
at `~/.claude/skills/gstack/`. Key patterns to study:

- `~/.claude/skills/gstack/office-hours/SKILL.md` — complex multi-phase skill
- `~/.claude/skills/gstack/investigate/SKILL.md` — skill with bash preamble
- `~/.claude/skills/gstack/bin/` — helper scripts called from skills

## Feature Completion Checklist

Before marking ANY feature as complete:

- [ ] Feature works as described in the design doc
- [ ] Tested against sample Rails app (where applicable)
- [ ] Bin scripts are executable (`chmod +x`)
- [ ] Changes committed with conventional commit messages
- [ ] fix_plan.md updated

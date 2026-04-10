# Phlexed — Ralph Development Instructions

## Context

You are Ralph, an autonomous AI development agent building **phlexed**: an AI skill
system for Phlex UI development in Rails. Phlexed makes AI coding assistants (Claude Code)
produce consistent, component-based Phlex output by providing skills, prompt templates,
CLAUDE.md routing rules, and a component registry.

**This is a monorepo.** Everything lives here: the skill system itself, a sample Rails app
for testing, the phlexed.com website, and the installer.

## Design Document

The full design doc is at: `~/.gstack/projects/phlexed/troy-unknown-design-20260410-120216.md`

Read it FIRST before doing anything. It contains the complete architecture, skill workflows,
registry schema, and technical decisions. Everything you build must match that document.

## Current Objectives

1. Study .ralph/fix_plan.md for current priorities
2. Read the design doc (path above) for architecture context
3. Implement the highest priority item
4. Test against the sample Rails app
5. Update fix_plan.md and AGENT.md with learnings
6. Commit working changes with descriptive messages

## Monorepo Structure

Build this directory layout:

```
phlexed/
  README.md                           # Project README with install instructions
  setup                               # Global installer script (executable)
  CHANGELOG.md                        # Version history

  # The skill system (this is what gets installed to ~/.claude/skills/phlexed/)
  skill/
    SKILL.md                          # Root skill definition (entry point)
    phlexed-build/SKILL.md            # Page/feature generation skill
    phlexed-component/SKILL.md        # Component creation skill
    bin/
      phlexed-detect                  # Detect which component library is installed
      phlexed-registry                # Build/query the component registry
    templates/
      claude-md-rules.md              # CLAUDE.md routing rules template
      component-patterns/             # Per-library prompt patterns
        phlexy-ui.md                  # PhlexyUI adapter prompt patterns
        shadcn-phlexcomponents.md     # shadcn_phlexcomponents adapter patterns
    adapters/
      phlexy_ui.rb                    # Registry builder for PhlexyUI
      shadcn_phlexcomponents.rb       # Registry builder for shadcn_phlexcomponents
      generic.rb                      # Fallback: scans app/ for any Phlex class

  # Sample Rails app for testing
  sample/
    Gemfile
    ...                               # Minimal Rails 8 app with PhlexyUI installed

  # Website (phlexed.com)
  site/
    ...                               # Landing page, docs, before/after demos

  # Ralph infrastructure
  .ralph/
    PROMPT.md                         # This file
    fix_plan.md                       # Task list
    AGENT.md                          # Build instructions
    specs/                            # Detailed specs
```

## Key Technical Details

### Component Registry

The registry is a JSON file (`.phlexed/registry.json`) that gets generated per-project.
It indexes every available Phlex component so Claude knows what's available:

```json
{
  "library": "phlexy_ui",
  "version": "0.1.0",
  "generated_at": "2026-04-10T12:00:00Z",
  "components": [
    {
      "name": "Button",
      "class": "PhlexyUI::Button",
      "props": ["variant", "size", "disabled"],
      "variants": ["primary", "secondary", "outline", "ghost"],
      "sizes": ["sm", "md", "lg"],
      "example": "render PhlexyUI::Button.new(variant: :primary) { 'Click me' }"
    }
  ],
  "patterns": {
    "layout": ["Card", "Container", "Grid"],
    "forms": ["Input", "Select", "Checkbox"],
    "feedback": ["Alert", "Toast", "Badge"],
    "navigation": ["Navbar", "Sidebar", "Tabs"]
  }
}
```

### How Registry Building Works

1. `phlexed-detect` reads `Gemfile.lock` for known gem names
2. `phlexed-registry` calls `bundle show <gem>` to find the gem's install path
3. The Ruby adapter walks the gem's component directory and parses each Phlex class:
   - Class name and inheritance chain
   - `initialize` keyword arguments (props)
   - Variants/slots via static source analysis (regex or Ripper AST for known macro
     patterns like `variant`, `renders_one`, `renders_many`)
   - Example usage from docs or test fixtures
4. Output goes to `.phlexed/registry.json`

**Staleness detection:** Check `Gemfile.lock` mtime vs `registry.json` mtime.

### Adapter System

Each supported library gets an adapter (Ruby script in `adapters/`). The adapter knows
the library's internal structure. For v1, build adapters for:
- PhlexyUI (DaisyUI-based)
- shadcn_phlexcomponents (Tailwind-native)
- generic.rb (fallback: scans `app/views/components/` and `app/components/` for any
  class inheriting from `Phlex::HTML`)

### Skill Definitions

Skills are Claude Code SKILL.md files. Study gstack's skill format at
`~/.claude/skills/gstack/` for reference. Each skill has:
- YAML frontmatter (name, description)
- Preamble bash (setup checks)
- Workflow steps
- AskUserQuestion for decisions
- Status reporting

### Installer (`setup` script)

The `setup` script at the repo root:
1. Symlinks or copies `skill/` to `~/.claude/skills/phlexed/`
2. Verifies Ruby is available
3. Prints confirmation with next steps

### Sample Rails App

A minimal Rails 8 app in `sample/` with:
- PhlexyUI installed (or shadcn_phlexcomponents, pick the better one)
- A few example pages built with Phlex components
- Used to test that phlexed-detect, phlexed-registry, and the skills work correctly

### Website

A simple landing page for phlexed.com in `site/`:
- Hero: before/after showing AI-generated Phlex output
- Install instructions
- Component gallery showing what phlexed-powered AI produces
- Can be a static site (HTML/CSS/JS) or a simple Rails app

## Key Principles

- ONE task per loop. Focus on the most important thing.
- Search the codebase before assuming something isn't implemented
- Use subagents for expensive operations (file searching, analysis)
- Write tests for new functionality (keep testing to ~20% of effort)
- Update .ralph/fix_plan.md after each task
- Commit working changes with descriptive messages
- Study `~/.claude/skills/gstack/` for how real Claude Code skills are structured

## When In Doubt: Read the Design Doc

If you're unsure about ANY architectural decision, naming convention, file layout,
workflow step, or implementation detail: **read the design doc first.**

```
~/.gstack/projects/phlexed/troy-unknown-design-20260410-120216.md
```

This document is the single source of truth. It covers the component registry schema,
how adapters work, what each skill does, how staleness detection works, what the
CLAUDE.md routing rules look like, and more. If the answer isn't in fix_plan.md or
AGENT.md, it's almost certainly in the design doc.

## Protected Files (DO NOT MODIFY)

- .ralph/ (entire directory and all contents)
- .ralphrc (project configuration)

## Status Reporting (CRITICAL)

At the end of your response, ALWAYS include:

```
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
TASKS_COMPLETED_THIS_LOOP: <number>
FILES_MODIFIED: <number>
TESTS_STATUS: PASSING | FAILING | NOT_RUN
WORK_TYPE: IMPLEMENTATION | TESTING | DOCUMENTATION | REFACTORING
EXIT_SIGNAL: false | true
RECOMMENDATION: <one line summary of what to do next>
---END_RALPH_STATUS---
```

Set EXIT_SIGNAL to true only when ALL fix_plan.md items are done, tests pass, and
all requirements from the design doc are implemented.

## Current Task

Follow .ralph/fix_plan.md and choose the most important item to implement next.

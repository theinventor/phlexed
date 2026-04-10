---
name: phlexed-setup
version: 0.2.0
description: |
  Configure phlexed for a Rails project. Detects the installed Phlex component library
  (PhlexyUI, shadcn_phlexcomponents, or custom), builds a merged component registry at
  .phlexed/registry.json combining library + local components with source tags and
  name-conflict flags, builds a style registry at .phlexed/style-registry.json from
  DaisyUI/Tailwind config, and appends routing rules to CLAUDE.md so Claude Code picks
  the right phlexed sub-skill for UI work. If the project uses Cursor (`.cursor/` or
  existing `.cursorrules`), offers to render a Cursor-aware .cursorrules file too.
  Surfaces library/local component name conflicts in the final report. Run once per
  project. Re-run to refresh after upgrading the component library or changing themes.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - AskUserQuestion
---

# /phlexed-setup

The entry point for phlexed. Makes Claude Code aware of your project's Phlex component
library so every "build me a page" prompt produces correct, component-based output
instead of inline Tailwind.

## Preamble (run first)

```bash
set -e
SKILL_DIR="$(cd "$(dirname "$0")" && pwd 2>/dev/null || echo ~/.claude/skills/phlexed)"
PHLEXED_HOME="${PHLEXED_HOME:-$HOME/.claude/skills/phlexed}"
export PATH="$PHLEXED_HOME/bin:$PATH"

echo "PHLEXED_HOME: $PHLEXED_HOME"

# Are we in a Rails project?
if [ -f "Gemfile.lock" ]; then
  echo "HAS_GEMFILE: yes"
else
  echo "HAS_GEMFILE: no"
fi

# Is phlex itself installed?
if [ -f "Gemfile.lock" ] && grep -q '^\s*phlex\s' Gemfile.lock 2>/dev/null; then
  echo "HAS_PHLEX: yes"
else
  echo "HAS_PHLEX: no"
fi

# Detect the component library
if [ -f "Gemfile.lock" ] && [ -x "$PHLEXED_HOME/bin/phlexed-detect" ]; then
  DETECTED=$("$PHLEXED_HOME/bin/phlexed-detect" Gemfile.lock 2>/dev/null || echo "none")
else
  DETECTED="none"
fi
echo "DETECTED_LIBRARY: $DETECTED"

# Does a registry already exist?
if [ -f ".phlexed/registry.json" ]; then
  echo "HAS_REGISTRY: yes"
  # Check staleness
  if "$PHLEXED_HOME/bin/phlexed-registry" --check 2>&1 | grep -q "STATUS: stale"; then
    echo "REGISTRY_STALE: yes"
  else
    echo "REGISTRY_STALE: no"
  fi
else
  echo "HAS_REGISTRY: no"
  echo "REGISTRY_STALE: no"
fi

# Does a style registry already exist?
if [ -f ".phlexed/style-registry.json" ]; then
  echo "HAS_STYLE_REGISTRY: yes"
else
  echo "HAS_STYLE_REGISTRY: no"
fi

# Is there a package.json? (needed for phlexed-style-scan)
if [ -f "package.json" ]; then
  echo "HAS_PACKAGE_JSON: yes"
else
  echo "HAS_PACKAGE_JSON: no"
fi

# Does CLAUDE.md already have phlexed routing?
if [ -f "CLAUDE.md" ] && grep -q "phlexed skill routing" CLAUDE.md 2>/dev/null; then
  echo "HAS_ROUTING: yes"
else
  echo "HAS_ROUTING: no"
fi

# Is .phlexed/ in .gitignore?
if [ -f ".gitignore" ] && grep -qE "^\.phlexed/?$" .gitignore 2>/dev/null; then
  echo "IN_GITIGNORE: yes"
else
  echo "IN_GITIGNORE: no"
fi

# Does this project use Cursor? If either .cursor/ dir exists or an existing
# .cursorrules file is present, we'll offer to render a phlexed-aware
# .cursorrules section at the end of setup (v0.2 feature).
if [ -d ".cursor" ] || [ -f ".cursorrules" ]; then
  echo "HAS_CURSOR: yes"
else
  echo "HAS_CURSOR: no"
fi
```

## Workflow

### Step 1: Verify we're in a Rails project

If `HAS_GEMFILE` is `no`: stop with `STATUS: BLOCKED`. Tell the user:

> phlexed needs a Rails project. Run `/phlexed-setup` from the root of a Rails app
> that has a `Gemfile.lock`.

If `HAS_PHLEX` is `no`: stop with `STATUS: BLOCKED`. Tell the user:

> Phlex isn't installed. Add `gem "phlex-rails"` to your Gemfile and run `bundle install`
> before running `/phlexed-setup`. Then pick a component library: PhlexyUI
> (https://phlexyui.com) or shadcn_phlexcomponents
> (https://github.com/sean-yeoh/shadcn_phlexcomponents). Or skip the library and
> phlexed will scan your existing Phlex classes with the generic adapter.

### Step 2: Handle re-runs

If `HAS_REGISTRY` is `yes`:
- If `REGISTRY_STALE` is `no`: Ask via AskUserQuestion — "phlexed is already set up.
  Registry is fresh. Rebuild anyway?"
  - A) Yes, rebuild both registries (useful after a gem upgrade or theme change)
  - B) No, skip — setup is current
  - C) Just re-inject CLAUDE.md rules
  - D) Just refresh the style registry (after editing tailwind.config.js)
- If `REGISTRY_STALE` is `yes`: Announce that Gemfile.lock is newer than
  .phlexed/registry.json and proceed to rebuild both registries automatically
  (no question).

If D is chosen: skip to Step 4b, run only `phlexed-style-scan`, then Step 7 report.
Do not re-build the component registry and do not touch CLAUDE.md. Step 8
(Cursor rules offer) is still eligible since the style registry change may
affect the rendered cursorrules styling section.

### Step 3: Handle no-library detection

If `DETECTED_LIBRARY` is `none`: AskUserQuestion —

> No known Phlex component library (phlexy_ui, shadcn_phlexcomponents, protos, ruby_ui)
> was found in Gemfile.lock. How do you want to proceed?

Options:
- A) Install PhlexyUI (DaisyUI-based, recommended for most projects)
- B) Install shadcn_phlexcomponents (Tailwind-native)
- C) Use the generic adapter to scan existing Phlex classes in `app/components/`
- D) Cancel setup

If A: print the install snippet for PhlexyUI and stop (the user needs to run bundle
install before re-running setup):

```ruby
# In Gemfile:
gem "phlexy_ui"
```

Then: `bundle install && /phlexed-setup`

If B: same pattern for `gem "shadcn_phlexcomponents"`.

If C: set `ADAPTER=generic` and continue.

If D: stop with `STATUS: BLOCKED`.

### Step 4: Build the component registry

Run the registry builder. If the user chose generic in Step 3, force the adapter:

```bash
if [ "$DETECTED_LIBRARY" = "none" ] || [ "$DETECTED_LIBRARY" = "custom" ]; then
  "$PHLEXED_HOME/bin/phlexed-registry" --adapter generic
else
  "$PHLEXED_HOME/bin/phlexed-registry"
fi
```

Verify `.phlexed/registry.json` was produced. If not, report the error from the
adapter and stop with `STATUS: BLOCKED`.

Read the first 40 lines of `.phlexed/registry.json` to confirm the library and
component count. Report the summary to the user: library name, version, component count.

### Step 4b: Build the style registry

Run the style scanner. This reads `package.json` for DaisyUI/Tailwind version and
`tailwind.config.js` for themes, custom theme definitions, and theme extensions. The
output is `.phlexed/style-registry.json` — the source of truth for
`/phlexed-theme`, and the file that `/phlexed-build` and `/phlexed-retrofit` consult
for styling anti-patterns.

```bash
"$PHLEXED_HOME/bin/phlexed-style-scan"
```

The scanner has three possible outcomes, all non-fatal:

1. **DaisyUI detected** → full style registry with themes, CSS variables, component
   vocabulary, and 9 anti-patterns. Report the active theme name and theme count.
2. **Raw Tailwind (no DaisyUI)** → minimal style registry with generic Tailwind
   anti-patterns. Report that theme switching is degraded.
3. **No design system detected** (no `package.json`, no tailwind config, or neither
   dep installed) → degraded-mode registry with 3 generic rules. `/phlexed-theme`
   will warn when invoked. Report this to the user but do NOT block setup.

If `HAS_PACKAGE_JSON` is `no`, still run `phlexed-style-scan` — it will produce the
degraded-mode registry correctly and the user gets a clear signal.

Verify `.phlexed/style-registry.json` was produced. If not (script crashed), report
the error but continue — the component registry alone is still useful.

### Step 5: Append CLAUDE.md routing rules

If `HAS_ROUTING` is `no`:

1. If `CLAUDE.md` does not exist, create it with a top-level heading:
   ```markdown
   # Project Instructions
   ```
2. Append the contents of `$PHLEXED_HOME/templates/claude-md-rules.md` to `CLAUDE.md`.
3. Report: "Appended phlexed routing rules to CLAUDE.md"

If `HAS_ROUTING` is `yes`: skip this step. If the user chose "re-inject CLAUDE.md rules"
in Step 2, remove the existing `## phlexed skill routing` section and re-append fresh.

### Step 6: Add .phlexed/ to .gitignore

If `IN_GITIGNORE` is `no`:

```bash
if [ ! -f .gitignore ]; then touch .gitignore; fi
# Only append if not already present
if ! grep -qE "^\.phlexed/?$" .gitignore; then
  echo "" >> .gitignore
  echo "# phlexed component registry (regenerated per project)" >> .gitignore
  echo ".phlexed/" >> .gitignore
fi
```

### Step 7: Report success

First, read the merged registry to surface any component counts and name
conflicts. These fields come from the v0.2 merge step in `phlexed-registry`
which runs both the library adapter AND the generic adapter and tags each
component with `source: "library"` or `source: "local"`:

```bash
ruby -rjson -e '
r = JSON.parse(File.read(".phlexed/registry.json"))
comps = r["components"] || []
lib = comps.count { |c| c["source"] != "local" }
loc = comps.count { |c| c["source"] == "local" }
meta = r["local_components"] || {}
conflicts = meta["conflicts"] || 0
puts "LIBRARY_COUNT: #{lib}"
puts "LOCAL_COUNT: #{loc}"
puts "CONFLICT_COUNT: #{conflicts}"
# List conflicting local components by name + file for the user to see.
comps.select { |c| c["conflict"] }.each do |c|
  puts "CONFLICT: #{c["name"]} at #{c["file"]}"
end
' 2>/dev/null
```

Then print a concise summary. Adjust the style registry line based on what
Step 4b produced, and include the local-components breakdown whenever there
are any local components:

```
phlexed is ready.

Library:        <library-name> <version>
Components:     <total> registered (<LIBRARY_COUNT> library + <LOCAL_COUNT> local)
Registry:       .phlexed/registry.json

Design system:  <daisyui|tailwind|none> <version>
Themes:         <count> available (active: <name>)
Style registry: .phlexed/style-registry.json

Routing:        added to CLAUDE.md

Next steps:
  /phlexed-build      build a page or feature
  /phlexed-component  create a new component
  /phlexed-retrofit   convert ERB/HAML views to Phlex
  /phlexed-theme      switch themes or restyle

Re-run /phlexed-setup after upgrading your component gem or tailwind.config.js
to refresh both registries.
```

**If `CONFLICT_COUNT > 0`**, add a clearly-formatted warning block above the
"Next steps" section listing every conflicting local component:

```
⚠ Name conflicts detected

<CONFLICT_COUNT> local component(s) share a short name with a library
component. The library version wins in the registry, so your local version
will be ignored by /phlexed-build until you rename it:

  - Card  (app/components/card.rb conflicts with PhlexyUI::Card)
  - Modal (app/components/modal.rb conflicts with PhlexyUI::Modal)

Rename each file + class and re-run /phlexed-setup to refresh the registry.
```

**If `LOCAL_COUNT == 0`**, omit the "(N library + N local)" parenthetical
from the Components line — show just "Components: N registered" as in v0.1.
This keeps the output terse for the common library-only case.

If the style registry is in degraded mode (`design_system: none`), surface that
explicitly so the user isn't surprised when `/phlexed-theme` refuses to switch
themes:

```
Design system:  none detected
Style registry: .phlexed/style-registry.json (degraded mode)

/phlexed-theme theme switching is unavailable until you add DaisyUI or Tailwind
to your package.json.
```

### Step 8: Offer Cursor rules generation (if detected)

If `HAS_CURSOR` is `yes`, this project uses Cursor as a second AI coding
assistant alongside Claude Code. phlexed ships a companion renderer
(`phlexed-render-cursorrules`) that produces a plain-text `.cursorrules` file
at the project root, giving Cursor the same component registry + styling rules
context that we just wrote into CLAUDE.md for Claude Code.

Use `AskUserQuestion` to offer the user three choices:

- **A) Generate .cursorrules now** — run `phlexed-render-cursorrules`. If a
  `.cursorrules` file already exists without phlexed markers, the renderer
  appends the phlexed section at the end, preserving the user's existing
  rules. If the file already has `# phlexed BEGIN` / `# phlexed END` markers
  from a prior run, the renderer replaces just that section.
- **B) Preview first** — run `phlexed-render-cursorrules --check` to print the
  generated output to stdout without writing. Useful if the user wants to see
  what would land before committing to the file change.
- **C) Skip** — leave Cursor rules for another time. The renderer can always
  be run manually later via:
  `ruby "$PHLEXED_HOME/bin/phlexed-render-cursorrules"`

Run the chosen command from the project root. If A or B, add a line to the
Step 7 report summary:

```
Cursor rules:   .cursorrules generated (<component_count> components)
```

If `HAS_CURSOR` is `no`, skip this step entirely — no prompt, no mention in
the report. The renderer is still available for users who install Cursor
later; they can run it manually.

Report status: `DONE`.

## Troubleshooting

- **"bundle show <gem> failed"**: the component gem is in Gemfile.lock but not installed.
  Run `bundle install` and retry.
- **"Registry shows 0 components"**: the adapter regexes didn't match the gem's source.
  Check that the gem version is supported (PhlexyUI ≥ 0.1, shadcn_phlexcomponents ≥ 0.3).
  Re-run with `--adapter generic` to fall back to scanning your own `app/components/`.
- **"CLAUDE.md routing already exists"**: phlexed-setup has been run before. Re-run
  with option C in Step 2 to refresh just the routing rules.

## Voice

Direct, concrete, no filler. Name the file, the command, the outcome. If something
fails, say what failed and what to try next.

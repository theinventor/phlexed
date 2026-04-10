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

# Are there existing ERB/HAML/Slim templates that could be retrofitted?
if [ -d "app/views" ]; then
  EXISTING_TEMPLATES=$(find app/views -type f \( -name '*.erb' -o -name '*.haml' -o -name '*.slim' \) 2>/dev/null | wc -l | tr -d ' ')
  echo "EXISTING_TEMPLATES: $EXISTING_TEMPLATES"
else
  echo "EXISTING_TEMPLATES: 0"
fi

# What's already in app/views and app/components? (for the "existing views" question)
if [ -d "app/views" ] || [ -d "app/components" ]; then
  echo "HAS_VIEW_CODE: yes"
else
  echo "HAS_VIEW_CODE: no"
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

**Operating principle: phlexed is the doer, not the instructor.** Never tell the
user "go do X then re-run." Always offer to do X yourself via `AskUserQuestion`.
Every option presented to the user must be an action this skill will take, not
homework for them. If something is genuinely blocked (no internet, no write
access), say so plainly — but never use a blocked status to mean "user, please
go do this."

### Step 1: Verify we're in a Rails project

If `HAS_GEMFILE` is `no`: this isn't a Rails project (or we're in the wrong
directory). Use `AskUserQuestion`:

> I don't see a `Gemfile.lock` in this directory, so this isn't a Rails
> project root. What would you like to do?

Options:
- A) I'm in the wrong directory — cancel so I can cd somewhere else
- B) Create a fresh Rails app here (I'll run `rails new . --skip-bundle` then continue)
- C) Cancel

If A or C: stop cleanly with `STATUS: DONE`. No blocking message, no homework.
If B: run `rails new . --force --skip-bundle`, then continue the workflow as if
HAS_GEMFILE was yes.

### Step 1.5: Phlex installation (the load-bearing UX moment)

If `HAS_PHLEX` is `no`: this is a Rails project that hasn't adopted Phlex yet.
This is the most important UX moment in the whole skill — phlexed has to be a
partner who takes action, not a clerk handing out forms.

Use `AskUserQuestion` with these options:

> I don't see Phlex installed in this project yet. Phlexed works best when Phlex
> is the view layer, but the right path depends on what you've already built.
> {{If EXISTING_TEMPLATES > 0:}} I notice you have {{EXISTING_TEMPLATES}}
> ERB/HAML/Slim templates in `app/views/` — those could be migrated to Phlex,
> or you could use Phlex only for new code going forward. {{end}}
> What would you like me to do?

Options (the exact set depends on `EXISTING_TEMPLATES`):

**If `EXISTING_TEMPLATES > 0` (existing app):**
- A) Install phlex-rails + phlexy_ui, then audit my existing views and recommend
  whether to retrofit them to Phlex (recommended)
- B) Install phlex-rails + phlexy_ui, leave my existing views alone, use Phlex
  for new code only
- C) Install phlex-rails + shadcn_phlexcomponents instead (Tailwind-native)
- D) Install phlex-rails only — I'll bring my own component library later
- E) Cancel

**If `EXISTING_TEMPLATES == 0` (greenfield or all-Phlex project):**
- A) Install phlex-rails + phlexy_ui (DaisyUI-based, recommended for most projects)
- B) Install phlex-rails + shadcn_phlexcomponents (Tailwind-native)
- C) Install phlex-rails only — I'll bring my own component library later
- D) Cancel

**Execute the choice (no homework, no re-run instructions):**

For option A (existing app, retrofit path):
1. Run `bundle add phlex-rails phlexy_ui` (this updates the Gemfile and runs `bundle install`)
2. Continue with the rest of setup — detect, build registry, build style registry, append CLAUDE.md rules
3. After Step 7 (success report), invoke `/phlexed-retrofit` as a sub-skill so the user lands directly in the audit + recommendation flow. The retrofit skill will analyze the existing views and tell the user whether they look like good migration candidates or whether using phlexed for new code is the better play.

For option B (existing app, install only):
1. Run `bundle add phlex-rails phlexy_ui`
2. Continue with the rest of setup
3. In the Step 7 report, mention the existing templates and tell the user that
   they can run `/phlexed-retrofit` later if they change their mind

For option C (existing app, shadcn):
1. Run `bundle add phlex-rails shadcn_phlexcomponents`
2. Continue with the rest of setup

For option D (existing app, phlex-only):
1. Run `bundle add phlex-rails`
2. Continue with the rest of setup. The generic adapter will scan whatever
   custom Phlex components exist (or none, in which case the registry is empty
   and that's fine).

For options A/B/C/D in the greenfield case: same as their existing-app counterparts
minus the retrofit recommendation in option A.

For option Cancel/E: stop cleanly with `STATUS: DONE`.

**If `bundle add` fails** (e.g. dependency conflict, network issue): surface the
exact error verbatim, then `AskUserQuestion`:

> `bundle add` failed: {{stderr}}. What do you want me to do?

Options:
- A) Roll back the Gemfile change and try a different library
- B) Show me the conflicting gem versions in `Gemfile.lock` so I can debug
- C) Try `bundle update` first (in case the lockfile is just stale)
- D) Cancel — I'll fix it myself

For A: revert the Gemfile change, return to the Step 1.5 question with the
chosen library removed from the options.
For B: print the relevant section of `Gemfile.lock` and any conflict messages.
For C: run `bundle update --conservative <gem>` and retry the original add.
For D: roll back the Gemfile change and stop cleanly.

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

This step only fires when `HAS_PHLEX` is `yes` but no known Phlex component
library was found in `Gemfile.lock`. (If `HAS_PHLEX` was `no`, Step 1.5
already handled the install + library choice.)

If `DETECTED_LIBRARY` is `none`: `AskUserQuestion` —

> Phlex is installed but no known component library (phlexy_ui,
> shadcn_phlexcomponents, protos, ruby_ui) is in your Gemfile.lock. How do you
> want me to proceed?

Options:
- A) Install PhlexyUI (DaisyUI-based, recommended for most projects)
- B) Install shadcn_phlexcomponents (Tailwind-native)
- C) Skip the library — scan my existing Phlex classes in `app/components/`
  with the generic adapter
- D) Cancel

**Execute the choice — never just print install snippets and stop:**

For option A: run `bundle add phlexy_ui`, then continue to Step 4 with
`DETECTED_LIBRARY=phlexy_ui`.

For option B: run `bundle add shadcn_phlexcomponents`, then continue to Step 4
with `DETECTED_LIBRARY=shadcn_phlexcomponents`.

For option C: set `ADAPTER=generic` and continue.

For option D: stop cleanly with `STATUS: DONE`.

**If `bundle add` fails** (dependency conflict, network issue): surface the exact
error, offer to roll back the Gemfile change, and ask whether to retry, switch
libraries, or cancel. Never just leave the user with "fix and re-run."

### Step 4: Build the component registry

Run the registry builder. If the user chose generic in Step 3, force the adapter:

```bash
if [ "$DETECTED_LIBRARY" = "none" ] || [ "$DETECTED_LIBRARY" = "custom" ]; then
  "$PHLEXED_HOME/bin/phlexed-registry" --adapter generic
else
  "$PHLEXED_HOME/bin/phlexed-registry"
fi
```

Verify `.phlexed/registry.json` was produced. If not, the adapter crashed —
surface the error verbatim and use `AskUserQuestion`:

> The {{library}} adapter failed to build the registry. Here's the error:
> {{stderr}}. What do you want me to do?

Options: A) Try the generic adapter against `app/components/` instead,
B) Show me the gem source so I can debug, C) Cancel.

Read the first 40 lines of `.phlexed/registry.json` to confirm the library and
component count. Report the summary: library name, version, component count.

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

phlexed will auto-refresh both registries when you upgrade your component gem
or change tailwind.config.js — no manual re-run needed. Just invoke any phlexed
skill and it'll detect the staleness and rebuild on the fly.
```

**If `CONFLICT_COUNT > 0`**, surface the conflicts and offer to fix them.
Add a warning block above the "Next steps" section, then immediately use
`AskUserQuestion`:

```
⚠ Name conflicts detected

<CONFLICT_COUNT> local component(s) share a short name with a library
component. The library version wins in the registry, so your local version
will be ignored by /phlexed-build:

  - Card  (app/components/card.rb conflicts with PhlexyUI::Card)
  - Modal (app/components/modal.rb conflicts with PhlexyUI::Modal)
```

> I can rename your conflicting local components so they coexist with the
> library versions. What would you like me to do?

Options:
- A) Rename them all with a project prefix (e.g. `Card` → `MyApp::Card`,
  updates the file, the class, and every render call across the app)
- B) Let me pick which to rename and which to keep as-is
- C) Leave them — I'll deal with the conflicts later
- D) Show me each conflicting file before deciding

For A: rewrite each conflicting file (rename class, move under a namespace),
grep for `render Card.new(` etc. across the app and update every call site,
then re-run `phlexed-registry` to refresh the registry. Show the diff.

For B: ask per-component, then apply the same rename logic to the chosen ones.

For C: leave the warning visible and continue. Note in the report that the
local versions won't be used until renamed.

For D: print the file contents for each conflicting file, then loop back to
this question.

**If `LOCAL_COUNT == 0`**, omit the "(N library + N local)" parenthetical
from the Components line — show just "Components: N registered" as in v0.1.
This keeps the output terse for the common library-only case.

If the style registry is in degraded mode (`design_system: none`), surface that
explicitly AND offer to fix it via `AskUserQuestion`:

```
Design system:  none detected
Style registry: .phlexed/style-registry.json (degraded mode)
```

> No DaisyUI or Tailwind found in `package.json`, so theme switching with
> `/phlexed-theme` won't work yet. What should I do?

Options:
- A) Install Tailwind CSS + DaisyUI now (recommended for full styling support)
- B) Install Tailwind CSS only (skip DaisyUI)
- C) Leave it — I'll add a design system later

For A: run `bundle add tailwindcss-rails` (if not present) then
`npm install -D tailwindcss daisyui` (or `yarn add -D` based on
which lockfile exists), generate `tailwind.config.js` if missing, then
re-run `phlexed-style-scan` to refresh the style registry. Print the diff.

For B: same flow without daisyui in the npm install.

For C: leave the warning visible and continue. The user can re-run
`/phlexed-setup` later after they install a design system.

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

## Failure handling

When something fails, the skill takes action — it doesn't hand the user a
worksheet. For each known failure mode, the right pattern is:

1. Detect the failure
2. Tell the user what happened in one sentence
3. Offer 2-4 concrete recovery actions via `AskUserQuestion` where the options
   are things this skill will do
4. Execute the choice

- **"bundle show <gem> failed"**: the component gem is in Gemfile.lock but not
  installed (probably because the user pulled changes without running
  `bundle install`). Don't tell them to run it — just run `bundle install`
  and retry. Only ask if it fails twice.

- **"Registry shows 0 components"**: the adapter regexes didn't match the gem's
  source. Most likely the gem version is unsupported. Use `AskUserQuestion`:
  > The {{library}} adapter ran but found 0 components. The installed version
  > may be outside the supported range. What should I do?
  Options: A) Try the generic adapter against `app/components/` instead,
  B) Show me the first few files in the gem so I can debug, C) Cancel.

- **"CLAUDE.md routing already exists"**: not actually a failure — phlexed has
  been run here before. The Step 2 re-run handler covers this. If somehow we
  reach Step 5 with existing routing, just refresh it in place rather than
  duplicating.

## Voice

Direct, concrete, no filler. Name the file, the command, the outcome. If
something fails, say what failed and offer to fix it — never hand the user
homework. The phrase "go do X then re-run" is banned.

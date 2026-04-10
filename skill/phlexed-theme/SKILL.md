---
name: phlexed-theme
version: 0.1.0
description: |
  Change how the project looks without wrecking the design system. Four modes:
  switch to a built-in theme, generate a custom theme from a color description,
  restyle components using the library's prop DSL (never raw classes), and
  audit the project for styling anti-patterns. Loads .phlexed/style-registry.json
  and .phlexed/registry.json so Claude knows the design system vocabulary and
  component surface. Use when the user says "dark mode," "switch theme," "change
  the primary color to indigo," "make it feel more modern," or "restyle this page."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /phlexed-theme

The styling engine. Everything this skill does goes through the design system —
no inline styles, no hardcoded colors, no reinvented CSS. If the user wants
something the design system can't express, the skill extends the theme config
instead of patching around it.

## Preamble (run first)

```bash
set -e
PHLEXED_HOME="${PHLEXED_HOME:-$HOME/.claude/skills/phlexed}"
export PATH="$PHLEXED_HOME/bin:$PATH"

# Rails project check
if [ -f "Gemfile.lock" ]; then
  echo "HAS_GEMFILE: yes"
else
  echo "HAS_GEMFILE: no"
fi

# Style registry (the main input for this skill)
if [ -f ".phlexed/style-registry.json" ]; then
  echo "HAS_STYLE_REGISTRY: yes"
  DESIGN_SYSTEM=$(ruby -rjson -e 'puts JSON.parse(File.read(".phlexed/style-registry.json"))["design_system"]' 2>/dev/null || echo "unknown")
  DS_VERSION=$(ruby -rjson -e 'puts JSON.parse(File.read(".phlexed/style-registry.json"))["version"] || "-"' 2>/dev/null || echo "-")
  ACTIVE_THEME=$(ruby -rjson -e 'puts((JSON.parse(File.read(".phlexed/style-registry.json"))["themes"] || {})["active"] || "-")' 2>/dev/null || echo "-")
  THEME_COUNT=$(ruby -rjson -e 'arr = (JSON.parse(File.read(".phlexed/style-registry.json"))["themes"] || {})["available"] || []; puts arr.size' 2>/dev/null || echo "0")
  echo "DESIGN_SYSTEM: $DESIGN_SYSTEM"
  echo "DS_VERSION: $DS_VERSION"
  echo "ACTIVE_THEME: $ACTIVE_THEME"
  echo "THEME_COUNT: $THEME_COUNT"
else
  echo "HAS_STYLE_REGISTRY: no"
  echo "DESIGN_SYSTEM: unknown"
fi

# Component registry (used when restyling or mapping props)
if [ -f ".phlexed/registry.json" ]; then
  echo "HAS_REGISTRY: yes"
  LIBRARY=$(ruby -rjson -e 'puts JSON.parse(File.read(".phlexed/registry.json"))["library"]' 2>/dev/null || echo "unknown")
  echo "LIBRARY: $LIBRARY"
else
  echo "HAS_REGISTRY: no"
  echo "LIBRARY: none"
fi

# Tailwind config file (needed for theme switching and custom theme injection)
TAILWIND_CONFIG=""
for name in tailwind.config.js tailwind.config.ts tailwind.config.cjs tailwind.config.mjs; do
  if [ -f "$name" ]; then
    TAILWIND_CONFIG="$name"
    break
  fi
done
echo "TAILWIND_CONFIG: ${TAILWIND_CONFIG:-none}"

# Layout file (where data-theme lives)
LAYOUT_FILE=""
for candidate in app/views/layouts/application.html.erb \
                 app/views/layouts/application.html.haml \
                 app/views/layouts/application.html.slim \
                 app/views/layouts/application_layout.rb; do
  if [ -f "$candidate" ]; then
    LAYOUT_FILE="$candidate"
    break
  fi
done
echo "LAYOUT_FILE: ${LAYOUT_FILE:-none}"

# Git cleanliness — theme changes should start from a clean base
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    echo "GIT_CLEAN: yes"
  else
    echo "GIT_CLEAN: no"
  fi
else
  echo "GIT_CLEAN: unknown"
fi
```

## Workflow

### Step 0: Verify prerequisites

**If `HAS_GEMFILE` is `no`:** stop with `STATUS: BLOCKED`. Tell the user to run
from a Rails project root.

**If `HAS_STYLE_REGISTRY` is `no`:** stop with `STATUS: BLOCKED`. Tell the user:

> phlexed-theme needs a style registry. Run `/phlexed-setup` first to scan your
> `tailwind.config.js` and `package.json` and build `.phlexed/style-registry.json`.

**If `DESIGN_SYSTEM` is `none`:** warn but don't block — the user may still want
to restyle via the component registry even without DaisyUI.

> Heads up: no DaisyUI or Tailwind detected in package.json. Theme switching
> will not work, but component restyling via `/phlexed-theme restyle` might
> still help. Continue?

If user declines, stop.

### Step 1: Understand what the user wants

Parse the user's request into one of four modes:

- **switch** — "dark mode," "use the cupcake theme," "switch to synthwave"
- **custom** — "make the primary color indigo," "generate a brand theme with
  orange accents," "create a dark theme based on navy"
- **restyle** — "restyle the dashboard to feel more modern," "make the buttons
  rounder," "change the card style across the app"
- **audit** — "check for styling anti-patterns," "find hardcoded colors,"
  "audit the CSS"

If the request is ambiguous, use AskUserQuestion:

> What kind of theme change do you want to make?

Options:
- A) Switch to a built-in theme (I'll show you what's available)
- B) Create a custom theme (describe the colors you want)
- C) Restyle specific components or pages (change feel without changing theme)
- D) Audit the project for styling anti-patterns

### Step 2: Load the registries

Read `.phlexed/style-registry.json` fully. Note:
- `design_system` — daisyui | tailwind | none
- `themes.available`, `themes.active`, `themes.dark_theme`, `themes.custom_themes`
- `css_variables` — the semantic color token map
- `component_classes` — the vocabulary (btn, card, alert, etc.)
- `anti_patterns` — rules that apply to every mode

Read `.phlexed/registry.json` if HAS_REGISTRY is yes. Note components that accept
a `variant:` prop (those are the ones you'll manipulate in restyle mode).

## Mode: SWITCH

Switch the active theme to one of the built-in or registered custom themes.

### Step S1: Pick the target theme

If the user named a theme ("use cupcake"), verify it's in `themes.available`. If
not, tell the user which themes ARE available and ask them to pick.

If the user said "dark mode" and `themes.dark_theme` is set, use that. If not,
pick the first theme named `dark` or containing `dark` in its name.

If the request is vague, AskUserQuestion with the full list of `themes.available`
as options (cap at 10 for readability).

### Step S2: Update the layout file

Edit `LAYOUT_FILE` to set `data-theme="<target>"` on the root `<html>` element.

- ERB: `<html data-theme="dark">`
- HAML: `%html{ "data-theme" => "dark" }`
- Slim: `html data-theme="dark"`
- Phlex: `html(data: { theme: "dark" })`

If `data-theme` is already present, replace the value. If missing, add it. Do not
touch anything else in the layout — this is a surgical edit.

### Step S3: Ensure the theme is enabled in tailwind.config.js

Read `TAILWIND_CONFIG`. Look for the `daisyui.themes: [...]` array. If the target
theme is not in the list, add it. Use the balanced-bracket awareness — the themes
array can contain custom theme objects, so string insertion must go at the end of
the array before the closing `]`.

If the target is a built-in DaisyUI theme, a single string literal is enough:
`"synthwave"`. If it's a custom theme, the user should already have defined it;
if not, bail with `STATUS: DONE_WITH_CONCERNS` and tell them to run
`/phlexed-theme` in custom mode first.

### Step S4: Rebuild the style registry

Theme state changed. Rerun the style scanner so `.phlexed/style-registry.json`
reflects the new active theme:

```bash
"$PHLEXED_HOME/bin/phlexed-style-scan"
```

### Step S5: Report

```
Theme switched: <previous> → <new>

Updated:
  app/views/layouts/application.html.erb (data-theme attribute)
  tailwind.config.js (daisyui.themes array, if needed)
  .phlexed/style-registry.json (refreshed)

Verify in the browser:
  bin/rails s
  open http://localhost:3000

To switch back: /phlexed-theme switch <previous>
```

Report status: `DONE`.

## Mode: CUSTOM

Create a custom DaisyUI theme from a color description, or modify an existing one.

### Step C1: Gather the color intent

From the user's request, extract:
- **Base tone** — "dark," "light," or explicit base color
- **Primary color** — the key accent (indigo, orange, emerald, etc.)
- **Optional overrides** — secondary, accent, success/warning/error tones
- **Theme name** — what to call it (default: derive from primary color, e.g.
  `brand-indigo`)

If any of these are missing, AskUserQuestion to fill gaps. Do not guess a
corporate-looking palette when the user asked for something specific.

### Step C2: Map the intent to OKLCH values

DaisyUI themes use OKLCH color space. For each color prop, convert the user's
stated hex/name to OKLCH. Use approximations from a known palette:

- indigo → `oklch(54% 0.22 260)`
- orange → `oklch(70% 0.19 50)`
- emerald → `oklch(68% 0.17 160)`
- red → `oklch(60% 0.24 25)`
- navy → `oklch(30% 0.08 260)`
- slate → `oklch(55% 0.03 260)`

If the user gave a hex value, use it directly — DaisyUI accepts hex for theme
definitions even though it normalizes internally.

### Step C3: Write the theme to tailwind.config.js

Edit `TAILWIND_CONFIG` to add the new theme object to the `daisyui.themes` array:

```js
daisyui: {
  themes: [
    "light",
    "dark",
    {
      "brand-indigo": {
        "primary":          "#4F46E5",
        "primary-content":  "#FFFFFF",
        "secondary":        "#F59E0B",
        "secondary-content":"#1F2937",
        "accent":           "#10B981",
        "neutral":          "#1F2937",
        "base-100":         "#FFFFFF",
        "info":             "#3B82F6",
        "success":          "#10B981",
        "warning":          "#F59E0B",
        "error":            "#EF4444"
      }
    }
  ]
}
```

Always emit all 11 semantic keys — DaisyUI will throw missing-key warnings
otherwise. Derive `*-content` colors from the base (black on light bases,
white on dark bases).

### Step C4: Offer to activate

AskUserQuestion:

> Theme `<name>` created in tailwind.config.js. Activate it now?

Options:
- A) Yes, switch to `<name>` (updates layout + rebuilds style registry)
- B) No, just create it — I'll activate later with `/phlexed-theme switch <name>`

If A: run Step S2 (update layout) and S4 (rebuild style registry).

### Step C5: Report

```
Custom theme created: <name>

Colors:
  primary:   <hex>  (<description>)
  secondary: <hex>
  accent:    <hex>

Updated:
  tailwind.config.js (added to daisyui.themes)
  {layout file}      (if activated)
  .phlexed/style-registry.json (refreshed)

Preview it:
  bin/rails s && open http://localhost:3000

To tweak: re-run /phlexed-theme custom <name> and describe the changes.
```

Report status: `DONE`.

## Mode: RESTYLE

Restyle specific components or pages without changing the theme. The goal here is
to adjust component props — `variant:`, `size:`, `bordered:`, etc. — to shift the
feel without rewriting the design system.

### Step R1: Determine the scope

What is the user restyling?
- **A single page** — read that view class, identify all component renders
- **A component type across the app** — grep for all uses of `PhlexyUI::Button`
- **An entire feature** — combine the above

AskUserQuestion if scope is ambiguous:

> Which parts of the app should I restyle?

Options:
- A) A specific page (point me to the file)
- B) A specific component type across the whole app
- C) A whole feature / section
- D) Just show me what my styling looks like first

### Step R2: Load the current usage

Read every view class that will be affected. For each `render Component.new(...)`
call, note the current props.

Cross-reference against the component registry to see which props are available
but unused (e.g., `Card` with no `bordered:` set, `Button` defaulting to `:md`).

### Step R3: Plan the changes

Before editing anything, show the user the planned changes:

```
Restyle plan for app/views/dashboard/index_view.rb:

  Card:   bordered: false → true (adds visible boundary)
  Button: variant: :primary → :primary    (no change)
          size: :md → :lg                 (larger CTAs)
  Stack:  gap: 2 → 6                      (more breathing room)

6 components across 1 file.
```

AskUserQuestion to confirm:

> Apply these changes?

Options:
- A) Yes, apply all
- B) Let me pick which to apply
- C) Show me a different direction (go back to Step R1)
- D) Cancel

### Step R4: Apply the changes

For each approved change, edit the view class. Rules:
- Only touch component prop values — never touch children or structure
- Use full namespace (`PhlexyUI::Button`, not `Button`)
- Use the library's variant vocabulary — check the registry for valid variant
  names before setting them
- If the user wanted a visual change that has no corresponding prop (e.g.,
  "make buttons rounder"), stop and suggest either (a) creating a new component
  with `/phlexed-component`, or (b) extending the theme config with a new
  border-radius utility. Do NOT inline a class string as a workaround.

### Step R5: Commit atomically

Stage only the files you touched. Commit with a descriptive message:

```bash
git add <specific files>
git commit -m "restyle: <what changed> in <scope>"
```

Example: `restyle: bordered cards + lg buttons in dashboard`

### Step R6: Report

```
Restyled <count> files.

Changes:
  app/views/dashboard/index_view.rb (3 components updated)
  app/views/dashboard/settings_view.rb (2 components updated)

Verify in the browser:
  bin/rails s && open http://localhost:3000/dashboard

To roll back: git revert HEAD
```

Report status: `DONE`.

## Mode: AUDIT

Scan the project for styling anti-patterns and report them. Does not modify any
files — this is a read-only diagnostic.

### Step A1: Load anti-patterns from the style registry

Read the `anti_patterns` array from `.phlexed/style-registry.json`. These are the
rules to check.

### Step A2: Scan the view layer

For each file in `app/views/**/*.rb`, `app/views/**/*.erb`, `app/views/**/*.haml`,
`app/views/**/*.slim`, `app/components/**/*.rb`, check for:

1. **Inline `style=""` attributes** — grep for `style=`
2. **Hardcoded hex colors** — grep for `#[0-9a-fA-F]{3,8}\b` in class/style contexts
3. **Raw Tailwind color utilities** — grep for `bg-(red|blue|green|yellow|purple|pink|indigo|gray|slate)-\d+` or `text-<same>`
4. **Inline btn-like classes when PhlexyUI::Button exists** — grep for
   `class.*btn\b` inside `div(...)` or raw HTML tags
5. **Custom CSS files created recently** — list files under
   `app/assets/stylesheets/` or `app/assets/css/`

### Step A3: Scan the stylesheets

For any custom CSS under `app/assets/stylesheets/`, grep for:
1. Hardcoded hex colors (should use `oklch(var(--p))` instead)
2. Custom media queries for responsive behavior (should use Tailwind `sm:/md:/lg:`)
3. `.btn { ... }` overrides (should extend tailwind.config.js instead)

### Step A4: Cross-check against registered components

For every class that a view inlines (e.g., `class="card card-bordered"`), check
if the component exists in `.phlexed/registry.json`. If it does, flag the inline
usage as "should use the component instead."

### Step A5: Report

```
Styling audit for this project:

  ✓ 0 inline style="" attributes
  ✗ 3 hardcoded hex colors
      app/views/home/index.html.erb:14: "#FF6600"
      app/views/shared/_nav.html.erb:22: "#F5F5F5"
      app/assets/stylesheets/custom.css:8: "#1F2937"
  ✗ 2 raw Tailwind color utilities
      app/views/dashboard/index_view.rb:34: bg-blue-500
      app/views/dashboard/index_view.rb:41: text-gray-600
  ✗ 1 btn class inlined when PhlexyUI::Button exists
      app/views/home/index_view.rb:18: button(class: "btn btn-primary")
  ✓ 0 custom CSS files with responsive media queries

Total: 6 issues found, 2 clean.

Next steps:
  - Run /phlexed-theme restyle to fix the inlined component classes
  - Replace hex colors with CSS variables (oklch(var(--p)) etc.)
  - Replace raw Tailwind color utilities with semantic classes (bg-primary, text-base-content)
```

Never auto-fix in audit mode — the report is the deliverable. Users can follow
up with explicit `/phlexed-theme restyle` calls.

Report status: `DONE`.

## Invariants

- **Never inline `style=""` attributes on any element — ever.** Use components,
  props, or Tailwind utilities.
- **Never hardcode hex/rgb/hsl colors in view code.** Use CSS variables or semantic
  class names.
- **Never add custom CSS files when the design system can handle it.** If a new
  color is needed, add it to `theme.extend.colors` in `tailwind.config.js`. If a
  new component variant is needed, add it to `register_modifiers` in a new Phlex
  class via `/phlexed-component`.
- **Never edit `.phlexed/style-registry.json` directly.** Always rebuild via
  `phlexed-style-scan`.
- **Always rebuild the style registry after theme or config changes.** Stale
  registries teach Claude the wrong vocabulary.
- **In audit mode, never auto-fix.** The audit produces a report, not changes.
- **Data-theme goes on `<html>`, never individual elements.** Section-scoped
  theming is an anti-pattern unless the user explicitly asks for it.

## Voice

Direct, concrete, color-literate. Name the theme, the file, the hex value, the
CSS variable. Show the user what changed — diffs and counts, not vague "styled
some things." When the user wants something the design system can't express,
tell them the two proper paths (extend the theme, or create a new component) and
pick one — don't inline workarounds.

## Troubleshooting

- **"Theme switched but the page still looks old":** browser cache or asset
  compilation. Run `bin/rails assets:precompile` and hard-refresh.
- **"Custom theme isn't showing up":** check `daisyui.themes` in
  `tailwind.config.js` — the theme name must be there for DaisyUI to generate
  its CSS. Then recompile assets.
- **"Restyle changed the prop but the component looks the same":** the prop may
  be aliased in the library's adapter. Check `bundle show phlexy_ui` →
  `lib/phlexy_ui/<component>.rb` for the actual `register_modifiers` mapping.
- **"Audit flagged something that's actually fine":** the audit uses regex
  heuristics. False positives are expected for dynamic class strings. Use
  `# phlexed:ignore` on the same line to suppress (v2 feature — for now,
  document the exception).
- **"I want a feel that has no existing DaisyUI theme":** generate a custom
  theme via mode CUSTOM, then iterate on the OKLCH values. Don't inline CSS.

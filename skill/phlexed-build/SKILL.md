---
name: phlexed-build
version: 0.2.0
description: |
  Generate a Rails page or feature using the project's registered Phlex components.
  Loads .phlexed/registry.json (merged library + local components with source tags
  as of v0.2), plans a component composition that prefers library over local for
  shared patterns, writes Phlex view classes, and wires the controller. Surfaces
  conflict warnings when the user's prompt targets a component name shared between
  library and local registries. Use when the user says "build me a settings page,"
  "add a dashboard," "make a profile screen," or any UI request that should produce
  Phlex output instead of inline Tailwind.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /phlexed-build

Generate a page or feature composed from the project's registered Phlex components.
The registry is the source of truth: every element you output must either come from
a registered component, or be created first via `/phlexed-component`.

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

# Registry check
if [ -f ".phlexed/registry.json" ]; then
  echo "HAS_REGISTRY: yes"
  LIBRARY=$(ruby -rjson -e 'puts JSON.parse(File.read(".phlexed/registry.json"))["library"]' 2>/dev/null || echo "unknown")
  COUNT=$(ruby -rjson -e 'puts JSON.parse(File.read(".phlexed/registry.json"))["component_count"]' 2>/dev/null || echo "0")
  echo "LIBRARY: $LIBRARY"
  echo "COMPONENT_COUNT: $COUNT"

  # Library vs local breakdown (v0.2 merged registries). For v0.1 registries
  # without source tags, LIBRARY_COUNT == COMPONENT_COUNT and LOCAL_COUNT == 0.
  LIBRARY_COUNT=$(ruby -rjson -e 'r=JSON.parse(File.read(".phlexed/registry.json"));c=r["components"]||[];puts c.count { |x| x["source"]!="local" }' 2>/dev/null || echo "0")
  LOCAL_COUNT=$(ruby -rjson -e 'r=JSON.parse(File.read(".phlexed/registry.json"));c=r["components"]||[];puts c.count { |x| x["source"]=="local" }' 2>/dev/null || echo "0")
  CONFLICT_COUNT=$(ruby -rjson -e 'r=JSON.parse(File.read(".phlexed/registry.json"));m=r["local_components"]||{};puts(m["conflicts"]||0)' 2>/dev/null || echo "0")
  echo "LIBRARY_COUNT: $LIBRARY_COUNT"
  echo "LOCAL_COUNT: $LOCAL_COUNT"
  echo "CONFLICT_COUNT: $CONFLICT_COUNT"

  # Staleness check
  if "$PHLEXED_HOME/bin/phlexed-registry" --check 2>&1 | grep -q "STATUS: stale"; then
    echo "REGISTRY_STALE: yes"
  else
    echo "REGISTRY_STALE: no"
  fi
else
  echo "HAS_REGISTRY: no"
  echo "LIBRARY: none"
  echo "COMPONENT_COUNT: 0"
  echo "LIBRARY_COUNT: 0"
  echo "LOCAL_COUNT: 0"
  echo "CONFLICT_COUNT: 0"
  echo "REGISTRY_STALE: no"
fi

# Style registry (for theme-aware generation)
if [ -f ".phlexed/style-registry.json" ]; then
  echo "HAS_STYLE_REGISTRY: yes"
else
  echo "HAS_STYLE_REGISTRY: no"
fi

# Detect Phlex base class used in this project (Rails 8 convention varies)
if [ -d "app/views" ]; then
  BASE_CLASS=$(grep -rh 'class.*<.*Views::Base\|class.*<.*ApplicationView\|class.*<.*Phlex::HTML' app/views 2>/dev/null | head -1 | sed -E 's/.*<[[:space:]]*//' | sed -E 's/[[:space:]]*$//' | tr -d ' ')
  echo "BASE_CLASS: ${BASE_CLASS:-unknown}"
else
  echo "BASE_CLASS: unknown"
fi

# Is this an existing Phlex-based Rails app?
if [ -d "app/views" ] && find app/views -name '*.rb' | head -1 | grep -q .; then
  echo "PHLEX_VIEWS_EXIST: yes"
else
  echo "PHLEX_VIEWS_EXIST: no"
fi
```

## Workflow

### Step 1: Verify prerequisites

If `HAS_GEMFILE` is `no`: stop with `STATUS: BLOCKED`. Tell the user:

> phlexed-build needs to run from a Rails project root. Change to your Rails app
> directory and try again.

If `HAS_REGISTRY` is `no`: stop with `STATUS: BLOCKED`. Tell the user:

> No `.phlexed/registry.json` found. Run `/phlexed-setup` first to detect your
> Phlex component library and build the registry.

If `REGISTRY_STALE` is `yes`: warn the user but do not block:

> Registry may be out of date (Gemfile.lock is newer than .phlexed/registry.json).
> Re-run `/phlexed-setup` to refresh. Proceeding with the current registry.

### Step 2: Understand the request

Read the user's request carefully. Every "build me a ..." request has three layers:

1. **What page/feature:** dashboard, settings, profile, checkout, pricing, etc.
2. **What content:** stats, forms, tables, cards, buttons, etc.
3. **What behavior:** static, interactive, form submission, real-time, etc.

If the request is vague ("build me a page"), use AskUserQuestion to narrow it:

> What kind of page do you want to build?

Options should be tailored to the user's phrasing. If they said "build me an admin
thing," offer: admin dashboard, user management table, settings panel, audit log.
Never proceed with a vague request — one clarifying question is cheaper than a
wrong generation.

### Step 3: Load the registry

Read `.phlexed/registry.json` fully. Note:

- The library (`phlexy_ui`, `shadcn_phlexcomponents`, or `custom`)
- The full class names (e.g. `PhlexyUI::Button`, not `Button`)
- Each component's props, variants, sizes, and slots
- The `patterns` map — which components fall into `layout`, `forms`, `feedback`, etc.

**Merged registry structure (v0.2).** If the preamble reports `LOCAL_COUNT > 0`,
the registry has been merged across two sources:

- **Library-sourced components** (`source: "library"`): from the installed gem
  (PhlexyUI, shadcn_phlexcomponents). Shared vocabulary that every teammate with
  the same gem gets. Use these as the default for any pattern that has a match.
- **Project-local components** (`source: "local"`): from `app/components/` or
  `app/views/`. Project-specific compositions that encode domain knowledge
  (e.g. `UserAvatar`, `ProductCard`, `Dashboard::StatsGrid`). Prefer these when
  they're semantically specific to the domain the user is building.

**Library-first preference when both exist.** If a library component AND a local
component could plausibly satisfy the same need (e.g. both `PhlexyUI::Card` and
`MyApp::Card` exist for a "card wrapper"), prefer the library version unless the
local version has a more specific prop or slot signature that matches the
request. Library components are the shared vocabulary and more likely to be
theme-aware, accessible, and consistent with other pages. The exception: if the
user's request explicitly names a domain concept that's a local component
(e.g. "use our UserAvatar"), use the local version.

**Conflict handling.** If `CONFLICT_COUNT > 0`, the merge step detected local
components whose short names collide with library components. Read each
component's `conflict` field — any component with `conflict: true` is a local
component shadowing a library one. **Do not use the conflicted local version
automatically.** In the composition plan, name the library version by default.
If the user's prompt explicitly references the conflicted name (e.g. "use our
Card"), stop and AskUserQuestion to confirm which one they meant, and suggest
the user rename the local component to disambiguate going forward.

If a per-library pattern template exists at
`$PHLEXED_HOME/templates/component-patterns/<library>.md`, read it too. It has
canonical examples of idiomatic composition for that library.

### Step 4: Plan the composition

Before writing any code, sketch the component tree. Example for "build me a
settings page":

```
SettingsIndexView (the page)
├── Container (layout) [library: PhlexyUI::Container]
│   ├── PageHeader [library: PhlexyUI::PageHeader]
│   │   ├── title: "Settings"
│   │   └── description
│   ├── Card [library: PhlexyUI::Card] (for each section: Profile, Security, Notifications)
│   │   ├── CardTitle [library: PhlexyUI::CardTitle]
│   │   ├── CardBody [library: PhlexyUI::CardBody]
│   │   │   └── Form fields (Input, Select, Toggle) [library]
│   │   └── CardActions [library: PhlexyUI::CardActions]
│   │       └── Button (variant: :primary) [library: PhlexyUI::Button] { "Save" }
│   └── NotificationPreferences [local: app/components/notification_preferences.rb]
```

Annotate each node with `[library: <full_class>]` or `[local: <file_path>]` so
the user can see at a glance which components come from the shared library vs.
project-local code. This is v0.2 behavior — it makes the library/local split
visible before any files are written.

For each node in the tree, verify the component exists in the registry. If it
does not, flag it.

**When the registry has both library and local components for the same need:**
apply the library-first preference from Step 3. If in doubt, library wins.
Only deviate when the user's prompt explicitly named a local component or
when the local component has a materially different API (more props, more
slots, domain-specific variants).

**If 1–2 components are missing:** invoke `/phlexed-component` as a sub-skill to
create them first, then continue. Do not inline missing components.

**If 3+ components are missing:** stop and AskUserQuestion. Present the list of
missing components and ask:

> The page I planned needs N components that don't exist in your registry:
> [list]. How do you want to handle this?

Options:
- A) Create them all now (I'll run /phlexed-component for each)
- B) Use a simpler layout that only needs registered components
- C) Let me pick which ones to create vs. simplify
- D) Cancel

### Step 5: Generate the view classes

File layout (Rails 8 + Phlex conventions):

```
app/views/
  <resource>/
    index_view.rb        # or show_view.rb, new_view.rb, etc.
    _partial_view.rb     # reusable partials as Phlex classes
```

For each view class:

1. Inherit from the project's base class (detected in preamble as `BASE_CLASS`).
   Fall back to `Views::Base` if unknown, with a comment noting the assumption.
2. Use the library's full namespace: `render PhlexyUI::Button.new(variant: :primary)`.
3. Pass props idiomatically — use the library's DSL, not raw CSS classes.
4. Block content for children: `render PhlexyUI::Card.new do ... end`.
5. For forms, use the library's form components if registered. If the library has
   no form wrapper, use Rails' `form_with` inside a Phlex block.

**Anti-patterns to avoid:**
- `div(class: "btn btn-primary")` when `PhlexyUI::Button.new(variant: :primary)` exists
- Hardcoded colors (`bg-blue-500`) — use semantic classes (`bg-primary`)
- Inline `style=""` attributes
- Ad-hoc component classes when the library provides them
- Guessing prop names — if a prop isn't in the registry, check the library source
  or ask

### Step 6: Wire the controller

1. If the controller action doesn't exist, create it. Use standard Rails conventions
   (`SettingsController#index`).
2. Render the Phlex view class: `render SettingsIndexView.new(user: @user)`.
3. Keep controller logic minimal — view classes handle all presentation.
4. If a route is missing, add it to `config/routes.rb`.

### Step 7: Verify and report

Run a minimal sanity check:

```bash
bundle exec ruby -Iapp -c app/views/<path>/index_view.rb 2>&1 | tail -5
```

This catches syntax errors without booting Rails. If the user runs a test suite,
run the relevant test file. Do not boot the full Rails server unless the user
asks — that's `/qa`'s job.

Report a concise summary. List components grouped by source (library first,
then local) so the user can see at a glance where each piece came from:

```
Generated <count> files.

  app/views/settings/index_view.rb
  app/views/settings/_profile_card_view.rb
  app/controllers/settings_controller.rb (updated)
  config/routes.rb (added: get "/settings")

Components used:
  library: PhlexyUI::Card, PhlexyUI::Button, PhlexyUI::Input, PhlexyUI::Toggle
  local:   MyApp::NotificationPreferences

Components created: 0

Next steps:
  bin/rails s                 start the server
  open http://localhost:3000/settings
  /phlexed-build "add password change form"  extend this page
```

If ALL components used are from the library (the common case for projects
without local components), omit the `local:` line and print `Components used:
PhlexyUI::Card, ...` as a flat list — keeps the output terse.

**If the user's prompt targeted a conflicted component name** (i.e. one where
`CONFLICT_COUNT > 0` in the preamble AND the user's request referenced that
exact name), include a warning in the report:

```
⚠ You asked for "Card" and this project has both PhlexyUI::Card (library)
and MyApp::Card (local, in app/components/card.rb). I used the library
version. Rename your local MyApp::Card to something more specific (e.g.,
ProfileCard) to avoid this ambiguity going forward.
```

Report status: `DONE`.

## Invariants

- **Every rendered element maps to a registered component or is created via
  `/phlexed-component` before generation continues.** No exceptions, no inline
  "just this once" markup. This is the whole point of phlexed.
- **Full class names always.** `PhlexyUI::Button`, not `Button`. The registry
  lists the full class — use it verbatim.
- **Props, not classes.** If the registry says `variant: :primary` exists, use
  that. Do not bypass with `class: "btn-primary"`.
- **The registry is read-only during a build.** If it needs to change (new
  components), invoke `/phlexed-component`, which rebuilds the registry before
  this skill continues.
- **Library wins by default when both sources have the same name.** If
  `PhlexyUI::Card` and `MyApp::Card` both exist in the registry, default to
  the library version. Only use the local version when the user's prompt
  explicitly named it or when the local version has a materially different
  API. Always surface the ambiguity in the report.
- **Never silently use a `conflict: true` component.** A local component
  flagged with `conflict: true` is shadowing a library component and is
  guaranteed to confuse downstream prompts. Either use the library version
  (default) or AskUserQuestion to confirm the user's intent.

## Voice

Direct, concrete. Name the file, the component, the prop. When you show the plan,
show the tree. When you report results, report files and counts. No filler.

## Troubleshooting

- **"Registry lists a component but its props don't work":** the adapter may have
  missed a prop. Check the gem source at `$(bundle show <gem>)/lib/.../<component>.rb`
  and add the prop manually to the generated code. File an issue on phlexed.
- **"The page renders but looks wrong":** styles are a separate concern. Run
  `/phlexed-theme` to verify the design system is respected, or `/qa` to check
  the actual rendered output.
- **"Tests fail after generation":** the view class probably references an instance
  variable the controller doesn't set. Check the controller action matches the
  view's `initialize` signature.

---
name: phlexed-component
version: 0.2.0
description: |
  Create a new Phlex component that matches the project's existing library conventions.
  Reads 2-3 similar components from the installed library for pattern consistency,
  generates the class file plus a matching test, then incrementally appends the new
  component to .phlexed/registry.json via generic.rb --append so it's immediately
  usable by /phlexed-build. Use when the user says "create a component," "new
  component," "wrap this markup," or when /phlexed-build reports a missing component
  it needs.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /phlexed-component

Create a new Phlex component that feels native to the project's existing library.
The skill reads real components from the installed gem for pattern consistency,
generates the new component plus a test, and incrementally adds it to the
registry (via `generic.rb --append`) so `/phlexed-build` can use it on the
very next run.

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
  echo "LIBRARY: $LIBRARY"
else
  echo "HAS_REGISTRY: no"
  echo "LIBRARY: none"
fi

# Detect test framework (prefer rspec if both exist — most Rails + Phlex projects use it)
if [ -d "spec" ] && find spec -name '*_spec.rb' 2>/dev/null | head -1 | grep -q .; then
  echo "TEST_FRAMEWORK: rspec"
elif [ -d "test" ] && find test -name '*_test.rb' 2>/dev/null | head -1 | grep -q .; then
  echo "TEST_FRAMEWORK: minitest"
elif [ -d "spec" ]; then
  echo "TEST_FRAMEWORK: rspec"
elif [ -d "test" ]; then
  echo "TEST_FRAMEWORK: minitest"
else
  echo "TEST_FRAMEWORK: none"
fi

# Where do existing user-level components live?
COMPONENT_DIR=""
for dir in "app/components" "app/views/components"; do
  if [ -d "$dir" ] && find "$dir" -name '*.rb' 2>/dev/null | head -1 | grep -q .; then
    COMPONENT_DIR="$dir"
    break
  fi
done
# If no components exist yet, pick the Rails 8 + Phlex default
if [ -z "$COMPONENT_DIR" ]; then
  if [ -d "app/components" ]; then
    COMPONENT_DIR="app/components"
  else
    COMPONENT_DIR="app/components"  # will be created
  fi
fi
echo "COMPONENT_DIR: $COMPONENT_DIR"

# Detect the gem path for the installed library (for reading example components)
if [ -f "Gemfile.lock" ] && [ -n "$LIBRARY" ] && [ "$LIBRARY" != "custom" ] && [ "$LIBRARY" != "none" ] && [ "$LIBRARY" != "unknown" ]; then
  GEM_PATH=$(bundle show "$LIBRARY" 2>/dev/null || echo "")
  if [ -n "$GEM_PATH" ] && [ -d "$GEM_PATH" ]; then
    echo "GEM_PATH: $GEM_PATH"
  else
    echo "GEM_PATH: unavailable"
  fi
else
  echo "GEM_PATH: none"
fi

# Base class to inherit from
if [ "$LIBRARY" = "phlexy_ui" ]; then
  echo "BASE_CLASS: PhlexyUI::Base"
elif [ "$LIBRARY" = "shadcn_phlexcomponents" ]; then
  echo "BASE_CLASS: ShadcnPhlexcomponents::Base"
else
  # Try to detect the project's own base
  if [ -f "app/views/base.rb" ]; then
    echo "BASE_CLASS: Views::Base"
  elif [ -f "app/components/application_component.rb" ]; then
    echo "BASE_CLASS: ApplicationComponent"
  else
    echo "BASE_CLASS: Phlex::HTML"
  fi
fi

# Was this invoked as a sub-skill from phlexed-build?
if [ -n "${PHLEXED_BUILD_CALLING:-}" ]; then
  echo "INVOKED_BY: phlexed-build"
else
  echo "INVOKED_BY: user"
fi
```

## Workflow

### Step 1: Verify prerequisites

If `HAS_GEMFILE` is `no`: stop with `STATUS: BLOCKED`. Tell the user to run from a
Rails project root.

If `HAS_REGISTRY` is `no`: stop with `STATUS: BLOCKED`. Tell the user:

> No `.phlexed/registry.json` found. Run `/phlexed-setup` first so the new component
> can be added to the registry and picked up by `/phlexed-build`.

### Step 2: Understand the component request

Four things must be clear before generating anything:

1. **Name** — singular, PascalCase (e.g. `Toast`, `EmptyState`, `AvatarGroup`).
2. **Shape** — leaf component or container (does it yield to a block)?
3. **Props** — what initializer kwargs does it need? (e.g. `variant:`, `title:`, `closable:`)
4. **Variants/sizes** — does it have visual variants like `primary/success/error`?

If the user request is specific ("create a Toast component with variant primary/success/warning/error
and an auto-dismiss timeout"), skip the questions. If vague ("I need a toast"), use
AskUserQuestion:

> A Toast component — what should it support?

Options:
- A) Simple: title + message + dismiss button, no variants
- B) Variants: success / warning / error / info with matching colors
- C) Variants + auto-dismiss timer prop
- D) Let me describe it in detail

Do not over-engineer. One clarifying question, then commit to the design.

### Step 3: Find pattern exemplars from the library

This is the step that makes the generated component feel native instead of generic.

If `GEM_PATH` is a valid directory, read 2-3 components from the gem source that
are structurally similar to the one being created. Use the registry's `patterns`
map to find siblings:

- Creating a **feedback** component (Toast, Banner, Snackbar)? Read the existing
  feedback exemplars from the registry (`Alert`, `Badge`), then read their
  source files: `$GEM_PATH/lib/phlexy_ui/alert.rb`, etc.
- Creating a **layout** component? Read `Card.rb`, `Stack.rb`.
- Creating an **actions** component? Read `Button.rb`, `Dropdown.rb`.
- Creating a **forms** component? Read `Input.rb`, `Select.rb`.

From each exemplar, extract:
- The inheritance chain (always `< Base` for PhlexyUI)
- The `initialize` signature style (splat + kwargs? kwargs only?)
- The `view_template` pattern (direct HTML vs. `generate_classes!` helper)
- How modifiers are registered (`register_modifiers(...)` for PhlexyUI,
  `class_variants(...)` for shadcn)
- How blocks are yielded to children
- Whether the library has a preferred element tag via `as:` kwarg

If `GEM_PATH` is `none` or `unavailable` (generic adapter, custom project): read
2-3 existing components from `COMPONENT_DIR` instead. Match whatever patterns the
project already uses.

If there are zero existing components to read (brand new project): use a minimal
`Phlex::HTML` template and note this to the user.

### Step 4: Generate the component class

Write the new component to `<COMPONENT_DIR>/<snake_case_name>.rb`. The file must:

1. Match the exemplars' style exactly. Same inheritance, same `initialize` shape,
   same modifier DSL, same `view_template` structure.
2. Use the full library namespace for any child components it renders internally
   (e.g. a Toast that contains a Button must render `PhlexyUI::Button`, not
   `Button`).
3. Use the library's prop-to-class mapping, never raw CSS. If creating a variant
   system, register it the same way the library does (`register_modifiers(...)`
   for PhlexyUI, `class_variants(...)` for shadcn, plain hash lookup otherwise).
4. Inherit from `BASE_CLASS` (detected in preamble).
5. Be namespaced to match the project's convention. If exemplars live in
   `PhlexyUI::` namespace but the new component is user-level, put it in the
   project's own namespace (or top-level) — do not monkey-patch the gem.

**Concrete PhlexyUI example** (a new Toast component):

```ruby
# app/components/toast.rb
class Toast < PhlexyUI::Base
  def initialize(*base_modifiers, variant: :info, dismissible: true, **)
    super(*base_modifiers, **)
    @variant = variant
    @dismissible = dismissible
  end

  def view_template(&)
    generate_classes!(
      component_html_class: "alert",
      modifiers_map: modifiers,
      base_modifiers: [@variant, *base_modifiers],
      options:
    ).then do |classes|
      div(class: classes, role: "alert", **options) do
        yield_content(&)
        if @dismissible
          render PhlexyUI::Button.new(variant: :ghost, size: :sm) { "✕" }
        end
      end
    end
  end

  private

  register_modifiers(
    info: "alert-info",
    success: "alert-success",
    warning: "alert-warning",
    error: "alert-error"
  )
end
```

Note: `alert` is a DaisyUI class that PhlexyUI uses — the new Toast piggybacks on
the same DaisyUI styles as `PhlexyUI::Alert`. This is the correct pattern. Do not
invent new CSS.

### Step 5: Generate the test

If `TEST_FRAMEWORK` is `none`: skip this step and note it in the final report.

If `TEST_FRAMEWORK` is `rspec`:

Write `spec/components/<snake_case_name>_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Toast, type: :view do
  it "renders with default variant" do
    output = render_inline(Toast.new) { "hello" }
    expect(output).to include("alert-info")
    expect(output).to include("hello")
  end

  it "applies the variant modifier" do
    output = render_inline(Toast.new(variant: :success)) { "done" }
    expect(output).to include("alert-success")
  end

  it "hides the dismiss button when dismissible is false" do
    output = render_inline(Toast.new(dismissible: false)) { "x" }
    expect(output).not_to include("✕")
  end
end
```

If `TEST_FRAMEWORK` is `minitest`:

Write `test/components/<snake_case_name>_test.rb` with equivalent assertions using
`Minitest::Test` and `Phlex::Testing::Rails::ViewHelper`.

Match whatever test helper the project already uses — grep existing specs for
`render_inline`, `rendered`, or `described_class.new` to learn the convention.

### Step 6: Add the new component to the registry

As of v0.2, registries are merged (library + local via `phlexed-registry`) and
new local components can be added incrementally via
`generic.rb --append <file.rb>` without re-scanning every file in the project.
This is the preferred path — it's fast, idempotent, and preserves the existing
library-sourced components untouched.

```bash
ruby "$PHLEXED_HOME/adapters/generic.rb" . --append <COMPONENT_DIR>/<snake_case_name>.rb
```

The append mode:

- Parses the single new Ruby file and tags it with `source: "local"`
- Dedups by file path — safe to re-run if you need to regenerate the class
- Flags the component with `conflict: true` if its short name collides with
  an existing library component (e.g., your new `Card` alongside
  `PhlexyUI::Card`). If a conflict is flagged, **tell the user** in the
  final report so they can rename before the AI gets confused.
- Auto-updates `local_components.count`, `local_components.conflicts`, and
  `has_local_components` in merged v0.2 registries

**When to fall back to a full rebuild instead:**

- The registry file is missing (`.phlexed/registry.json` doesn't exist) —
  append requires an existing registry. Run `/phlexed-setup` first.
- The user has upgraded a library gem and wants the full library re-scanned
  — in that case run the full `phlexed-registry` which calls both the
  library adapter and `generic.rb` and merges them.
- The user deleted a component from disk — append doesn't know about
  removals. Full rebuild cleans up stale entries.

Full rebuild command, if any of those apply:

```bash
"$PHLEXED_HOME/bin/phlexed-registry"
```

Full rebuild takes ~1 second for typical projects and is still fast enough to
run on every component creation if you prefer the simpler model. Append is the
recommended default because it's faster, it preserves exact ordering, and it
never touches library-sourced entries.

### Step 7: Sanity check

Verify the component file parses:

```bash
ruby -c <COMPONENT_DIR>/<snake_case_name>.rb
```

Run the new test file if one was generated:

```bash
# rspec
bundle exec rspec spec/components/<snake_case_name>_spec.rb

# minitest
bundle exec rails test test/components/<snake_case_name>_test.rb
```

If tests fail, do not rebuild the registry (Step 6 already ran — registry is
fine) but do report the failure. The user needs to fix the component before it's
usable.

### Step 8: Report

If `INVOKED_BY` is `phlexed-build`: return a terse, machine-parseable summary so
phlexed-build can continue:

```
COMPONENT_CREATED: Toast
FILE: app/components/toast.rb
TEST: spec/components/toast_spec.rb
REGISTRY_REBUILT: yes
```

If `INVOKED_BY` is `user`: print a richer report:

```
Created Toast component.

  app/components/toast.rb       (class definition)
  spec/components/toast_spec.rb (3 specs)

Registry:    rebuilt (N components, was N-1)
Library:     phlexy_ui
Base class:  PhlexyUI::Base
Variants:    info, success, warning, error
Props:       variant, dismissible

Use it:
  render Toast.new(variant: :success) { "Saved!" }

Or invoke /phlexed-build and reference Toast in your next page request.
```

Report status: `DONE`.

## Invariants

- **Match exemplars exactly.** The whole point of reading gem source is to produce
  output that feels native. Do not improvise a "better" shape — match what exists.
- **Full namespaces inside the class body.** Render child components as
  `PhlexyUI::Button`, never as `Button`, even if the new component is top-level.
- **Register the new component before finishing.** A component that isn't in
  the registry doesn't exist from `/phlexed-build`'s perspective. Always run
  Step 6 — use `generic.rb --append` for speed, fall back to full rebuild only
  if one of the Step 6 fallback conditions applies.
- **Surface conflicts in the report.** If `--append` flags the new component
  with `conflict: true` (its short name collides with a library component),
  tell the user explicitly and suggest a rename. Don't silently produce a
  conflicting component — the AI will get confused on the next `/phlexed-build`.
- **Never monkey-patch the gem.** New components live in the user's Rails app,
  not inside the installed gem's `lib/` directory.
- **One component per invocation.** If the user wants three, run this skill three
  times. Batching creates confused generation — each component gets less attention.

## Voice

Direct, concrete. Name the file, the class, the props. Show the exemplar you're
copying from so the user can verify your pattern choice. No filler.

## Troubleshooting

- **"New component isn't picked up by /phlexed-build":** the append step in
  Step 6 didn't run or silently failed. Re-run it explicitly:
  `ruby "$PHLEXED_HOME/adapters/generic.rb" . --append app/components/<snake_name>.rb`,
  then verify with `grep '"<ComponentName>"' .phlexed/registry.json`.
  If that fails, fall back to a full rebuild: `"$PHLEXED_HOME/bin/phlexed-registry"`.
- **"Tests fail with 'uninitialized constant'":** the test file is missing its
  `require "rails_helper"` or the project uses a different testing convention.
  Check an existing spec file and copy its header exactly.
- **"I wanted variants but got a plain component":** the exemplar you copied from
  didn't use `register_modifiers`. Pick a different exemplar (e.g. `Button`, `Alert`)
  and re-run, or manually add the variant block.

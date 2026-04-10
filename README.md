# phlexed

[![Tests](https://github.com/theinventor/phlexed/actions/workflows/test.yml/badge.svg)](https://github.com/theinventor/phlexed/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> Make Claude Code write beautiful Phlex.

**phlexed** is a Claude Code skill system that makes AI assistants produce
consistent, component-based [Phlex](https://www.phlex.fun/) output in Rails apps.
Drop it into any Rails project and "build me a settings page" stops producing 200
lines of inline Tailwind and starts producing 25 lines of well-composed Phlex
components from your installed library.

- **Website:** [phlexed.com](https://phlexed.com)
- **Repo:** [theinventor/phlexed](https://github.com/theinventor/phlexed)
- **License:** MIT
- **Status:** v0.1 — early but functional. Works with [PhlexyUI](https://phlexyui.com/),
  [shadcn_phlexcomponents](https://github.com/sean-yeoh/shadcn_phlexcomponents),
  and any custom Phlex library.

---

## The problem

AI coding assistants are great at generating Rails code. They're bad at knowing
which components your project already has. Ask Claude Code to "build a settings
page" in a project with PhlexyUI installed and you'll usually get a wall of
inline `<div class="card card-bordered">...` ERB instead of
`render PhlexyUI::Card.new(bordered: true)`.

The components exist. The AI just doesn't know about them.

**phlexed fixes that.** It scans your installed component library, builds a
structured registry, reads your DaisyUI/Tailwind config, and injects routing
rules into `CLAUDE.md` so every prompt that asks for UI automatically runs
through the right skill with the right context.

## Before / after

Prompt: *"build me a settings page with a profile form"*

**Without phlexed** — 40 lines of inline ERB + DaisyUI classes:

```erb
<h1 class="text-3xl font-bold mb-6">Settings</h1>

<div class="card card-bordered bg-base-100 max-w-2xl">
  <div class="card-body">
    <h2 class="card-title">Profile</h2>
    <%= form_with model: @user, url: settings_path, method: :patch do |f| %>
      <div class="form-control">
        <%= f.label :name, class: "label" %>
        <%= f.text_field :name, class: "input input-bordered w-full" %>
      </div>
      <!-- ...repeat for every field... -->
    <% end %>
  </div>
</div>
```

**With phlexed** — 24 lines of composed PhlexyUI components:

```ruby
module Settings
  class IndexView < Views::Base
    def initialize(user:)
      @user = user
    end

    def view_template
      h1(class: "text-3xl font-bold mb-6") { "Settings" }

      render PhlexyUI::Card.new(bordered: true, class: "max-w-2xl") do
        render PhlexyUI::CardTitle.new { "Profile" }
        render PhlexyUI::CardBody.new do
          form_with(model: @user, url: settings_path, method: :patch) do |f|
            render PhlexyUI::FormControl.new(label: "Name")  { f.text_field :name, class: "input input-bordered w-full" }
            render PhlexyUI::FormControl.new(label: "Email") { f.email_field :email, class: "input input-bordered w-full" }
            render PhlexyUI::CardActions.new(justify: :end) do
              render PhlexyUI::Button.new(as: :submit, variant: :primary) { "Save" }
            end
          end
        end
      end
    end
  end
end
```

Same output, fewer lines, theme-switch safe, every piece reusable on the next page.

## Install

**Requirements:** Ruby 3.0+, [Claude Code](https://docs.anthropic.com/en/docs/claude-code),
and a Rails project with [Phlex](https://www.phlex.fun/) installed.

### 1. Install globally (once per machine)

```bash
git clone git@github.com:theinventor/phlexed.git ~/.claude/skills/phlexed
cd ~/.claude/skills/phlexed
./setup
```

The installer defaults to a symlink so `git pull` picks up updates with no
re-install. Pass `--copy` to vendor a snapshot instead. See `./setup --help`
for all modes (`--copy`, `--force`, `--uninstall`, `--check`).

### 2. Configure a project (once per Rails app)

From your Rails project root, open Claude Code and run:

```
/phlexed-setup
```

This:

1. Reads `Gemfile.lock` and detects your Phlex component library
2. Runs the matching adapter to build `.phlexed/registry.json` — a structured
   index of every available component, its props, variants, sizes, and examples
3. Scans `package.json` + `tailwind.config.js` to build `.phlexed/style-registry.json`
   — DaisyUI version, themes, CSS variables, component classes, anti-patterns
4. Appends routing + styling rules to `CLAUDE.md` so every future prompt is aware
5. Adds `.phlexed/` to `.gitignore` (the registries are generated, not committed)

That's it. Your next "build me a ..." prompt uses all of this automatically.

## The five skills

phlexed ships as five slash commands that cover the full Phlex lifecycle:

### `/phlexed-setup` — detect, index, configure

One-time setup per project. Detects your Phlex library from `Gemfile.lock`,
runs the right adapter, builds both registries, and wires up CLAUDE.md. Re-run
to refresh after adding a new gem version, changing Tailwind config, or installing
a new theme. Handles three states: fresh (prompts before rebuild), stale (auto-
rebuilds with announcement), missing (proceeds).

### `/phlexed-build` — generate a page or feature

Your every-day UI skill. Describe what you want ("build me a pricing page"),
and Claude plans the layout using registered components, generates Phlex view
classes, and composes them correctly. If the plan needs a component that isn't
in the registry, the skill auto-invokes `/phlexed-component` as a sub-skill to
create it before resuming. Stops and asks for clarification if 3+ new components
are needed — prevents runaway component creation on over-ambitious requests.

### `/phlexed-component` — create a new component

Creates a new Phlex component that follows your library's conventions exactly.
Reads existing components for pattern consistency, generates the component class
with props and variants, writes tests (RSpec if `spec/` exists, Minitest otherwise),
and rebuilds the registry so it's immediately available to `/phlexed-build`.

### `/phlexed-retrofit` — convert ERB → Phlex autonomously

The migration engine. Four phases:

1. **Audit** — scans `app/views/` for all templates (.erb, .haml, .slim), classifies
   complexity, maps matches against the registry, traces shared-partial dependencies,
   flags anything already Phlex. Writes `.phlexed/retrofit-audit.json`.
2. **Plan** — groups views into 5 batches (shared partials → layouts → simple pages →
   medium → complex), synthesizes new components needed from shared partials, and
   presents a summary. You approve, modify, or cancel.
3. **Generate loop** — writes `.phlexed/retrofit/PROMPT.md`, `fix_plan.md`, and
   `.ralphrc` — a complete Ralph-format conversion plan tailored to your project.
4. **Execute** — fires `ralph -p .phlexed/retrofit/PROMPT.md`. Each iteration
   converts one view, runs tests, commits atomically. If a conversion fails tests,
   it skips and moves on. Stops after 3 consecutive failures (usually a signal of
   non-standard conventions needing human input).

Old templates are renamed to `.pre-phlex` so you can compare before/after and roll
back individual conversions. Cleanup is a final manual pass.

### `/phlexed-theme` — restyle without wrecking the design system

Four modes:

- **Switch** — change to a built-in DaisyUI theme (light, dark, cupcake, corporate,
  synthwave, etc.). Updates `data-theme` on `<html>` and the `tailwind.config.js`
  themes array.
- **Custom** — generate a new DaisyUI theme from a color description ("make it feel
  like GitHub dark"). Writes a full theme object with all 11 required semantic
  keys (primary, secondary, accent, neutral, base-100, info, success, warning, error,
  plus -content colors derived from base lightness).
- **Restyle** — adjust component usage across files (never raw classes, always via
  props). If a visual change has no prop equivalent, the skill presents two proper
  paths: create a new component, or extend the theme config.
- **Audit** — read-only anti-pattern scan for inline styles, hardcoded hex colors,
  raw Tailwind color utilities, and custom CSS files. Produces a report; doesn't fix.

## How it works

```
Rails project
├── Gemfile.lock               ─┐
├── package.json               ─┤ phlexed-setup reads these
├── tailwind.config.js         ─┤ and produces:
│                                │
├── .phlexed/
│   ├── registry.json           ◄── every Phlex component, props, variants
│   └── style-registry.json     ◄── themes, CSS vars, class vocabulary, anti-patterns
│
├── CLAUDE.md                   ◄── routing rules + styling rules injected here
│
└── app/
    └── views/                  ◄── target of /phlexed-build + /phlexed-retrofit
```

The core innovation is the **component registry**. Each supported library has
an adapter (a Ruby script in `skill/adapters/`) that knows the library's internal
structure. During setup, phlexed calls `bundle show <gem>`, finds the gem's install
path, walks its component directory, and parses each Phlex class for its class name,
`initialize` keyword arguments, variants, sizes, and slots via static source analysis
(regex + Ripper AST scanning — no runtime reflection).

The result is a structured JSON index that gets referenced by every skill:

```json
{
  "library": "phlexy_ui",
  "version": "0.1.0",
  "components": [
    {
      "name": "Button",
      "class": "PhlexyUI::Button",
      "props": ["variant", "size", "disabled"],
      "variants": ["primary", "secondary", "outline", "ghost"],
      "sizes": ["sm", "md", "lg"],
      "example": "render PhlexyUI::Button.new(variant: :primary) { 'Click me' }"
    }
  ]
}
```

Skills check staleness on every invocation by comparing `Gemfile.lock` mtime
against `.phlexed/registry.json` mtime. If the lockfile is newer, they warn and
suggest running `/phlexed-setup --refresh`.

## Supported libraries

| Library | Adapter | Detection | Notes |
|---------|---------|-----------|-------|
| [PhlexyUI](https://phlexyui.com/) | `adapters/phlexy_ui.rb` | `phlexy_ui` in Gemfile.lock | Parses `register_modifiers` for variants/sizes, `component_html_class:` for base classes. DaisyUI-based. |
| [shadcn_phlexcomponents](https://github.com/sean-yeoh/shadcn_phlexcomponents) | `adapters/shadcn_phlexcomponents.rb` | `shadcn_phlexcomponents` in Gemfile.lock | Parses `class_variants(variant: {...}, size: {...})` DSL + subcomponent factory methods. Tailwind-native. |
| Custom Phlex components | `adapters/generic.rb` | fallback | Scans `app/views/components/`, `app/components/`, `app/views/layouts/` for any class inheriting from `Phlex::HTML`, `Views::Base`, `ApplicationView`, or `ApplicationComponent`. |

Detection priority order: `phlexy_ui` > `shadcn_phlexcomponents` > `protos` > `ruby_ui` > custom > none.

Adapters are small (~150 lines each), stateless, and easy to add. If your library
isn't listed, the generic adapter almost always works — or open a PR with a new
adapter and a smoke test against the library's source.

## Repo layout

This is a monorepo. Everything lives here:

```
phlexed/
├── README.md                 ◄── you are here
├── setup                     ◄── global installer script
├── skill/                    ◄── the skill system itself (installed to ~/.claude/skills/phlexed/)
│   ├── SKILL.md              ◄── /phlexed-setup entry point
│   ├── phlexed-build/SKILL.md
│   ├── phlexed-component/SKILL.md
│   ├── phlexed-retrofit/SKILL.md
│   ├── phlexed-theme/SKILL.md
│   ├── bin/                  ◄── phlexed-detect, phlexed-registry, phlexed-audit,
│   │                              phlexed-retrofit-plan, phlexed-style-scan
│   ├── adapters/             ◄── phlexy_ui.rb, shadcn_phlexcomponents.rb, generic.rb
│   └── templates/            ◄── CLAUDE.md rules, component patterns, retrofit scaffolds
├── sample/                   ◄── minimal Rails 8 fixture with PhlexyUI + intentional before/after content
└── site/                     ◄── phlexed.com landing page (single-file static HTML)
```

## FAQ

**Does this replace PhlexyUI / shadcn_phlexcomponents / Phlex itself?**
No. phlexed is pure glue — it indexes what's already in your project and makes
Claude Code aware of it. Install any Phlex component library the normal way,
then run `/phlexed-setup`.

**Do I need to commit `.phlexed/`?**
No. The registries are generated from `Gemfile.lock` + your Tailwind config, so
each developer runs `/phlexed-setup` once and their registries live locally.
The setup script adds `.phlexed/` to `.gitignore` automatically.

**What if I'm using a Phlex library you don't support yet?**
The generic adapter scans `app/components/` and `app/views/components/` for any
`Phlex::HTML` subclass and indexes what it finds. It won't know about library-
specific conventions (variants, register_modifiers), but it captures class names,
props, and slots — enough for Claude to use them correctly in generated code.
For proper support, see the adapter contribution guide below.

**Does phlexed index my custom components alongside PhlexyUI?**
Yes. As of v0.2, `phlexed-registry` always runs both the library adapter AND
the generic adapter on every invocation, then merges the results into one
`.phlexed/registry.json` with a `source` field per component (`"library"` or
`"local"`). A project with PhlexyUI plus custom components in `app/components/`
gets both surfaces indexed, so `/phlexed-build` can compose from either. Name
collisions (e.g., your own `Card` vs. `PhlexyUI::Card`) are flagged with
`conflict: true` so you can rename before the AI gets confused. Pass
`--library-only` if you don't want the local scan.

**Does `/phlexed-retrofit` actually work on a real app?**
It's designed to, but v0.1 has only been smoke-tested against the `sample/`
fixture. Test on a branch first. Old templates are preserved as `.pre-phlex`
backups and commits are atomic, so rollback is a `git revert` away.

**How is this different from just putting prompts in CLAUDE.md?**
CLAUDE.md is static. The component registry is a structured index generated
from your actual installed gems — it's always accurate, it always matches the
version you have, and it gets regenerated when your `Gemfile.lock` changes.
phlexed is "CLAUDE.md + a build step that keeps context fresh."

**What about Cursor / Copilot / other AI tools?**
Claude Code is the primary target, but a Cursor `.cursorrules` generator is
available as of v0.2:

```bash
cd my-rails-app
ruby ~/.claude/skills/phlexed/bin/phlexed-render-cursorrules
```

It reads your existing `.phlexed/registry.json` + `.phlexed/style-registry.json`
(produced by `/phlexed-setup`) and writes a `.cursorrules` file at the project
root with the same component surface, design system vocabulary, and anti-patterns
that CLAUDE.md gets. Marker comments preserve any user-authored rules on re-runs.
The registry files are plain JSON, so any AI tool that reads project-level
context can consume them directly.

## Contributing

phlexed is open source (MIT). See [`CONTRIBUTING.md`](CONTRIBUTING.md) for
the full contributor guide, including a 10-step walkthrough for authoring
a new library adapter (using "adding a `protos` adapter" as the worked
example). Quick summary:

- **New adapters.** Add a Ruby file to `skill/adapters/` that returns a registry
  hash. Use `generic.rb` as the starting template.
- **Bug reports.** File an issue with your `Gemfile.lock` excerpt and the output
  of `/phlexed-setup` so we can reproduce.
- **New libraries to detect.** Edit `skill/bin/phlexed-detect` to recognize your
  gem, and add the adapter.

The `sample/` fixture is the primary smoke-test target — a hand-crafted Rails 8
app with PhlexyUI, DaisyUI, a custom theme, and intentional ERB/Phlex mix for
retrofit testing. Run any `skill/bin/*` script against it directly:

```bash
cd sample
ruby ../skill/bin/phlexed-audit --project .
ruby ../skill/bin/phlexed-style-scan --project .
```

**Before sending a PR**, run the regression suites:

```bash
./scripts/test-adapters.sh           # full suite (offline + clones phlexy_ui + shadcn upstream)
./scripts/test-adapters.sh --quick   # offline only (no network — runs against sample/)
./scripts/test-installer.sh          # installer lifecycle against an isolated fake HOME
```

- **`test-adapters.sh`** runs 60 assertions in full mode: 42 offline checks
  (detect, audit, retrofit-plan, style-scan, generic adapter, SKILL.md
  frontmatter validation for all 5 skills) plus 18 online checks that clone
  real `phlexy_ui` and `shadcn_phlexcomponents` sources and verify both
  library adapters produce correct output. Each check references the bug
  number it guards against.
- **`test-installer.sh`** runs 24 assertions covering the full `./setup`
  lifecycle: clean state, symlink install, bin scripts through the install,
  idempotent re-run, `--copy --force`, `--force` symlink restoration,
  `--uninstall`, and argument parsing edge cases. Uses a fake `$HOME` so
  your real `~/.claude/skills/phlexed/` is never touched.

CI (`.github/workflows/test.yml`) runs both suites on every push and PR —
`test-adapters.sh --quick` (skipping network tests to avoid upstream flakiness)
plus the full `test-installer.sh`.

For changes that touch a `SKILL.md` workflow, the automated suites can't
exercise the live Claude Code invocation path. Work through
[`docs/MANUAL_VERIFICATION.md`](docs/MANUAL_VERIFICATION.md) — a
step-by-step checklist for the three end-to-end flows (`/phlexed-setup` +
`/phlexed-build`, `/phlexed-retrofit`, `/phlexed-theme`) with expected
outputs, pass criteria, and failure-capture guidance.

For a one-file snapshot of the project's current state — what's shipped,
what's tested, what's NOT tested, known limitations, and the release
readiness checklist — see [`docs/STATUS.md`](docs/STATUS.md).

## Credits

Built on top of:

- [Phlex](https://www.phlex.fun/) — the component framework
- [PhlexyUI](https://phlexyui.com/) — DaisyUI-based Phlex components
- [shadcn_phlexcomponents](https://github.com/sean-yeoh/shadcn_phlexcomponents) — shadcn-style Phlex components
- [DaisyUI](https://daisyui.com/) + [Tailwind CSS](https://tailwindcss.com/) — the design system layer
- [gstack](https://github.com/garrytan/gstack) — the skill system architecture pattern

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, ship it.

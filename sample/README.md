# Phlexed Sample App

A minimal Rails 8 app that exercises every phlexed skill. This directory is
NOT meant to be a runnable production app — it is a hand-crafted set of fixtures
that phlexed's tooling treats as a real Rails project.

## Purpose

Phlexed's bin scripts and skills need realistic input to exercise their logic.
Instead of generating synthetic fixtures in `/tmp` every time, this directory
lives in git so:

- Tests are reproducible across machines
- Fixtures evolve alongside the skills that read them
- Contributors can see what "a phlexed project" looks like at a glance
- Before/after comparisons (ERB → Phlex) have a stable baseline

## Layout

```
sample/
  Gemfile                        Rails 8 + phlex-rails + phlexy_ui
  Gemfile.lock                   hand-crafted, matches Gemfile versions
  package.json                   daisyui + tailwindcss + typography
  tailwind.config.js             4 built-in themes + 1 custom (phlexed-brand)
  bin/rails                      standard Rails boot stub
  config/
    application.rb               Rails::Application stub
    boot.rb                      bundler + bootsnap
    database.yml                 sqlite config for Rails boot/render commands
    environment.rb               standard Rails boot + initializer entrypoint
    initializers/
      phlexy_ui_runtime_fixture.rb Ruby 3.3 render shim for the PhlexyUI fixture
    routes.rb                    root + dashboard + settings + profile
  app/
    controllers/                 ApplicationController + one per resource
    views/
      layouts/
        application.html.erb     ERB layout (retrofit target)
      shared/
        _top_nav.html.erb        ERB partial (shared — retrofit batch 1)
        _footer.html.erb         ERB partial (shared — retrofit batch 1)
        _flash.html.erb          ERB partial (shared — retrofit batch 1)
      home/
        index.html.erb           Simple ERB view (retrofit batch 3)
      dashboard/
        index.html.erb           Medium ERB view with stats + table (batch 4)
      settings/
        index.html.erb           Medium ERB view with form_with (batch 4)
      profile/
        show_view.rb             **Already-Phlex example** — target state
      base.rb                    Views::Base < Phlex::HTML
```

The mix of ERB and Phlex is intentional. It represents a real app mid-migration:
some views already converted to Phlex (profile/show_view.rb), most still on ERB.
This lets `/phlexed-retrofit` exercise every branch of its audit + plan logic.

## Running phlexed against this sample

From this directory (`sample/`), any phlexed bin script works against the committed
fixtures:

```bash
# Detect the installed component library
../skill/bin/phlexed-detect Gemfile.lock
# → phlexy_ui

# Audit views for retrofit candidates
ruby ../skill/bin/phlexed-audit --project .
# → 7 templates found, 1 already Phlex, 6 convertible

# Build the retrofit plan
ruby ../skill/bin/phlexed-retrofit-plan --project .
# → 4 batches, new components: Flash, Footer, TopNav

# Scan the design system
ruby ../skill/bin/phlexed-style-scan --project .
# → daisyui 4.12.10, 5 themes (active: phlexed-brand)
```

`phlexed-registry` needs `bundle show phlexy_ui` to resolve the real gem path,
which requires `bundle install` to actually succeed. Running the full
component registry build end-to-end is therefore the one test that depends on
having a working Ruby + Bundler toolchain with the phlexy_ui gem available.
The rendered profile page uses `config/initializers/phlexy_ui_runtime_fixture.rb`
to replace the PhlexyUI component autoloads that Ruby 3.3 cannot parse with
small local components matching the sample's Card/Button usage. The rest of the
skills work against static files in this directory.

## What each skill tests against

| Skill                | What it reads here                                  |
|----------------------|------------------------------------------------------|
| `/phlexed-setup`     | Gemfile.lock + package.json + tailwind.config.js    |
| `/phlexed-build`     | .phlexed/registry.json (after setup)                 |
| `/phlexed-component` | .phlexed/registry.json + app/views/base.rb (exemplar)|
| `/phlexed-retrofit`  | app/views/**/*.erb (6 convertible templates)         |
| `/phlexed-theme`     | .phlexed/style-registry.json (after setup)           |

## Before/after comparison

The dramatic before/after that justifies phlexed's existence:

- **Before:** `app/views/settings/index.html.erb` (60+ lines of inline classes,
  repeated DaisyUI strings, raw Rails form helpers with pasted class names)
- **After:** `app/views/profile/show_view.rb` (20 lines, all composition from
  registered PhlexyUI components, no class strings, full namespaces)

Both do similar things — render a user profile in a card. One is 3x longer and
breaks the moment you switch themes. The other composes primitives and survives
any design system change.

## Updating the sample

When phlexed skills evolve, the sample may need new fixtures to exercise new
branches. Keep the skills and the sample in sync by:

1. Adding a new edge case to the sample (new template engine, new DaisyUI theme
   config syntax, new Phlex pattern)
2. Running the relevant bin scripts against the updated sample
3. Committing the sample changes alongside the skill changes in one PR

Never commit `.phlexed/registry.json` or `.phlexed/style-registry.json` — those
are generated and live in `.gitignore`.

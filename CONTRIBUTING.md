# Contributing to phlexed

Thanks for considering a contribution. phlexed is a small, focused project
with a fast feedback loop — most PRs are one file and a handful of test
assertions.

## Before you start

Read [`docs/STATUS.md`](docs/STATUS.md) for the one-file project state
snapshot (what's shipped, what's tested, what's deferred). Skim
[`.ralph/fix_plan.md`](.ralph/fix_plan.md) for the per-loop engineering
notes if you want deeper context on why things are the way they are — it's
verbose but grep-friendly.

For changes that touch a `SKILL.md` workflow (the skill instruction files
that Claude Code reads at runtime), you'll also want to read
[`docs/MANUAL_VERIFICATION.md`](docs/MANUAL_VERIFICATION.md) which
documents the 3 live-Claude-Code verification flows that automated tests
can't exercise.

## Running the tests

phlexed has three test suites. Run them all before opening a PR:

```bash
./scripts/test-adapters.sh           # Full suite (offline + online, 145 checks)
./scripts/test-adapters.sh --quick   # Offline only (127 checks, no network)
./scripts/test-installer.sh          # Installer lifecycle (24 checks)
```

The full mode clones real `phlexy_ui` and `shadcn_phlexcomponents` sources
from GitHub and runs the library adapters against them. The quick mode
skips that to avoid upstream-flakiness false failures in CI — but locally
you should run the full mode to catch adapter regressions against real
upstream source.

CI (`.github/workflows/test.yml`) runs `--quick` + installer + a
shellcheck lint step on every push and PR.

## Adding a new library adapter

The most common contribution path. phlexed ships with adapters for
`phlexy_ui` and `shadcn_phlexcomponents` plus a `generic.rb` fallback
that scans `app/components/` for any `Phlex::HTML` subclass. If you use
[Protos](https://github.com/paco/protos), [RubyUI](https://rubyui.com/), or
another Phlex component library, you can add a first-class adapter.

### Worked example: adding a `protos` adapter

`protos` is already recognized by `phlexed-detect` (it's in the library
list at `skill/bin/phlexed-detect:27`), but has no adapter yet, so a
project using Protos currently falls back to `generic.rb`. A dedicated
adapter would extract library-specific metadata — named slots, variant
vocabulary, prop-to-class mappings — that the generic scanner can't know
about.

**Step 1. Copy `generic.rb` as your starting point.**

```bash
cp skill/adapters/generic.rb skill/adapters/protos.rb
```

The generic adapter has the full parsing skeleton: `parse_phlex_file`,
the main scan loop, JSON output. Use it as the structural template and
replace the class-detection regex + prop-extraction logic with
Protos-specific patterns.

**Step 2. Study 2-3 real components from the target library.**

Clone the library source and read a few components to understand its
conventions:

```bash
git clone --depth 1 https://github.com/paco/protos.git /tmp/protos
find /tmp/protos -name "*.rb" -path "*/components/*" | head
cat /tmp/protos/path/to/button.rb
```

Questions to answer from the source:
- What does the base class look like? (`class Button < Protos::Base`,
  `class Button < Protos::Component`, something else?)
- How are variants defined? Is it a `class_variants` DSL, a
  `register_modifiers` macro, a `variants:` hash in the class body,
  or inline `case`/`if` in the render method?
- How are subcomponents/slots declared? (`renders_one`, `renders_many`,
  factory methods like `def trigger`, sibling classes?)
- What's the gemspec file look like? Does it use a VERSION constant or
  a literal string?

**Step 3. Update the class-detection regex.**

In `parse_phlex_file`, find the inheritance match line and add the
library's base class name:

```ruby
# Before (from generic.rb):
return nil unless source.match?(/class\s+[\w:]+.*<\s*(?:Phlex::HTML|Views::Base|ApplicationView|ApplicationComponent)/) ||
                  source.match?(/include\s+Phlex/)

# After (for protos):
return nil unless source.match?(/class\s+[\w:]+.*<\s*(?:Protos::Component|Protos::Base)/) ||
                  source.match?(/include\s+Phlex/)
```

**Step 4. Extract variants/sizes/slots using library-specific regex.**

This is where adapters differ. Look at
[`skill/adapters/phlexy_ui.rb`](skill/adapters/phlexy_ui.rb) for an
example that parses `register_modifiers(...)` DSL, and
[`skill/adapters/shadcn_phlexcomponents.rb`](skill/adapters/shadcn_phlexcomponents.rb)
for an example that walks nested `class_variants(variants: { variant: {...}, size: {...} })`
hashes with balanced-brace matching.

If the library uses a sufficiently simple convention, regex scan works.
If it has nested DSL (like shadcn's config hash), you'll need a balanced
brace walker — copy the `extract_balanced` and `extract_top_level_keys`
lambdas from `shadcn_phlexcomponents.rb:70` as a starting template.

**Step 5. Handle gemspec version parsing.**

Most gemspecs use `s.version = "1.2.3"` (literal string), but some use a
constant reference like `s.version = MyLib::VERSION` (where `lib/mylib/version.rb`
defines `VERSION = "1.2.3"`). phlexy_ui uses the constant form. Write the
version parser to try the literal form first, then fall back to reading
`lib/<gem_name>/version.rb`:

```ruby
version = "unknown"
gemspec = Dir.glob(File.join(gem_path, "*.gemspec")).first
if gemspec
  content = File.read(gemspec)
  if content =~ /\.version\s*=\s*["']([^"']+)["']/
    version = $1
  end
end

if version == "unknown"
  version_file = File.join(gem_path, "lib", "protos", "version.rb")
  if File.exist?(version_file)
    vcontent = File.read(version_file)
    version = $1 if vcontent =~ /VERSION\s*=\s*["']([^"']+)["']/
  end
end
```

**Step 6. Canonical example variant.**

Each adapter picks a "canonical" variant for each component's example
string. For DaisyUI/PhlexyUI this is `:primary` (DaisyUI's base semantic
color). For shadcn it's `:default` (shadcn's base). Pick whatever the
library considers its canonical starting variant.

```ruby
PROTOS_SEMANTIC_VARIANTS = %w[primary secondary accent ghost link].freeze

# In parse_component, after extracting variants:
example_variant = (PROTOS_SEMANTIC_VARIANTS & variants).first || variants.first
```

The left-operand ordering matters (`SEMANTIC & variants` preserves SEMANTIC
order) so the example uses `:primary` first, falling back to the first
available variant when no semantic match exists.

**Step 7. Verify against real source.**

Run your adapter directly against the cloned library source:

```bash
ruby skill/adapters/protos.rb /tmp/protos /tmp/protos-registry.json
cat /tmp/protos-registry.json | head -100
```

Eyeball the output: does every component have a reasonable name, props
list, variants/sizes? Any fields stuck as `null` or `unknown`? Is the
`example` line something a Claude Code prompt could actually use?

**Step 8. Add regression assertions.**

Edit `scripts/test-adapters.sh` to exercise the new adapter. Find the
existing "phlexy_ui adapter (real github.com/...)" subsection and mirror
its pattern for your library. Key assertions:

1. Component count reasonable (`>= 20` or similar minimum)
2. Version parsed (not `"unknown"`)
3. A few specific components exist by name (`Button`, `Card`, etc.)
4. `Button` has a non-empty `variants` list
5. `Button.example` mentions the canonical variant

Pin exact expected values where you can — they're the regression guards
that catch silent upstream changes.

**Step 9. Run the full suite.**

```bash
./scripts/test-adapters.sh         # Full mode exercises the new online path
./scripts/test-installer.sh
```

Both should pass. If the online mode fails because the upstream repo
rename happened between your test writing and now, update the clone URL.

**Step 10. Update the CHANGELOG and README.**

Add a `Added` entry to `CHANGELOG.md`'s `[Unreleased]` section describing
the new adapter. Add the library to the "Supported libraries" table in
`README.md`.

## Fixing a bug

1. Write a failing regression test first in `scripts/test-adapters.sh` (or
   `test-installer.sh` if it's installer-related). Run the suite — the
   new assertion should fail.
2. Fix the bug in `skill/bin/*` or `skill/adapters/*`.
3. Re-run the suite — the new assertion should pass and nothing else
   should regress.
4. Add a `Fixed` entry to `CHANGELOG.md` referencing the root cause and
   the test that guards against regression.

This "test-first" workflow catches a surprising number of near-misses
where a fix looks right but doesn't actually exercise the bug path.
Several bugs fixed during the project's Ralph-loop development were
originally surfaced this way (see `.ralph/fix_plan.md` for the narrative).

## Editing a `SKILL.md`

SKILL.md files are the instructions Claude Code reads when running a
skill. They can't be automatically tested — the regression suites verify
the bin scripts they invoke, not the interpretation of the markdown.

When you edit a SKILL.md:

1. The frontmatter regression test (`scripts/test-adapters.sh` "skill
   frontmatter" subsection) verifies `name`, `version`, `description`,
   and `allowed-tools` are structurally valid. Your edit must keep those
   four fields present and semver-valid.
2. If your change materially affects behavior, bump the skill's
   `version:` frontmatter field. Three skills already sit on 0.2.0
   (setup, component, build) for their v0.2-feature integrations.
3. Update `docs/MANUAL_VERIFICATION.md` with expected behavior changes
   so the next human running through the verification flows knows what
   to look for.
4. Note in the PR description that manual verification is required
   before merging.

## Style and conventions

- **Bash scripts:** zero shellcheck warnings. CI runs shellcheck across
  all 5 shell scripts on every PR. Use `# shellcheck disable=CODE`
  comments only for intentional exemptions, with a rationale comment.
- **Ruby scripts:** no formal style checker but follow the existing
  patterns in `skill/adapters/` — single-file scripts, `# frozen_string_literal: true`
  at the top, minimal dependencies (just `json`, `pathname`, `optparse`).
- **Commit messages:** present tense imperative ("add protos adapter",
  not "added protos adapter"). Keep the subject under 72 chars. Body
  optional but welcome for non-trivial changes.
- **PR size:** prefer small, focused PRs. A new adapter is usually one
  file + one test subsection + CHANGELOG entry. Don't mix a bug fix and
  a feature in the same PR.
- **No emojis in committed files** unless explicitly requested — this
  is a project-wide convention carried over from the maintainer's
  global preferences.

## What the automated tests DO and DON'T catch

**DO catch:**
- Bin-script regressions (all 5 scripts under test)
- Adapter output shape + specific field values against real upstream source
- Registry merge pipeline end-to-end (with a fake-bundle shim)
- Installer lifecycle (fake HOME, 24 assertions)
- SKILL.md frontmatter structural validity
- Shell script lint quality (via shellcheck)
- HAML/Slim + ERB prop inference correctness

**DON'T catch:**
- Runtime behavior of SKILL.md instructions (Claude Code interprets those)
- Integration against a real full Rails app (tests use synthetic fixtures)
- UI/visual changes to `site/index.html` (no screenshot diffing)
- Deploy-side issues (no canary tests)

For the "DON'T catch" items, the manual verification flows in
`docs/MANUAL_VERIFICATION.md` are your safety net.

## Getting help

- File an issue at [github.com/theinventor/phlexed/issues](https://github.com/theinventor/phlexed/issues)
  with the relevant `.phlexed/registry.json` excerpt, your `Gemfile.lock`
  contents, and the exact error or unexpected behavior.
- For design questions, the
  [`~/.gstack/projects/phlexed/troy-unknown-design-20260410-120216.md`](.)
  design doc is the single source of truth (not distributed with the
  repo; held by the maintainer).
- For scope questions ("should I build X?"), open an issue first with
  a short proposal before writing code. Most feature questions are
  resolved in a 3-message issue thread.

## License

By contributing, you agree your contributions will be licensed under the
MIT License (same as the project).

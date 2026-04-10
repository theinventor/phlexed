---
name: phlexed-retrofit
version: 0.1.0
description: |
  Convert a Rails app's existing ERB/HAML/Slim views to Phlex components. Runs in
  4 phases: audit (scan app/views/ + classify complexity), present plan (batched
  conversion order + new components needed), generate Ralph loop (.phlexed/retrofit/
  with PROMPT.md + fix_plan.md + .ralphrc), execute (fire Ralph to convert views
  one at a time with atomic commits). Use when the user says "convert to Phlex,"
  "migrate views," "retrofit," or "move off ERB/HAML/Slim."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /phlexed-retrofit

The migration engine. Converts an existing Rails app's ERB/HAML/Slim views to
Phlex components autonomously via a Ralph loop — but only after showing the user
the plan and getting explicit approval.

This skill is deliberately multi-step with user checkpoints. It does not kick off
the conversion without approval. It is the most load-bearing skill in phlexed and
the one users will be most nervous about running, so treat their time and their
git history with care.

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

# Registry check (required — retrofit needs to know what components are available)
if [ -f ".phlexed/registry.json" ]; then
  echo "HAS_REGISTRY: yes"
  LIBRARY=$(ruby -rjson -e 'puts JSON.parse(File.read(".phlexed/registry.json"))["library"]' 2>/dev/null || echo "unknown")
  COMPONENT_COUNT=$(ruby -rjson -e 'puts JSON.parse(File.read(".phlexed/registry.json"))["component_count"]' 2>/dev/null || echo "0")
  echo "LIBRARY: $LIBRARY"
  echo "COMPONENT_COUNT: $COMPONENT_COUNT"
else
  echo "HAS_REGISTRY: no"
  echo "LIBRARY: none"
  echo "COMPONENT_COUNT: 0"
fi

# Existing audit? (if re-running)
if [ -f ".phlexed/retrofit-audit.json" ]; then
  echo "HAS_AUDIT: yes"
  AUDIT_AGE_SECONDS=$((($(date +%s) - $(stat -f %m .phlexed/retrofit-audit.json 2>/dev/null || stat -c %Y .phlexed/retrofit-audit.json)) ))
  echo "AUDIT_AGE_SECONDS: $AUDIT_AGE_SECONDS"
else
  echo "HAS_AUDIT: no"
  echo "AUDIT_AGE_SECONDS: 0"
fi

# Existing plan?
if [ -f ".phlexed/retrofit-plan.json" ]; then
  echo "HAS_PLAN: yes"
else
  echo "HAS_PLAN: no"
fi

# Existing retrofit directory (Ralph loop artifacts)
if [ -d ".phlexed/retrofit" ]; then
  echo "HAS_RETROFIT_DIR: yes"
  if [ -f ".phlexed/retrofit/fix_plan.md" ]; then
    REMAINING=$(grep -c '^- \[ \]' .phlexed/retrofit/fix_plan.md 2>/dev/null || echo "0")
    DONE=$(grep -c '^- \[x\]' .phlexed/retrofit/fix_plan.md 2>/dev/null || echo "0")
    echo "RETROFIT_REMAINING: $REMAINING"
    echo "RETROFIT_DONE: $DONE"
  fi
else
  echo "HAS_RETROFIT_DIR: no"
fi

# Git cleanliness check — retrofit commits atomically, so the working tree
# needs to be clean when we start
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    echo "GIT_CLEAN: yes"
  else
    echo "GIT_CLEAN: no"
  fi
  BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
  echo "GIT_BRANCH: $BRANCH"
else
  echo "GIT_CLEAN: unknown"
  echo "GIT_BRANCH: unknown"
fi

# Detect whether ralph is available for Phase 4 execution
if command -v ralph >/dev/null 2>&1; then
  echo "HAS_RALPH: yes"
else
  echo "HAS_RALPH: no"
fi

# app/views/ must exist
if [ -d "app/views" ]; then
  TEMPLATE_COUNT=$(find app/views -type f \( -name '*.erb' -o -name '*.haml' -o -name '*.slim' \) 2>/dev/null | wc -l | tr -d ' ')
  echo "TEMPLATE_COUNT: $TEMPLATE_COUNT"
else
  echo "TEMPLATE_COUNT: 0"
fi
```

## Workflow

### Step 0: Verify prerequisites

**If `HAS_GEMFILE` is `no`:** stop with `STATUS: BLOCKED`. Tell the user to run
from a Rails project root.

**If `HAS_REGISTRY` is `no`:** stop with `STATUS: BLOCKED`. Tell the user:

> phlexed-retrofit needs to know what Phlex components are available. Run
> `/phlexed-setup` first to build `.phlexed/registry.json`, then re-run
> `/phlexed-retrofit`.

**If `TEMPLATE_COUNT` is `0`:** stop with `STATUS: DONE_WITH_CONCERNS`. Nothing
to retrofit — this project has no ERB/HAML/Slim templates in `app/views/`.

**If `GIT_CLEAN` is `no`:** stop with `STATUS: BLOCKED`. Tell the user:

> Your working tree has uncommitted changes. phlexed-retrofit commits atomically
> after each conversion and needs a clean starting point so you can cleanly diff
> or roll back any iteration. Commit or stash your work first, then re-run.

**If `HAS_RALPH` is `no`:** warn but don't block — the user can still get through
Phase 3 (plan + generated loop artifacts) and run Ralph manually.

### Step 1: Handle re-runs

**If `HAS_RETROFIT_DIR` is `yes`** and `RETROFIT_REMAINING > 0`, the user has a
retrofit in progress. AskUserQuestion:

> A retrofit is already in progress. {{RETROFIT_DONE}} converted, {{RETROFIT_REMAINING}}
> remaining. What do you want to do?

Options:
- A) Resume — fire the Ralph loop to continue from where it stopped
- B) Re-audit and start fresh (archives the existing retrofit directory)
- C) Just show me the remaining tasks (open fix_plan.md)
- D) Cancel — leave the in-progress retrofit untouched

If A: jump directly to Step 6 (Execute).
If B: archive `.phlexed/retrofit/` to `.phlexed/retrofit.archived-<timestamp>/` and
continue to Step 2.
If C: print the remaining tasks from `.phlexed/retrofit/fix_plan.md` and stop.
If D: stop with `STATUS: DONE`.

### Step 2: Run the audit (Phase 1)

Invoke `phlexed-audit`. Do not write extra logic here — the tool produces
`.phlexed/retrofit-audit.json`.

```bash
"$PHLEXED_HOME/bin/phlexed-audit" --project .
```

Read the output summary. If `total_templates` is 0 and `already_phlex > 0`, the
project is already fully Phlex — stop with `STATUS: DONE`. Tell the user:

> All {{already_phlex}} views are already Phlex classes. Nothing to retrofit.

If audit fails (non-zero exit or missing output file), stop with `STATUS: BLOCKED`
and surface the error.

### Step 3: Build the plan (end of Phase 1 → Phase 2)

Invoke `phlexed-retrofit-plan`. This reads the audit and produces
`.phlexed/retrofit-plan.json`.

```bash
"$PHLEXED_HOME/bin/phlexed-retrofit-plan" --project .
```

Read the plan output. Note:
- total_convertible, total_batches
- Each batch name + view_count
- new_components_needed (list of new Phlex components to create during batch 1)

### Step 4: Present the plan to the user (Phase 2)

Show a concise summary of the plan. Format:

```
Phlexed retrofit plan for this project:

  Library:      {{library}} ({{component_count}} components)
  Templates:    {{total_convertible}} to convert, {{skipped_already_phlex}} already Phlex
  Batches:
    1. Shared partials — {{count}} views
    2. Layouts         — {{count}} views
    3. Simple pages    — {{count}} views
    4. Medium pages    — {{count}} views
    5. Complex pages   — {{count}} views (manual review recommended)

  New components needed: {{n}}
    {{name}} (used by {{count}} views, props: {{props}})
    ...

Estimated commits: {{total_convertible + new_components}} (one per conversion)
```

Then AskUserQuestion:

> How would you like to proceed with the retrofit?

Options:
- A) Convert everything (recommended) — run all batches end to end
- B) Convert the easy ones only — skip complex pages (batch 5)
- C) Convert specific batches — I'll pick which to include
- D) Just give me the plan file, don't generate the Ralph loop yet
- E) Cancel

**If C**, AskUserQuestion again with batch-by-batch checkboxes:

> Which batches should the retrofit include? (You can always re-run to include more later.)

Options for each batch: Include / Skip. Default: all except "Complex pages".

**If D**: Plan is already written to `.phlexed/retrofit-plan.json`. Print its path
and stop with `STATUS: DONE`.

**If E**: Stop with `STATUS: DONE`.

**If A, B, or C**: continue to Step 5.

### Step 5: Generate the Ralph loop (Phase 3)

Create the `.phlexed/retrofit/` directory and generate three files from the
templates in `$PHLEXED_HOME/templates/`:

1. **`.phlexed/retrofit/PROMPT.md`** — from `templates/retrofit-prompt.md`. Substitute:
   - `{{GENERATED_AT}}` → current ISO timestamp
   - `{{LIBRARY}}` → library name from registry (e.g. `phlexy_ui`)
   - `{{LIBRARY_SLUG}}` → library slug for the pattern template filename
     (`phlexy_ui` → `phlexy-ui`, `shadcn_phlexcomponents` → `shadcn-phlexcomponents`)
   - `{{NAMESPACE}}` → Ruby namespace (`PhlexyUI`, `ShadcnPhlexcomponents`)
   - `{{COMPONENT_COUNT}}` → component count from registry

2. **`.phlexed/retrofit/fix_plan.md`** — a markdown task list, one task per view
   to convert, ordered by batch. Format:

   ```markdown
   # Retrofit fix_plan
   
   Generated from .phlexed/retrofit-plan.json on {{GENERATED_AT}}.
   
   ## Batch 1: Shared partials
   
   - [ ] Convert app/views/shared/_top_nav.html.erb → TopNav component
         - engine: erb, complexity: simple
         - component matches: Navbar
         - new component to create: TopNav (props: current_user)
         - used by: 1 downstream view (layout)
   - [ ] Convert app/views/shared/_flash.html.erb → Flash component
         - engine: erb, complexity: simple
         - new component to create: Flash (props: message, type)
         - used by: 4 downstream views
   
   ## Batch 2: Layouts
   
   - [ ] Convert app/views/layouts/application.html.erb → ApplicationLayout
         - depends on: TopNav, Flash (batch 1)
   
   ## Batch 3: Simple pages
   
   - [ ] Convert app/views/home/index.html.erb → HomeIndexView
         - component matches: Button, Card
   ...
   ```

   Each task gets `- [ ]` (unchecked) so the Ralph loop can mark them `- [x]` as
   it progresses. Failed conversions use `- [!]`. Dependencies listed explicitly
   so Ralph can skip when prerequisites aren't met.

   If the user chose B or C in Step 4, exclude skipped batches entirely.

3. **`.phlexed/retrofit/.ralphrc`** — from `templates/retrofit-ralphrc.template`.
   Substitute:
   - `{{GENERATED_AT}}` → current ISO timestamp
   - `{{MAX_ITERATIONS}}` → `ceil(total_convertible * 1.2) + new_components_needed.size`
   - `{{PROJECT_ROOT}}` → absolute path of the project root

Write all three files. Print a confirmation:

```
Generated retrofit loop:
  .phlexed/retrofit/PROMPT.md
  .phlexed/retrofit/fix_plan.md   ({{task_count}} tasks)
  .phlexed/retrofit/.ralphrc      (max {{max_iterations}} iterations)

Review the files. When you're ready, run:
  ralph -p .phlexed/retrofit/PROMPT.md
```

### Step 6: Execute (Phase 4)

AskUserQuestion:

> Ready to start the retrofit? This will run a Ralph loop that converts each view
> one at a time, tests after each, and commits atomically. You can stop it anytime
> with Ctrl-C — each iteration is already committed, so nothing is ever lost.

Options:
- A) Start the Ralph loop now
- B) Let me review the generated files first — I'll run ralph myself when ready
- C) Cancel (leave the generated files in place for later)

**If A and `HAS_RALPH` is `yes`:** fire the loop. Do NOT background the process —
Ralph is interactive and the user needs to see its output.

```bash
cd "$PROJECT_ROOT" && ralph -p .phlexed/retrofit/PROMPT.md
```

Let Ralph run. When it exits, run Step 7.

**If A and `HAS_RALPH` is `no`:** stop with `STATUS: BLOCKED`. Tell the user:

> Ralph is not installed or not in PATH. Install it first, then run:
>   ralph -p .phlexed/retrofit/PROMPT.md

**If B**: print the file paths and the ralph command, stop with `STATUS: DONE`.

**If C**: stop with `STATUS: DONE`. The generated files stay in place for later.

### Step 7: Post-retrofit (after Ralph completes or is cancelled)

After the Ralph loop exits (naturally or via Ctrl-C):

1. **Refresh the registry** — new Phlex components were probably created, and
   the library adapter may not have seen them. Run:
   ```bash
   "$PHLEXED_HOME/bin/phlexed-registry"
   ```

2. **Read the final state of `.phlexed/retrofit/fix_plan.md`** and count:
   - `- [x]` converted
   - `- [!]` failed / skipped for manual review
   - `- [ ]` unconverted (Ralph stopped early)

3. **Find the `.pre-phlex` backup files** left by the retrofit:
   ```bash
   find app/views -name '*.pre-phlex' -type f
   ```

4. **Print the summary report:**

   ```
   Retrofit complete.
   
   Converted:      {{converted}} views
   Manual review:  {{failed}} views (see .phlexed/retrofit/fix_plan.md for details)
   Unconverted:    {{unconverted}} views (Ralph stopped early)
   
   Backup files ({{backup_count}}):
     app/views/...
     ...
   
   Next steps:
     1. Run your full test suite to verify everything works:
          bundle exec rspec   (or rails test)
     2. Review each .pre-phlex backup against its new Phlex class
     3. Once satisfied: find app/views -name '*.pre-phlex' -delete
     4. For manual-review items, convert them manually or re-run
        /phlexed-retrofit after fixing the underlying issues
   ```

Report `STATUS: DONE`.

## Invariants

- **Never kick off the Ralph loop without explicit user approval.** Every
  execution must go through Step 6's AskUserQuestion. This is non-negotiable —
  retrofits touch a lot of files and users need to consent.
- **Never run on a dirty working tree.** Step 0 blocks. Users must commit or
  stash first.
- **Never delete `.pre-phlex` backup files.** The user does that in a final
  manual pass after reviewing each conversion.
- **Never modify `.phlexed/registry.json` directly** — always through
  `phlexed-registry`.
- **Every conversion = one atomic commit.** The generated PROMPT.md enforces
  this; do not bypass it in the skill body.
- **Re-runs always preserve existing retrofit state unless the user explicitly
  asks to archive it** (Step 1, option B).

## Voice

Direct, concrete, slightly more cautious than other phlexed skills because this
one modifies many files. Name counts, file paths, commit messages. Never say
"let me try" — either do it or report a block. Always give the user a way to
bail out cheaply.

## Troubleshooting

- **"Registry may be stale":** warning from Step 2 — means Gemfile.lock is newer
  than `.phlexed/registry.json`. Run `/phlexed-setup` first to refresh.
- **"3 consecutive failures" during Ralph loop:** the generated PROMPT.md tells
  Ralph to stop. Usually means the project has a non-standard convention
  (custom base class, unusual helper) that the conversion can't handle. Read
  the last few entries in `.phlexed/retrofit/logs/` and convert those files
  manually.
- **"Dependency cycle detected":** rare, but can happen if partials render each
  other. Ralph skips both and flags them. Convert manually.
- **Tests pass for the view but the page looks wrong:** styling is separate —
  run `/phlexed-theme` to verify the design system is respected, then `/qa` to
  check the actual rendered output.
- **User wants to undo everything:** `git reset --hard <commit-before-retrofit>`
  will revert all converted views in one go, since each was its own commit.
  This is safer than cherry-picking reverts. Only do this if the user
  explicitly asks — do not suggest it unless they say they want to abort.

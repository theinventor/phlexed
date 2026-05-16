#!/usr/bin/env bash
# shellcheck disable=SC2059,SC2016
# SC2059 is disabled because we use `printf "${COLOR}text${NC}\n"` throughout
# as the terminal-coloring idiom. The shellcheck-preferred alternative is
# measurably uglier and the "variables in format string" concern doesn't
# apply here since COLOR values are literals we control.
# SC2016 is disabled because `run_ruby_checks FILE '<ruby source>'` passes
# the Ruby block as a single-quoted string intentionally — the single quotes
# prevent shell variable expansion so the Ruby code sees literal sigils.
# scripts/test-adapters.sh — Regression guard for phlexed adapters and bin scripts
#
# Runs each adapter and bin script against either the committed sample/ fixture
# or real upstream sources (cloned on demand) and validates the output JSON
# shape, key fields, and specific values. Exits non-zero on any failure.
#
# This script codifies the manual verification loop that discovered 9 adapter
# bugs on 2026-04-10. Re-run after touching any adapter to catch regressions.
#
# Usage:
#   ./scripts/test-adapters.sh              Run all tests (offline + online)
#   ./scripts/test-adapters.sh --quick      Skip network tests (no git clone)
#   ./scripts/test-adapters.sh --online     Run ONLY network tests
#   ./scripts/test-adapters.sh --help       Show this help
#
# Requires: ruby 3.0+, git (for online tests)

set -uo pipefail

# --- Locate repo + paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_ROOT/skill/bin"
ADAPTERS="$REPO_ROOT/skill/adapters"
SAMPLE="$REPO_ROOT/sample"

# --- Ephemeral workspace ---
WORKDIR=$(mktemp -d -t phlexed-test.XXXXXX)
# shellcheck disable=SC2329
# cleanup() is invoked by the trap below; shellcheck can't see trap-invoked
# usage so it incorrectly flags this as unused.
cleanup() {
  rm -rf "$WORKDIR"
  # Also clean up any .phlexed artifacts written to sample/ during testing
  rm -rf "$SAMPLE/.phlexed"
}
trap cleanup EXIT INT TERM

# --- Colors (TTY only) ---
if [ -t 1 ]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; DIM=''; NC=''
fi

# --- Test bookkeeping ---
PASSED=0
FAILED=0
FAILURES_FILE="$WORKDIR/failures.txt"
: > "$FAILURES_FILE"

pass() {
  printf "    ${GREEN}✓${NC} %s\n" "$1"
  PASSED=$((PASSED + 1))
}
fail() {
  printf "    ${RED}✗${NC} %s\n" "$1"
  echo "$1" >> "$FAILURES_FILE"
  FAILED=$((FAILED + 1))
}
section() {
  printf "\n${BOLD}%s${NC}\n" "$1"
}
subsection() {
  printf "\n  ${BOLD}%s${NC}\n" "$1"
}
skip() {
  printf "    ${YELLOW}⊘${NC} %s ${DIM}(%s)${NC}\n" "$1" "${2:-skipped}"
}

# --- Arg parsing ---
MODE="all"
while [ $# -gt 0 ]; do
  case "$1" in
    --quick)  MODE="offline"; shift ;;
    --online) MODE="online";  shift ;;
    --help|-h)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      echo "try: $0 --help" >&2
      exit 2
      ;;
  esac
done

# --- Preflight ---
if ! command -v ruby >/dev/null 2>&1; then
  echo "${RED}error${NC}: ruby not found in PATH" >&2
  exit 2
fi
RUBY_VERSION=$(ruby -e 'puts RUBY_VERSION')
printf "${DIM}ruby %s · repo %s${NC}\n" "$RUBY_VERSION" "$REPO_ROOT"

# =============================================================================
# Helper: run a ruby block that reads a JSON registry and emits
# "pass<TAB>message" or "fail<TAB>message" lines. The shell forwards them to
# pass/fail. This keeps each test's assertions co-located with the ruby code
# that understands the registry schema.
# =============================================================================
run_ruby_checks() {
  local outfile="$1"
  local ruby_block="$2"
  local output
  output=$(OUTFILE="$outfile" ruby -rjson - <<RUBY
begin
  r = JSON.parse(File.read(ENV['OUTFILE']))
  $ruby_block
rescue => e
  puts "fail\t(ruby error) #{e.class}: #{e.message}"
end
RUBY
)
  while IFS=$'\t' read -r status msg; do
    case "$status" in
      pass) pass "$msg" ;;
      fail) fail "$msg" ;;
    esac
  done <<< "$output"
}

text_matches() {
  local text="$1"
  local pattern="$2"
  grep -q -- "$pattern" <<< "$text"
}

text_matches_e() {
  local text="$1"
  local pattern="$2"
  grep -Eq -- "$pattern" <<< "$text"
}

first_matching_line() {
  local text="$1"
  local pattern="$2"
  grep -m 1 -- "$pattern" <<< "$text" || true
}

first_matching_line_e() {
  local text="$1"
  local pattern="$2"
  grep -Em 1 -- "$pattern" <<< "$text" || true
}

file_mtime() {
  local file="$1"

  if stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
  else
    stat -f %m "$file"
  fi
}

# =============================================================================
# OFFLINE TESTS — against the committed sample/ fixture. No network.
# =============================================================================
run_offline_tests() {
  section "Offline tests (against committed sample/)"

  # --- shellcheck lint (if the binary is available) ---
  # Skipped when the shellcheck binary isn't on the PATH so local dev machines
  # without a brew-installed copy don't get spurious failures. CI runs it
  # unconditionally because ubuntu-latest ships the linter in its default
  # package set.
  subsection "shellcheck"
  if command -v shellcheck >/dev/null 2>&1; then
    local shellcheck_output
    local shellcheck_exit
    set +e
    shellcheck_output=$(shellcheck \
      "$REPO_ROOT/setup" \
      "$BIN/phlexed-detect" \
      "$BIN/phlexed-registry" \
      "$SCRIPT_DIR/test-adapters.sh" \
      "$SCRIPT_DIR/test-installer.sh" 2>&1)
    shellcheck_exit=$?
    set -e
    if [ "$shellcheck_exit" -eq 0 ]; then
      pass "shellcheck clean across 5 shell scripts"
    else
      fail "shellcheck found issues:"
      # shellcheck disable=SC2001
      # Style suggestion is `${var//pattern/replace}` but bash parameter
      # expansion can't do line-anchored multi-line prefixing cleanly. sed
      # is the right tool here.
      echo "$shellcheck_output" | sed 's/^/      /' >&2
    fi
  else
    skip "shellcheck" "not installed (install via: brew install shellcheck)"
  fi

  # --- phlexed-detect ---
  subsection "phlexed-detect"
  local detect_out
  detect_out=$(cd "$SAMPLE" && "$BIN/phlexed-detect" 2>&1)
  if [ "$detect_out" = "phlexy_ui" ]; then
    pass "identifies phlexy_ui in sample/Gemfile.lock"
  else
    fail "expected 'phlexy_ui', got: $detect_out"
  fi

  # --- phlexed-audit --check ---
  subsection "phlexed-audit"
  local audit_check
  audit_check=$(cd "$SAMPLE" && ruby "$BIN/phlexed-audit" --project . --check 2>&1)
  if text_matches "$audit_check" "convertible:[[:space:]]*7"; then
    pass "--check reports 7 convertible templates"
  else
    fail "expected 7 convertible, got output: $(echo "$audit_check" | tr '\n' ' ')"
  fi
  if text_matches "$audit_check" "already_phlex:[[:space:]]*2"; then
    pass "--check reports 2 already-phlex files"
  else
    fail "expected 2 already_phlex, got output: $(echo "$audit_check" | tr '\n' ' ')"
  fi

  # --- phlexed-audit (write) ---
  (cd "$SAMPLE" && ruby "$BIN/phlexed-audit" --project . >/dev/null 2>&1)
  if [ -f "$SAMPLE/.phlexed/retrofit-audit.json" ]; then
    pass "writes .phlexed/retrofit-audit.json"
    run_ruby_checks "$SAMPLE/.phlexed/retrofit-audit.json" '
      views = r["views"] || []
      puts "#{views.size >= 9 ? "pass" : "fail"}\taudit.views has 9+ entries (got #{views.size})"
      puts "#{r["summary"]["convertible"] == 7 ? "pass" : "fail"}\taudit.summary.convertible == 7"
      puts "#{r["summary"]["already_phlex"] == 2 ? "pass" : "fail"}\taudit.summary.already_phlex == 2"
      puts "#{r["registry"] ? "pass" : "fail"}\taudit has registry metadata block"

      # Already-phlex files identified by path
      already_phlex = views.select { |v| v["already_phlex"] }.map { |v| v["path"] }
      base_flagged = already_phlex.any? { |p| p.end_with?("app/views/base.rb") }
      showview_flagged = already_phlex.any? { |p| p.end_with?("profile/show_view.rb") }
      puts "#{base_flagged ? "pass" : "fail"}\taudit flags app/views/base.rb as already_phlex"
      puts "#{showview_flagged ? "pass" : "fail"}\taudit flags profile/show_view.rb as already_phlex"

      # Complexity distribution — the sample has deliberately varied views so
      # both simple and medium classifications should appear
      convertible = views.reject { |v| v["already_phlex"] || v["skipped"] }
      complexities = convertible.map { |v| v["complexity"] }.compact
      puts "#{complexities.include?("simple") ? "pass" : "fail"}\taudit classifies at least one view as simple (got: #{complexities.tally})"
      puts "#{complexities.any? { |c| c != "simple" } ? "pass" : "fail"}\taudit classifies at least one view as non-simple (medium/complex)"

      # Dependency tracing — the sample layout + pages render shared partials
      # so dependencies should be non-empty on at least one view
      with_deps = convertible.select { |v| (v["dependencies"] || []).any? }
      puts "#{with_deps.any? ? "pass" : "fail"}\taudit traces partial dependencies on 1+ views (got #{with_deps.size})"

      # Component match heuristic — at least one view should map to a
      # registry component (the sample deliberately uses DaisyUI classes)
      with_matches = convertible.select { |v| (v["component_matches"] || []).any? }
      puts "#{with_matches.any? ? "pass" : "fail"}\taudit extracts component_matches from 1+ views (got #{with_matches.size})"

      # Engine detection — at least one view should be tagged "erb" (sample
      # has no HAML/Slim, but ERB detection must at least work)
      engines = convertible.map { |v| v["engine"] }.uniq
      puts "#{engines.include?("erb") ? "pass" : "fail"}\taudit tags ERB views with engine=erb (got: #{engines})"
    '
  else
    fail "phlexed-audit did not produce retrofit-audit.json"
  fi

  # --- phlexed-retrofit-plan ---
  subsection "phlexed-retrofit-plan"
  (cd "$SAMPLE" && ruby "$BIN/phlexed-retrofit-plan" --project . >/dev/null 2>&1)
  if [ -f "$SAMPLE/.phlexed/retrofit-plan.json" ]; then
    pass "writes .phlexed/retrofit-plan.json"
    run_ruby_checks "$SAMPLE/.phlexed/retrofit-plan.json" '
      batches = r["batches"] || []
      puts "#{batches.size >= 3 ? "pass" : "fail"}\tplan.batches has 3+ batches (got #{batches.size})"
      new_comps = (r["new_components_needed"] || []).map { |c| c["name"] }
      expected = %w[Flash Footer TopNav]
      missing = expected - new_comps
      puts "#{missing.empty? ? "pass" : "fail"}\tplan synthesizes new components #{expected} (missing: #{missing})"
      shared = batches.find { |b| b["name"] == "Shared partials" }
      puts "#{shared ? "pass" : "fail"}\tplan has Shared partials batch"
      layouts = batches.find { |b| b["name"] == "Layouts" }
      puts "#{layouts ? "pass" : "fail"}\tplan has Layouts batch"

      # Batch ordering invariant — the retrofit loop depends on this order
      # because shared partials are dependencies that must convert first, then
      # layouts (which reference the partials-turned-components), then pages
      # (which use the layout + partials).
      batch_names = batches.map { |b| b["name"] }
      shared_idx = batch_names.index("Shared partials")
      layouts_idx = batch_names.index("Layouts")
      if shared_idx && layouts_idx
        puts "#{shared_idx < layouts_idx ? "pass" : "fail"}\tbatches ordered: Shared partials before Layouts (got indices #{shared_idx}, #{layouts_idx})"
      else
        puts "fail\tcannot verify batch order — one or both batches missing"
      end

      # Simple pages should come after Layouts when present
      simple_idx = batch_names.index("Simple pages")
      if layouts_idx && simple_idx
        puts "#{layouts_idx < simple_idx ? "pass" : "fail"}\tbatches ordered: Layouts before Simple pages"
      elsif layouts_idx && !simple_idx
        puts "pass\tno Simple pages batch to order against"
      end

      # New component prop inference.
      # The sample shared partials intentionally use Rails helpers (flash,
      # current_user, Time.current.year, link_to, image_tag) and block-scoped
      # iteration variables that are NOT props. The inference engine should
      # correctly identify zero props for all three:
      #   - Flash:  `flash.each do |type, message|` + `<% variant = ... %>`
      #             — both `message` (block param) and `variant` (ERB assignment)
      #             are scope-local, not props. Fixes a v0.2 false-positive
      #             bug where they were being extracted as component props.
      #   - Footer: only `Time.current.year` (method chain) — not a prop.
      #   - TopNav: `current_user` is in LOCAL_BLACKLIST (Rails helper);
      #             all other references are helper calls (link_to, image_tag).
      nc = r["new_components_needed"] || []
      nc_by_name = nc.each_with_object({}) { |c, h| h[c["name"]] = c }

      flash = nc_by_name["Flash"]
      if flash
        props = flash["suggested_props"] || []
        puts "#{props.empty? ? "pass" : "fail"}\tFlash prop inference: block-local vars excluded (got #{props.inspect}, expected [])"
      else
        puts "fail\tFlash component not found in new_components_needed"
      end

      footer = nc_by_name["Footer"]
      if footer
        props = footer["suggested_props"] || []
        puts "#{props.empty? ? "pass" : "fail"}\tFooter prop inference: Time.current.year correctly not inferred as prop (got #{props.inspect})"
      else
        puts "fail\tFooter component not found in new_components_needed"
      end

      top_nav = nc_by_name["TopNav"]
      if top_nav
        props = top_nav["suggested_props"] || []
        puts "#{props.empty? ? "pass" : "fail"}\tTopNav prop inference: Rails helpers + current_user filtered (got #{props.inspect})"
      else
        puts "fail\tTopNav component not found in new_components_needed"
      end

      # Each new component should record source_partial + used_by_count
      valid_meta = nc.select { |c| c["source_partial"] && c["used_by_count"] }
      puts "#{valid_meta.size == nc.size ? "pass" : "fail"}\tevery new_component has source_partial + used_by_count metadata"

      # Registry block should carry through from the audit
      puts "#{r["registry"] ? "pass" : "fail"}\tplan carries registry metadata block through from audit"

      # Summary should report by_batch counts
      summary = r["summary"] || {}
      by_batch = summary["by_batch"] || []
      puts "#{by_batch.any? ? "pass" : "fail"}\tplan.summary.by_batch is populated (got #{by_batch.size} entries)"
    '
  else
    fail "phlexed-retrofit-plan did not produce retrofit-plan.json"
  fi

  # --- phlexed-audit/retrofit-plan against HAML + Slim templates ---
  # The committed sample/ has only ERB templates, so the audit's HAML and
  # Slim code paths are completely untested by the sample-based checks above.
  # This subsection builds a synthetic multi-engine project in $WORKDIR and
  # verifies:
  #   - Engine detection tags .haml files with engine="haml"
  #   - Engine detection tags .slim files with engine="slim"
  #   - Render detection works on HAML/Slim syntax (`= render "..."`)
  #   - Dependency tracing resolves HAML and Slim shared partials
  #   - retrofit-plan synthesizes new_components from non-ERB shared partials
  subsection "phlexed-audit HAML + Slim coverage"

  local multi_project="$WORKDIR/multi-engine-project"
  mkdir -p "$multi_project/app/views/home" "$multi_project/app/views/shared" "$multi_project/app/views/admin" "$multi_project/.phlexed"

  cat > "$multi_project/Gemfile.lock" <<'LOCK'
GEM
  specs:
    phlex (2.0.0)
DEPENDENCIES
  phlex
LOCK

  # HAML page — uses content_for + render + HAML class syntax for component hints
  cat > "$multi_project/app/views/home/index.html.haml" <<'HAML'
- content_for :title, "Home"

%section.hero
  .hero-content.text-center
    %h1.text-5xl= @page_title
    %p.mb-4= @description
    %button.btn.btn-primary Get Started

= render "shared/footer"
HAML

  # Slim page — uses content_for + render with locals + Slim class syntax
  cat > "$multi_project/app/views/home/show.html.slim" <<'SLIM'
- content_for :title, "Product"

.card.card-bordered.bg-base-100
  .card-body
    h2.card-title = @product.name
    p = @product.description
    .card-actions.justify-end
      button.btn.btn-primary = t(".add_to_cart")

= render "shared/reviews", locals: { product: @product }
SLIM

  # Complex HAML page — deliberately triggers multiple HAML/Slim-specific
  # complexity signals to verify the v0.2 signal expansion in phlexed-audit
  # actually classifies non-ERB templates by their real complexity instead
  # of defaulting toward "simple". Expected score:
  #   +1 (content_for), +2 (- case), +1 (- each ... do),
  #   +1 (- if), +3 (= raw), +1 (= render) = 9 total → "complex"
  cat > "$multi_project/app/views/admin/dashboard.html.haml" <<'HAML'
- content_for :title, "Admin Dashboard"

.dashboard
  - case @user.role
  - when :admin
    %p.role Admin
  - when :moderator
    %p.role Moderator

  %ul.items
    - @items.each do |item|
      %li= item.name

  - if @show_raw_html
    = raw @raw_content

  = render "shared/footer"
HAML

  # Shared HAML partial — simple, no props
  cat > "$multi_project/app/views/shared/_footer.html.haml" <<'HAML'
%footer.footer.bg-base-300
  %p Copyright #{Time.current.year}
HAML

  # Shared Slim partial — has call-site locals, block-scoped var
  cat > "$multi_project/app/views/shared/_reviews.html.slim" <<'SLIM'
.reviews
  - reviews.each do |review|
    .review
      p = review.body
SLIM

  # Shared HAML partial with legitimate props — exercises HAML line-start
  # `= expr` extraction and HAML `#{interp}` extraction. Expected props
  # after the v0.2 HAML/Slim prop inference fix: [description, price, title].
  cat > "$multi_project/app/views/shared/_product_card.html.haml" <<'HAML'
.product-card
  %h2
    = title
  %p
    = description
  %span.price Price: #{price}
HAML

  # Shared Slim partial with legitimate props — exercises Slim line-start
  # `= expr` and Slim `#{interp}`. Expected props: [author, content, review,
  # timestamp].
  cat > "$multi_project/app/views/shared/_review_card.html.slim" <<'SLIM'
.review-card
  h3
    = review
  .body
    = content
  .meta
    | Posted by #{author} at #{timestamp}
SLIM

  (cd "$multi_project" && ruby "$BIN/phlexed-audit" --project . >/dev/null 2>&1)

  if [ -f "$multi_project/.phlexed/retrofit-audit.json" ]; then
    pass "HAML+Slim audit produces retrofit-audit.json"
    run_ruby_checks "$multi_project/.phlexed/retrofit-audit.json" '
      views = r["views"] || []

      # Engine detection: at least one view each for haml and slim
      engines = views.map { |v| v["engine"] }.uniq.sort
      puts "#{engines.include?("haml") ? "pass" : "fail"}\taudit detects HAML engine (got engines: #{engines})"
      puts "#{engines.include?("slim") ? "pass" : "fail"}\taudit detects Slim engine"

      # View counts — 4 HAML (2 pages + 2 partials) and 3 Slim (page + 2 partials)
      haml_views = views.select { |v| v["engine"] == "haml" }
      slim_views = views.select { |v| v["engine"] == "slim" }
      puts "#{haml_views.size == 4 ? "pass" : "fail"}\taudit finds 4 HAML templates (home + admin pages + 2 partials, got #{haml_views.size})"
      puts "#{slim_views.size == 3 ? "pass" : "fail"}\taudit finds 3 Slim templates (page + 2 partials, got #{slim_views.size})"

      # Dependency tracing: the HAML page renders shared/footer, the Slim
      # page renders shared/reviews. Both render calls use the HAML/Slim
      # `= render "..."` prefix syntax that the audit regexes must handle.
      home_index = views.find { |v| v["path"].end_with?("home/index.html.haml") }
      if home_index
        deps = home_index["dependencies"] || []
        footer_dep = deps.any? { |d| d.include?("_footer.html.haml") }
        puts "#{footer_dep ? "pass" : "fail"}\tHAML page dependency trace resolves shared/_footer.html.haml (got #{deps})"
      else
        puts "fail\tHAML page home/index.html.haml not found in audit output"
      end

      home_show = views.find { |v| v["path"].end_with?("home/show.html.slim") }
      if home_show
        deps = home_show["dependencies"] || []
        reviews_dep = deps.any? { |d| d.include?("_reviews.html.slim") }
        puts "#{reviews_dep ? "pass" : "fail"}\tSlim page dependency trace resolves shared/_reviews.html.slim (got #{deps})"
      else
        puts "fail\tSlim page home/show.html.slim not found in audit output"
      end

      # Component matches from HAML class syntax (.hero, .btn, etc.) and
      # from Slim class syntax. Both engines should trigger CLASS_HINTS.
      with_matches = views.select { |v| (v["component_matches"] || []).any? }
      puts "#{with_matches.size >= 2 ? "pass" : "fail"}\tHAML/Slim component_matches extracted from 2+ views (got #{with_matches.size})"

      # Summary counts — 7 total views (3 pages + 4 shared partials),
      # 6 convertible and 1 complex_manual_review because the admin
      # dashboard is now correctly classified as complex.
      summary = r["summary"] || {}
      puts "#{summary["convertible"] == 6 ? "pass" : "fail"}\tHAML+Slim summary.convertible == 6 (got #{summary["convertible"]})"
      puts "#{summary["complex_manual_review"] == 1 ? "pass" : "fail"}\tHAML+Slim summary.complex_manual_review == 1 (got #{summary["complex_manual_review"]})"
      puts "#{summary["total_templates"] == 7 ? "pass" : "fail"}\tHAML+Slim summary.total_templates == 7 (got #{summary["total_templates"]})"

      # v0.2 HAML/Slim complexity signals — the admin/dashboard.html.haml
      # fixture deliberately triggers multiple signals that the old
      # ERB-centric COMPLEXITY_SIGNALS would have missed. With the new
      # line-anchored HAML/Slim patterns, it should classify as "complex"
      # (score >= 5). Expected score breakdown:
      #   content_for=1 + case=2 + each=1 + if=1 + raw=3 + render=1 = 9
      admin_dash = views.find { |v| v["path"].end_with?("admin/dashboard.html.haml") }
      if admin_dash
        complexity = admin_dash["complexity"]
        puts "#{complexity == "complex" ? "pass" : "fail"}\tHAML admin dashboard classified complex (new signals — got #{complexity.inspect})"
      else
        puts "fail\tadmin/dashboard.html.haml not found in audit output"
      end

      # Regression guard: the simpler HAML home/index page should STILL
      # classify as its existing non-complex level. Without the line-anchored
      # new signals, it would otherwise get accidentally bumped if the
      # patterns over-match.
      home_haml = views.find { |v| v["path"].end_with?("home/index.html.haml") }
      if home_haml
        complexity = home_haml["complexity"]
        puts "#{%w[simple medium].include?(complexity) ? "pass" : "fail"}\tHAML home page still classified simple/medium (not over-scored by new signals — got #{complexity.inspect})"
      else
        puts "fail\thome/index.html.haml not found in audit output"
      end
    '
  else
    fail "HAML+Slim audit did not produce retrofit-audit.json"
  fi

  # retrofit-plan should synthesize new_components from both .haml and .slim
  # shared partials — exercises the partial-name-to-component-name conversion
  # across non-ERB extensions AND the v0.2 HAML/Slim prop inference.
  (cd "$multi_project" && ruby "$BIN/phlexed-retrofit-plan" --project . >/dev/null 2>&1)
  if [ -f "$multi_project/.phlexed/retrofit-plan.json" ]; then
    pass "HAML+Slim retrofit-plan produces retrofit-plan.json"
    run_ruby_checks "$multi_project/.phlexed/retrofit-plan.json" '
      nc = r["new_components_needed"] || []
      names = nc.map { |c| c["name"] }.sort
      puts "#{names.include?("Footer") ? "pass" : "fail"}\tplan synthesizes Footer from _footer.html.haml (got #{names})"
      puts "#{names.include?("Reviews") ? "pass" : "fail"}\tplan synthesizes Reviews from _reviews.html.slim"
      puts "#{names.include?("ProductCard") ? "pass" : "fail"}\tplan synthesizes ProductCard from _product_card.html.haml"
      puts "#{names.include?("ReviewCard") ? "pass" : "fail"}\tplan synthesizes ReviewCard from _review_card.html.slim"

      # HAML/Slim prop inference — the v0.2 fix. Previously these partials
      # would have zero props because the inference engine only scanned
      # `<%=` regex which doesnt match HAML/Slim output expressions.
      # Now the inference also handles:
      #   - HAML/Slim `= expr` at line start
      #   - HAML/Slim `#{interp}` string interpolation
      nc_by_name = nc.each_with_object({}) { |c, h| h[c["name"]] = c }

      product_card = nc_by_name["ProductCard"]
      if product_card
        props = (product_card["suggested_props"] || []).sort
        expected = %w[description price title]
        puts "#{props == expected ? "pass" : "fail"}\tProductCard (HAML) props via `= expr` + `\#{interp}`: got #{props.inspect}, expected #{expected.inspect}"
      else
        puts "fail\tProductCard not found in new_components_needed"
      end

      review_card = nc_by_name["ReviewCard"]
      if review_card
        props = (review_card["suggested_props"] || []).sort
        expected = %w[author content review timestamp]
        puts "#{props == expected ? "pass" : "fail"}\tReviewCard (Slim) props via `= expr` + `\#{interp}`: got #{props.inspect}, expected #{expected.inspect}"
      else
        puts "fail\tReviewCard not found in new_components_needed"
      end

      # Regression guard: Footer (HAML with Time.current.year interpolation)
      # should STILL have zero props because Time is uppercase and doesnt
      # match the [a-z_] regex.
      footer = nc_by_name["Footer"]
      if footer
        props = footer["suggested_props"] || []
        puts "#{props.empty? ? "pass" : "fail"}\tFooter still has zero props (Time.current.year is method chain, not prop)"
      end
    '
  else
    fail "HAML+Slim retrofit-plan did not produce retrofit-plan.json"
  fi

  # --- phlexed-style-scan ---
  subsection "phlexed-style-scan"
  local style_check
  style_check=$(cd "$SAMPLE" && ruby "$BIN/phlexed-style-scan" --project . --check 2>&1)
  if text_matches "$style_check" "design_system:[[:space:]]*daisyui"; then
    pass "--check detects daisyui"
  else
    fail "expected daisyui, got: $(echo "$style_check" | tr '\n' ' ')"
  fi
  if text_matches "$style_check" "version:[[:space:]]*4.12.10"; then
    pass "--check detects daisyui version 4.12.10"
  else
    fail "expected version 4.12.10, got: $(echo "$style_check" | tr '\n' ' ')"
  fi
  if text_matches "$style_check" "active: phlexed-brand"; then
    pass "--check detects custom active theme 'phlexed-brand'"
  else
    fail "expected active: phlexed-brand, got: $(echo "$style_check" | tr '\n' ' ')"
  fi

  # --- generic adapter against sample ---
  subsection "generic adapter"
  ruby "$ADAPTERS/generic.rb" "$SAMPLE" "$WORKDIR/generic-registry.json" >/dev/null 2>&1
  if [ -f "$WORKDIR/generic-registry.json" ]; then
    pass "writes registry JSON"
    run_ruby_checks "$WORKDIR/generic-registry.json" '
      comps = r["components"] || []
      names = comps.map { |c| c["name"] }
      puts "#{comps.size >= 2 ? "pass" : "fail"}\tfinds 2+ components in sample (got #{comps.size}: #{names})"
      base = comps.find { |c| c["name"] == "Base" }
      puts "#{base ? "pass" : "fail"}\tfinds Views::Base (direct Phlex::HTML subclass)"
      showview = comps.find { |c| c["name"] == "ShowView" }
      puts "#{showview ? "pass" : "fail"}\tfinds Profile::ShowView (transitive via Views::Base — bug fix #9)"
      if showview
        puts "#{showview["props"].include?("user") ? "pass" : "fail"}\tShowView extracts user prop from initialize"
      end
    '
  else
    fail "generic adapter did not produce output"
  fi

  # --- generic adapter incremental --append mode (v0.2) ---
  # Exercises the incremental rebuild path that /phlexed-component should
  # eventually call after creating a new Phlex class. Four distinct scenarios:
  #   1. Append to a flat v0.1 registry — new component lands, count +1
  #   2. Re-append the same file — idempotent (count stays the same)
  #   3. Append to a merged v0.2 registry with a library-colliding name —
  #      conflict flag set, local_components metadata updated
  #   4. Non-Phlex file rejected with exit 1
  subsection "generic adapter --append (v0.2)"

  local append_project="$WORKDIR/append-project"
  mkdir -p "$append_project/app/components" "$append_project/.phlexed"

  # Scenario 1: flat v0.1 registry, empty, append one component
  cat > "$append_project/.phlexed/registry.json" <<'JSON'
{
  "library": "custom",
  "version": "0.0.0",
  "generated_at": "2026-04-10T00:00:00Z",
  "component_count": 0,
  "components": [],
  "patterns": {}
}
JSON
  cat > "$append_project/app/components/user_avatar.rb" <<'RB'
module MyApp
  class UserAvatar < Phlex::HTML
    def initialize(user:, size: :md)
      @user = user
      @size = size
    end
  end
end
RB

  ruby "$ADAPTERS/generic.rb" "$append_project" --append "$append_project/app/components/user_avatar.rb" >/dev/null 2>&1
  run_ruby_checks "$append_project/.phlexed/registry.json" '
    comps = r["components"] || []
    puts "#{comps.size == 1 ? "pass" : "fail"}\tappend to flat registry grows count by 1 (got #{comps.size})"
    c = comps.first
    if c
      puts "#{c["name"] == "UserAvatar" ? "pass" : "fail"}\tappended component has correct name (got #{c["name"]})"
      puts "#{c["source"] == "local" ? "pass" : "fail"}\tappended component tagged source=local (got #{c["source"]})"
      puts "#{c["props"] && c["props"].include?("user") ? "pass" : "fail"}\tappended component extracts props (got #{c["props"]})"
      puts "#{c["file"] && c["file"].include?("user_avatar.rb") ? "pass" : "fail"}\tappended component records file path"
    else
      puts "fail\tappended component missing"
    end
  '

  # Scenario 2: re-append the same file — idempotent dedup
  ruby "$ADAPTERS/generic.rb" "$append_project" --append "$append_project/app/components/user_avatar.rb" >/dev/null 2>&1
  run_ruby_checks "$append_project/.phlexed/registry.json" '
    comps = r["components"] || []
    puts "#{comps.size == 1 ? "pass" : "fail"}\tre-append same file is idempotent (still 1 component, got #{comps.size})"
  '

  # Scenario 3: merged v0.2 registry with a library Card — append a local
  # Card that should get flagged as a conflict, and local_components metadata
  # should update.
  cat > "$append_project/.phlexed/registry.json" <<'JSON'
{
  "library": "phlexy_ui",
  "version": "0.3.1",
  "generated_at": "2026-04-10T00:00:00Z",
  "component_count": 1,
  "has_local_components": false,
  "local_components": {"count": 0, "conflicts": 0},
  "components": [
    {"name": "Card", "class": "PhlexyUI::Card", "variants": ["bordered"], "source": "library"}
  ]
}
JSON
  cat > "$append_project/app/components/card.rb" <<'RB'
module MyApp
  class Card < Phlex::HTML
    def initialize(title:)
      @title = title
    end
  end
end
RB
  ruby "$ADAPTERS/generic.rb" "$append_project" --append "$append_project/app/components/card.rb" >/dev/null 2>&1

  run_ruby_checks "$append_project/.phlexed/registry.json" '
    comps = r["components"] || []
    puts "#{comps.size == 2 ? "pass" : "fail"}\tappend to merged registry grows count to 2 (got #{comps.size})"
    puts "#{r["has_local_components"] == true ? "pass" : "fail"}\tappend updates has_local_components flag"
    meta = r["local_components"] || {}
    puts "#{meta["count"] == 1 ? "pass" : "fail"}\tappend updates local_components.count to 1 (got #{meta["count"]})"
    puts "#{meta["conflicts"] == 1 ? "pass" : "fail"}\tappend updates local_components.conflicts to 1 (got #{meta["conflicts"]})"
    local_card = comps.find { |c| c["source"] == "local" && c["name"] == "Card" }
    puts "#{local_card && local_card["conflict"] == true ? "pass" : "fail"}\tappended local Card flagged as library conflict"
    library_card = comps.find { |c| c["source"] == "library" && c["name"] == "Card" }
    puts "#{library_card && !library_card["conflict"] ? "pass" : "fail"}\tlibrary Card not flagged (library wins)"
  '

  # Scenario 4: non-Phlex file should be rejected with exit 1
  cat > "$append_project/not_phlex.rb" <<'RB'
class JustAPlainRubyClass
  def hello; "not a phlex view"; end
end
RB
  set +e
  ruby "$ADAPTERS/generic.rb" "$append_project" --append "$append_project/not_phlex.rb" >/dev/null 2>&1
  local reject_exit=$?
  set -e
  if [ "$reject_exit" -ne 0 ]; then
    pass "non-Phlex file rejected with exit $reject_exit"
  else
    fail "non-Phlex file unexpectedly accepted (exit 0)"
  fi

  # --- phlexed-render-cursorrules ---
  # Build synthetic registries in the workdir so we don't touch sample/.phlexed,
  # then run the renderer against that workdir-as-project-root. Verifies the
  # full render pipeline: load registries, format components, inject markers,
  # write output, handle idempotent re-run against an existing file with markers.
  subsection "phlexed-render-cursorrules"

  local cr_project="$WORKDIR/cr-project"
  mkdir -p "$cr_project/.phlexed"

  # Synthetic registry with enough components to exercise variant/size/subcomponent
  # formatting paths. Keep it tiny — we're testing the renderer, not the registry builder.
  cat > "$cr_project/.phlexed/registry.json" <<'JSON'
{
  "library": "phlexy_ui",
  "version": "0.3.1",
  "generated_at": "2026-04-10T00:00:00Z",
  "component_count": 3,
  "components": [
    {"name": "Button", "variants": ["primary", "secondary", "ghost"], "sizes": ["sm", "md", "lg"], "example": "render PhlexyUI::Button.new(variant: :primary) { \"Click\" }"},
    {"name": "Card",   "variants": ["bordered", "compact"],           "sizes": [],                   "example": "render PhlexyUI::Card.new(bordered: true)"},
    {"name": "Avatar", "variants": [],                                "sizes": [],                   "example": "render PhlexyUI::Avatar.new"}
  ]
}
JSON

  cat > "$cr_project/.phlexed/style-registry.json" <<'JSON'
{
  "design_system": "daisyui",
  "version": "4.12.10",
  "themes": {"active": "dark", "available": ["light", "dark", "cupcake"]},
  "anti_patterns": [
    "NEVER hardcode hex colors — use semantic tokens.",
    "NEVER inline style attributes on Phlex components.",
    "NEVER create custom CSS when DaisyUI classes exist."
  ]
}
JSON

  ruby "$BIN/phlexed-render-cursorrules" --project "$cr_project" >/dev/null 2>&1
  if [ -f "$cr_project/.cursorrules" ]; then
    pass "writes .cursorrules to project root"
  else
    fail "phlexed-render-cursorrules did not produce .cursorrules"
  fi

  local cr_content
  cr_content=$(cat "$cr_project/.cursorrules" 2>/dev/null || echo "")

  if text_matches "$cr_content" "^# phlexed BEGIN$"; then
    pass ".cursorrules contains BEGIN marker"
  else
    fail ".cursorrules missing BEGIN marker"
  fi

  if text_matches "$cr_content" "^# phlexed END$"; then
    pass ".cursorrules contains END marker"
  else
    fail ".cursorrules missing END marker"
  fi

  if text_matches_e "$cr_content" "Library: phlexy_ui v0\.3\.1"; then
    pass ".cursorrules reports library name + version"
  else
    fail ".cursorrules missing 'Library: phlexy_ui v0.3.1' line"
  fi

  if text_matches_e "$cr_content" "^- Button \(variants:.*primary"; then
    pass ".cursorrules formats Button component line correctly"
  else
    fail ".cursorrules Button line malformed (found: $(first_matching_line "$cr_content" "Button"))"
  fi

  if text_matches "$cr_content" "daisyui v4.12.10"; then
    pass ".cursorrules includes design system + version"
  else
    fail ".cursorrules missing design system info"
  fi

  if text_matches "$cr_content" "Active theme: .dark."; then
    pass ".cursorrules reports active theme"
  else
    fail ".cursorrules missing active theme info"
  fi

  if text_matches "$cr_content" "NEVER hardcode hex colors"; then
    pass ".cursorrules includes anti-patterns from style registry"
  else
    fail ".cursorrules missing anti-patterns section"
  fi

  # Idempotent re-inject: prepend user content, re-run, verify user content survives
  # and we still have exactly one BEGIN/END pair.
  {
    echo "# USER PROJECT RULES (must survive re-run)"
    cat "$cr_project/.cursorrules"
  } > "$cr_project/.cursorrules.tmp"
  mv "$cr_project/.cursorrules.tmp" "$cr_project/.cursorrules"

  ruby "$BIN/phlexed-render-cursorrules" --project "$cr_project" >/dev/null 2>&1

  if head -1 "$cr_project/.cursorrules" | grep -q "USER PROJECT RULES"; then
    pass "user content above markers preserved on re-run"
  else
    fail "user content above markers lost on re-run"
  fi

  local begin_count end_count
  begin_count=$(grep -c "^# phlexed BEGIN$" "$cr_project/.cursorrules")
  end_count=$(grep -c "^# phlexed END$" "$cr_project/.cursorrules")
  if [ "$begin_count" = "1" ] && [ "$end_count" = "1" ]; then
    pass "re-run produces exactly 1 BEGIN/END pair (idempotent)"
  else
    fail "re-run left $begin_count BEGIN markers, $end_count END markers (expected 1 each)"
  fi

  # --check mode should print to stdout without touching the file
  local before_mtime after_mtime
  before_mtime=$(file_mtime "$cr_project/.cursorrules")
  local check_output
  check_output=$(ruby "$BIN/phlexed-render-cursorrules" --project "$cr_project" --check 2>&1)
  after_mtime=$(file_mtime "$cr_project/.cursorrules")
  if [ "$before_mtime" = "$after_mtime" ]; then
    pass "--check does not modify the file"
  else
    fail "--check modified the file (mtime changed $before_mtime → $after_mtime)"
  fi
  if text_matches "$check_output" "^# phlexed BEGIN$"; then
    pass "--check prints rendered output to stdout"
  else
    fail "--check output missing BEGIN marker"
  fi

  # --- phlexed-render-cursorrules source-field partitioning (v0.2) ---
  # Now that registries have a `source` field (library vs local) from the
  # merge step, the cursorrules renderer partitions the component listing
  # into two sub-sections and flags name conflicts inline. These tests cover
  # the new partitioning path — the earlier tests cover the flat/backward-
  # compat path (registry without source tags).
  local cr_merged_project="$WORKDIR/cr-merged-project"
  mkdir -p "$cr_merged_project/.phlexed"

  # Synthetic merged registry: 2 library + 2 local, one conflict
  cat > "$cr_merged_project/.phlexed/registry.json" <<'JSON'
{
  "library": "phlexy_ui",
  "version": "0.3.1",
  "generated_at": "2026-04-10T00:00:00Z",
  "component_count": 4,
  "has_local_components": true,
  "local_components": {"count": 2, "conflicts": 1},
  "components": [
    {"name": "Button", "variants": ["primary", "ghost"], "sizes": ["sm", "md"], "source": "library"},
    {"name": "Card",   "variants": ["bordered"],          "sizes": [],          "source": "library"},
    {"name": "Card",   "variants": [],                    "sizes": [],          "source": "local", "conflict": true, "file": "app/components/card.rb"},
    {"name": "UserBadge", "variants": [],                 "sizes": [],          "source": "local", "file": "app/components/user_badge.rb"}
  ]
}
JSON

  ruby "$BIN/phlexed-render-cursorrules" --project "$cr_merged_project" >/dev/null 2>&1
  local merged_content
  merged_content=$(cat "$cr_merged_project/.cursorrules" 2>/dev/null || echo "")

  if text_matches "$merged_content" "^### From library (phlexy_ui)$"; then
    pass "partitioned listing has 'From library' sub-heading"
  else
    fail "missing 'From library' sub-heading in merged-registry output"
  fi

  if text_matches "$merged_content" "^### Project-local"; then
    pass "partitioned listing has 'Project-local' sub-heading"
  else
    fail "missing 'Project-local' sub-heading in merged-registry output"
  fi

  if text_matches "$merged_content" "(2 from library, 2 project-local)"; then
    pass "summary line shows library/local counts"
  else
    fail "summary line missing library/local count breakdown"
  fi

  if text_matches "$merged_content" "1 component conflict with library names"; then
    pass "project-local section shows conflict count callout"
  else
    fail "project-local conflict count callout missing"
  fi

  # Inline conflict warning on the colliding Card
  if text_matches_e "$merged_content" "^- Card.*⚠.*name conflict"; then
    pass "conflicting Card component has inline ⚠ warning"
  else
    fail "conflicting Card missing inline warning (found: $(first_matching_line_e "$merged_content" "^- Card"))"
  fi

  # Non-conflicting UserBadge should NOT have a warning
  if text_matches_e "$merged_content" "^- UserBadge$"; then
    pass "non-conflicting UserBadge has no warning"
  else
    fail "UserBadge line missing or incorrectly has a warning (found: $(first_matching_line_e "$merged_content" "^- UserBadge"))"
  fi

  # Library components should NOT get warnings even if one of them shares a
  # name with a local component (the library one is canonical).
  library_button_line=$(awk '/^### From library/,/^### Project-local/' <<< "$merged_content" | grep -E "^- Button" || true)
  if text_matches "$library_button_line" "⚠"; then
    fail "library Button incorrectly has a conflict warning"
  else
    pass "library Button has no warning (library wins in conflicts)"
  fi

  # --- phlexed-registry merged multi-adapter (v0.2) ---
  # Exercises the full phlexed-registry pipeline end-to-end including the
  # merge step. Needs `bundle show phlexy_ui` to resolve a gem path, which we
  # don't have in CI — so we stub it with a fake bundle in PATH that returns
  # a synthetic "phlexy_ui-like" directory. The synthetic dir has just enough
  # structure for the phlexy_ui adapter to produce a valid registry
  # (lib/phlexy_ui/*.rb with a couple of Base subclasses + a version.rb).
  subsection "phlexed-registry merged multi-adapter (v0.2)"

  local merge_project="$WORKDIR/merge-project"
  local fake_gem="$WORKDIR/fake-phlexy-gem"
  local fake_bin="$WORKDIR/fake-bin"

  # Build a minimal fake phlexy_ui gem source that the adapter can parse.
  # Two components + a version.rb. Using the same register_modifiers DSL the
  # real gem uses so the adapter's parsers actually exercise their real paths.
  mkdir -p "$fake_gem/lib/phlexy_ui"
  cat > "$fake_gem/lib/phlexy_ui/version.rb" <<'RB'
module PhlexyUI
  VERSION = "9.9.9"
end
RB
  cat > "$fake_gem/lib/phlexy_ui/button.rb" <<'RB'
module PhlexyUI
  class Button < Base
    def initialize(*, as: :button, **)
      super(*, **)
      @as = as
    end

    def view_template(&)
      generate_classes!(component_html_class: :btn, modifiers_map: modifiers)
    end

    register_modifiers(primary: "btn-primary", ghost: "btn-ghost", lg: "btn-lg", sm: "btn-sm")
  end
end
RB
  cat > "$fake_gem/lib/phlexy_ui/card.rb" <<'RB'
module PhlexyUI
  class Card < Base
    def initialize(*, as: :div, **)
      super(*, **)
      @as = as
    end

    def view_template(&)
      generate_classes!(component_html_class: :card, modifiers_map: modifiers)
    end

    register_modifiers(bordered: "card-bordered")
  end
end
RB
  cat > "$fake_gem/phlexy_ui.gemspec" <<'RB'
Gem::Specification.new do |s|
  s.name = "phlexy_ui"
  s.version = PhlexyUI::VERSION
end
RB

  # Build a fake `bundle` binary that only responds to `bundle show phlexy_ui`
  # and returns the fake gem path. Prepended to PATH when invoking phlexed-registry.
  mkdir -p "$fake_bin"
  cat > "$fake_bin/bundle" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "show" ] && [ "\$2" = "phlexy_ui" ]; then
  echo "$fake_gem"
  exit 0
fi
echo "fake-bundle: unsupported: \$*" >&2
exit 1
EOF
  chmod +x "$fake_bin/bundle"

  # Build a project with a Gemfile.lock referencing phlexy_ui + 2 local Phlex
  # components (one of which conflicts with the library's Button). This is the
  # minimal setup that exercises library detection, library adapter, local
  # adapter scan, merge, source tagging, and conflict detection.
  mkdir -p "$merge_project/app/components"
  cat > "$merge_project/Gemfile.lock" <<'LOCK'
GEM
  remote: https://rubygems.org/
  specs:
    phlex-rails (1.2.0)
    phlexy_ui (9.9.9)
      phlex (>= 2.0.0)

DEPENDENCIES
  phlex-rails
  phlexy_ui
LOCK
  cat > "$merge_project/app/components/card.rb" <<'RB'
module MyApp
  class Card < Phlex::HTML
    def initialize(title:)
      @title = title
    end

    def view_template
      div(class: "my-card") { h2 { @title } }
    end
  end
end
RB
  cat > "$merge_project/app/components/user_badge.rb" <<'RB'
module MyApp
  class UserBadge < Phlex::HTML
    def initialize(user:)
      @user = user
    end

    def view_template
      span(class: "user-badge") { @user.name }
    end
  end
end
RB

  # Run the full phlexed-registry pipeline with the fake bundle in PATH.
  (cd "$merge_project" && PATH="$fake_bin:$PATH" "$BIN/phlexed-registry" >/dev/null 2>&1)

  if [ -f "$merge_project/.phlexed/registry.json" ]; then
    pass "phlexed-registry writes merged .phlexed/registry.json"
  else
    fail "phlexed-registry did not produce registry.json"
  fi

  run_ruby_checks "$merge_project/.phlexed/registry.json" '
    comps = r["components"] || []
    lib_comps = comps.select { |c| c["source"] == "library" }
    loc_comps = comps.select { |c| c["source"] == "local" }
    untagged = comps.reject { |c| c["source"] }

    puts "#{r["library"] == "phlexy_ui" ? "pass" : "fail"}\tprimary library is phlexy_ui (got #{r["library"]})"
    puts "#{r["version"] == "9.9.9" ? "pass" : "fail"}\tlibrary version parsed from fake version.rb (got #{r["version"]})"
    puts "#{r["has_local_components"] == true ? "pass" : "fail"}\thas_local_components flag set to true"
    puts "#{lib_comps.size == 2 ? "pass" : "fail"}\t2 library components tagged source=library (got #{lib_comps.size})"
    puts "#{loc_comps.size == 2 ? "pass" : "fail"}\t2 local components tagged source=local (got #{loc_comps.size})"
    puts "#{untagged.empty? ? "pass" : "fail"}\tevery component has a source tag (#{untagged.size} untagged)"

    local_meta = r["local_components"] || {}
    puts "#{local_meta["count"] == 2 ? "pass" : "fail"}\tlocal_components.count == 2 (got #{local_meta["count"]})"
    puts "#{local_meta["conflicts"] == 1 ? "pass" : "fail"}\tlocal_components.conflicts == 1 (got #{local_meta["conflicts"]})"

    card_conflict = loc_comps.find { |c| c["name"] == "Card" && c["conflict"] }
    puts "#{card_conflict ? "pass" : "fail"}\tlocal Card flagged as conflict with library Card"

    user_badge = loc_comps.find { |c| c["name"] == "UserBadge" }
    puts "#{user_badge && !user_badge["conflict"] ? "pass" : "fail"}\tlocal UserBadge exists without conflict flag"
  '

  # Verify intermediate files are cleaned up (no .registry-library.json leftover)
  if [ ! -f "$merge_project/.phlexed/.registry-library.json" ] && \
     [ ! -f "$merge_project/.phlexed/.registry-local.json" ]; then
    pass "intermediate .registry-*.json files cleaned up after merge"
  else
    fail "intermediate files leaked into .phlexed/ after merge"
  fi

  # Test --library-only mode produces consistent schema (source tags + metadata)
  # but with zero local components
  (cd "$merge_project" && PATH="$fake_bin:$PATH" "$BIN/phlexed-registry" --library-only >/dev/null 2>&1)

  run_ruby_checks "$merge_project/.phlexed/registry.json" '
    comps = r["components"] || []
    lib_comps = comps.select { |c| c["source"] == "library" }
    loc_comps = comps.select { |c| c["source"] == "local" }
    puts "#{lib_comps.size == 2 && loc_comps.empty? ? "pass" : "fail"}\t--library-only skips local scan (lib=#{lib_comps.size}, local=#{loc_comps.size})"
    puts "#{r["has_local_components"] == false ? "pass" : "fail"}\t--library-only sets has_local_components=false"
    meta = r["local_components"] || {}
    puts "#{meta["count"] == 0 ? "pass" : "fail"}\t--library-only sets local_components.count=0"
    # Still tagged for schema consistency
    untagged = comps.reject { |c| c["source"] }
    puts "#{untagged.empty? ? "pass" : "fail"}\t--library-only still tags library components (consistent schema)"
  '

  # --- skill frontmatter validation ---
  # Each of the 5 SKILL.md files must have valid YAML frontmatter with the
  # required fields: name (matching the expected slug), version (semver),
  # description (substantive — at least 100 chars so placeholder text trips
  # the check), and allowed-tools (array containing the core Claude Code
  # tool set). If frontmatter breaks, Claude Code can't load the skill.
  subsection "skill frontmatter"
  local fm_output
  fm_output=$(SKILL_ROOT="$REPO_ROOT/skill" ruby -ryaml - <<'RUBY'
EXPECTED_SKILLS = {
  "SKILL.md"                     => "phlexed-setup",
  "phlexed-build/SKILL.md"       => "phlexed-build",
  "phlexed-component/SKILL.md"   => "phlexed-component",
  "phlexed-retrofit/SKILL.md"    => "phlexed-retrofit",
  "phlexed-theme/SKILL.md"       => "phlexed-theme",
}.freeze

root = ENV.fetch("SKILL_ROOT")

# Sanity: inventory check — catches accidental addition or removal of a
# skill without updating the expected list. Limit to SKILL.md files in the
# skill dir root and immediate subdirs so we don't pick up nested fixtures.
found = Dir.glob(File.join(root, "SKILL.md")).map { |p| p.sub(root + "/", "") } +
        Dir.glob(File.join(root, "*", "SKILL.md")).map { |p| p.sub(root + "/", "") }
found.sort!
expected = EXPECTED_SKILLS.keys.sort
extras = found - expected
missing = expected - found
if extras.empty? && missing.empty?
  puts "pass\tskill inventory matches expected 5 files"
else
  puts "fail\tskill inventory drift: extras=#{extras.inspect}, missing=#{missing.inspect}"
end

EXPECTED_SKILLS.each do |rel, expected_name|
  path = File.join(root, rel)

  unless File.exist?(path)
    puts "fail\t#{rel}: file does not exist"
    next
  end

  content = File.read(path)
  unless content =~ /\A---\s*\n(.*?)\n---\s*\n/m
    puts "fail\t#{rel}: no YAML frontmatter block at top of file"
    next
  end
  fm_yaml = Regexp.last_match(1)

  begin
    fm = YAML.safe_load(fm_yaml)
  rescue => e
    puts "fail\t#{rel}: YAML parse error: #{e.class}: #{e.message}"
    next
  end

  unless fm.is_a?(Hash)
    puts "fail\t#{rel}: frontmatter parsed as #{fm.class}, expected Hash"
    next
  end

  # name must match expected slug
  if fm["name"] == expected_name
    puts "pass\t#{rel}: name == #{expected_name}"
  else
    puts "fail\t#{rel}: expected name #{expected_name.inspect}, got #{fm["name"].inspect}"
  end

  # version must be semver (major.minor.patch)
  ver = fm["version"].to_s
  if ver.match?(/\A\d+\.\d+\.\d+\z/)
    puts "pass\t#{rel}: version #{ver} is valid semver"
  else
    puts "fail\t#{rel}: version #{ver.inspect} is not semver (x.y.z)"
  end

  # description must be substantive — block scalars are valid, check length
  desc = fm["description"].to_s.strip
  if desc.length >= 100
    puts "pass\t#{rel}: description is #{desc.length} chars"
  else
    puts "fail\t#{rel}: description too short (#{desc.length} chars, need 100+)"
  end

  # allowed-tools must be an array containing at least the core tool set
  core_tools = %w[Bash Read Write Edit]
  tools = fm["allowed-tools"]
  if tools.is_a?(Array) && core_tools.all? { |t| tools.include?(t) }
    puts "pass\t#{rel}: allowed-tools includes #{core_tools.join("/")}"
  else
    puts "fail\t#{rel}: allowed-tools missing core tools (got #{tools.inspect})"
  end
end
RUBY
)
  while IFS=$'\t' read -r status msg; do
    case "$status" in
      pass) pass "$msg" ;;
      fail) fail "$msg" ;;
    esac
  done <<< "$fm_output"
}

# =============================================================================
# ONLINE TESTS — clone real upstream sources and run the library adapters.
# These tests guard the 7 bug fixes made in phlexy_ui.rb and
# shadcn_phlexcomponents.rb on 2026-04-10.
# =============================================================================
run_online_tests() {
  section "Online tests (real upstream sources)"

  # Check network + git
  if ! command -v git >/dev/null 2>&1; then
    skip "phlexy_ui adapter" "git not available"
    skip "shadcn adapter" "git not available"
    return
  fi

  # --- phlexy_ui adapter ---
  subsection "phlexy_ui adapter (real github.com/PhlexyUI/phlexy_ui)"
  if ! git clone --depth 1 --quiet https://github.com/phlexyui/phlexy_ui.git "$WORKDIR/phlexy_ui" 2>/dev/null; then
    skip "phlexy_ui adapter" "clone failed (offline or rate limited)"
  else
    ruby "$ADAPTERS/phlexy_ui.rb" "$WORKDIR/phlexy_ui" "$WORKDIR/phlexy-registry.json" >/dev/null 2>&1
    if [ -f "$WORKDIR/phlexy-registry.json" ]; then
      pass "writes registry JSON"
      run_ruby_checks "$WORKDIR/phlexy-registry.json" '
        comps = r["components"] || []
        puts "#{comps.size >= 30 ? "pass" : "fail"}\textracts 30+ components (got #{comps.size})"
        puts "#{r["version"] != "unknown" ? "pass" : "fail"}\tversion parsed from lib/phlexy_ui/version.rb (got #{r["version"].inspect}) — bug fix #1"
        btn = comps.find { |c| c["name"] == "Button" }
        if btn
          puts "#{btn["html_class"] == "btn" ? "pass" : "fail"}\tButton.html_class == \"btn\" — bug fix #2 (symbol regex)"
          puts "#{btn["example"].include?("variant: :primary") ? "pass" : "fail"}\tButton example uses :primary — bug fix #3 (semantic variant preference)"
          puts "#{btn["variants"].include?("primary") ? "pass" : "fail"}\tButton variants include primary"
          puts "#{btn["sizes"] == %w[lg md sm xs] ? "pass" : "fail"}\tButton sizes correctly split from modifiers (got #{btn["sizes"].inspect})"
        else
          puts "fail\tButton component not found"
        end
        alert = comps.find { |c| c["name"] == "Alert" }
        if alert
          puts "#{alert["html_class"] == "alert" ? "pass" : "fail"}\tAlert.html_class == \"alert\""
        end
      '
    else
      fail "phlexy_ui adapter did not produce output"
    fi
  fi

  # --- shadcn_phlexcomponents adapter ---
  subsection "shadcn adapter (real github.com/sean-yeoh/shadcn_phlexcomponents)"
  if ! git clone --depth 1 --quiet https://github.com/sean-yeoh/shadcn_phlexcomponents.git "$WORKDIR/shadcn" 2>/dev/null; then
    skip "shadcn adapter" "clone failed (offline or rate limited)"
  else
    ruby "$ADAPTERS/shadcn_phlexcomponents.rb" "$WORKDIR/shadcn" "$WORKDIR/shadcn-registry.json" >/dev/null 2>&1
    if [ -f "$WORKDIR/shadcn-registry.json" ]; then
      pass "writes registry JSON"
      run_ruby_checks "$WORKDIR/shadcn-registry.json" '
        comps = r["components"] || []
        puts "#{comps.size >= 50 ? "pass" : "fail"}\textracts 50+ components (got #{comps.size})"
        puts "#{r["version"] != "unknown" ? "pass" : "fail"}\tversion parsed (got #{r["version"].inspect})"

        btn = comps.find { |c| c["name"] == "Button" }
        if btn
          expected_variants = %w[default destructive outline secondary ghost link]
          missing = expected_variants - btn["variants"]
          puts "#{missing.empty? ? "pass" : "fail"}\tButton has all 6 expected variants (missing: #{missing}) — bug fix #4 (nested class_variants parser)"
          puts "#{btn["sizes"].include?("default") && btn["sizes"].include?("sm") ? "pass" : "fail"}\tButton extracts sizes from nested structure (got #{btn["sizes"].inspect}) — bug fix #4"
          puts "#{btn["example"].include?("variant: :default") ? "pass" : "fail"}\tButton example uses :default (shadcn canonical) — bug fix #7"
        else
          puts "fail\tButton component not found"
        end

        badge = comps.find { |c| c["name"] == "Badge" }
        if badge
          puts "#{!badge["variants"].include?("variant") ? "pass" : "fail"}\tBadge variants do NOT include literal \"variant\" key — bug fix #5"
        end

        select_c = comps.find { |c| c["name"] == "Select" }
        if select_c
          puts "#{!select_c["subcomponents"].include?("class_variants") ? "pass" : "fail"}\tSelect subcomponents exclude class_variants — bug fix #6 (blacklist)"
          puts "#{select_c["subcomponents"].include?("trigger") ? "pass" : "fail"}\tSelect has trigger subcomponent"
        end

        dialog = comps.find { |c| c["name"] == "Dialog" }
        if dialog
          expected_subs = %w[trigger content header title description]
          present = expected_subs & dialog["subcomponents"]
          puts "#{present.size == expected_subs.size ? "pass" : "fail"}\tDialog has all expected subcomponents (got #{dialog["subcomponents"]})"
        end
      '
    else
      fail "shadcn adapter did not produce output"
    fi
  fi
}

# =============================================================================
# MAIN
# =============================================================================
printf "${BOLD}phlexed adapter regression tests${NC}\n"

case "$MODE" in
  all)     run_offline_tests; run_online_tests ;;
  offline) run_offline_tests ;;
  online)  run_online_tests ;;
esac

# --- Final summary ---
printf "\n${BOLD}Summary${NC}\n"
printf "  passed: ${GREEN}%d${NC}\n" "$PASSED"
printf "  failed: ${RED}%d${NC}\n" "$FAILED"

if [ "$FAILED" -gt 0 ]; then
  printf "\n${RED}FAILURES:${NC}\n"
  sed 's/^/  /' "$FAILURES_FILE"
  exit 1
fi

printf "\n${GREEN}✓ All %d checks passed${NC}\n" "$PASSED"
exit 0

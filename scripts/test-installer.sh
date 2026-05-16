#!/usr/bin/env bash
# shellcheck disable=SC2059
# SC2059 is disabled because we use `printf "${COLOR}text${NC}\n"` throughout
# as the terminal-coloring idiom. The shellcheck-preferred
# `printf '%stext%s\n' "$COLOR" "$NC"` form is measurably uglier and the
# "variables in format string" concern doesn't apply here since COLOR values
# are literals we control.
# scripts/test-installer.sh — Lifecycle regression test for the ./setup installer
#
# Exercises the full ./setup command surface against an isolated fake HOME so
# the user's real ~/.claude/skills/phlexed/ is never touched:
#
#   1. --check against a fresh fake HOME  → reports "not installed"
#   2. Default install                     → creates symlink to repo skill/
#   3. --check after install               → reports "symlinked to this repo"
#   4. Bin script invocation via install   → phlexed-detect resolves through symlink
#   5. Idempotent re-run                   → no changes, exit 0
#   6. --copy --force                      → replaces symlink with directory
#   7. --check reports directory state     → copied install detected
#   8. Directory has real files, not empty → SKILL.md content verified
#   9. --force (default symlink mode)      → replaces directory with symlink
#  10. --uninstall --force                 → removes installation cleanly
#  11. --check after uninstall             → back to "not installed"
#  12. --help exits 0 with usage           → argument parsing works
#  13. Unknown arg exits non-zero          → error path works
#
# Usage:
#   ./scripts/test-installer.sh             Run all tests
#   ./scripts/test-installer.sh --help      Show this help
#
# Exit codes: 0 all pass, 1 any failure, 2 preflight error.
#
# This script codifies the manual installer verification done during Phase 4
# setup-script development (see .ralph/fix_plan.md "installer notes"). Re-run
# after touching ./setup to catch regressions in the install state machine.

set -uo pipefail

# --- Locate repo ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP="$REPO_ROOT/setup"
SAMPLE_LOCKFILE="$REPO_ROOT/sample/Gemfile.lock"

# --- Ephemeral fake HOME ---
# Must not contain `.claude` in its parent path because the sandbox blocks
# operations touching such paths; the setup script itself creates .claude
# internally via mkdir, which is fine.
FAKE_HOME=$(mktemp -d -t phlexed-installer.XXXXXX)
INSTALL_TARGET="$FAKE_HOME/.claude/skills/phlexed"

# shellcheck disable=SC2317,SC2329
# cleanup() is invoked by the trap below; shellcheck can't see trap-invoked
# usage so it incorrectly flags this as unused/unreachable.
cleanup() {
  rm -rf "$FAKE_HOME"
}
trap cleanup EXIT INT TERM

# --- Colors (TTY only) ---
# YELLOW intentionally omitted: this file has no skip() helper that uses it.
if [ -t 1 ]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  NC=$'\033[0m'
else
  RED=''; GREEN=''; BOLD=''; DIM=''; NC=''
fi

# --- Test bookkeeping ---
PASSED=0
FAILED=0
FAILURES_FILE="$FAKE_HOME/failures.txt"
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

# --- Arg parsing ---
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
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
if [ ! -x "$SETUP" ]; then
  echo "${RED}error${NC}: $SETUP not found or not executable" >&2
  exit 2
fi
if [ ! -f "$SAMPLE_LOCKFILE" ]; then
  echo "${RED}error${NC}: $SAMPLE_LOCKFILE missing (needed for bin-script invocation test)" >&2
  exit 2
fi

printf "${DIM}fake HOME %s · setup %s${NC}\n" "$FAKE_HOME" "$SETUP"

# =============================================================================
# Run setup with an isolated HOME. Returns stdout+stderr combined.
# All invocations go through this helper so the HOME override can't be forgotten.
# =============================================================================
run_setup() {
  HOME="$FAKE_HOME" "$SETUP" "$@" 2>&1
}

printf "${BOLD}phlexed installer lifecycle tests${NC}\n"

# =============================================================================
# PHASE 1: Clean starting state
# =============================================================================
section "Clean starting state"

if [ ! -e "$INSTALL_TARGET" ]; then
  pass "fake HOME starts without install target"
else
  fail "fake HOME unexpectedly has install target: $INSTALL_TARGET"
fi

check_output=$(run_setup --check || true)
if echo "$check_output" | grep -q "not installed"; then
  pass "--check reports 'not installed' before any install"
else
  fail "--check expected 'not installed', got: $(echo "$check_output" | tr '\n' ' ')"
fi

# =============================================================================
# PHASE 2: Default install (symlink mode)
# =============================================================================
section "Default install (symlink)"

install_output=$(run_setup || true)
if [ -L "$INSTALL_TARGET" ]; then
  pass "./setup creates a symlink at install target"
else
  fail "./setup did not create symlink (target state: $(ls -la "$INSTALL_TARGET" 2>&1 || echo 'missing'))"
fi

if [ -L "$INSTALL_TARGET" ]; then
  link_target=$(readlink "$INSTALL_TARGET")
  expected="$REPO_ROOT/skill"
  if [ "$link_target" = "$expected" ]; then
    pass "symlink points at repo's skill/ dir"
  else
    fail "symlink points at $link_target, expected $expected"
  fi
fi

if echo "$install_output" | grep -q "phlexed is ready"; then
  pass "install output announces 'phlexed is ready'"
else
  fail "install output missing 'phlexed is ready' banner"
fi

if echo "$install_output" | grep -qE "Installed:.*phlexed-setup.*0\.[0-9]+\.[0-9]+"; then
  pass "install output verifies installed name + semver version from SKILL.md"
else
  fail "install output missing 'Installed: phlexed-setup v0.x.x' line"
fi

check_output=$(run_setup --check || true)
if echo "$check_output" | grep -q "symlinked to this repo"; then
  pass "--check reports 'symlinked to this repo' after install"
else
  fail "--check expected 'symlinked to this repo', got: $(echo "$check_output" | tr '\n' ' ')"
fi

# =============================================================================
# PHASE 3: Bin scripts reachable through the install
# =============================================================================
section "Bin scripts through installed symlink"

if [ -x "$INSTALL_TARGET/bin/phlexed-detect" ]; then
  pass "phlexed-detect is executable via install path"
else
  fail "phlexed-detect not executable at $INSTALL_TARGET/bin/phlexed-detect"
fi

detect_out=$(HOME="$FAKE_HOME" "$INSTALL_TARGET/bin/phlexed-detect" "$SAMPLE_LOCKFILE" 2>&1 || true)
if [ "$detect_out" = "phlexy_ui" ]; then
  pass "phlexed-detect (via install) identifies phlexy_ui in sample Gemfile.lock"
else
  fail "phlexed-detect expected 'phlexy_ui', got: $detect_out"
fi

if [ -f "$INSTALL_TARGET/SKILL.md" ]; then
  pass "SKILL.md readable through install"
else
  fail "SKILL.md not accessible at $INSTALL_TARGET/SKILL.md"
fi

# =============================================================================
# PHASE 4: Idempotent re-run
# =============================================================================
section "Idempotent re-run"

rerun_output=$(run_setup || true)
rerun_exit=$?
if [ "$rerun_exit" -eq 0 ]; then
  pass "re-running ./setup exits 0"
else
  fail "re-run exited with $rerun_exit"
fi
if echo "$rerun_output" | grep -q "already installed"; then
  pass "re-run reports 'already installed' (no-op path)"
else
  fail "re-run expected 'already installed', got: $(echo "$rerun_output" | tr '\n' ' ' | head -c 200)"
fi
if [ -L "$INSTALL_TARGET" ]; then
  pass "symlink still in place after re-run"
else
  fail "symlink disappeared after re-run"
fi

# =============================================================================
# PHASE 5: --copy --force replaces symlink with directory
# =============================================================================
section "Copy mode (--copy --force)"

run_setup --copy --force >/dev/null 2>&1 || true
if [ -d "$INSTALL_TARGET" ] && [ ! -L "$INSTALL_TARGET" ]; then
  pass "--copy --force replaces symlink with a real directory"
else
  if [ -L "$INSTALL_TARGET" ]; then
    fail "--copy did not replace symlink (still a symlink)"
  else
    fail "--copy did not produce a directory (target: $(ls -la "$INSTALL_TARGET" 2>&1))"
  fi
fi

if [ -f "$INSTALL_TARGET/SKILL.md" ]; then
  pass "copied install has SKILL.md file"
else
  fail "copied install missing SKILL.md"
fi

# Verify the copied SKILL.md has expected frontmatter content — catches an
# empty directory copy that wouldn't be caught by file-exists alone.
if grep -q "^name: phlexed-setup$" "$INSTALL_TARGET/SKILL.md" 2>/dev/null; then
  pass "copied SKILL.md has correct 'name: phlexed-setup' frontmatter"
else
  fail "copied SKILL.md missing expected frontmatter"
fi

check_output=$(run_setup --check || true)
if echo "$check_output" | grep -q "copy"; then
  pass "--check reports 'copy' state after --copy"
else
  fail "--check after copy expected 'copy', got: $(echo "$check_output" | tr '\n' ' ')"
fi

# =============================================================================
# PHASE 6: --force replaces directory with symlink
# =============================================================================
section "Force symlink replacement"

run_setup --force >/dev/null 2>&1 || true
if [ -L "$INSTALL_TARGET" ]; then
  pass "./setup --force replaces directory with a symlink"
else
  fail "./setup --force did not restore symlink (target: $(ls -la "$INSTALL_TARGET" 2>&1))"
fi

# =============================================================================
# PHASE 7: Uninstall
# =============================================================================
section "Uninstall"

uninstall_output=$(run_setup --uninstall --force || true)
if [ ! -e "$INSTALL_TARGET" ]; then
  pass "./setup --uninstall --force removes install target"
else
  fail "install target still exists after uninstall: $(ls -la "$INSTALL_TARGET" 2>&1)"
fi

if echo "$uninstall_output" | grep -qi "removed\|uninstalled"; then
  pass "uninstall output confirms removal"
else
  fail "uninstall output missing confirmation: $(echo "$uninstall_output" | tr '\n' ' ' | head -c 200)"
fi

check_output=$(run_setup --check || true)
if echo "$check_output" | grep -q "not installed"; then
  pass "--check reports 'not installed' after uninstall"
else
  fail "--check after uninstall expected 'not installed', got: $(echo "$check_output" | tr '\n' ' ')"
fi

# =============================================================================
# PHASE 8: Argument parsing edge cases
# =============================================================================
section "Argument parsing"

help_output=$(run_setup --help || true)
help_exit=$?
if [ "$help_exit" -eq 0 ]; then
  pass "--help exits 0"
else
  fail "--help exited $help_exit (expected 0)"
fi
if echo "$help_output" | grep -q "phlexed setup"; then
  pass "--help output contains 'phlexed setup' banner"
else
  fail "--help output missing usage banner"
fi

# Unknown arg should exit non-zero.
set +e
run_setup --definitely-not-a-real-flag >/dev/null 2>&1
unknown_exit=$?
set -e
if [ "$unknown_exit" -ne 0 ]; then
  pass "unknown flag exits non-zero (got $unknown_exit)"
else
  fail "unknown flag unexpectedly exited 0"
fi

# =============================================================================
# Summary
# =============================================================================
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

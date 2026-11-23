#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
mkdir -p "$HOME"
# shellcheck source=../install.sh
source "$ROOT_DIR/install.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

MOCK_SRCINFO=""
makepkg() {
  [[ ${1:-} == --printsrcinfo ]] || return 2
  cat "$MOCK_SRCINFO"
}

pacman() {
  case ${1:-} in
    -T)
      case ${2:-} in
        glibc) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    -Si)
      case ${2:-} in
        cmake|gtest) printf 'Version : 1.2-1\n'; return 0 ;;
        badver) printf 'Version : 1.0-1\n'; return 0 ;;
        *) return 1 ;;
      esac
      ;;
    -Qi)
      case ${2:-} in
        dependent-too-new)
          printf 'Name : dependent-too-new\nDepends On : hyprland>=0.55.0\nRequired By : None\n'
          ;;
        dependent-compatible)
          printf 'Name : dependent-compatible\nDepends On : hyprland>=0.54.0\nRequired By : None\n'
          ;;
        dependent-current-too-new)
          printf 'Name : dependent-current-too-new\nDepends On : hyprland<0.55.0\nRequired By : None\n'
          ;;
        *) return 1 ;;
      esac
      ;;
    *) return 2 ;;
  esac
}

fc-match() { printf 'Space Grotesk\n'; }
aur_provided() { [[ ${1:-} == songrec ]]; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
target_pin_version() { printf '%s' '0.54.3-4'; }
vercmp() {
  if [[ $1 == 0.54.3-4 && $2 == 0.55.0 ]]; then
    printf '%s' -1
  elif [[ $1 == 0.54.3-4 && $2 == 0.54.0 ]]; then
    printf '%s' 1
  elif [[ $1 == 1.2-1 && $2 == 1.0 ]]; then
    printf '%s' 1
  elif [[ $1 == 1.2-1 && $2 == 2.0 ]]; then
    printf '%s' -1
  elif [[ $1 == 1.0-1 && $2 == 2.0 ]]; then
    printf '%s' -1
  elif [[ $1 == 0.50.0-1 && $2 == 0.54.3 ]]; then
    printf '%s' -1
  elif [[ $1 == 0.56.0-1 && $2 == 0.55.0 ]]; then
    printf '%s' 1
  else
    printf '%s' 0
  fi
}

mkdir -p "$TEST_DIR/pkg"

# .SRCINFO properties are indented; required dependencies are parsed, optional ones ignored.
cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = glibc
    makedepends_x86_64 = cmake>=1.0
    checkdepends = gtest<2.0
    optdepends = optional-not-installed
SRC
MOCK_SRCINFO="$TEST_DIR/srcinfo"
export MOCK_SRCINFO
check_aur_dependencies "$TEST_DIR/pkg" fixture || fail "repo dependency preflight rejected available dependencies"
pass "indented .SRCINFO and repository dependencies"
dependency_version_satisfied "cmake>=1.0" "1.2-1" || fail "satisfied repository version constraint was rejected"
if dependency_version_satisfied "cmake>=2.0" "1.2-1"; then
  fail "unsatisfied repository version constraint was accepted"
fi
pass "repository version constraints"

# AUR dependencies not already installed must be reported before makepkg -s.
cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = songrec
SRC
if check_aur_dependencies "$TEST_DIR/pkg" fixture 3>&1 >/dev/null 2>&1; then
  fail "missing pinned AUR dependency was accepted"
fi
pass "missing AUR dependency is rejected"

# AUR makepkg must never fetch a Hyprland package from the unpinned sync repos.
cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = hyprland>=0.54.3
SRC
if check_aur_dependencies "$TEST_DIR/pkg" fixture 3>&1 >/dev/null 2>&1; then
  fail "unpinned Hyprland repository dependency was accepted"
fi
pass "unpinned Hyprland dependency is rejected"

# Even an installed pinned package must satisfy the version constraint.
pkg_installed() { [[ $1 == hyprland ]]; }
pkg_version() { printf '%s' '0.50.0-1'; }
cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = hyprland>=0.54.3
SRC
if check_aur_dependencies "$TEST_DIR/pkg" fixture 3>&1 >/dev/null 2>&1; then
  fail "incompatible installed Hyprland version was accepted"
fi
pass "installed pinned package version is checked"

# A dependency absent from configured repositories must be reported.
cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = package-not-in-repo
SRC
if check_aur_dependencies "$TEST_DIR/pkg" fixture 3>&1 >/dev/null 2>&1; then
  fail "missing repository dependency was accepted"
fi
pass "missing repository dependency is rejected"

# A repository package with an insufficient version must also be rejected.
cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = badver>=2.0
SRC
if check_aur_dependencies "$TEST_DIR/pkg" fixture 3>&1 >/dev/null 2>&1; then
  fail "insufficient repository package version was accepted"
fi
pass "insufficient repository package version is rejected"

# Space Grotesk is provided by the verified local font install, not by an AUR package.
cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = otf-space-grotesk
SRC
check_aur_dependencies "$TEST_DIR/pkg" fixture || fail "local Space Grotesk dependency was not recognized"
pass "locally installed Space Grotesk dependency"

package_requires_incompatible_pin dependent-too-new || fail "newer Hyprland constraint was missed"
pass "incompatible reverse dependency detected"
if package_requires_incompatible_pin dependent-compatible; then
  fail "compatible Hyprland constraint was incorrectly rejected"
fi
pass "compatible reverse dependency preserved"
if ! (
  pkg_installed() { [[ $1 == hyprland ]]; }
  pkg_version() { printf '%s' '0.56.0-1'; }
  package_requires_incompatible_pin dependent-current-too-new
); then
  fail "currently installed incompatible version was missed"
fi
pass "current installed version is checked before system upgrade"

# A repair run must be allowed to reach the pinned-package restoration step.
mkdir -p "$(dirname -- "$PINS_LOCK")"
: >"$PINS_LOCK"
MODE=repair
PINS_RESTORED=0
pkg_version() { printf '%s' '0.99-1'; }
expected_pin_version() { printf '%s' '0.54.3-4'; }
log() { :; }
die() { return 42; }
assert_pins_intact || fail "repair mode stopped before restoring the pinned stack"
pass "repair mode defers pin-lock validation until restoration"
PINS_RESTORED=1
if assert_pins_intact; then
  fail "pin drift was accepted after restoration"
fi
pass "pin drift is rejected after restoration"

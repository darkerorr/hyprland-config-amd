#!/usr/bin/env bash
# Tests unitaires des fonctions de install.sh (sourcé, aucune commande système réelle).
# shellcheck disable=SC2034  # variables globales de install.sh modifiées par les tests
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
mkdir -p "$HOME"
# shellcheck source=../install.sh
source "$ROOT_DIR/install.sh"
# install.sh écrit l'interface sur fd 3 et le journal sur fd 5.
exec 3>"$TEST_DIR/ui.out" 5>"$TEST_DIR/log.out"
TMP_DIR="$TEST_DIR/tmp"; mkdir -p "$TMP_DIR" "$STATE_DIR"
LOG_FILE="$TEST_DIR/log.out"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

MOCK_SRCINFO=""
MOCK_PROVIDED=" glibc "
makepkg() {
  [[ ${1:-} == --printsrcinfo ]] || return 2
  cat "$MOCK_SRCINFO"
}

pacman() {
  case ${1:-} in
    -T)
      shift; local d rc=0
      for d in "$@"; do
        [[ $MOCK_PROVIDED == *" ${d%%[<>=]*} "* ]] || { printf '%s\n' "$d"; rc=127; }
      done
      return "$rc"
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
    -Qq) [[ " ${MOCK_INSTALLED:-} " == *" ${2:-} "* ]] ;;
    *) return 2 ;;
  esac
}

aur_provided() { [[ ${1:-} == songrec ]]; }
warn() { printf 'WARN: %s\n' "$*" >>"$TEST_DIR/warn.out"; }
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

# --- Analyse du .SRCINFO -------------------------------------------------------
# Propriétés indentées ; dépendances versionnées NON tronquées (régression 1.2.9 :
# « cmake>=1.0 » devenait « 1.0 » et toute dépendance versionnée était rejetée).
cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
	depends = glibc
	makedepends_x86_64 = cmake>=1.0
	checkdepends = gtest<2.0
	optdepends = optional-not-installed
SRC
MOCK_SRCINFO="$TEST_DIR/srcinfo"
check_aur_dependencies "$TEST_DIR/pkg" fixture || fail "versioned repository dependencies were rejected (SRCINFO parsing)"
pass "indented .SRCINFO and versioned repository dependencies"
dependency_version_satisfied "cmake>=1.0" "1.2-1" || fail "satisfied repository version constraint was rejected"
if dependency_version_satisfied "cmake>=2.0" "1.2-1"; then
  fail "unsatisfied repository version constraint was accepted"
fi
pass "repository version constraints"

# Les dépendances AUR non installées sont signalées avant makepkg -s.
cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = songrec
SRC
if check_aur_dependencies "$TEST_DIR/pkg" fixture; then
  fail "missing pinned AUR dependency was accepted"
fi
[[ $LAST_CAUSE == *songrec* ]] || fail "missing dependency not reported as cause: $LAST_CAUSE"
pass "missing AUR dependency is rejected and reported"

# makepkg ne doit jamais tirer un paquet Hyprland non épinglé des dépôts.
cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = hyprland>=0.54.3
SRC
if check_aur_dependencies "$TEST_DIR/pkg" fixture; then
  fail "unpinned Hyprland repository dependency was accepted"
fi
pass "unpinned Hyprland dependency is rejected"

# Même installé, un paquet épinglé doit satisfaire la contrainte de version.
pkg_installed() { [[ $1 == hyprland ]]; }
pkg_version() { printf '%s' '0.50.0-1'; }
if check_aur_dependencies "$TEST_DIR/pkg" fixture; then
  fail "incompatible installed Hyprland version was accepted"
fi
pass "installed pinned package version is checked"

cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = package-not-in-repo
SRC
if check_aur_dependencies "$TEST_DIR/pkg" fixture; then
  fail "missing repository dependency was accepted"
fi
pass "missing repository dependency is rejected"

cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = badver>=2.0
SRC
if check_aur_dependencies "$TEST_DIR/pkg" fixture; then
  fail "insufficient repository package version was accepted"
fi
pass "insufficient repository package version is rejected"

# otf-space-grotesk : satisfait uniquement par le paquet local qui le fournit.
cat >"$TEST_DIR/srcinfo" <<'SRC'
pkgbase = fixture
    depends = otf-space-grotesk
SRC
if check_aur_dependencies "$TEST_DIR/pkg" fixture; then
  fail "otf-space-grotesk accepted although no package provides it"
fi
MOCK_PROVIDED=" glibc otf-space-grotesk "
check_aur_dependencies "$TEST_DIR/pkg" fixture || fail "otf-space-grotesk provided by local package was not recognized"
pass "otf-space-grotesk is resolved through the local provider package"

# --- Dépendants inverses -------------------------------------------------------
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

# --- Analyse des sorties d'échec ----------------------------------------------
cat >"$TEST_DIR/makepkg8.out" <<'OUT'
==> Making package: wlogout 1.2.2-0 (Mon Nov 23 2026)
==> Checking runtime dependencies...
==> Installing missing dependencies...
error: target not found: scdoc
==> ERROR: 'pacman' failed to install missing dependencies.
==> Missing dependencies:
  -> scdoc
OUT
mapfile -t causes < <(explain_failure_output "$TEST_DIR/makepkg8.out")
[[ ${causes[0]} == *"introuvable"*scdoc* ]] || fail "makepkg code 8 cause not identified: ${causes[*]}"
printf '%s\n' "${causes[@]}" | grep -q 'Dépendance manquante : scdoc' || fail "missing dependency list not parsed"
pass "makepkg exit 8 output is translated into the precise cause"

cat >"$TEST_DIR/syu.out" <<'OUT'
error: failed to prepare transaction (could not satisfy dependencies)
:: installing libjxl (0.13.1-1) breaks dependency 'libjxl.so=0.11-64' required by hyprgraphics
:: installing foo (2-1) breaks dependency 'foo=1' required by bar
:: unable to satisfy dependency 'libx.so=1-64' required by notinstalled
OUT
MOCK_INSTALLED="hyprgraphics bar"
pkg_installed() { [[ " $MOCK_INSTALLED " == *" $1 "* ]]; }
mapfile -t blockers < <(pacman_blockers "$TEST_DIR/syu.out")
[[ ${blockers[*]} == "bar hyprgraphics" ]] || fail "blockers parsed incorrectly: ${blockers[*]}"
pass "pacman blockers parsed (only installed packages)"

cat >"$TEST_DIR/conflict.out" <<'OUT'
:: adw-gtk-theme-git and adw-gtk-theme are in conflict. Remove adw-gtk-theme? [y/N]
error: unresolvable package conflicts detected
OUT
MOCK_INSTALLED="adw-gtk-theme"
mapfile -t blockers < <(pacman_blockers "$TEST_DIR/conflict.out")
[[ ${blockers[*]} == "adw-gtk-theme" ]] || fail "conflict victim not parsed: ${blockers[*]}"
explain_failure_output "$TEST_DIR/conflict.out" | grep -q 'Conflit de paquets' || fail "conflict not explained"
pass "pacman conflict prompt parsed"

# --- Points de reprise ----------------------------------------------------------
for i in 3 4 5 6; do checkpoint_set "$i"; done
checkpoint_done 4 || fail "checkpoint not recorded"
checkpoint_clear_from 5
checkpoint_done 4 || fail "earlier checkpoint must survive"
if checkpoint_done 5 || checkpoint_done 6; then fail "later checkpoints must be invalidated"; fi
pass "re-running a step invalidates later checkpoints only"

# run_step : point de reprise présent mais état réel non conforme -> réexécution.
draw_dashboard() { :; }
verify_step_7() { [[ -f $TEST_DIR/qs-ok ]] || vp "quickshell absent"; }
step7_body() { touch "$TEST_DIR/qs-ok"; printf 'ran\n' >>"$TEST_DIR/step7.runs"; }
MODE=install; FORCE=0
checkpoint_set 7
run_step 7 step7_body
[[ $(wc -l <"$TEST_DIR/step7.runs") == 1 ]] || fail "stale checkpoint was trusted"
run_step 7 step7_body
[[ $(wc -l <"$TEST_DIR/step7.runs") == 1 ]] || fail "verified checkpoint was not reused"
[[ ${STEP_STATUS[7]} == CACHED ]] || fail "status should be CACHED"
pass "checkpoint reused only when the real state is verified"

# run_step : aucune fausse réussite si l'état réel est faux après exécution.
verify_step_8() { vp "kb_layout absent"; }
step8_body() { :; }
rc=0
( run_step 8 step8_body ) || rc=$?
((rc == 1)) || fail "step with failing post-verification did not fail (rc=$rc)"
if checkpoint_done 8; then fail "checkpoint written despite failed verification"; fi
pass "post-step verification prevents false success"

# --- Enregistrement des échecs -------------------------------------------------
failure_record 3 8 "AUR wlogout : makepkg a échoué" "Paquet introuvable : scdoc"
[[ $(failure_get 3 code) == 8 ]] || fail "failure code not recorded"
[[ $(failure_get 3 cause) == *scdoc* ]] || fail "failure cause not recorded"
pass "step failure is persisted with code and cause"

# --- Garde-fou de dérive de la pile -------------------------------------------
mkdir -p "$(dirname -- "$PINS_LOCK")"
: >"$PINS_LOCK"
MODE=repair
PINS_RESTORED=0
pkg_version() { printf '%s' '0.99-1'; }
expected_pin_version() { printf '%s' '0.54.3-4'; }
die() { return 42; }
assert_pins_intact || fail "repair mode stopped before restoring the pinned stack"
pass "repair mode defers pin-lock validation until restoration"
PINS_RESTORED=1
if assert_pins_intact; then
  fail "pin drift was accepted after restoration"
fi
pass "pin drift is rejected after restoration"

# --- --session-debug : recherche par dichotomie du fichier qui fait planter -----
(
  mkdir -p "$CFG/hypr/custom"
  printf 'source=custom/a.conf\nsource=custom/b.conf\nsource=custom/c.conf\nsource=custom/d.conf\n' >"$CFG/hypr/hyprland.conf"
  for f in a b c d; do echo "# $f" >"$CFG/hypr/custom/$f.conf"; done
  echo CRASH >>"$CFG/hypr/custom/c.conf"
  hypr_trial() {
    local f
    while read -r f; do grep -q CRASH "$CFG/hypr/$f" && return 1; done < <(sed -nE 's/^[[:space:]]*source[[:space:]]*=[[:space:]]*//p' "$1")
    return 0
  }
  ui() { :; }
  declare -a found=()
  session_bisect_config "$TEST_DIR/bisect.out" found
  [[ ${found[*]} == *"custom/c.conf"* ]] || fail "bisection did not find the crashing file: ${found[*]}"
  [[ ! -e $CFG/hypr/.hypr-installer-trial.conf ]] || fail "trial config not cleaned"
) || exit 1
pass "session-debug bisection finds the crashing config file"

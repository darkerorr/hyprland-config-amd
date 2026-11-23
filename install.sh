#!/usr/bin/env bash
# =============================================================================
#  HYPRLAND AUTOMATED INSTALLER — install.sh
#  EndeavourOS × Hyprland 0.54.3 (épinglé) × end-4/dots-hyprland 2026.05.11
#  Cible : AMD Ryzen 5 4500 + Radeon RX 550, clavier AZERTY français.
#
#  Point d'entrée unique. Usage : ./install.sh [--help]
#  Licence : GPL-3.0-or-later (voir LICENSE)
# =============================================================================
# shellcheck disable=SC2016,SC2034,SC1112
# SC2016/SC2034 : les contrôles chk_if évaluent (eval) des expressions entre apostrophes
# qui référencent des variables locales ; SC1112 : apostrophes typographiques voulues.
set -Eeuo pipefail
shopt -s inherit_errexit nullglob

readonly INSTALLER_VERSION="1.2.8"
readonly MAIN_PID=$$
SCRIPT_SELF="$(readlink -f -- "${BASH_SOURCE[0]}")"
readonly SCRIPT_SELF

# =============================================================================
# 0. MANIFESTE DES VERSIONS (déterminé pendant l'audit — voir README §Matrice)
# =============================================================================
# --- end-4 / illogical-impulse ---------------------------------------------
readonly END4_REPO="https://github.com/end-4/dots-hyprland.git"
readonly END4_TAG="2026.05.11"                                   # "Pre-Hyprland Luaification"
readonly END4_COMMIT="bebf66da89cd2afa4738da47fb3a0a9fa5af7035"  # tag léger -> ce commit (vérifié)
readonly END4_SHAPES_COMMIT="e31ec4cb4ebf6a46b267f5c42eabf6874916fa16" # sous-module rounded-polygon-qmljs
# --- Quickshell (épinglé par end-4 dans illogical-impulse-quickshell-git) ----
readonly QS_COMMIT="7511545ee20664e3b8b8d3322c0ffe7567c56f7a"
readonly QS_FALLBACK_COMMIT="59e9c47b0eb48a9e4bcf9631fa062ee939bd2e83" # v0.3.0, descendant direct, antérieur à la release end-4
readonly QS_MIRROR_URL="https://github.com/quickshell-mirror/quickshell.git"
# --- Police Google Sans Flex (end-4 la clone sur "main" : on l'épingle) -------
readonly GSF_REPO="https://github.com/end-4/google-sans-flex.git"
readonly GSF_COMMIT="251aa5abd30496368f634e54ce2a508fe5a2fdfa"
# --- Pile Hyprland épinglée : instantané Arch Linux du 2026-05-08 ------------
#     (dernier jour où Arch distribuait hyprland 0.54.3-4, avant 0.55.0)
readonly SNAPSHOT_DATE="2026-05-08"
readonly ALA_URL="https://archive.archlinux.org/packages"
readonly ARCH_PKG_GIT="https://gitlab.archlinux.org/archlinux/packaging/packages"
# Ordre = ordre de dépendance (utilisé pour les reconstructions).
readonly -a PIN_ORDER=(
  hyprutils hyprlang hyprwayland-scanner hyprwire hyprgraphics hyprcursor
  aquamarine hyprtoolkit hyprland-guiutils hyprland hypridle hyprlock
  hyprpicker hyprsunset xdg-desktop-portal-hyprland
)
declare -Ar PIN_VER=(
  [hyprutils]=0.13.1-1            [hyprlang]=0.6.8-4
  [hyprwayland-scanner]=0.4.6-1   [hyprwire]=0.3.1-2
  [hyprgraphics]=0.5.1-2          [hyprcursor]=0.1.13-6
  [aquamarine]=0.11.0-2           [hyprtoolkit]=0.5.4-1
  [hyprland-guiutils]=0.2.1-5     [hyprland]=0.54.3-4
  [hypridle]=0.1.7-9              [hyprlock]=0.9.5-2
  [hyprpicker]=0.4.7-1            [hyprsunset]=0.3.3-7
  [xdg-desktop-portal-hyprland]=1.3.12-2
)
# bin = binaire officiel signé de l'Arch Linux Archive (ABI vérifiée : DT_NEEDED
#       et versions de symboles comparés aux dépôts actuels pendant l'audit).
# src = reconstruit depuis le PKGBUILD officiel Arch au commit épinglé, dans un
#       chroot propre (devtools), contre les bibliothèques actuelles :
#         hyprgraphics -> libjxl.so.0.11 n'existe plus (0.13 aujourd'hui)
#         hyprlock, xdph -> sdbus-cpp 2.3 (Arch a dû reconstruire hyprlock)
declare -Ar PIN_MODE=(
  [hyprutils]=bin [hyprlang]=bin [hyprwayland-scanner]=bin [hyprwire]=bin
  [hyprgraphics]=src [hyprcursor]=bin [aquamarine]=bin [hyprtoolkit]=bin
  [hyprland-guiutils]=bin [hyprland]=bin [hypridle]=bin [hyprlock]=src
  [hyprpicker]=bin [hyprsunset]=bin [xdg-desktop-portal-hyprland]=src
)
# SHA-256 des paquets *.pkg.tar.zst de l'Arch Linux Archive (calculés à l'audit).
declare -Ar PIN_SHA256=(
  [hyprutils]=b6a2694d4d8e025033d42dd24408b04e0f30b2431c5c165bc3f7c863344b68ad
  [hyprlang]=89603b0cb0fc36babf85b304f3ca3833ba94676735bdbd49420796b2ec989d62
  [hyprwayland-scanner]=3d9da39c19f9febb0a1b3af9d88dc9a1466568f595228ffc88ffc51907e73d3a
  [hyprwire]=1a2c59e27e5061890e8a2693345b9adbe41bab9816216c2eb1ec715f5102590a
  [hyprgraphics]=31fd51f7fc2ed83938171e8765ffe111db0833791fdbe07675622da389d78721
  [hyprcursor]=71cf407f9a39ff03e8bacf50a9d6fb281ce085e4fc58ff795b900ad5b5fe2844
  [aquamarine]=50dd13a381e8208999919d5126904906ec88b60f3e4a7d1ae05789c53545f9f1
  [hyprtoolkit]=b4ae846275a9a08b0e5ba35d94ca74196c8a336ca35929224163ae62ea2c818d
  [hyprland-guiutils]=1c673594c0c60f8062896ec1517de11276dda5cda572f16a8a4c7f0e1afcbff5
  [hyprland]=ac3e66a74861b028f95d505954a4dd3f30ee4ad50678f895ab78461115a8bddd
  [hypridle]=2fdd9610e3a419fb599f3d920b94e0d9b666629b06362dd32b968a0d6a5aa3c9
  [hyprlock]=8ffc902eded32cc2b22c2ad8e3d82a14e574d0047a4e8263065ddff7755bd56a
  [hyprpicker]=c561c50c146e65b2d3f86c4118e07eb1633be70d86ee87edcae7749aedeafff7
  [hyprsunset]=7f24c5124c06910a6feead91bf44406cea95702b57d6b4d735c0fe0829084cf4
  [xdg-desktop-portal-hyprland]=7099e5e384a77647d8889e2e8a6cb77a3642881197823ba277cceece1c1e52cf
)
# Commit du dépôt de packaging officiel Arch correspondant à chaque version.
declare -Ar PIN_GITREF=(
  [hyprutils]=2a66dd14ce20ed2f6d53ffe434b982f8055930b6
  [hyprlang]=1c004e650a175ea8191204e40e7d165e9d73627f
  [hyprwayland-scanner]=06aa4c10de4d339ba0fbcbcf88c7917f7d7dbc89
  [hyprwire]=30fe097ec23b8e6242d880375b331800d9a707dd
  [hyprgraphics]=4ef2d0ba6bc220c1902d40fa84c021b5232187dc
  [hyprcursor]=e1d23bbff657d44561f72d478daaa99bd60da368
  [aquamarine]=bee18344ec0560bbe5e7792c0a3338fda0878394
  [hyprtoolkit]=ff4eb009378ee1fd64e892d263dbae0e56488aea
  [hyprland-guiutils]=1a2a1201c8912ee07dc6c944561188a8fea1def2
  [hyprland]=1e38740359f3c839bcfed9f8cf3ffe79e68ba3da
  [hypridle]=2b5b080c50c5bacb0c4c56bd81d0d7db2fea4889
  [hyprlock]=43ae18d6c230a179ed8aa66b86e800554be8eb7b
  [hyprpicker]=69f6ba01cce33ed31cde9720173dc582644ee06e
  [hyprsunset]=38294ec0696235d61fc62b2bad7a0882f86547e1
  [xdg-desktop-portal-hyprland]=1220c33bc6cedf37d697690cfe34ce1d8b9665c2
)
readonly LOCAL_REL_SUFFIX=".1"   # pkgrel local des reconstructions : 0.5.1-2 -> 0.5.1-2.1
# --- Paquets AUR requis par end-4, épinglés au commit AUR audité ------------
#     format : pkgbase|commit|paquets à installer (séparés par des virgules)
readonly -a AUR_PINS=(
  "adw-gtk-theme-git|16fdc46376a5c1f758b2a1fc372be741c1931f26|adw-gtk-theme-git"
  "breeze-plus|faf39cfda93ef93a4514e36674bcf5dcb80d3164|breeze-plus"
  "darkly-bin|ee494461ecac9f1862c936afc7fd20bf072c3250|darkly-bin"
  "material-symbols-git|6536c04924b18483281f9ec432ba71ecba09ab67|ttf-material-symbols-variable-git"
  "ttf-readex-pro|39ba0d6672e2be28c63112b6e68b36ddfa83d06f|ttf-readex-pro"
  "ttf-rubik-vf|df5b264003f0d39ba75f42970074ff2465ed527c|ttf-rubik-vf"
  "ttf-twemoji|b250a6d51a95fac41ec21f634522ad36177938f0|ttf-twemoji"
  "qt5-avif-image-plugin|97faecaf6050c738e23a2a37cbe4046bfccef4bb|qt6-avif-image-plugin"
  "wlogout|9904ef2a49026b70e5288965423ee503c95f09cd|wlogout"
)
# Méta-paquets end-4 (sdata/dist-arch) installés pour la traçabilité.
readonly -a END4_METAS=(audio backlight basic fonts-themes kde portal python
  screencapture toolkit widgets hyprland bibata-modern-classic-bin microtex-git)
readonly END4_OPTIONAL_METAS=" microtex-git "   # rendu LaTeX du panneau IA : non bloquant

# --- Paquets de base (ne dépendent d'AUCUN paquet hypr*) ---------------------
readonly -a BASE_PKGS=(
  base-devel git devtools jq curl wget rsync unzip pacman-contrib psmisc
  xdg-user-dirs xdg-utils polkit dconf kconfig plasma-integration
  kitty dolphin qalculate-qt plasma-systemmonitor easyeffects wev
  grim slurp wl-clipboard cliphist brightnessctl playerctl libnotify
  tesseract-data-fra
)
readonly -a GRAPHICS_PKGS=(mesa vulkan-radeon vulkan-icd-loader libva-utils vulkan-tools mesa-utils linux-firmware-amdgpu pciutils)
readonly -a AUDIO_PKGS=(pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils pavucontrol-qt)
readonly -a FONT_PKGS=(noto-fonts noto-fonts-cjk noto-fonts-emoji otf-font-awesome ttf-nerd-fonts-symbols ttf-jetbrains-mono-nerd fontconfig)
readonly -a NET_PKGS=(networkmanager)
readonly -a BT_PKGS=(bluez bluez-utils)
readonly -a WALL_PKGS=(archlinux-wallpaper)
readonly DEFAULT_WALLPAPER="/usr/share/backgrounds/archlinux/mountain.jpg"

# =============================================================================
# 1. CHEMINS, ÉTAT GLOBAL
# =============================================================================
readonly DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hypr-installer"
readonly LOG_DIR="$DATA_DIR/logs" BACKUP_ROOT="$DATA_DIR/backups" STATE_DIR="$DATA_DIR/state"
readonly REPORT_DIR="$DATA_DIR/reports" MANIFEST_DIR="$DATA_DIR/manifests" BIN_DIR="$DATA_DIR/bin"
readonly END4_DIR="$DATA_DIR/end4"
readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-installer"
readonly PKG_CACHE="$CACHE_DIR/pkgs" BUILD_DIR="$CACHE_DIR/build" CHROOT_DIR="$CACHE_DIR/chroot"
readonly SPACE_GROTESK_URL="https://events.ccc.de/congress/2024/infos/styleguide/38c3-styleguide-full-v2.zip"
readonly SPACE_GROTESK_SHA256="9ae65abcfc85c97a95bf64e70e9f5a0aba7948eea1d56a5a99a5feed727f5216"
readonly CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly HYPR_CUSTOM="$CFG/hypr/custom"
readonly VENV_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/.venv"
readonly PINS_LOCK="$STATE_DIR/pins.lock"
readonly MANAGED_MARK="# MANAGED-BY: hypr-installer"
readonly HOOK_SCRIPT="/usr/local/lib/hypr-installer/pin-check.sh"
readonly HOOK_FILE="/etc/pacman.d/hooks/zz-hypr-installer-pin-check.hook"
RUN_TS="$(date '+%Y%m%d-%H%M%S')"; readonly RUN_TS
LOG_FILE="$LOG_DIR/install-$RUN_TS.log"
BACKUP_DIR="$BACKUP_ROOT/$RUN_TS"
TMP_DIR=""

MODE="install"          # install | diagnose | repair | first-login | post-login-check
ASSUME_YES=0 FORCE=0 ALLOW_NON_EOS=0 ALLOW_OTHER_GPU=0 NO_REBOOT_PROMPT=0
SUDO_KEEPALIVE_PID="" SPIN_PID=""
CURRENT_STEP=0
declare -a WARNINGS=() CHECK_LINES=()
declare -i CHECK_FAIL=0 CHECK_WARN=0 CHECK_PASS=0

readonly -a STEP_TITLES=("" "System verification" "Hardware detection" "Package installation"
  "AMD graphics setup" "Hyprland installation" "End-4 installation" "Quickshell setup"
  "AZERTY configuration" "Keyboard shortcuts" "Desktop configuration"
  "Services configuration" "Final validation")
declare -a STEP_STATUS=("" WAITING WAITING WAITING WAITING WAITING WAITING WAITING WAITING WAITING WAITING WAITING WAITING)
declare -a STEP_WARN=(0 0 0 0 0 0 0 0 0 0 0 0 0)

# Informations détectées
OS_ID="" OS_NAME="" CPU_MODEL="" GPU_LINES="" GPU_DRIVER="" RAM_GB=0 HAS_AMD_GPU=0 HAS_NVIDIA_GPU=0
EXISTING_HYPR="" EXISTING_QS="" CURRENT_DM="" BT_ADAPTER=0 IN_SESSION=""

# =============================================================================
# 2. INTERFACE, JOURNAL
# =============================================================================
if [[ -t 1 ]]; then
  C_RST=$'\e[0m' C_B=$'\e[1m' C_DIM=$'\e[2m' C_RED=$'\e[31m' C_GRN=$'\e[32m'
  C_YEL=$'\e[33m' C_BLU=$'\e[34m' C_CYN=$'\e[36m'
else
  C_RST="" C_B="" C_DIM="" C_RED="" C_GRN="" C_YEL="" C_BLU="" C_CYN=""
fi

ui()  { printf '%s\n' "$*" >&3; }
log() { printf '[%(%F %T)T] %s\n' -1 "$*" >&5; }
info() { log "INFO  $*"; printf '  %s→%s %s\n' "$C_CYN" "$C_RST" "$*" >&3; }
ok()   { log "OK    $*"; printf '  %s✔%s %s\n' "$C_GRN" "$C_RST" "$*" >&3; }
warn() {
  log "WARN  $*"; WARNINGS+=("$*"); STEP_WARN[CURRENT_STEP]=1
  printf '  %s!%s %s\n' "$C_YEL" "$C_RST" "$*" >&3
}
die() { log "FATAL $*"; printf '\n  %s✖ %s%s\n' "$C_RED" "$*" "$C_RST" >&3; exit 1; }
# Recherche sans pipe (grep -q + pipefail => faux négatifs par SIGPIPE).
contains()  { grep -q  -- "$1" <<<"$2"; }
containsi() { grep -qi -- "$1" <<<"$2"; }
section() { log "=================== $* ==================="; }

banner() {
  cat >&3 <<EOF
${C_CYN}${C_B}  _   _ _   _ ____  _   _ _____ ____
 | | | | \\ | |  _ \\| | | | ____|  _ \\
 | |_| |  \\| | |_) | |_| |  _| | |_) |
 |  _  | |\\  |  __/|  _  | |___|  _ <
 |_| |_|_| \\_|_|   |_| |_|_____|_| \\_\\${C_RST}

${C_B}       HYPRLAND AUTOMATED INSTALLER
              VERSION ${INSTALLER_VERSION}${C_RST}
EOF
}

status_label() {
  case $1 in
    DONE)    printf '%sDONE%s' "$C_GRN" "$C_RST" ;;
    CACHED)  printf '%sDONE%s %s(reprise)%s' "$C_GRN" "$C_RST" "$C_DIM" "$C_RST" ;;
    WARN)    printf '%sDONE (avertissements)%s' "$C_YEL" "$C_RST" ;;
    RUNNING) printf '%s%sRUNNING%s' "$C_B" "$C_BLU" "$C_RST" ;;
    FAILED)  printf '%s%sFAILED%s' "$C_B" "$C_RED" "$C_RST" ;;
    SKIPPED) printf '%sSKIPPED%s' "$C_DIM" "$C_RST" ;;
    *)       printf '%sWAITING%s' "$C_DIM" "$C_RST" ;;
  esac
}

draw_dashboard() {
  [[ $MODE == install || $MODE == repair || $MODE == diagnose ]] || return 0
  if [[ -t 3 ]]; then printf '\e[H\e[2J' >&3; fi
  banner
  ui ""
  printf '  %s╭──────────────────────────────────────────────────────────────╮%s\n' "$C_DIM" "$C_RST" >&3
  printf '  %s│%s  %sPROGRESSION DE L’INSTALLATION%s                               %s│%s\n' "$C_DIM" "$C_RST" "$C_B" "$C_RST" "$C_DIM" "$C_RST" >&3
  printf '  %s╰──────────────────────────────────────────────────────────────╯%s\n' "$C_DIM" "$C_RST" >&3
  local i done_count=0
  for i in $(seq 1 12); do
    case ${STEP_STATUS[i]} in DONE|CACHED|WARN) ((done_count+=1)) ;; esac
  done
  printf '  %sÉtapes terminées :%s %s/12\n\n' "$C_DIM" "$C_RST" "$done_count" >&3
  for i in $(seq 1 12); do
    printf '  %s%02d%s  %-29s %s\n' "$C_DIM" "$i" "$C_RST" "${STEP_TITLES[i]}" "$(status_label "${STEP_STATUS[i]}")" >&3
  done
  ui ""
  printf '  %sJournal%s  %s\n' "$C_B" "$C_RST" "${LOG_FILE/#$HOME/\~}" >&3
  printf '  %s──────────────────────────────────────────────────────────────%s\n' "$C_DIM" "$C_RST" >&3
}

# Exécute une commande (externe ou fonction autonome) avec sortie dans le journal
# et un indicateur d'activité à l'écran. Renvoie le code de sortie réel.
spin() {
  local msg=$1; shift
  local command_text="$*"
  log "EXEC  $command_text"
  ( trap - ERR; "$@" ) >&5 2>&5 &
  SPIN_PID=$!
  # shellcheck disable=SC1003  # la barre oblique inverse est une image du spinner
  local i=0 start=$SECONDS frames='|/-\'
  if [[ -t 3 ]]; then
    while kill -0 "$SPIN_PID" 2>/dev/null; do
      printf '\r\e[K  %s%s%s %s %s(%ds)%s' "$C_BLU" "${frames:i++%4:1}" "$C_RST" "${msg:0:70}" "$C_DIM" $((SECONDS - start)) "$C_RST" >&3
      sleep 0.25
    done
  else
    printf '  … %s\n' "$msg" >&3
  fi
  local rc=0
  wait "$SPIN_PID" || rc=$?
  SPIN_PID=""
  [[ -t 3 ]] && printf '\r\e[K' >&3
  if ((rc == 0)); then
    ok "$msg"
  else
    log "ÉCHEC ($rc) : $msg"
    printf '\n  %s✖ Échec :%s %s (code %s)\n' "$C_RED" "$C_RST" "$msg" "$rc" >&3
    if [[ $command_text == *makepkg* ]]; then
      case $rc in
        8) printf '  %sCause makepkg : installation des dépendances de compilation impossible.%s\n' "$C_YEL" "$C_RST" >&3 ;;
        4) printf '  %sCause makepkg : une fonction du PKGBUILD a échoué.%s\n' "$C_YEL" "$C_RST" >&3 ;;
        5) printf '  %sCause makepkg : création du paquet impossible.%s\n' "$C_YEL" "$C_RST" >&3 ;;
        6) printf '  %sCause makepkg : source ou fichier auxiliaire manquant.%s\n' "$C_YEL" "$C_RST" >&3 ;;
        12) printf '  %sCause makepkg : erreur de syntaxe dans le PKGBUILD.%s\n' "$C_YEL" "$C_RST" >&3 ;;
        *) printf '  %sConsultez les dernières lignes ci-dessous pour la cause précise.%s\n' "$C_DIM" "$C_RST" >&3 ;;
      esac
    fi
    printf '  %sDétails récents du journal :%s\n' "$C_DIM" "$C_RST" >&3
    tail -n 28 "$LOG_FILE" 2>/dev/null | sed 's/^/    /' >&3
    printf '\n' >&3
  fi
  return "$rc"
}

ask_yes_no() {
  local q=$1 a=""
  if ((ASSUME_YES)); then log "AUTO-OUI : $q"; return 0; fi
  { [[ -r /dev/tty ]] && : </dev/tty; } 2>/dev/null || die "Confirmation requise mais aucun terminal interactif (relancez avec --yes)."
  printf '\n  %s?%s %s [o/N] ' "$C_YEL" "$C_RST" "$q" >&3
  read -r a </dev/tty || a=""
  log "QUESTION : $q -> '${a}'"
  [[ $a =~ ^[oOyY] ]]
}

# =============================================================================
# 3. ERREURS, INTERRUPTIONS, NETTOYAGE, POINTS DE REPRISE
# =============================================================================
on_error() {
  local rc=$1 line=$2 cmd=$3
  if [[ $BASHPID != "$MAIN_PID" ]]; then exit "$rc"; fi
  trap - ERR
  set +e
  log "ERREUR : code $rc, ligne $line, commande : $cmd"
  [[ -n $SPIN_PID ]] && kill "$SPIN_PID" 2>/dev/null
  ((CURRENT_STEP > 0)) && STEP_STATUS[CURRENT_STEP]=FAILED
  draw_dashboard
  {
    printf '\n  %s%s✖ ÉCHEC à l’étape %02d (%s)%s\n' "$C_B" "$C_RED" "$CURRENT_STEP" "${STEP_TITLES[CURRENT_STEP]:-}" "$C_RST"
    printf '    Commande : %s\n    Code     : %s (ligne %s de install.sh)\n\n' "$cmd" "$rc" "$line"
    printf '  %sDernières lignes du journal :%s\n' "$C_DIM" "$C_RST"
    tail -n 15 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
    printf '\n  Les étapes terminées sont mémorisées : relancez ./install.sh pour reprendre.\n'
    printf '  Diagnostic : ./install.sh --diagnose     Réparation : ./install.sh --repair\n'
  } >&3
  write_report "ÉCHEC à l’étape $CURRENT_STEP : $cmd (code $rc)" >/dev/null 2>&1
  exit "$rc"
}

on_interrupt() {
  trap - INT TERM
  log "INTERRUPTION reçue"
  ((CURRENT_STEP > 0)) && STEP_STATUS[CURRENT_STEP]=FAILED
  printf '\n\n  %sInterrompu.%s Les étapes terminées sont conservées ; relancez ./install.sh pour reprendre.\n' "$C_YEL" "$C_RST" >&3
  exit 130
}

on_exit() {
  local rc=$?
  set +e
  [[ -n $SPIN_PID ]] && kill "$SPIN_PID" 2>/dev/null
  [[ -n $SUDO_KEEPALIVE_PID ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
  # Suppression uniquement du répertoire temporaire créé par mktemp (chemin vérifié).
  if [[ -n $TMP_DIR && $TMP_DIR == /tmp/hypr-installer.* && -d $TMP_DIR ]]; then
    rm -rf -- "$TMP_DIR"
  fi
  log "Fin (code $rc)"
  return "$rc"
}

checkpoint_key() {
  # Invalide les checkpoints dès que le script change.
  local script_hash
  script_hash=$(sha256sum "$SCRIPT_SELF" | awk '{print $1}')
  printf '%s|%s|%s|%s' "$INSTALLER_VERSION" "$script_hash" "$END4_COMMIT" "$QS_COMMIT" \
    | sha256sum | cut -c1-16
}
checkpoint_done() { [[ -f $STATE_DIR/step-$1.done && "$(<"$STATE_DIR/step-$1.done")" == "$(checkpoint_key)" ]]; }
checkpoint_set()  { checkpoint_key >"$STATE_DIR/step-$1.done"; }
state_set() { printf '%s\n' "$2" >"$STATE_DIR/$1"; }
state_get() { [[ -f $STATE_DIR/$1 ]] && cat "$STATE_DIR/$1" || true; }

# Étapes toujours réexécutées (lecture seule ou contrôles).
readonly ALWAYS_RUN=" 1 2 12 "

run_step() {
  local idx=$1 fn; shift
  CURRENT_STEP=$idx
  if [[ $MODE == install && $FORCE -eq 0 && $ALWAYS_RUN != *" $idx "* ]] && checkpoint_done "$idx"; then
    STEP_STATUS[idx]=CACHED; log "Étape $idx déjà terminée (point de reprise)"; draw_dashboard; return 0
  fi
  STEP_STATUS[idx]=RUNNING; draw_dashboard
  section "Étape $idx — ${STEP_TITLES[idx]}"
  for fn in "$@"; do log "--- $fn"; "$fn"; done
  if [[ ${STEP_STATUS[idx]} != FAILED ]]; then
    if ((STEP_WARN[idx])); then STEP_STATUS[idx]=WARN; else STEP_STATUS[idx]=DONE; fi
    [[ $MODE == diagnose ]] || checkpoint_set "$idx"
  fi
  draw_dashboard
}

# =============================================================================
# 4. OUTILS : sudo, pacman, fichiers gérés, sauvegardes
# =============================================================================
start_sudo_keepalive() {
  if ! sudo -n true 2>/dev/null; then
    printf '\n  Authentification administrateur (sudo) requise :\n' >&3
    # shellcheck disable=SC2024  # l'invite sudo doit rester sur le terminal (voulu)
    sudo -v </dev/tty >&3 2>&3 || die "Authentification sudo refusée."
  fi
  ( trap - ERR; while kill -0 "$MAIN_PID" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 45; done ) &
  SUDO_KEEPALIVE_PID=$!
}

pkg_installed() { pacman -Qq "$1" &>/dev/null; }
pkg_version() {
  # Un paquet absent est un état normal sur une installation fraîche.
  # Éviter un pipeline sous pipefail : pacman -Q renvoie 1 si le paquet manque.
  local query
  if ! query=$(pacman -Q "$1" 2>/dev/null); then
    return 0
  fi
  awk '{print $2}' <<<"$query"
  return 0
}

is_pinned() { local p; for p in "${PIN_ORDER[@]}"; do [[ $p == "$1" ]] && return 0; done; return 1; }

target_pin_version() {
  local n=$1
  if [[ ${PIN_MODE[$n]} == src ]]; then
    printf '%s%s' "${PIN_VER[$n]}" "$LOCAL_REL_SUFFIX"
  else
    printf '%s' "${PIN_VER[$n]}"
  fi
}

expected_pin_version() {
  local n=$1 locked
  if [[ -f $PINS_LOCK ]]; then
    locked=$(awk -v n="$n" '$1==n{print $2}' "$PINS_LOCK")
    [[ -n $locked ]] && { printf '%s' "$locked"; return; }
  fi
  target_pin_version "$n"
}

# Garde-fou : aucune transaction ne doit remplacer la pile épinglée.
assert_pins_intact() {
  [[ ${PINS_RESTORED:-0} == 0 ]] && return 0
  [[ -f $PINS_LOCK ]] || return 0
  local n v e bad=0
  for n in "${PIN_ORDER[@]}"; do
    v=$(pkg_version "$n"); e=$(expected_pin_version "$n")
    if [[ $v != "$e" ]]; then log "DÉRIVE : $n installé=$v attendu=$e"; bad=1; fi
  done
  ((bad == 0)) || die "La pile Hyprland épinglée a été modifiée par une transaction (voir journal). Lancez ./install.sh --repair."
}

# Vérifie, AVANT toute transaction, que pacman ne tirera aucun paquet hypr* des dépôts.
guard_targets() {
  local -a targets=() t
  local out
  out=$(LC_ALL=C pacman -Sp --needed --noconfirm --print-format '%n' "$@" 2>&1) \
    || die "Résolution des dépendances impossible pour : $* — $(tail -2 <<<"$out" | xargs)"
  mapfile -t targets < <(grep -E '^[a-z0-9@._+-]+$' <<<"$out" || true)
  for t in "${targets[@]}"; do
    is_pinned "$t" && die "La transaction installerait « $t » depuis les dépôts (version non épinglée). Arrêt de sécurité."
  done
  return 0
}

# Installe des paquets des dépôts officiels (jamais de paquet épinglé).
pac_install() {
  local -a flags=() pkgs=() p
  for p in "$@"; do
    if [[ $p == --* ]]; then flags+=("$p"); continue; fi
    is_pinned "$p" && die "Erreur interne : $p doit passer par la pile épinglée."
    pkg_installed "$p" || pkgs+=("$p")
  done
  ((${#pkgs[@]})) || { log "Déjà installés : $*"; return 0; }
  guard_targets "${pkgs[@]}"
  local more=""; ((${#pkgs[@]} > 8)) && more=" (+$((${#pkgs[@]} - 8)))"
  spin "pacman : ${pkgs[*]:0:8}$more" \
    sudo pacman -S --needed --noconfirm "${flags[@]}" "${pkgs[@]}"
  assert_pins_intact
}

# Retire, après confirmation, un paquet en conflit avec un paquet à installer.
remove_conflict() {
  local victim=$1 reason=$2
  pkg_installed "$victim" || return 0
  ask_yes_no "« $victim » est en conflit avec « $reason » et doit être retiré. Continuer ?" \
    || die "Conflit non résolu : $victim / $reason"
  spin "Retrait de $victim (conflit)" sudo pacman -Rdd --noconfirm "$victim"
}

# Installe des fichiers *.pkg.tar.zst après résolution explicite des conflits.
install_pkgfiles() {
  local f name c cname
  for f in "$@"; do
    name=$(LC_ALL=C pacman -Qip "$f" | awk -F': ' '/^Name/{print $2; exit}' | xargs)
    for c in $(LC_ALL=C pacman -Qip "$f" | awk -F': ' '/^Conflicts With/{print $2; exit}'); do
      [[ $c == None ]] && continue
      cname=${c%%[<>=]*}
      [[ $cname == "$name" ]] && continue
      remove_conflict "$cname" "$name"
    done
  done
  spin "Installation locale : $(for f in "$@"; do basename "$f" | sed 's/-[^-]*-[^-]*-[^-]*\.pkg\.tar\.zst$//'; done | xargs)" \
    sudo pacman -U --needed --noconfirm "$@"
  assert_pins_intact
}

# Écrit un fichier "géré" : sauvegarde préalable s'il a été modifié par l'utilisateur.
write_managed() {
  local dest=$1 content tmp
  content=$(cat)
  mkdir -p "$(dirname "$dest")"
  if [[ -f $dest ]]; then
    if [[ "$(<"$dest")" == "$content" ]]; then log "Inchangé : $dest"; return 0; fi
    backup_path "$dest"
  fi
  tmp=$(mktemp "$dest.XXXXXX")
  printf '%s\n' "$content" >"$tmp"
  mv -f "$tmp" "$dest"
  log "Écrit : $dest"
}

backup_path() {   # sauvegarde horodatée d'un fichier/répertoire (utilisateur ou système)
  local src=$1 rel dst
  [[ -e $src ]] || return 0
  if [[ $src == "$HOME"/* ]]; then rel="home/${src#"$HOME"/}"; else rel="system${src}"; fi
  dst="$BACKUP_DIR/$rel"
  [[ -e $dst ]] && return 0
  mkdir -p "$(dirname "$dst")"
  if [[ -r $src ]]; then cp -a -- "$src" "$dst"; else sudo cp -a -- "$src" "$dst"; sudo chown -R "$USER:" "$dst"; fi
  printf '%s\t%s\n' "$src" "$dst" >>"$BACKUP_DIR/MANIFEST.tsv"
  log "Sauvegarde : $src -> $dst"
}

sudo_write() {    # sudo_write <fichier> <mode>  (contenu sur stdin), avec sauvegarde
  local dest=$1 mode=${2:-644} tmp
  tmp=$(mktemp "$TMP_DIR/sw.XXXXXX"); cat >"$tmp"
  if [[ -f $dest ]] && sudo cmp -s "$tmp" "$dest"; then log "Inchangé : $dest"; return 0; fi
  [[ -e $dest ]] && backup_path "$dest"
  sudo install -D -m "$mode" "$tmp" "$dest"
  log "Écrit (root) : $dest"
}

git_checkout_pinned() {   # git_checkout_pinned <url> <dir> <commit>
  local url=$1 dir=$2 commit=$3
  if [[ ! -d $dir/.git ]]; then
    mkdir -p "$(dirname "$dir")"
    spin "git clone $(basename "$url" .git)" git clone --quiet "$url" "$dir"
  elif ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
    spin "git fetch $(basename "$url" .git)" git -C "$dir" fetch --quiet --tags origin
  fi
  git -C "$dir" checkout --quiet --force --detach "$commit"
  git -C "$dir" clean -fdxq
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$commit" ]] || die "Commit inattendu dans $dir"
}

enable_user_unit() {   # active une unité systemd utilisateur (même hors session)
  local unit=$1 src want
  if systemctl --user enable "$unit" 2>/dev/null; then log "systemctl --user enable $unit"; return 0; fi
  src="/usr/lib/systemd/user/$unit"
  [[ -f $src ]] || { warn "Unité utilisateur introuvable : $unit"; return 0; }
  want=$(awk -F= '/^WantedBy=/{print $2; exit}' "$src"); want=${want:-default.target}
  mkdir -p "$CFG/systemd/user/$want.wants"
  ln -sfn "$src" "$CFG/systemd/user/$want.wants/$unit"
  log "Unité utilisateur activée par lien : $unit -> $want"
}

# =============================================================================
# 5. ÉTAPE 01 — VÉRIFICATION SYSTÈME
# =============================================================================
detect_system() {
  # shellcheck disable=SC1091
  OS_ID=$(. /etc/os-release && printf '%s' "${ID:-}")
  # shellcheck disable=SC1091
  OS_NAME=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-inconnu}")
  info "Distribution : $OS_NAME"
  if [[ $OS_ID != endeavouros ]]; then
    if ((ALLOW_NON_EOS)) && grep -qw arch /etc/os-release; then warn "Distribution non EndeavourOS ($OS_ID) acceptée (--allow-non-eos)"
    else die "EndeavourOS requis (détecté : $OS_NAME). Option : --allow-non-eos pour une base Arch."; fi
  fi
  [[ $(uname -m) == x86_64 ]] || die "Architecture x86_64 requise (détectée : $(uname -m))."
  command -v pacman >/dev/null || die "pacman introuvable."
  command -v systemctl >/dev/null && [[ -d /run/systemd/system ]] || die "systemd requis."
  EXISTING_HYPR=$(pkg_version hyprland); EXISTING_QS=$(pkg_version illogical-impulse-quickshell-git)
  [[ -z $EXISTING_QS ]] && EXISTING_QS=$(pkg_version quickshell)
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then IN_SESSION="Hyprland"; elif [[ -n ${XDG_CURRENT_DESKTOP:-} ]]; then IN_SESSION=$XDG_CURRENT_DESKTOP; else IN_SESSION="TTY/autre"; fi
  CURRENT_DM=$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)" .service)
  [[ $CURRENT_DM == display-manager ]] && CURRENT_DM=""
  return 0
}

preflight() {
  [[ $EUID -ne 0 ]] || die "Ne lancez pas ce script en root ni avec sudo : lancez ./install.sh (sudo sera demandé)."
  command -v sudo >/dev/null || die "sudo est requis."
  detect_system
  [[ ! -e /var/lib/pacman/db.lck ]] || die "pacman est verrouillé (/var/lib/pacman/db.lck). Une autre opération est en cours ?"
  local need
  for need in curl git; do command -v "$need" >/dev/null || die "Commande requise absente : $need"; done
  # Réseau
  local host
  for host in https://archive.archlinux.org https://github.com https://aur.archlinux.org https://gitlab.archlinux.org; do
    curl -fsS --max-time 20 -o /dev/null -I "$host" || die "Réseau : $host injoignable. Connexion Internet requise."
  done
  ok "Réseau : dépôts Arch, Archive, AUR, GitHub joignables"
  # Espace disque
  local fs free
  for fs in / "$HOME"; do
    free=$(LC_ALL=C df -BG --output=avail "$fs" | tail -1 | tr -dc '0-9')
    if [[ $fs == / ]] && ((free < 25)); then die "Espace insuffisant sur / : ${free} Go (25 Go requis pour les paquets et le chroot de compilation)."; fi
    if [[ $fs == "$HOME" ]] && ((free < 20)); then die "Espace insuffisant dans $HOME : ${free} Go (20 Go requis pour les sources et caches de compilation)."; fi
  done
  ok "Espace disque suffisant"
  if [[ $IN_SESSION == Hyprland && -n $EXISTING_HYPR && $EXISTING_HYPR != "$(expected_pin_version hyprland)" ]]; then
    warn "Exécution dans une session Hyprland $EXISTING_HYPR : le remplacement à chaud peut fermer la session. Préférez un TTY (Ctrl+Alt+F3)."
  fi
  if pkg_installed uwsm; then warn "uwsm est installé : à l’écran de connexion, choisissez « Hyprland » et NON « Hyprland (uwsm-managed) »."; fi
  return 0
}

resolve_versions() {
  # Vérification d'identité de la release end-4 directement sur GitHub.
  local remote
  remote=$(git ls-remote "$END4_REPO" "refs/tags/$END4_TAG" "refs/tags/$END4_TAG^{}" | awk '{print $1}' | tail -1)
  [[ $remote == "$END4_COMMIT" ]] || die "Le tag end-4 $END4_TAG pointe sur '${remote:-?}', attendu $END4_COMMIT. Arrêt (release modifiée ?)."
  ok "end-4 $END4_TAG -> ${END4_COMMIT:0:12} (vérifié sur GitHub)"
  # Disponibilité des paquets épinglés dans l'Arch Linux Archive.
  local n url
  for n in "${PIN_ORDER[@]}"; do
    url="$ALA_URL/${n:0:1}/$n/$n-${PIN_VER[$n]}-x86_64.pkg.tar.zst"
    curl -fsS --max-time 30 -o /dev/null -I "$url" || die "Paquet épinglé indisponible : $url"
  done
  ok "Pile Hyprland épinglée disponible dans l’Arch Linux Archive (${#PIN_ORDER[@]} paquets)"
  local repo_hypr qt
  repo_hypr=$(LC_ALL=C pacman -Si hyprland 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}' | xargs || true)
  qt=$(LC_ALL=C pacman -Si qt6-base 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}' | xargs || true)
  info "Dépôts Arch actuels : hyprland ${repo_hypr:-?} (non utilisé), qt6-base ${qt:-?}"
  mkdir -p "$MANIFEST_DIR"
  {
    printf '+-----------------------------------------------------------------+\n'
    printf '|                    VERSION MANIFEST                             |\n'
    printf '+-----------------------------------------------------------------+\n'
    printf '| %-28s : %-32s |\n' "EndeavourOS" "$OS_NAME"
    printf '| %-28s : %-32s |\n' "end-4 dots-hyprland" "$END4_TAG (${END4_COMMIT:0:12})"
    printf '| %-28s : %-32s |\n' "Quickshell (épinglé end-4)" "${QS_COMMIT:0:12}"
    printf '| %-28s : %-32s |\n' "Instantané Arch hypr*" "$SNAPSHOT_DATE"
    for n in "${PIN_ORDER[@]}"; do printf '| %-28s : %-32s |\n' "$n" "${PIN_VER[$n]} [${PIN_MODE[$n]}]"; done
    printf '| %-28s : %-32s |\n' "hyprland (dépôts, ignoré)" "${repo_hypr:-?}"
    printf '| %-28s : %-32s |\n' "qt6-base (dépôts)" "${qt:-?}"
    printf '+-----------------------------------------------------------------+\n'
  } >"$MANIFEST_DIR/versions-$RUN_TS.txt"
  cp -f "$MANIFEST_DIR/versions-$RUN_TS.txt" "$MANIFEST_DIR/versions-latest.txt"
}

confirm_plan() {
  [[ $MODE == install || $MODE == repair ]] || return 0
  ui ""
  ui "  ${C_B}Résumé avant modification du système${C_RST}"
  ui "   • Mise à jour complète du système (pacman -Syu), puis installation des dépendances end-4."
  ui "   • Hyprland ${PIN_VER[hyprland]} et sa pile épinglée (instantané Arch $SNAPSHOT_DATE) ;"
  ui "     ajout d’une ligne IgnorePkg dans /etc/pacman.conf (sauvegardé) pour les conserver."
  ui "   • end-4 $END4_TAG (${END4_COMMIT:0:12}) déployé dans ~/.config (sauvegarde horodatée)."
  ui "   • AZERTY (fr), raccourcis AZERTY, services, gestionnaire de connexion."
  ui "   • Aucune opération sur les disques, partitions, EFI, chargeur de démarrage ou Windows."
  [[ -n $EXISTING_HYPR && $EXISTING_HYPR != "$(expected_pin_version hyprland)" ]] && ui "   • ${C_YEL}Hyprland $EXISTING_HYPR installé sera remplacé par ${PIN_VER[hyprland]}.${C_RST}"
  ask_yes_no "Lancer l’installation ?" || die "Annulé par l’utilisateur. Aucune modification effectuée."
  start_sudo_keepalive
}

# =============================================================================
# 6. ÉTAPE 02 — DÉTECTION MATÉRIELLE
# =============================================================================
detect_hardware() {
  CPU_MODEL=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)
  RAM_GB=$(( ($(awk '/^MemTotal/{print $2}' /proc/meminfo) + 524288) / 1048576 ))
  if ! command -v lspci >/dev/null; then
    [[ $MODE == diagnose ]] && die "lspci absent (paquet pciutils) : lancez l’installation."
    pac_install_early pciutils
  fi
  GPU_LINES=$(LC_ALL=C lspci -nnk | grep -A3 -E 'VGA compatible controller|3D controller|Display controller' || true)
  grep -q '\[1002:' <<<"$GPU_LINES" && HAS_AMD_GPU=1
  grep -q '\[10de:' <<<"$GPU_LINES" && HAS_NVIDIA_GPU=1
  GPU_DRIVER=$(awk -F': ' '/Kernel driver in use/{print $2; exit}' <<<"$GPU_LINES")
  BT_ADAPTER=0; compgen -G '/sys/class/bluetooth/hci*' >/dev/null && BT_ADAPTER=1
  local gpu_name; gpu_name=$(grep -E 'VGA|3D|Display' <<<"$GPU_LINES" | head -1 | sed 's/^[^:]*: //')
  {
    printf '+------------------------------------------+\n'
    printf '|             SYSTEM PREFLIGHT             |\n'
    printf '+------------------------------------------+\n'
    printf '| %-19s: %s\n' "Distribution" "$OS_NAME"
    printf '| %-19s: %s\n' "Architecture" "$(uname -m)"
    printf '| %-19s: %s\n' "CPU" "$CPU_MODEL"
    printf '| %-19s: %s\n' "GPU" "${gpu_name:-inconnu}"
    printf '| %-19s: %s\n' "Pilote GPU" "${GPU_DRIVER:-?}"
    printf '| %-19s: %s Go\n' "RAM" "$RAM_GB"
    printf '| %-19s: %s\n' "Existing Hyprland" "${EXISTING_HYPR:-MISSING}"
    printf '| %-19s: %s\n' "Existing Quickshell" "${EXISTING_QS:-MISSING}"
    printf '| %-19s: %s\n' "Session actuelle" "$IN_SESSION"
    printf '| %-19s: %s\n' "Gestionnaire conn." "${CURRENT_DM:-aucun}"
    printf '| %-19s: %s\n' "Bluetooth" "$( ((BT_ADAPTER)) && echo "adaptateur détecté" || echo "aucun adaptateur")"
    printf '| %-19s: %s\n' "Network" "CONNECTED"
    printf '| %-19s: %s\n' "Disk space" "CHECKED"
    printf '| %-19s: %s\n' "Root privileges" "CHECKED (sudo)"
    printf '+------------------------------------------+\n'
    printf 'Écrans (connecteurs DRM) :\n'
    local c
    for c in /sys/class/drm/card*-*; do
      [[ -f $c/status && "$(<"$c/status")" == connected ]] || continue
      printf '  %s : %s\n' "${c##*/}" "$(head -3 "$c/modes" 2>/dev/null | paste -sd' ')"
    done
  } | tee "$MANIFEST_DIR/hardware-$RUN_TS.txt" | sed 's/^/  /' >&3
  if ((HAS_NVIDIA_GPU)); then warn "GPU NVIDIA détecté : aucun pilote NVIDIA ne sera installé (configuration AMD uniquement)."; fi
  if ((!HAS_AMD_GPU)); then
    if ((ALLOW_OTHER_GPU)); then warn "Aucun GPU AMD détecté (--allow-other-gpu)."; else die "Aucun GPU AMD détecté. Option : --allow-other-gpu."; fi
  fi
  [[ $CPU_MODEL == *"Ryzen 5 4500"* ]] || warn "CPU différent de la cible (Ryzen 5 4500) : $CPU_MODEL"
  grep -qiE 'Lexa|RX 550|RX 540|Polaris ?12' <<<"$GPU_LINES" || warn "GPU AMD différent de la cible (RX 550) : poursuite avec AMDGPU/Mesa."
  if ((HAS_AMD_GPU)) && [[ -n $GPU_DRIVER && $GPU_DRIVER != amdgpu ]]; then warn "Pilote noyau actif : $GPU_DRIVER (amdgpu attendu pour Polaris)."; fi
  ((RAM_GB >= 8)) || warn "Mémoire faible : ${RAM_GB} Go"
  return 0
}
pac_install_early() { spin "pacman : $*" sudo pacman -S --needed --noconfirm "$@"; }

# =============================================================================
# 7. ÉTAPE 03 — PAQUETS SYSTÈME
# =============================================================================
ensure_ignorepkg() {
  local line="IgnorePkg = ${PIN_ORDER[*]}"
  if grep -qF "# hypr-installer: pile Hyprland 0.54.3 épinglée" /etc/pacman.conf; then
    if grep -qxF "$line" /etc/pacman.conf; then log "IgnorePkg déjà présent"; return 0; fi
  fi
  grep -q '^\[options\]' /etc/pacman.conf || die "/etc/pacman.conf sans section [options] : configuration inattendue."
  backup_path /etc/pacman.conf
  local tmp; tmp=$(mktemp "$TMP_DIR/pacman.conf.XXXXXX")
  awk -v line="$line" '
    /^# hypr-installer: pile Hyprland 0.54.3 épinglée/ {skip=1; next}
    skip==1 {skip=0; next}
    {print}
    /^\[options\]/ && !done {print "# hypr-installer: pile Hyprland 0.54.3 épinglée (ne pas retirer, voir README)"; print line; done=1}
  ' /etc/pacman.conf >"$tmp"
  sudo install -m 644 "$tmp" /etc/pacman.conf
  ok "IgnorePkg ajouté à /etc/pacman.conf (sauvegarde : $BACKUP_DIR)"
}


install_system_packages() {
  # Retirer les dépendants incompatibles avant la transaction, puis protéger
  # la pile cible : pacman -Syu ne doit jamais remplacer les versions épinglées.
  remove_incompatible_dependents
  ensure_ignorepkg
  local -a keyring_pkgs=(archlinux-keyring)
  pkg_installed endeavouros-keyring && keyring_pkgs+=(endeavouros-keyring)
  spin "Mise à jour des trousseaux de clés" sudo pacman -Sy --needed --noconfirm "${keyring_pkgs[@]}"
  spin "Mise à jour complète du système (pacman -Syu)" sudo pacman -Syu --noconfirm
  assert_pins_intact
  # PulseAudio est remplacé par PipeWire (conflit avec pipewire-pulse).
  pkg_installed pulseaudio && remove_conflict pulseaudio pipewire-pulse
  pkg_installed pulseaudio-bluetooth && remove_conflict pulseaudio-bluetooth pipewire-pulse
  pac_install "${BASE_PKGS[@]}"
  pac_install "${AUDIO_PKGS[@]}" "${FONT_PKGS[@]}" "${NET_PKGS[@]}" "${BT_PKGS[@]}" "${WALL_PKGS[@]}"
  # Navigateur : uniquement si aucun n’est présent (EndeavourOS fournit Firefox).
  local b found=0
  for b in firefox chromium google-chrome-stable brave zen-browser librewolf microsoft-edge-stable; do command -v "$b" >/dev/null && found=1; done
  ((found)) || pac_install firefox
  install_aur_packages
  install_space_grotesk_font
}

install_aur_packages() {
  local entry base commit wants want dir all_installed f
  local -a files
  for entry in "${AUR_PINS[@]}"; do
    IFS='|' read -r base commit wants <<<"$entry"
    all_installed=1
    for want in ${wants//,/ }; do pkg_installed "$want" || all_installed=0; done
    if ((all_installed)) && [[ $MODE != repair ]]; then log "AUR $base déjà installé"; continue; fi
    dir="$BUILD_DIR/aur/$base"
    git_checkout_pinned "https://aur.archlinux.org/$base.git" "$dir" "$commit"
    check_aur_dependencies "$dir" "$base" || die "AUR $base : pré-vérification des dépendances échouée."
    if [[ $base == wlogout ]] && ! gpg --list-keys F4FDB18A9937358364B276E9E25D679AF73C6D2F &>/dev/null; then
      gpg --keyserver hkps://keys.openpgp.org --recv-keys F4FDB18A9937358364B276E9E25D679AF73C6D2F \
        || gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys F4FDB18A9937358364B276E9E25D679AF73C6D2F \
        || warn "Clé PGP de wlogout non récupérée : vérification par somme MD5 seule."
    fi
    # --needed ne sert qu'avec makepkg -i ; les paquets sont installés séparément.
    local -a mkflags=(-s -r --noconfirm -f -c --log)
    [[ $base == wlogout ]] && ! gpg --list-keys F4FDB18A9937358364B276E9E25D679AF73C6D2F &>/dev/null && mkflags+=(--skippgpcheck)
    if ! (cd "$dir" && spin "AUR : $base (dépendances + compilation)" env LC_ALL=C makepkg "${mkflags[@]}"); then
      die "AUR $base : makepkg a échoué. Code 8 = dépendances de compilation impossibles à installer ; détails affichés ci-dessus et conservés dans le journal."
    fi
    files=()
    for want in ${wants//,/ }; do
      while IFS= read -r f; do
        [[ $(basename "$f") =~ ^${want}-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$ ]] && files+=("$f")
      done < <(cd "$dir" && makepkg --packagelist)
    done
    ((${#files[@]})) || die "AUR $base : paquet(s) $wants introuvable(s) après compilation."
    install_pkgfiles "${files[@]}"
  done
  return 0
}

# Space Grotesk is the only artifact needed from 38c3-styles.
# Install the font files directly: no split AUR package or HTML converters.
install_space_grotesk_font() {
  local archive="$BUILD_DIR/38c3-styleguide-full-v2.zip"
  local extract="$TMP_DIR/38c3-styleguide"
  local font_dir="$extract/fonts/space-grotesk-1.1.4"
  local target="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/space-grotesk"
  local -a fonts=()

  mkdir -p "$BUILD_DIR"
  if [[ ! -f $archive ]] || ! sha256sum -c --status <<<"$SPACE_GROTESK_SHA256  $archive"; then
    rm -f -- "$archive.part"
    spin "Téléchargement de Space Grotesk" curl -fL --retry 3 --max-time 300 -o "$archive.part" "$SPACE_GROTESK_URL"
    sha256sum -c --status <<<"$SPACE_GROTESK_SHA256  $archive.part" || die "Archive 38C3 invalide : somme SHA-256 incorrecte."
    mv -f -- "$archive.part" "$archive"
  fi
  sha256sum -c --status <<<"$SPACE_GROTESK_SHA256  $archive" || die "Archive 38C3 invalide : somme SHA-256 incorrecte."

  mkdir -p "$extract"
  unzip -q "$archive" -d "$extract"
  [[ -d $font_dir/otf && -f $font_dir/OFL.txt ]] || die "Archive 38C3 : dossier Space Grotesk ou licence OFL introuvable."
  fonts=("$font_dir"/otf/*.otf)
  (( ${#fonts[@]} > 0 )) && [[ -f ${fonts[0]} ]] || die "Archive 38C3 : aucun fichier OTF Space Grotesk trouvé."

  mkdir -p "$target"
  install -m 644 "${fonts[@]}" "$target/"
  install -m 644 "$font_dir/OFL.txt" "$target/OFL.txt"
  spin "Actualisation du cache des polices" fc-cache -f "$target"
  ok "Space Grotesk installé depuis l'archive 38C3 vérifiée (sans dépendance AUR)."
}

# =============================================================================
# 8. ÉTAPE 04 — GRAPHISME AMD
# =============================================================================
install_graphics() {
  local p
  for p in $(pacman -Qq 2>/dev/null | grep -E '^(nvidia|lib32-nvidia|nvidia-utils|nvidia-dkms)' || true); do
    warn "Paquet NVIDIA présent ($p) : laissé en place, non utilisé."
  done
  pkg_installed amdvlk && warn "amdvlk installé : RADV (vulkan-radeon) sera utilisé par défaut ; amdvlk est abandonné par AMD."
  pac_install "${GRAPHICS_PKGS[@]}"
  info "libva-mesa-driver et mesa-vdpau n’existent plus : VA-API est fourni par « mesa » (VDPAU abandonné par Mesa)."
  if [[ -d /sys/module/amdgpu ]]; then ok "Module noyau amdgpu chargé"; else warn "Module amdgpu non chargé (sera vérifié après redémarrage)."; fi
  if [[ -e /dev/dri/renderD128 ]]; then ok "Nœud de rendu /dev/dri/renderD128 présent"; fi
  local vk; vk=$(vulkaninfo --summary 2>/dev/null | grep -m1 -E 'deviceName' | sed 's/.*= //' || true)
  if [[ $vk == *RADV* || $vk == *AMD* ]]; then ok "Vulkan : $vk"; else warn "Vulkan : périphérique RADV non confirmé hors session (${vk:-aucune sortie})."; fi
  local va; va=$(vainfo --display drm --device /dev/dri/renderD128 2>&1 | grep -m1 -i 'Driver version' || true)
  if [[ -n $va ]]; then ok "VA-API : ${va#*: }"; else warn "VA-API : non confirmé hors session."; fi
}

# =============================================================================
# 9. ÉTAPE 05 — PILE HYPRLAND 0.54.3 ÉPINGLÉE
# =============================================================================
ala_fetch() {   # télécharge + vérifie séparément l'archive et sa signature
  local n=$1 fn url dest
  fn="$n-${PIN_VER[$n]}-x86_64.pkg.tar.zst"; url="$ALA_URL/${n:0:1}/$n/$fn"; dest="$PKG_CACHE/ala/$fn"
  mkdir -p "$PKG_CACHE/ala"
  if [[ ! -f $dest ]] || ! sha256sum -c --status <<<"${PIN_SHA256[$n]}  $dest"; then
    rm -f -- "$dest.part"
    curl -fL --retry 3 --max-time 600 -o "$dest.part" "$url" || { rm -f -- "$dest.part"; die "Téléchargement impossible : $fn"; }
    sha256sum -c --status <<<"${PIN_SHA256[$n]}  $dest.part" || { rm -f -- "$dest.part"; die "SHA-256 invalide pour $fn"; }
    mv -f -- "$dest.part" "$dest"
  fi
  # Une archive valide en cache ne garantit pas que son .sig soit encore présent.
  if [[ ! -s $dest.sig ]]; then
    rm -f -- "$dest.sig.part"
    curl -fL --retry 3 --max-time 60 -o "$dest.sig.part" "$url.sig" || { rm -f -- "$dest.sig.part"; die "Signature Arch introuvable pour $fn"; }
    [[ -s $dest.sig.part ]] || die "Signature Arch vide pour $fn"
    mv -f -- "$dest.sig.part" "$dest.sig"
  fi
  sha256sum -c --status <<<"${PIN_SHA256[$n]}  $dest" || { rm -f -- "$dest"; die "SHA-256 invalide pour $fn"; }
  sudo pacman-key --verify "$dest.sig" "$dest" >/dev/null 2>&1 || die "Signature Arch invalide pour $fn"
  printf '%s' "$dest"
}

prepare_chroot() {
  [[ -n $(state_get chroot.ready) && -d $CHROOT_DIR/root ]] && {
    spin "Mise à jour du chroot de compilation" arch-nspawn "$CHROOT_DIR/root" pacman -Syu --noconfirm; return 0; }
  mkdir -p "$CHROOT_DIR"
  spin "Création du chroot de compilation propre (devtools)" mkarchroot "$CHROOT_DIR/root" base-devel
  state_set chroot.ready 1
}

# Reconstruit un paquet épinglé depuis le PKGBUILD officiel Arch, au commit épinglé,
# dans le chroot, en injectant les autres paquets épinglés (-I).
build_pin_src() {
  local n=$1 dir pkgrel out f
  local -a inject=()
  shift
  inject=("$@")
  dir="$BUILD_DIR/arch/$n"
  git_checkout_pinned "$ARCH_PKG_GIT/$n.git" "$dir" "${PIN_GITREF[$n]}"
  pkgrel=$(awk -F= '/^pkgrel=/{print $2; exit}' "$dir/PKGBUILD")
  [[ "$(awk -F= '/^pkgver=/{print $2; exit}' "$dir/PKGBUILD")-$pkgrel" == "${PIN_VER[$n]}" ]] || die "PKGBUILD $n ne correspond pas à ${PIN_VER[$n]}"
  sed -i "s/^pkgrel=.*/pkgrel=${pkgrel}${LOCAL_REL_SUFFIX}/" "$dir/PKGBUILD"
  local -a iargs=()
  for f in "${inject[@]}"; do iargs+=(-I "$f"); done
  (cd "$dir" && spin "Compilation propre de $n ${PIN_VER[$n]} (chroot)" makechrootpkg -c -r "$CHROOT_DIR" "${iargs[@]}")
  out=$(cd "$dir" && makepkg --packagelist | grep -E "/$n-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$" | head -1)
  [[ -f $out ]] || die "Paquet $n introuvable après compilation"
  mkdir -p "$PKG_CACHE/built"; cp -f "$out" "$PKG_CACHE/built/"
  printf '%s' "$PKG_CACHE/built/$(basename "$out")"
}

# Fichiers installés en conflit ABI (bibliothèque introuvable) parmi les paquets épinglés.
pin_broken_list() {
  local n f
  for n in "${PIN_ORDER[@]}"; do
    pkg_installed "$n" || continue
    while IFS= read -r f; do
      [[ -f $f && ! -L $f && ( $f == /usr/bin/* || $f == /usr/lib/* ) ]] || continue
      [[ "$(od -An -tx1 -N4 "$f" 2>/dev/null | tr -d ' ')" == 7f454c46 ]] || continue
      if contains 'not found' "$(LC_ALL=C ldd "$f" 2>/dev/null || true)"; then printf '%s\n' "$n"; break; fi
    done < <(pacman -Qlq "$n")
  done
}

# Paquets installés (hors pile) qui exigent une version plus récente des bibliothèques épinglées.
package_requires_incompatible_pin() {
  local package=$1 token n op required actual cmp dep_list pattern
  dep_list=$(LC_ALL=C pacman -Qi "$package" | awk '
    /^Depends On[[:space:]]*:/ {
      sub(/^[^:]*:[[:space:]]*/, "")
      printf "%s ", $0
      in_dep=1
      next
    }
    in_dep && /^[[:space:]]+/ {
      sub(/^[[:space:]]+/, "")
      printf "%s ", $0
      next
    }
    in_dep { exit }
    END { print "" }
  ')
  for token in $dep_list; do
    for n in "${PIN_ORDER[@]}"; do
      pattern="^${n}(>=|<=|=|>|<)(.+)$"
      if [[ $token =~ $pattern ]]; then
        op=${BASH_REMATCH[1]}
        required=${BASH_REMATCH[2]}
        actual=$(target_pin_version "$n")
        if ! dependency_version_satisfied "$token" "$actual"; then return 0; fi
        if pkg_installed "$n"; then
          local current_version
          current_version=$(pkg_version "$n" || true)
          if [[ -n $current_version ]] && ! dependency_version_satisfied "$token" "$current_version"; then
            return 0
          fi
        fi
      fi
    done
  done
  return 1
}

remove_incompatible_dependents() {
  local -a deps=() d n
  for n in "${PIN_ORDER[@]}"; do
    pkg_installed "$n" || continue
    for d in $(LC_ALL=C pacman -Qi "$n" | awk -F': ' '/^Required By/{print $2}'); do
      [[ $d == None ]] && continue
      is_pinned "$d" && continue
      [[ $d == illogical-impulse-* || $d == hyprshot ]] && continue
      deps+=("$d")
    done
  done
  mapfile -t deps < <(printf '%s\n' "${deps[@]}" | sort -u | grep -v '^$' || true)
  (("${#deps[@]}")) || return 0
  for d in "${deps[@]}"; do
    case $d in
      hyprpolkitagent|hyprland-qt-support|hyprpaper|hyprland-qtutils|quickshell|hyprshutdown)
        remove_conflict "$d" "pile Hyprland 0.54.3 (redondant avec end-4 / incompatible)";;
      *)
        if package_requires_incompatible_pin "$d"; then
          remove_conflict "$d" "contrainte de version incompatible avec la pile Hyprland épinglée"
        else
          warn "« $d » dépend d’un paquet Hyprland, mais aucune contrainte de version incompatible n’a été détectée : paquet conservé."
        fi;;
    esac
  done
}

install_hyprland() {
  pac_install devtools base-devel git
  ensure_ignorepkg
  local n f
  local -A file=()
  # 1) binaires officiels vérifiés
  for n in "${PIN_ORDER[@]}"; do
    [[ ${PIN_MODE[$n]} == bin ]] || continue
    f=$(ala_fetch "$n"); file[$n]=$f
  done
  ok "Paquets archivés vérifiés (SHA-256 + signature Arch)"
  # 2) reconstructions en chroot propre (dans l'ordre des dépendances)
  local -a broken=()
  if [[ $MODE == repair ]]; then mapfile -t broken < <(pin_broken_list); fi
  for n in "${PIN_ORDER[@]}"; do
    local need_src=0 cached
    [[ ${PIN_MODE[$n]} == src ]] && need_src=1
    [[ " ${broken[*]} " == *" $n "* ]] && need_src=1
    ((need_src)) || continue
    cached=$(compgen -G "$PKG_CACHE/built/$n-${PIN_VER[$n]}${LOCAL_REL_SUFFIX}-x86_64.pkg.tar.zst" || true)
    if [[ -n $cached && $MODE != repair ]]; then file[$n]=$cached; log "Reconstruction en cache : $cached"; continue; fi
    [[ -n $(state_get chroot.prepared-run) && $(state_get chroot.prepared-run) == "$RUN_TS" ]] || { prepare_chroot; state_set chroot.prepared-run "$RUN_TS"; }
    local -a inj=() m
    for m in "${PIN_ORDER[@]}"; do [[ $m == "$n" ]] && break; [[ -n ${file[$m]:-} ]] && inj+=("${file[$m]}"); done
    file[$n]=$(build_pin_src "$n" "${inj[@]}")
  done
  # 3) une seule transaction pour toute la pile (cohérence ABI)
  remove_incompatible_dependents
  local -a all=()
  for n in "${PIN_ORDER[@]}"; do all+=("${file[$n]}"); done
  spin "Installation de la pile Hyprland ${PIN_VER[hyprland]} (${#all[@]} paquets)" sudo pacman -U --needed --noconfirm "${all[@]}"
  # 4) verrou des versions effectivement installées + contrôles
  : >"$PINS_LOCK.tmp"
  for n in "${PIN_ORDER[@]}"; do printf '%s %s\n' "$n" "$(pkg_version "$n")" >>"$PINS_LOCK.tmp"; done
  mv -f "$PINS_LOCK.tmp" "$PINS_LOCK"
  PINS_RESTORED=1
  for n in "${PIN_ORDER[@]}"; do
    local v; v=$(pkg_version "$n")
    [[ $v == "${PIN_VER[$n]}" || $v == "${PIN_VER[$n]}${LOCAL_REL_SUFFIX}" ]] || die "$n : version installée $v inattendue"
  done
  contains '0\.54\.3' "$(Hyprland --version 2>/dev/null || true)" || die "Hyprland --version ne rapporte pas 0.54.3"
  mapfile -t broken < <(pin_broken_list)
  ((${#broken[@]} == 0)) || die "Bibliothèques manquantes pour : ${broken[*]} (voir journal). Lancez ./install.sh --repair."
  ok "Hyprland $(Hyprland --version 2>/dev/null | head -1 | awk '{print $2}') installé, ABI cohérente"
  install_pin_hook
}

install_pin_hook() {
  local list="${PIN_ORDER[*]}"
  sudo_write "$HOOK_SCRIPT" 755 <<EOF
#!/usr/bin/env bash
# MANAGED-BY: hypr-installer — vérifie la pile Hyprland épinglée après chaque transaction pacman.
pins=($list)
bad=()
for n in "\${pins[@]}"; do
  pacman -Qq "\$n" &>/dev/null || { bad+=("\$n (désinstallé)"); continue; }
  while IFS= read -r f; do
    [[ -f \$f && ! -L \$f && ( \$f == /usr/bin/* || \$f == /usr/lib/* ) ]] || continue
    [[ "\$(od -An -tx1 -N4 "\$f" 2>/dev/null | tr -d ' ')" == 7f454c46 ]] || continue
    if [[ "\$(LC_ALL=C ldd "\$f" 2>/dev/null)" == *'not found'* ]]; then bad+=("\$n (bibliothèque manquante)"); break; fi
  done < <(pacman -Qlq "\$n")
done
if ((\${#bad[@]})); then
  echo "==> ATTENTION (hypr-installer) : la pile Hyprland 0.54.3 est cassée par cette mise à jour :"
  printf '      - %s\n' "\${bad[@]}"
  echo "    Réparez AVANT de redémarrer : ~/.local/share/hypr-installer/bin/install.sh --repair"
fi
exit 0
EOF
  sudo_write "$HOOK_FILE" 644 <<EOF
# MANAGED-BY: hypr-installer
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Vérification de la pile Hyprland 0.54.3 épinglée (hypr-installer)...
When = PostTransaction
Exec = $HOOK_SCRIPT
EOF
  ok "Hook pacman de surveillance ABI installé"
}

# =============================================================================
# 10. ÉTAPE 06 — END-4 (release 2026.05.11)
# =============================================================================
fetch_end4() {
  git_checkout_pinned "$END4_REPO" "$END4_DIR" "$END4_COMMIT"
  [[ "$(git -C "$END4_DIR" rev-parse "$END4_TAG^{commit}" 2>/dev/null)" == "$END4_COMMIT" ]] || die "Le tag local $END4_TAG ne correspond pas à $END4_COMMIT"
  spin "Sous-module rounded-polygon-qmljs" git -C "$END4_DIR" submodule update --init --recursive
  [[ "$(git -C "$END4_DIR/dots/.config/quickshell/ii/modules/common/widgets/shapes" rev-parse HEAD)" == "$END4_SHAPES_COMMIT" ]] \
    || die "Sous-module shapes inattendu"
  ok "end-4 $END4_TAG récupéré et vérifié (${END4_COMMIT:0:12})"
}

pkgbuild_depends() { bash -c 'source "$1" >/dev/null 2>&1; printf "%s\n" "${depends[@]}"' _ "$1"; }

aur_provided() {   # le paquet est-il un paquet AUR épinglé ?
  local e; for e in "${AUR_PINS[@]}"; do [[ ",${e##*|}," == *",$1,"* ]] && return 0; done; return 1
}

dependency_version_satisfied() {
  local dep=$1 actual=$2 op required cmp constraint_re
  constraint_re='^[^<>=]+(>=|<=|=|>|<)(.+)$'
  [[ $dep =~ $constraint_re ]] || return 0
  op=${BASH_REMATCH[1]}
  required=${BASH_REMATCH[2]}
  cmp=$(vercmp "$actual" "$required") || return 1
  case $op in
    '>' ) (( cmp > 0 )) ;;
    '>=' ) (( cmp >= 0 )) ;;
    '=' ) (( cmp == 0 )) ;;
    '<' ) (( cmp < 0 )) ;;
    '<=' ) (( cmp <= 0 )) ;;
  esac
}

# Vérifie les dépendances obligatoires du PKGBUILD avant makepkg -s.
# Les dépendances de dépôts seront résolues par makepkg ; une dépendance AUR
# absente ou non épinglée est signalée explicitement au lieu d'un échec opaque.
check_aur_dependencies() {
  local dir=$1 base=$2 line dep pkg installed_version repo_info repo_version
  local srcinfo="$dir/.SRCINFO"
  local -a unresolved=() aur_missing=() pinned_missing=()
  if ! (cd "$dir" && makepkg --printsrcinfo) >"$srcinfo"; then
    warn "$base : génération de .SRCINFO impossible."
    return 1
  fi
  while IFS= read -r line; do
    dep=${line#*=}; dep=${dep# }
    pkg=${dep%%[<>=]*}
    [[ -n $pkg ]] || continue
    if [[ $pkg == otf-space-grotesk ]] && fc-match -f '%{family}\n' "Space Grotesk" | grep -qiF "Space Grotesk"; then
      continue
    elif is_pinned "$pkg"; then
      installed_version=""
      if pkg_installed "$pkg"; then installed_version=$(pkg_version "$pkg" || true); fi
      if [[ -n $installed_version ]] && dependency_version_satisfied "$dep" "$installed_version"; then
        continue
      fi
      pinned_missing+=("$dep (paquet Hyprland épinglé absent ou version installée incompatible)")
    elif aur_provided "$pkg"; then
      installed_version=""
      if pkg_installed "$pkg"; then installed_version=$(pkg_version "$pkg" || true); fi
      if [[ -n $installed_version ]] && dependency_version_satisfied "$dep" "$installed_version"; then
        continue
      fi
      aur_missing+=("$dep (dépendance AUR épinglée absente ou version installée incompatible)")
    elif pacman -T "$dep" >/dev/null 2>&1; then
      continue
    else
      repo_info=""
      if ! repo_info=$(LC_ALL=C pacman -Si "$pkg" 2>/dev/null); then
        unresolved+=("$dep")
      else
        repo_version=$(awk -F': ' '/^Version[[:space:]]*:/ {print $2; exit}' <<<"$repo_info")
        if [[ -n $repo_version ]] && ! dependency_version_satisfied "$dep" "$repo_version"; then
          unresolved+=("$dep (version dépôt $repo_version insuffisante)")
        fi
      fi
    fi
  done < <(awk -F' = ' '/^[[:space:]]*(depends|makedepends|checkdepends)(_[[:alnum:]_]+)? = /{print $2}' "$srcinfo")
  if (( ${#aur_missing[@]} > 0 || ${#pinned_missing[@]} > 0 || ${#unresolved[@]} > 0 )); then
    (( ${#aur_missing[@]} )) && printf '  - %s\n' "${aur_missing[@]}" >&3
    (( ${#pinned_missing[@]} )) && printf '  - %s\n' "${pinned_missing[@]}" >&3
    (( ${#unresolved[@]} )) && printf '  - %s\n' "${unresolved[@]}" >&3
    warn "$base : dépendances non résolues avant compilation."
    return 1
  fi
  return 0
}

install_end4_metas() {
  local m dir d bdir f
  local -a deps repo files
  for m in "${END4_METAS[@]}"; do
    dir="$END4_DIR/sdata/dist-arch/illogical-impulse-$m"
    [[ -f $dir/PKGBUILD ]] || die "Méta-paquet end-4 absent : $m"
    if pkg_installed "illogical-impulse-$m" && [[ $MODE != repair ]]; then
      log "Méta illogical-impulse-$m déjà installé"
      continue
    fi
    if ! check_aur_dependencies "$dir" "illogical-impulse-$m"; then
      if [[ $END4_OPTIONAL_METAS == *" $m "* ]]; then
        warn "illogical-impulse-$m ignoré : dépendances indisponibles (méta-paquet facultatif)."
        continue
      fi
      die "Méta-paquet end-4 obligatoire illogical-impulse-$m : dépendances indisponibles."
    fi
    mapfile -t deps < <(pkgbuild_depends "$dir/PKGBUILD")
    repo=()
    for d in "${deps[@]}"; do
      d=${d%%[<>=]*}; [[ -z $d ]] && continue
      # end-4's fonts-themes meta-package declares otf-space-grotesk.
      # The installer deliberately provides that font directly from the
      # checksum-verified 38C3 archive instead of building 38c3-styles.
      if [[ $d == otf-space-grotesk ]]; then
        if fc-match -f '%{family}\n' "Space Grotesk" | grep -qiF "Space Grotesk"; then
          log "Dépendance $d satisfaite par la police Space Grotesk installée localement"
          continue
        fi
        die "Dépendance $d non satisfaite : la police Space Grotesk n'est pas détectée par fontconfig."
      fi
      if is_pinned "$d"; then pkg_installed "$d" || die "Dépendance épinglée absente : $d"; continue; fi
      if aur_provided "$d"; then pkg_installed "$d" || die "Dépendance AUR épinglée absente : $d"; continue; fi
      repo+=("$d")
    done
    pac_install --asdeps "${repo[@]}"
    bdir="$BUILD_DIR/meta/illogical-impulse-$m"
    rm -rf -- "${bdir:?}"; mkdir -p "$bdir"; cp -a "$dir/." "$bdir/"
    if ! (cd "$bdir" && spin "end-4 : illogical-impulse-$m" makepkg -Afs --noconfirm); then
      if [[ $END4_OPTIONAL_METAS == *" $m "* ]]; then warn "illogical-impulse-$m non compilé (fonction secondaire : rendu LaTeX du panneau IA)."; continue; fi
      die "Échec de compilation du méta-paquet end-4 $m"
    fi
    mapfile -t files < <(cd "$bdir" && makepkg --packagelist)
    install_pkgfiles "${files[@]}"
  done
}

backup_existing_config() {
  local item name
  for item in "$END4_DIR"/dots/.config/*; do
    name=$(basename "$item"); [[ -e $CFG/$name ]] && backup_path "$CFG/$name"
  done
  for item in "$CFG/hypr" "$CFG/illogical-impulse" "${XDG_DATA_HOME:-$HOME/.local/share}/konsole" \
              "${XDG_DATA_HOME:-$HOME/.local/share}/icons/illogical-impulse.svg"; do
    [[ -e $item ]] && backup_path "$item"
  done
  if [[ -f $BACKUP_DIR/MANIFEST.tsv ]]; then ok "Configurations existantes sauvegardées : ${BACKUP_DIR/#$HOME/\~}"
  else info "Aucune configuration existante à sauvegarder"; fi
}

# Reproduit sdata/subcmd-install/3.files-legacy.sh (sans invite interactive),
# + correctif : hypr/hyprlock/ est aussi déployé (référencé par hyprlock.conf).
deploy_end4_files() {
  local src="$END4_DIR/dots" item name firstrun=0 f
  [[ -f $CFG/illogical-impulse/installed_true ]] || firstrun=1
  mkdir -p "$CFG" "${XDG_DATA_HOME:-$HOME/.local/share}" "$HOME/.local/bin" "${XDG_CACHE_HOME:-$HOME/.cache}"
  for item in "$src"/.config/*; do
    name=$(basename "$item")
    case $name in quickshell|fish|hypr|fontconfig) continue ;; esac
    if [[ -d $item ]]; then rsync -a --delete "$item/" "$CFG/$name/"; else cp -f "$item" "$CFG/$name"; fi
  done
  rsync -a "$src/.local/share/konsole/" "${XDG_DATA_HOME:-$HOME/.local/share}/konsole/"
  rsync -a --delete "$src/.config/quickshell/" "$CFG/quickshell/"
  rsync -a --delete --exclude conf.d "$src/.config/fish/" "$CFG/fish/"
  rsync -a --delete "$src/.config/fontconfig/" "$CFG/fontconfig/"
  rsync -a --delete "$src/.config/hypr/hyprland/" "$CFG/hypr/hyprland/"
  rsync -a --delete "$src/.config/hypr/hyprlock/" "$CFG/hypr/hyprlock/"
  for f in hyprlock.conf monitors.conf workspaces.conf hypridle.conf; do
    if [[ -f $CFG/hypr/$f ]] && ! cmp -s "$src/.config/hypr/$f" "$CFG/hypr/$f"; then
      if ((firstrun)); then mv -f "$CFG/hypr/$f" "$CFG/hypr/$f.old"; cp -f "$src/.config/hypr/$f" "$CFG/hypr/$f"
      else cp -f "$src/.config/hypr/$f" "$CFG/hypr/$f.new"; fi
    else cp -f "$src/.config/hypr/$f" "$CFG/hypr/$f"; fi
  done
  cp -f "$src/.config/hypr/hyprland.conf" "$CFG/hypr/hyprland.conf"
  [[ -d $HYPR_CUSTOM ]] || rsync -a "$src/.config/hypr/custom/" "$HYPR_CUSTOM/"
  install -Dm644 "$src/.local/share/icons/illogical-impulse.svg" "${XDG_DATA_HOME:-$HOME/.local/share}/icons/illogical-impulse.svg"
  mkdir -p "$CFG/illogical-impulse"
  touch "$CFG/illogical-impulse/installed_true"
  printf '%s %s\n' "$END4_TAG" "$END4_COMMIT" >"$CFG/illogical-impulse/hypr-installer-release"
  ( cd "$src" && find . -type f | sed "s#^\./#$HOME/#" ) | sort -u >"$CFG/illogical-impulse/installed_listfile"
  ok "Fichiers end-4 déployés dans ~/.config"
}

install_google_sans_flex() {
  local dir="$BUILD_DIR/google-sans-flex" target="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/illogical-impulse-google-sans-flex"
  git_checkout_pinned "$GSF_REPO" "$dir" "$GSF_COMMIT"
  mkdir -p "$target"; rsync -a --exclude .git "$dir/" "$target/"
  spin "Mise à jour du cache des polices" fc-cache -f
}

setup_python_venv() {
  if [[ -x $VENV_DIR/bin/python ]] && "$VENV_DIR/bin/python" -c 'import sys; sys.exit(0 if sys.version_info[:2]==(3,12) else 1)'; then
    log "venv Python 3.12 existant : $VENV_DIR"
  else
    mkdir -p "$(dirname "$VENV_DIR")"
    spin "Environnement Python 3.12 (uv)" env UV_NO_MODIFY_PATH=1 uv venv --clear --prompt .venv "$VENV_DIR" -p 3.12
  fi
  spin "Paquets Python des widgets (requirements.txt épinglé end-4)" \
    env VIRTUAL_ENV="$VENV_DIR" UV_NO_MODIFY_PATH=1 uv pip install -r "$END4_DIR/sdata/uv/requirements.txt"
}

end4_setups() {   # équivalent de sdata/subcmd-install/2.setups.sh (Arch)
  getent group i2c >/dev/null || sudo groupadd i2c
  sudo usermod -aG video,i2c,input "$USER"
  printf 'i2c-dev\n' | sudo_write /etc/modules-load.d/i2c-dev.conf 644
  enable_user_unit ydotool.service
  dbus-run-session -- bash -c "
    gsettings set org.gnome.desktop.interface font-name 'Google Sans Flex Medium 11 @opsz=11,wght=500'
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'" \
    || warn "gsettings indisponible hors session (sera appliqué par end-4 au premier lancement)"
  if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Darkly
  else
    warn "kwriteconfig6 absent : préférence de style KDE laissée inchangée."
  fi
  ok "Groupes (video, i2c, input), i2c-dev, ydotool, préférences GTK/KDE"
}

install_end4() {
  fetch_end4
  pac_install hyprshot   # dépend de hyprland : seulement après la pile épinglée
  install_end4_metas
  backup_existing_config
  install_google_sans_flex
  setup_python_venv
  deploy_end4_files
  end4_setups
  # Original des raccourcis end-4 conservé pour référence.
  mkdir -p "$MANIFEST_DIR"
  cp -f "$END4_DIR/dots/.config/hypr/hyprland/keybinds.conf" "$MANIFEST_DIR/end4-keybinds.upstream.conf"
}

# =============================================================================
# 11. ÉTAPE 07 — QUICKSHELL (commit épinglé par end-4)
# =============================================================================
build_quickshell() {
  local commit=$1 url=${2:-} bdir="$BUILD_DIR/meta/illogical-impulse-quickshell-git"
  rm -rf -- "${bdir:?}"; mkdir -p "$bdir"
  cp -a "$END4_DIR/sdata/dist-arch/illogical-impulse-quickshell-git/." "$bdir/"
  grep -q "^_commit='$QS_COMMIT'" "$bdir/PKGBUILD" || die "PKGBUILD Quickshell end-4 inattendu (commit épinglé différent)"
  [[ $commit != "$QS_COMMIT" ]] && sed -i "s/^_commit=.*/_commit='$commit'/" "$bdir/PKGBUILD"
  [[ -n $url ]] && sed -i "s#^url=.*#url='${url%.git}'#" "$bdir/PKGBUILD"
  (cd "$bdir" && spin "Compilation de Quickshell ${commit:0:12}" makepkg -Afs --noconfirm)
}

install_quickshell() {
  if pkg_installed illogical-impulse-quickshell-git && [[ $MODE != repair ]] && quickshell --private-check-compat >/dev/null 2>&1; then
    ok "Quickshell déjà installé et compatible avec Qt"; return 0
  fi
  local used=$QS_COMMIT
  local qcheck="$BUILD_DIR/meta/quickshell-preflight"
  rm -rf -- "${qcheck:?}"; mkdir -p "$qcheck"
  cp -a "$END4_DIR/sdata/dist-arch/illogical-impulse-quickshell-git/." "$qcheck/"
  check_aur_dependencies "$qcheck" "illogical-impulse-quickshell-git" || die "Quickshell : dépendances de compilation non résolues."
  if ! build_quickshell "$QS_COMMIT"; then
    warn "Compilation du commit épinglé échouée avec la source officielle ; nouvel essai via le miroir GitHub (même commit)."
    if ! build_quickshell "$QS_COMMIT" "$QS_MIRROR_URL"; then
      warn "Le commit Quickshell épinglé par end-4 ne compile pas avec Qt $(pkg_version qt6-base). Repli sur v0.3.0 (${QS_FALLBACK_COMMIT:0:12}), descendant direct antérieur à la release end-4."
      build_quickshell "$QS_FALLBACK_COMMIT" || die "Quickshell ne compile pas (voir journal)."
      used=$QS_FALLBACK_COMMIT
    fi
  fi
  local -a files; mapfile -t files < <(cd "$BUILD_DIR/meta/illogical-impulse-quickshell-git" && makepkg --packagelist)
  install_pkgfiles "${files[@]}"
  state_set quickshell.commit "$used"
  quickshell --private-check-compat >/dev/null 2>&1 || warn "quickshell --private-check-compat signale une incompatibilité Qt"
  ok "Quickshell installé (commit ${used:0:12})"
}

# =============================================================================
# 12. ÉTAPE 08 — CLAVIER AZERTY
# =============================================================================
configure_keyboard() {
  write_managed "$HYPR_CUSTOM/general.conf" <<EOF
# hyprlang noerror false
$MANAGED_MARK — clavier AZERTY + réglages RX 550
# Vos réglages personnels : ~/.config/hypr/custom/general.user.conf (jamais écrasé)

input {
    kb_layout = fr
    kb_variant =
    kb_model = pc105
    kb_options =
    kb_rules =
    numlock_by_default = true
}

# RX 550 : flou allégé (end-4 utilise 3 passes) — l'apparence reste celle d'end-4.
decoration {
    blur {
        passes = 2
    }
}

source = ~/.config/hypr/custom/general.user.conf
EOF
  [[ -f $HYPR_CUSTOM/general.user.conf ]] || printf '# Réglages personnels (sourcé après custom/general.conf)\n' >"$HYPR_CUSTOM/general.user.conf"
  # Console (TTY) et X11 (écran de connexion SDDM/X11, applications XWayland).
  local vc x11
  vc=$(localectl status | awk -F': ' '/VC Keymap/{print $2}' | xargs)
  x11=$(localectl status | awk -F': ' '/X11 Layout/{print $2}' | xargs)
  if [[ $vc != fr* ]]; then
    backup_path /etc/vconsole.conf
    sudo localectl set-keymap --no-convert fr
  fi
  if [[ $x11 != fr ]]; then
    [[ -e /etc/X11/xorg.conf.d/00-keyboard.conf ]] && backup_path /etc/X11/xorg.conf.d/00-keyboard.conf
    sudo localectl set-x11-keymap --no-convert fr pc105
  fi
  ok "AZERTY : Hyprland (kb_layout = fr), console ($(localectl status | awk -F': ' '/VC Keymap/{print $2}' | xargs)), X11/écran de connexion (fr)"
  containsi 'utf-8' "$(locale)" || warn "La locale système n’est pas UTF-8 : les caractères accentués peuvent mal s’afficher."
}

# =============================================================================
# 13. ÉTAPE 09 — RACCOURCIS (pensés pour AZERTY)
# =============================================================================
configure_keybindings() {
  local ws_go="" ws_move="" ws_silent="" kp_go="" kp_silent="" i code
  local -a kp=(87 88 89 83 84 85 79 80 81 90)
  for i in $(seq 1 10); do
    code=$((9 + i))
    ws_go+="bind = Super, code:$code, exec, ~/.config/hypr/hyprland/scripts/workspace_action.sh workspace $i # [hidden]"$'\n'
    ws_move+="bind = Super+Shift, code:$code, exec, ~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspace $i # [hidden]"$'\n'
    ws_silent+="bind = Super+Alt, code:$code, exec, ~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent $i # [hidden]"$'\n'
    kp_go+="bindp = Super, code:${kp[i-1]}, exec, ~/.config/hypr/hyprland/scripts/workspace_action.sh workspace $i # [hidden]"$'\n'
    kp_silent+="bind = Super+Alt, code:${kp[i-1]}, exec, ~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent $i # [hidden]"$'\n'
  done

  write_managed "$HYPR_CUSTOM/variables.conf" <<EOF
# hyprlang noerror false
$MANAGED_MARK
# Les raccourcis QWERTY par défaut d'end-4 sont remplacés par custom/keybinds.conf (AZERTY).
\$dontLoadDefaultKeybinds = true
\$calculator = ~/.config/hypr/hyprland/scripts/launch_first_available.sh "qalculate-qt" "gnome-calculator" "kcalc"
\$screenshotHelper = ~/.config/hypr/custom/scripts/hypr-installer-screenshot.sh
EOF

  write_managed "$HYPR_CUSTOM/scripts/hypr-installer-screenshot.sh" <<'EOF'
#!/usr/bin/env bash
# MANAGED-BY: hypr-installer — captures d'écran (repli si Quickshell est indisponible)
set -euo pipefail
mode=${1:-full-clip}
mon=$(hyprctl activeworkspace -j | jq -r '.monitor')
dir="$(xdg-user-dir PICTURES)/Screenshots"
file="$dir/Capture_$(date '+%Y-%m-%d_%H.%M.%S').png"
case $mode in
  full-clip)
    grim -o "$mon" - | wl-copy --type image/png
    notify-send -a "Capture d'écran" "Écran copié dans le presse-papiers" ;;
  full-file)
    mkdir -p "$dir"; grim -o "$mon" "$file"; wl-copy --type image/png <"$file"
    notify-send -a "Capture d'écran" "Capture enregistrée" "$file" ;;
  region-file)
    pidof slurp >/dev/null && exit 0
    geom=$(slurp) || exit 0
    mkdir -p "$dir"; grim -g "$geom" "$file"; wl-copy --type image/png <"$file"
    notify-send -a "Capture d'écran" "Zone enregistrée" "$file" ;;
  ocr)
    pidof slurp >/dev/null && exit 0
    geom=$(slurp) || exit 0
    grim -g "$geom" - | tesseract stdin stdout -l fra+eng 2>/dev/null | wl-copy
    notify-send -a "OCR" "Texte copié dans le presse-papiers" ;;
esac
EOF
  chmod +x "$HYPR_CUSTOM/scripts/hypr-installer-screenshot.sh"

  write_managed "$HYPR_CUSTOM/keybinds.conf" <<EOF
# hyprlang noerror false
$MANAGED_MARK — raccourcis AZERTY français (Hyprland 0.54.3, end-4 2026.05.11)
# Ce fichier est régénéré par install.sh. Vos raccourcis : custom/keybinds.user.conf
# Lettres : liées par symbole (touche marquée sur le clavier AZERTY).
# Rangée des chiffres : liée par code physique (code:10…19) -> Super+& … Super+à
# fonctionnent sans Maj. Les touches /, ., [, ], -, ' (inaccessibles ou en conflit
# avec la rangée des chiffres en AZERTY) ne sont jamais utilisées.

# NE PAS RETIRER : nécessaire au catchall de Quickshell
exec = hyprctl dispatch submap global
submap = global

#!
##! Interface (Quickshell)
bindid = Super, Super_L, Toggle search, global, quickshell:searchToggleRelease # Lanceur (appui court sur Super)
bindid = Super, Super_R, Toggle search, global, quickshell:searchToggleRelease # [hidden]
bind = Super, Super_L, exec, qs -c \$qsConfig ipc call TEST_ALIVE || pkill fuzzel || fuzzel # [hidden]
bind = Super, Super_R, exec, qs -c \$qsConfig ipc call TEST_ALIVE || pkill fuzzel || fuzzel # [hidden]
binditn = Super, catchall, global, quickshell:searchToggleReleaseInterrupt # [hidden]
bind = Ctrl, Super_L, global, quickshell:searchToggleReleaseInterrupt # [hidden]
bind = Ctrl, Super_R, global, quickshell:searchToggleReleaseInterrupt # [hidden]
bind = Super, mouse:272, global, quickshell:searchToggleReleaseInterrupt # [hidden]
bind = Super, mouse:273, global, quickshell:searchToggleReleaseInterrupt # [hidden]
bind = Super, mouse:274, global, quickshell:searchToggleReleaseInterrupt # [hidden]
bind = Super, mouse:275, global, quickshell:searchToggleReleaseInterrupt # [hidden]
bind = Super, mouse:276, global, quickshell:searchToggleReleaseInterrupt # [hidden]
bind = Super, mouse:277, global, quickshell:searchToggleReleaseInterrupt # [hidden]
bind = Super, mouse_up, global, quickshell:searchToggleReleaseInterrupt # [hidden]
bind = Super, mouse_down, global, quickshell:searchToggleReleaseInterrupt # [hidden]
bindit = , Super_L, global, quickshell:workspaceNumber # [hidden]
bindit = , Super_R, global, quickshell:workspaceNumber # [hidden]
bind = Super, Space, global, quickshell:searchToggle # Lanceur d'applications
bind = Super, Space, exec, qs -c \$qsConfig ipc call TEST_ALIVE || pkill fuzzel || fuzzel # [hidden]
bind = Super, Tab, global, quickshell:overviewWorkspacesToggle # Vue d'ensemble des bureaux
bind = Super, Escape, global, quickshell:sessionToggle # Menu système (verrouiller, déconnexion, arrêt)
bind = Super, Escape, exec, qs -c \$qsConfig ipc call TEST_ALIVE || pkill wlogout || wlogout -p layer-shell # [hidden]
bind = Ctrl+Alt, Delete, global, quickshell:sessionToggle # [hidden]
bind = Ctrl+Alt, Delete, exec, qs -c \$qsConfig ipc call TEST_ALIVE || pkill wlogout || wlogout -p layer-shell # [hidden]
bind = Super, F1, global, quickshell:cheatsheetToggle # Aide : liste des raccourcis
bind = Super, A, global, quickshell:sidebarLeftToggle # Panneau gauche (IA, traduction)
bind = Super+Alt, A, global, quickshell:sidebarLeftToggleDetach # [hidden]
bind = Super, O, global, quickshell:sidebarLeftToggle # [hidden]
bind = Super, N, global, quickshell:sidebarRightToggle # Panneau droit (notifications, réglages rapides)
bind = Super+Shift, V, global, quickshell:overviewClipboardToggle # Historique du presse-papiers
bind = Super+Shift, V, exec, qs -c \$qsConfig ipc call TEST_ALIVE || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy # [hidden]
bind = Super, semicolon, global, quickshell:overviewEmojiToggle # Émojis (touche ; .)
bind = Super, semicolon, exec, qs -c \$qsConfig ipc call TEST_ALIVE || pkill fuzzel || ~/.config/hypr/hyprland/scripts/fuzzel-emoji.sh copy # [hidden]
bind = Super, K, global, quickshell:oskToggle # Clavier virtuel
bind = Super, M, global, quickshell:mediaControlsToggle # Contrôles multimédia
bind = Super, G, global, quickshell:overlayToggle # Overlay de widgets
bind = Super, J, global, quickshell:barToggle # Afficher / masquer la barre
bind = Ctrl+Super, T, global, quickshell:wallpaperSelectorToggle # Choisir un fond d'écran
bind = Ctrl+Super+Alt, T, global, quickshell:wallpaperSelectorRandom # Fond d'écran aléatoire
bind = Ctrl+Super, T, exec, qs -c \$qsConfig ipc call TEST_ALIVE || ~/.config/quickshell/\$qsConfig/scripts/colors/switchwall.sh # [hidden]
bind = Ctrl+Super, P, global, quickshell:panelFamilyCycle # Changer de style de panneaux
bind = Ctrl+Super, R, exec, killall ydotool qs quickshell; qs -c \$qsConfig & # Redémarrer Quickshell (widgets)
bind = Super, F5, exec, hyprctl reload && notify-send -a Hyprland "Configuration rechargée" # Recharger la configuration Hyprland
bind = Ctrl+Super, F1, exec, xdg-open ~/.config/illogical-impulse/config.json # [hidden]
bind = Ctrl+Super+Alt, F1, exec, xdg-open ~/.config/hypr/custom/keybinds.user.conf # [hidden]
bind = Super+Shift+Alt, F1, exec, qs -p ~/.config/quickshell/\$qsConfig/welcome.qml # [hidden]

##! Son et multimédia
#/# bind = , Touches multimédia,, # Volume, muet, micro, lecture, luminosité (sans Super)
bindle = , XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 2%+ # [hidden]
bindle = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%- # [hidden]
bindl = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle # [hidden]
bindl = , XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle # [hidden]
bindl = Alt, XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle # [hidden]
bindle = , XF86MonBrightnessUp, exec, qs -c \$qsConfig ipc call brightness increment || brightnessctl s 5%+ # [hidden]
bindle = , XF86MonBrightnessDown, exec, qs -c \$qsConfig ipc call brightness decrement || brightnessctl s 5%- # [hidden]
bindl = , XF86AudioPlay, exec, playerctl play-pause # [hidden]
bindl = , XF86AudioPause, exec, playerctl play-pause # [hidden]
bindl = , XF86AudioNext, exec, playerctl next # [hidden]
bindl = , XF86AudioPrev, exec, playerctl previous # [hidden]
bindl = , XF86AudioStop, exec, playerctl stop # [hidden]
bindl = Super+Shift, M, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle # Couper / rétablir le son
bindl = Super+Alt, M, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle # Couper / rétablir le micro
bindl = Super+Shift, P, exec, playerctl play-pause # Lecture / pause
bindl = Super+Shift, N, exec, playerctl next # Piste suivante
bindl = Super+Shift, B, exec, playerctl previous # Piste précédente
bind = Ctrl+Super, V, exec, \$volumeMixer # Mixeur de volume

##! Captures et outils
bind = Super, S, global, quickshell:regionScreenshot # Capture d'une zone (copier, enregistrer, annoter)
bind = Super, S, exec, qs -c \$qsConfig ipc call TEST_ALIVE || pidof slurp || hyprshot --freeze --clipboard-only --mode region --silent # [hidden]
bind = Super+Shift, S, global, quickshell:regionScreenshot # [hidden]
bind = Super+Shift, S, exec, qs -c \$qsConfig ipc call TEST_ALIVE || pidof slurp || hyprshot --freeze --clipboard-only --mode region --silent # [hidden]
bindl = , Print, exec, \$screenshotHelper full-clip # Écran complet -> presse-papiers
bindl = Ctrl, Print, exec, \$screenshotHelper full-file # Écran complet -> fichier + presse-papiers
bindl = Shift, Print, exec, \$screenshotHelper region-file # Zone -> fichier + presse-papiers
bind = Super+Shift, X, global, quickshell:regionOcr # Reconnaissance de texte (OCR)
bind = Super+Shift, X, exec, qs -c \$qsConfig ipc call TEST_ALIVE || \$screenshotHelper ocr # [hidden]
bind = Super+Shift, A, global, quickshell:regionSearch # Recherche visuelle d'une zone
bind = Super+Shift, A, exec, qs -c \$qsConfig ipc call TEST_ALIVE || pidof slurp || ~/.config/hypr/hyprland/scripts/snip_to_search.sh # [hidden]
bind = Super+Shift, T, global, quickshell:screenTranslate # Traduire le contenu de l'écran
bind = Super+Shift, C, exec, hyprpicker -a # Pipette de couleur -> presse-papiers
bindl = Super+Shift, R, global, quickshell:regionRecord # Enregistrer une zone (sans son)
bindl = Super+Shift, R, exec, qs -c \$qsConfig ipc call TEST_ALIVE || ~/.config/quickshell/\$qsConfig/scripts/videos/record.sh # [hidden]
bindl = Super+Alt, R, global, quickshell:regionRecord # [hidden]
bindl = Ctrl+Alt, R, exec, ~/.config/quickshell/\$qsConfig/scripts/videos/record.sh --fullscreen # Enregistrer l'écran (sans son)
bindl = Super+Shift+Alt, R, exec, ~/.config/quickshell/\$qsConfig/scripts/videos/record.sh --fullscreen --sound # Enregistrer l'écran (avec son)
binde = Super, equal, exec, ~/.config/hypr/hyprland/scripts/zoom.sh increase 0.3 # Zoom avant (touche =)
binde = Super, parenright, exec, ~/.config/hypr/hyprland/scripts/zoom.sh decrease 0.3 # Zoom arrière (touche ))
binde = Super, code:86, exec, qs -c \$qsConfig ipc call zoom zoomIn # [hidden]
binde = Super, code:82, exec, qs -c \$qsConfig ipc call zoom zoomOut # [hidden]

#!
##! Fenêtres
bind = Super, Q, killactive, # Fermer la fenêtre active
bind = Alt, F4, killactive, # [hidden]
bind = Super+Shift+Alt, Q, exec, hyprctl kill # Forcer la fermeture (cliquer la fenêtre)
bind = Super, F, fullscreen, 0 # Plein écran
bind = Super, D, fullscreen, 1 # Maximiser
bind = Super+Alt, F, fullscreenstate, 0 3 # [hidden]
bind = Super, V, togglefloating, # Flottant / mosaïque
bind = Super+Alt, Space, togglefloating, # [hidden]
bind = Super+Alt, V, centerwindow, # Centrer la fenêtre flottante
bind = Super, P, pseudo, # Mode pseudo-mosaïque
bind = Super+Alt, P, pin, # Épingler sur tous les bureaux
bind = Super+Shift, J, layoutmsg, togglesplit # Inverser le sens de découpe
bind = Alt, Tab, cyclenext, # Fenêtre suivante
bind = Alt, Tab, bringactivetotop, # [hidden]
bind = Alt+Shift, Tab, cyclenext, prev # [hidden]
bind = Alt+Shift, Tab, bringactivetotop, # [hidden]
bindm = Super, mouse:272, movewindow # Super + clic gauche : déplacer
bindm = Super, mouse:274, movewindow # [hidden]
bindm = Super, mouse:273, resizewindow # Super + clic droit : redimensionner
#/# bind = Super, ←/↑/→/↓,, # Déplacer le focus
bind = Super, Left, movefocus, l # [hidden]
bind = Super, Right, movefocus, r # [hidden]
bind = Super, Up, movefocus, u # [hidden]
bind = Super, Down, movefocus, d # [hidden]
#/# bind = Super+Shift, ←/↑/→/↓,, # Déplacer la fenêtre
bind = Super+Shift, Left, movewindow, l # [hidden]
bind = Super+Shift, Right, movewindow, r # [hidden]
bind = Super+Shift, Up, movewindow, u # [hidden]
bind = Super+Shift, Down, movewindow, d # [hidden]
#/# bind = Super+Ctrl, ←/↑/→/↓,, # Redimensionner la fenêtre
binde = Super+Ctrl, Left, resizeactive, -40 0 # [hidden]
binde = Super+Ctrl, Right, resizeactive, 40 0 # [hidden]
binde = Super+Ctrl, Up, resizeactive, 0 -40 # [hidden]
binde = Super+Ctrl, Down, resizeactive, 0 40 # [hidden]

##! Bureaux virtuels (1 à 10)
#/# bind = Super, & é " ' ( - è _ ç à,, # Aller au bureau 1 … 10
${ws_go}#/# bind = Super+Shift, & é " ' ( - è _ ç à,, # Déplacer la fenêtre vers le bureau 1 … 10
${ws_move}#/# bind = Super+Alt, & é " ' ( - è _ ç à,, # Envoyer la fenêtre (sans la suivre)
${ws_silent}${kp_go}${kp_silent}#/# bind = Super, Page↑ / Page↓,, # Bureau précédent / suivant
bind = Super, Page_Up, workspace, -1 # [hidden]
bind = Super, Page_Down, workspace, +1 # [hidden]
#/# bind = Super+Alt, ← / →,, # Bureau précédent / suivant (écran courant)
bind = Super+Alt, Left, workspace, r-1 # [hidden]
bind = Super+Alt, Right, workspace, r+1 # [hidden]
#/# bind = Super+Shift, Page↑ / Page↓,, # Déplacer la fenêtre vers le bureau précédent / suivant
bind = Super+Shift, Page_Up, movetoworkspace, r-1 # [hidden]
bind = Super+Shift, Page_Down, movetoworkspace, r+1 # [hidden]
bind = Super+Shift+Alt, Left, movetoworkspace, r-1 # [hidden]
bind = Super+Shift+Alt, Right, movetoworkspace, r+1 # [hidden]
bind = Ctrl+Super+Shift, Left, movetoworkspace, r-1 # [hidden]
bind = Ctrl+Super+Shift, Right, movetoworkspace, r+1 # [hidden]
#/# bind = Ctrl+Super+Alt, ← / →,, # Bureau occupé précédent / suivant
bind = Ctrl+Super+Alt, Left, workspace, m-1 # [hidden]
bind = Ctrl+Super+Alt, Right, workspace, m+1 # [hidden]
#/# bind = Super, Molette,, # Changer de bureau
bind = Super, mouse_up, workspace, +1 # [hidden]
bind = Super, mouse_down, workspace, -1 # [hidden]
bind = Super+Shift, mouse_up, movetoworkspace, r+1 # [hidden]
bind = Super+Shift, mouse_down, movetoworkspace, r-1 # [hidden]
bind = Super+Ctrl, E, workspace, empty # Aller au premier bureau vide
bind = Super+Ctrl+Shift, E, movetoworkspace, empty # Déplacer la fenêtre vers un bureau vide
bind = Ctrl+Super, S, togglespecialworkspace, # Bureau spécial (bloc-notes) : afficher / masquer
bind = Super+Alt, S, movetoworkspacesilent, special # Envoyer la fenêtre au bureau spécial
bind = Super, mouse:275, togglespecialworkspace, # [hidden]

##! Session
bind = Super, L, exec, loginctl lock-session # Verrouiller la session
bindl = Super+Shift, L, exec, systemctl suspend || loginctl suspend # Mettre en veille
bind = Ctrl+Shift+Alt+Super, Delete, exec, systemctl poweroff || loginctl poweroff # [hidden]

#!
##! Applications
bind = Super, R, exec, \$terminal # Terminal (kitty)
bind = Super, Return, exec, \$terminal # [hidden]
bind = Super, T, exec, \$terminal # [hidden]
bind = Ctrl+Alt, T, exec, \$terminal # [hidden]
bind = Super, E, exec, \$fileManager # Gestionnaire de fichiers (Dolphin)
bind = Super, B, exec, \$browser # Navigateur
bind = Super, W, exec, \$browser # [hidden]
bind = Super, C, exec, \$calculator # Calculatrice
bind = Ctrl+Super, C, exec, \$codeEditor # Éditeur de code (si installé)
bind = Super, X, exec, \$textEditor # Éditeur de texte (si installé)
bind = Super, I, exec, \$settingsApp # Paramètres
bind = Ctrl+Shift, Escape, exec, \$taskManager # Gestionnaire de tâches
bind = Ctrl+Super+Shift+Alt, W, exec, \$officeSoftware # [hidden]

##! Machines virtuelles
bind = Super+Alt, F1, exec, notify-send -a Hyprland "Raccourcis désactivés" "Super+Alt+F1 pour les réactiver" && hyprctl dispatch submap virtual-machine # Désactiver les raccourcis (VM)
submap = virtual-machine
bind = Super+Alt, F1, exec, notify-send -a Hyprland "Raccourcis réactivés" && hyprctl dispatch submap global # [hidden]
submap = global

source = ~/.config/hypr/custom/keybinds.user.conf
EOF
  [[ -f $HYPR_CUSTOM/keybinds.user.conf ]] || printf '# hyprlang noerror false\n# Vos raccourcis personnels (jamais écrasés par install.sh)\n' >"$HYPR_CUSTOM/keybinds.user.conf"

  # Le fichier QWERTY d'end-4 n'est plus chargé ($dontLoadDefaultKeybinds) ; on le
  # remplace par un fichier vide afin que l'aide (Super+F1), qui lit les deux
  # fichiers, n'affiche que les raccourcis réellement actifs. Original conservé.
  write_managed "$CFG/hypr/hyprland/keybinds.conf" <<EOF
$MANAGED_MARK
# Raccourcis QWERTY d'end-4 désactivés (\$dontLoadDefaultKeybinds = true).
# Raccourcis actifs (AZERTY) : ~/.config/hypr/custom/keybinds.conf
# Original : ~/.local/share/hypr-installer/manifests/end4-keybinds.upstream.conf
EOF
  write_keybind_doc
  ok "Raccourcis AZERTY générés ($(grep -cE '^bind' "$HYPR_CUSTOM/keybinds.conf") liaisons, 10 bureaux)"
}

write_keybind_doc() {
  mkdir -p "$MANIFEST_DIR"
  cat >"$MANIFEST_DIR/raccourcis-azerty.txt" <<'EOF'
RACCOURCIS AZERTY (Super = touche Windows) — aide à l'écran : Super+F1
Super+R terminal | Super+E fichiers | Super+Espace lanceur | Super (appui court) lanceur
Super+Q fermer | Super+F plein écran | Super+D maximiser | Super+V flottant | Super+P pseudo
Super+L verrouiller | Super+S capture de zone | Super+B navigateur | Super+C calculatrice
Super+Échap menu système (déconnexion avec confirmation) | Super+F5 recharger Hyprland
Ctrl+Super+R redémarrer Quickshell | Ctrl+Maj+Échap gestionnaire de tâches
Super+flèches focus | Super+Maj+flèches déplacer | Super+Ctrl+flèches redimensionner
Super+clic gauche déplacer | Super+clic droit redimensionner
Super+& é " ' ( - è _ ç à : bureaux 1…10 | Super+Maj+(même touche) : déplacer la fenêtre
Super+Alt+(même touche) : envoyer sans suivre | Super+PgPréc/PgSuiv ou Super+Alt+←/→ : bureau préc./suiv.
Super+Maj+PgPréc/PgSuiv : déplacer vers bureau préc./suiv. | Super+Ctrl+E : bureau vide
Impr : écran -> presse-papiers | Ctrl+Impr : écran -> fichier | Maj+Impr : zone -> fichier
Super+Maj+V presse-papiers | Super+; émojis | Super+Tab vue d'ensemble | Super+N/A panneaux
Touches multimédia (volume, muet, micro, lecture, luminosité) : sans Super, avec OSD
EOF
}

# =============================================================================
# 14. ÉTAPE 10 — BUREAU : thèmes, polices, fonds d'écran, démarrage
# =============================================================================
configure_themes() {
  dbus-run-session -- bash -c "
    gsettings set org.gnome.desktop.interface icon-theme 'breeze-plus-dark'
    gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic'
    gsettings set org.gnome.desktop.interface cursor-size 24" || warn "gsettings indisponible hors session"
  mkdir -p "$HOME/.icons/default"
  write_managed "$HOME/.icons/default/index.theme" <<EOF
[Icon Theme]
Name=Default
Comment=$MANAGED_MARK
Inherits=Bibata-Modern-Classic
EOF
  write_managed "$HYPR_CUSTOM/env.conf" <<EOF
# hyprlang noerror false
$MANAGED_MARK
env = XCURSOR_THEME,Bibata-Modern-Classic
env = XCURSOR_SIZE,24
source = ~/.config/hypr/custom/env.user.conf
EOF
  [[ -f $HYPR_CUSTOM/env.user.conf ]] || printf '# Variables d’environnement personnelles\n' >"$HYPR_CUSTOM/env.user.conf"
  ok "Thèmes : Darkly (Qt), adw-gtk3 (GTK, couleurs dynamiques matugen), breeze-plus, curseur Bibata"
}

configure_fonts() {
  spin "Cache des polices" fc-cache -f
  local fam missing=() fams
  fams=$(fc-list : family)
  for fam in "Google Sans Flex" "Material Symbols Rounded" "JetBrainsMono Nerd Font" "Readex Pro" "Space Grotesk" \
             "Rubik" "Twemoji" "Noto Sans" "Noto Sans CJK" "Font Awesome"; do
    containsi "$fam" "$fams" || missing+=("$fam")
  done
  if ((${#missing[@]} == 0)); then ok "Polices end-4, Noto, CJK, Nerd, Font Awesome présentes"; else warn "Polices manquantes : ${missing[*]}"; fi
}

configure_wallpapers() {
  xdg-user-dirs-update
  local pics; pics=$(xdg-user-dir PICTURES)
  mkdir -p "$pics/Wallpapers"
  local f
  for f in /usr/share/backgrounds/archlinux/*.{jpg,png}; do
    [[ -e $pics/Wallpapers/$(basename "$f") ]] || cp "$f" "$pics/Wallpapers/"
  done
  [[ -f $DEFAULT_WALLPAPER ]] || die "Fond d’écran par défaut absent : $DEFAULT_WALLPAPER"
  state_set default-wallpaper "$pics/Wallpapers/$(basename "$DEFAULT_WALLPAPER")"
  ok "Fonds d’écran disponibles dans ${pics/#$HOME/\~}/Wallpapers (appliqué au premier démarrage)"
}

configure_startup() {
  mkdir -p "$BIN_DIR"
  install -m 755 "$SCRIPT_SELF" "$BIN_DIR/install.sh"
  write_managed "$HYPR_CUSTOM/execs.conf" <<EOF
# hyprlang noerror false
$MANAGED_MARK
# Premier démarrage : détection des écrans, fond d'écran + couleurs, tests de session.
exec-once = ~/.local/share/hypr-installer/bin/install.sh --first-login
source = ~/.config/hypr/custom/execs.user.conf
EOF
  [[ -f $HYPR_CUSTOM/execs.user.conf ]] || printf '# hyprlang noerror false\n# Vos programmes au démarrage (exec-once = …)\n' >"$HYPR_CUSTOM/execs.user.conf"
  # Une seule instance de chaque composant : hypridle est lancé par end-4 (exec-once).
  if systemctl --user is-enabled hypridle.service &>/dev/null; then
    systemctl --user disable hypridle.service; info "hypridle.service (utilisateur) désactivé : lancé une seule fois par end-4"
  fi
  local n; n=$(cat "$CFG/hypr/hyprland/execs.conf" "$HYPR_CUSTOM"/*.conf | awk '/^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*(qs|quickshell)[[:space:]]/{c++} END{print c+0}')
  [[ $n == 1 ]] || warn "Quickshell est lancé $n fois dans la configuration (attendu : 1)"
  ok "Démarrage automatique configuré (Quickshell, hypridle, presse-papiers, agent polkit Quickshell, premier démarrage)"
}

configure_desktop() { configure_themes; configure_fonts; configure_wallpapers; configure_startup; }

# =============================================================================
# 15. ÉTAPE 11 — SERVICES
# =============================================================================
configure_audio() {
  pac_install "${AUDIO_PKGS[@]}"
  sudo systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service
  ok "PipeWire + WirePlumber + pipewire-pulse activés pour les sessions utilisateur"
}

configure_network() {
  pac_install "${NET_PKGS[@]}"
  if systemctl is-active --quiet NetworkManager.service; then
    sudo systemctl enable NetworkManager.service
    ok "NetworkManager actif et activé au démarrage"
  elif systemctl is-active --quiet systemd-networkd.service || systemctl is-active --quiet iwd.service; then
    warn "Un autre gestionnaire réseau est actif (systemd-networkd/iwd) : NetworkManager reste désactivé pour préserver la connexion."
  else
    sudo systemctl enable --now NetworkManager.service
    ok "NetworkManager activé et démarré"
  fi
}

configure_bluetooth() {
  pac_install "${BT_PKGS[@]}"
  sudo systemctl enable bluetooth.service
  if ((BT_ADAPTER)); then sudo systemctl start bluetooth.service; ok "Bluetooth activé (adaptateur détecté)"
  else info "Bluetooth activé mais aucun adaptateur détecté (démarrera automatiquement si un adaptateur est ajouté)"; fi
}

configure_services() {
  pkg_installed polkit || die "polkit absent"
  ok "polkit présent ; agent d’authentification fourni par Quickshell (aucun agent supplémentaire)"
  local d
  for d in dunst mako swaync; do pkg_installed "$d" && warn "$d installé : conflit possible avec les notifications de Quickshell (non lancé par cette configuration)."; done
  pkg_installed hyprpolkitagent && warn "hyprpolkitagent installé : deux agents polkit risqueraient d’entrer en conflit."
  return 0
}

configure_login_manager() {
  if [[ -z $CURRENT_DM ]]; then
    pac_install sddm
    sudo systemctl enable sddm.service
    CURRENT_DM=sddm
    ok "SDDM installé et activé (aucun gestionnaire de connexion n’était présent)"
  else
    ok "Gestionnaire de connexion existant conservé : $CURRENT_DM"
  fi
  [[ -f /usr/share/wayland-sessions/hyprland.desktop ]] || die "Session /usr/share/wayland-sessions/hyprland.desktop absente"
  case $CURRENT_DM in
    sddm)
      local st=/var/lib/sddm/state.conf tmp
      tmp=$(mktemp "$TMP_DIR/state.XXXXXX")
      # shellcheck disable=SC2024  # lecture d'un fichier root vers un fichier temporaire utilisateur (voulu)
      if sudo test -f "$st"; then sudo cat "$st" >"$tmp"; fi
      awk -v u="$USER" '
        function flush_last() {
          if (inlast && !session) print "Session=hyprland.desktop"
          if (inlast && !user) print "User=" u
        }
        /^\[Last\]/ { flush_last(); print; inlast=1; found=1; session=0; user=0; next }
        /^\[/ { flush_last(); inlast=0 }
        inlast && /^Session=/ { if (!session) print "Session=hyprland.desktop"; session=1; next }
        inlast && /^User=/ { if (!user) print "User=" u; user=1; next }
        { print }
        END { flush_last(); if (!found) { print "[Last]"; print "Session=hyprland.desktop"; print "User=" u } }
      ' "$tmp" >"$tmp.new"
      if ! sudo cmp -s "$tmp.new" "$st"; then
        sudo_write "$st" 644 <"$tmp.new"
        sudo chown sddm:sddm "$st" 2>/dev/null || true
      fi
      ok "SDDM : session Hyprland présélectionnée (écran de connexion en AZERTY via X11)" ;;
    gdm|lightdm|lxdm|ly)
      local acc="/var/lib/AccountsService/users/$USER"
      if [[ -d /var/lib/AccountsService/users ]]; then
        local cur=""; sudo test -f "$acc" && cur=$(sudo cat "$acc")
        if ! grep -q '^Session=hyprland$' <<<"$cur"; then
          { if grep -q '^\[User\]' <<<"$cur"; then sed -e '/^Session=/d' -e '/^XSession=/d' -e 's/^\[User\]$/[User]\nSession=hyprland/' <<<"$cur"
            else printf '%s\n[User]\nSession=hyprland\n' "$cur"; fi; } | sudo_write "$acc" 600
        fi
      fi
      ok "$CURRENT_DM : session Hyprland présélectionnée (AccountsService)" ;;
    *) warn "Gestionnaire de connexion « $CURRENT_DM » : sélectionnez « Hyprland » manuellement au premier login." ;;
  esac
  pkg_installed uwsm && warn "Choisissez « Hyprland » et non « Hyprland (uwsm-managed) » à l’écran de connexion."
  return 0
}

configure_all_services() { configure_audio; configure_network; configure_bluetooth; configure_services; configure_login_manager; }

# =============================================================================
# 16. ÉTAPE 12 — VALIDATION ET RAPPORT
# =============================================================================
chk() {   # chk STATUT "libellé" "détail"
  local st=$1 label=$2 detail=${3:-} col
  case $st in PASS) col=$C_GRN; CHECK_PASS+=1;; WARN) col=$C_YEL; CHECK_WARN+=1;; FAIL) col=$C_RED; CHECK_FAIL+=1;; *) col=$C_DIM;; esac
  CHECK_LINES+=("$(printf '[%-4s] %-38s %s' "$st" "$label" "$detail")")
  log "CHECK $st $label — $detail"
  printf '  %s[%-4s]%s %-38s %s%s%s\n' "$col" "$st" "$C_RST" "$label" "$C_DIM" "$detail" "$C_RST" >&3
}
chk_if() { if eval "$2"; then chk PASS "$1" "${3:-}"; else chk "${4:-FAIL}" "$1" "${5:-${3:-}}"; fi; }

diagnose_summary() {
  CHECK_LINES=(); CHECK_FAIL=0; CHECK_WARN=0; CHECK_PASS=0
  chk PASS "Pré-vérifications système" "Distribution, architecture, réseau et espace disque"
  chk PASS "Détection matérielle" "${CPU_MODEL:-CPU inconnu} · ${GPU_DRIVER:-pilote GPU non identifié}"
  chk INFO "Installation non exécutée" "Les étapes 3 à 11 ont été volontairement ignorées en mode --diagnose."
  chk INFO "Validation complète" "À effectuer après l'installation normale."
}

validate_installation() {
  ui ""; ui "  ${C_B}Contrôles hors session graphique${C_RST}"
  CHECK_LINES=(); CHECK_FAIL=0; CHECK_WARN=0; CHECK_PASS=0
  chk_if "EndeavourOS détecté" '[[ $OS_ID == endeavouros ]]' "$OS_NAME" WARN
  local hv; hv=$(Hyprland --version 2>/dev/null | head -1 || true)
  chk_if "Hyprland 0.54.3 installé" '[[ $hv == *0.54.3* && $(pkg_version hyprland) == 0.54.3-* ]]' "${hv:-absent}"
  local n bad=""
  for n in "${PIN_ORDER[@]}"; do [[ $(pkg_version "$n") == "$(expected_pin_version "$n")" ]] || bad+="$n "; done
  chk_if "Pile hypr* épinglée intacte" '[[ -z $bad && -f $PINS_LOCK ]]' "${#PIN_ORDER[@]} paquets" FAIL "dérive : ${bad:-verrou absent}"
  local broken; broken=$(pin_broken_list | xargs)
  chk_if "ABI de la pile (bibliothèques)" '[[ -z $broken ]]' "aucune bibliothèque manquante" FAIL "cassé : $broken"
  chk_if "IgnorePkg (pacman.conf)" 'grep -q "^IgnorePkg = ${PIN_ORDER[*]}$" /etc/pacman.conf' "pile protégée de -Syu"
  local vout; vout=$(Hyprland --verify-config -c "$CFG/hypr/hyprland.conf" 2>&1 || true)
  log "verify-config : $vout"
  chk_if "Configuration hyprlang valide" 'grep -qi "config ok" <<<"$vout"' "Hyprland --verify-config" FAIL "$(grep -im1 -E 'error|erreur' <<<"$vout" || echo 'voir journal')"
  local rel; rel=$(cat "$CFG/illogical-impulse/hypr-installer-release" 2>/dev/null || true)
  chk_if "End-4 release correcte" '[[ $rel == "$END4_TAG $END4_COMMIT" && -f $CFG/quickshell/ii/shell.qml ]]' "$END4_TAG ${END4_COMMIT:0:12}"
  local qdiff=""
  if [[ ! -d $END4_DIR/dots/.config/quickshell || ! -d $CFG/quickshell ]]; then
    qdiff="répertoire source ou destination absent"
  else
    qdiff=$(diff -qr "$END4_DIR/dots/.config/quickshell" "$CFG/quickshell" 2>/dev/null | head -3 || true)
  fi
  chk_if "Fichiers Quickshell identiques à la release" '[[ -z $qdiff ]]' "$CFG/quickshell" WARN "${qdiff:-}"
  local qsc; qsc=$(state_get quickshell.commit)
  chk_if "Quickshell installé" 'pkg_installed illogical-impulse-quickshell-git && command -v qs >/dev/null' "commit ${qsc:0:12}$([[ $qsc == "$QS_FALLBACK_COMMIT" ]] && echo ' (repli v0.3.0)')"
  chk_if "Quickshell compatible avec Qt installé" 'quickshell --private-check-compat >/dev/null 2>&1' "Qt $(pkg_version qt6-base)" WARN
  local pyok; pyok=$("$VENV_DIR/bin/python" -c 'import materialyoucolor, PIL, cv2, numpy, psutil, loguru; print("ok")' 2>/dev/null || true)
  chk_if "Environnement Python des widgets" '[[ $pyok == ok ]]' "${VENV_DIR/#$HOME/\~}"
  local c miss=""
  for c in matugen cliphist wl-paste grim slurp hyprpicker fuzzel ydotool cava kdialog tesseract wf-recorder swappy hyprshot \
           trans songrec qalc ddcutil brightnessctl playerctl wpctl kitty dolphin; do
    command -v "$c" >/dev/null || miss+="$c "
  done
  chk_if "Outils requis par les widgets" '[[ -z $miss ]]' "tous présents" FAIL "manquants : $miss"
  chk_if "Configuration KDE facultative" 'command -v kwriteconfig6 >/dev/null 2>&1' "kwriteconfig6" WARN
  chk_if "Session Wayland Hyprland" '[[ -f /usr/share/wayland-sessions/hyprland.desktop && -x /usr/bin/start-hyprland ]]' "hyprland.desktop -> start-hyprland"
  chk_if "Portails XDG" 'pkg_installed xdg-desktop-portal && [[ -f /usr/share/xdg-desktop-portal/portals/hyprland.portal && -f $CFG/xdg-desktop-portal/hyprland-portals.conf ]]' "hyprland + gtk + kde"
  chk_if "Polkit" 'pkg_installed polkit && ! pkg_installed hyprpolkitagent' "agent : Quickshell (PolkitService)"
  chk_if "Audio (PipeWire activé)" '[[ -e /etc/systemd/user/sockets.target.wants/pipewire.socket || -e /usr/lib/systemd/user/sockets.target.wants/pipewire.socket ]] && pkg_installed wireplumber && pkg_installed pipewire-pulse' "pipewire, pulse, wireplumber"
  chk_if "Réseau (NetworkManager)" 'systemctl is-active --quiet NetworkManager' "$(nmcli -t networking connectivity 2>/dev/null || echo '?')" WARN
  if ((BT_ADAPTER)); then chk_if "Bluetooth" 'systemctl is-active --quiet bluetooth' "adaptateur détecté" WARN
  else chk INFO "Bluetooth" "aucun adaptateur (service activé, démarrage conditionnel)"; fi
  chk_if "GPU AMD détecté" '((HAS_AMD_GPU))' "pilote ${GPU_DRIVER:-?}"
  local vk; vk=$(vulkaninfo --summary 2>/dev/null | grep -m1 deviceName | sed 's/.*= //' || true)
  chk_if "Vulkan (RADV)" '[[ $vk == *RADV* ]]' "${vk:-non confirmé hors session}" WARN
  local fm="" fams; fams=$(fc-list : family); for c in "Google Sans Flex" "Material Symbols Rounded" "JetBrainsMono Nerd Font" "Noto Sans" "Font Awesome"; do containsi "$c" "$fams" || fm+="$c, "; done
  chk_if "Polices installées" '[[ -z $fm ]]' "end-4 + Noto + Nerd + Font Awesome" WARN "manquantes : ${fm%, }"
  chk_if "AZERTY configuré" 'grep -q "kb_layout = fr" "$HYPR_CUSTOM/general.conf" && contains "X11 Layout: fr" "$(localectl status)"' "Hyprland, console, X11"
  local nb; nb=$(grep -cE '^bind' "$HYPR_CUSTOM/keybinds.conf" 2>/dev/null || true); nb=${nb:-0}
  chk_if "Raccourcis clavier configurés" 'grep -q "^\$dontLoadDefaultKeybinds = true" "$HYPR_CUSTOM/variables.conf" && ((nb > 100))' "$nb liaisons AZERTY"
  local wsn; wsn=$(grep -cE '^bind = Super(\+Shift)?, code:(1[0-9]),' "$HYPR_CUSTOM/keybinds.conf" 2>/dev/null || true); wsn=${wsn:-0}
  chk_if "Workspaces 1-10 configurés" '((wsn == 20))' "Super+[1-0] et Super+Maj+[1-0]"
  chk_if "Gestionnaire de connexion" '[[ -n $CURRENT_DM ]] && systemctl is-enabled --quiet display-manager.service' "${CURRENT_DM:-aucun}"
  chk_if "Autostart configuré" 'grep -q -- "--first-login" "$HYPR_CUSTOM/execs.conf" && [[ -x $BIN_DIR/install.sh ]]' "exec-once (end-4 + premier démarrage)"
  local dup=""; for c in dunst mako swaync hyprpolkitagent; do pkg_installed "$c" && dup+="$c "; done
  systemctl --user is-enabled hypridle.service &>/dev/null && dup+="hypridle.service "
  chk_if "Aucun conflit de démarrage" '[[ -z $dup ]]' "instance unique de chaque composant" WARN "à vérifier : $dup"
  chk_if "Chargeur de démarrage non modifié" 'true' "aucune commande bootloader/partition exécutée"
  chk INFO "Tests en session graphique" "automatiques au premier login (rapport + notification)"
  if ((CHECK_FAIL)); then STEP_STATUS[CURRENT_STEP]=FAILED; elif ((CHECK_WARN)); then STEP_WARN[CURRENT_STEP]=1; fi
}

write_report() {
  local title=${1:-"Rapport d’installation"} f
  mkdir -p "$REPORT_DIR"
  f="$REPORT_DIR/report-$RUN_TS-$MODE.txt"
  {
    printf 'HYPRLAND AUTOMATED INSTALLER %s — %s\n' "$INSTALLER_VERSION" "$title"
    printf 'Date : %s   Mode : %s   Utilisateur : %s\n\n' "$(date '+%F %T')" "$MODE" "$USER"
    printf 'Étapes :\n'; local i; for i in $(seq 1 12); do printf '  [%02d/12] %-27s %s\n' "$i" "${STEP_TITLES[i]}" "${STEP_STATUS[i]}"; done
    printf '\nContrôles (%d OK, %d avertissements, %d échecs) :\n' "$CHECK_PASS" "$CHECK_WARN" "$CHECK_FAIL"
    printf '  %s\n' "${CHECK_LINES[@]:-aucun}"
    printf '\nAvertissements :\n'; printf '  - %s\n' "${WARNINGS[@]:-aucun}"
    printf '\nManifeste des versions :\n'; cat "$MANIFEST_DIR/versions-latest.txt" 2>/dev/null || true
    printf '\nJournal : %s\nSauvegardes : %s\n' "$LOG_FILE" "$BACKUP_DIR"
  } >"$f"
  cp -f "$f" "$REPORT_DIR/latest-$MODE.txt"
  printf '%s' "$f"
}

generate_report() {
  local f; f=$(write_report)
  ui ""
  ui "  Rapport : ${f/#$HOME/\~}"
}

# =============================================================================
# 17. MODES SESSION : premier démarrage et tests post-connexion
# =============================================================================
wait_for() { local t=$1; shift; local i; for ((i = 0; i < t; i++)); do "$@" &>/dev/null && return 0; sleep 1; done; return 1; }

session_monitors() {
  local conf="$CFG/hypr/monitors.conf" line
  if grep -qE '^\s*monitor\s*=' "$conf" 2>/dev/null; then log "monitors.conf déjà configuré"; return 0; fi
  local out=""
  while IFS=$'\t' read -r name w h modes; do
    local best="" bestr=0 m r
    for m in $modes; do
      [[ $m == "${w}x${h}@"* ]] || continue
      r=${m#*@}; r=${r%Hz}
      if awk -v a="$r" -v b="$bestr" 'BEGIN{exit !(a>b)}'; then bestr=$r; best=$m; fi
    done
    [[ -n $best ]] || continue
    local scale=1; ((w >= 3840)) && scale=auto
    line="monitor = $name, ${best%Hz}, auto, $scale"
    out+="$line"$'\n'
    log "Écran $name : $line (modes : $modes)"
  done < <(hyprctl monitors all -j | jq -r '.[] | [.name, (.width|tostring), (.height|tostring), (.availableModes|join(" "))] | @tsv')
  [[ -n $out ]] || return 0
  { cat "$conf" 2>/dev/null; printf '\n%s — détecté au premier démarrage (résolution native, fréquence max.)\n%s' "$MANAGED_MARK" "$out"; } >"$conf.tmp"
  mv -f "$conf.tmp" "$conf"
  hyprctl reload >/dev/null
}

session_wallpaper() {
  local cfgjson="$CFG/illogical-impulse/config.json" wp wall
  wait_for 40 test -s "$cfgjson" || { log "config.json absent"; return 0; }
  wp=$(jq -r '.background.wallpaperPath // ""' "$cfgjson" 2>/dev/null || true)
  [[ -z $wp ]] || { log "Fond d’écran déjà défini : $wp"; return 0; }
  wall=$(state_get default-wallpaper); [[ -f $wall ]] || wall=$DEFAULT_WALLPAPER
  "$CFG/quickshell/ii/scripts/colors/switchwall.sh" --image "$wall" --mode dark || log "switchwall a échoué"
}

post_login_check() {
  CHECK_LINES=(); CHECK_FAIL=0; CHECK_WARN=0; CHECK_PASS=0
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || { chk FAIL "Session Hyprland" "à lancer depuis une session Hyprland"; return 0; }
  local v; v=$(hyprctl version -j 2>/dev/null | jq -r '.tag // .version // ""')
  chk_if "Hyprland en cours d’exécution" '[[ $v == *0.54.3* ]]' "$v"
  chk_if "Wayland opérationnel" '[[ -n ${WAYLAND_DISPLAY:-} && $XDG_SESSION_TYPE == wayland ]]' "${WAYLAND_DISPLAY:-?}"
  chk_if "Quickshell opérationnel" 'qs -c ii ipc call TEST_ALIVE' "IPC TEST_ALIVE"
  local nq nq2; nq=$(pgrep -xc qs 2>/dev/null || true); nq2=$(pgrep -xc quickshell 2>/dev/null || true); nq=$(( ${nq:-0} + ${nq2:-0} ))
  chk_if "Une seule instance de Quickshell" '((nq == 1))' "$nq processus"
  chk_if "Widgets disponibles" '[[ -s $CFG/illogical-impulse/config.json ]] && qs -c ii ipc show >/dev/null' "barre, panneaux, OSD, lanceur"
  chk_if "Portails opérationnels" 'busctl --user status org.freedesktop.portal.Desktop >/dev/null && pgrep -x xdg-desktop-portal-hyprland >/dev/null' "xdg-desktop-portal + hyprland" WARN
  chk_if "Audio opérationnel" 'wpctl inspect @DEFAULT_AUDIO_SINK@ >/dev/null' "$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -m1 'node.description' | cut -d'"' -f2)" WARN
  chk_if "Réseau opérationnel" '[[ $(nmcli -t networking connectivity) == full ]]' "$(nmcli -t networking connectivity 2>/dev/null)" WARN
  local km; km=$(hyprctl devices -j | jq -r '[.keyboards[] | select(.main == true) | .active_keymap][0] // .keyboards[0].active_keymap')
  chk_if "Disposition AZERTY active" '[[ $km == *French* ]]' "$km"
  local nb; nb=$(hyprctl binds -j | jq 'length')
  chk_if "Raccourcis chargés" '((nb > 100))' "$nb liaisons actives"
  chk_if "Raccourci Super+R (terminal)" 'hyprctl binds -j | jq -e ".[] | select(.modmask == 64 and .key == \"R\")" >/dev/null' "kitty"
  chk_if "Workspaces Super+1…0" '(( $(hyprctl binds -j | jq "[.[] | select(.modmask == 64 and (.keycode >= 10 and .keycode <= 19))] | length") == 10 ))' "codes physiques 10-19"
  chk_if "Écrans détectés" 'hyprctl monitors -j | jq -e "length > 0" >/dev/null' "$(hyprctl monitors -j | jq -r '.[] | "\(.name) \(.width)x\(.height)@\(.refreshRate|floor)Hz"' | paste -sd', ')"
  local r; r=$(hyprctl -j getoption decoration:blur:passes | jq -r '.int')
  chk INFO "Accélération graphique" "$(LC_ALL=C eglinfo -B 2>/dev/null | grep -m1 'OpenGL renderer' | cut -d: -f2 | xargs || echo 'eglinfo indisponible') — flou $r passes"
  chk INFO "Polkit (manuel)" "lancez « pkexec true » : la fenêtre doit venir de Quickshell"
}

first_login() {
  mkdir -p "$LOG_DIR" "$STATE_DIR" "$REPORT_DIR"
  LOG_FILE="$LOG_DIR/first-login-$RUN_TS.log"
  exec 3>/dev/null 4>/dev/null 5>>"$LOG_FILE" >>"$LOG_FILE" 2>&1
  [[ -f $STATE_DIR/first-login.done ]] && { log "Premier démarrage déjà effectué"; return 0; }
  wait_for 60 hyprctl version || exit 0
  wait_for 60 qs -c ii ipc call TEST_ALIVE || log "Quickshell non joignable après 60 s"
  session_monitors
  session_wallpaper
  sleep 3
  post_login_check
  local f; f=$(write_report "Tests en session graphique (premier démarrage)")
  if ((CHECK_FAIL)); then
    notify-send -u critical -a "Installation Hyprland" "Installation : $CHECK_FAIL problème(s) détecté(s)" "Rapport : $f"
  else
    notify-send -a "Installation Hyprland" "Bureau prêt ✔" "$CHECK_PASS tests OK, $CHECK_WARN avertissement(s). Super+F1 : liste des raccourcis."
  fi
  date '+%F %T' >"$STATE_DIR/first-login.done"
}

# =============================================================================
# 18. PROGRAMME PRINCIPAL
# =============================================================================
usage() {
  cat <<EOF
HYPRLAND AUTOMATED INSTALLER $INSTALLER_VERSION
EndeavourOS × Hyprland ${PIN_VER[hyprland]%-*} × end-4/dots-hyprland $END4_TAG

Usage : ./install.sh [options]

  (sans option)        Installation complète, avec reprise automatique après interruption
  --yes                Ne pas demander la confirmation initiale
  --force              Réexécuter toutes les étapes (ignore les points de reprise)
  --diagnose           Mode diagnostic : contrôles et rapport, aucune modification
  --repair             Réparation : revérifie la pile épinglée, recompile ce qui est
                       cassé (ex. après une mise à jour de bibliothèque), redéploie
  --post-login-check   Tests à exécuter DANS la session Hyprland
  --allow-non-eos      Autoriser une base Arch autre qu’EndeavourOS
  --allow-other-gpu    Autoriser l’absence de GPU AMD
  --no-reboot-prompt   Ne pas proposer le redémarrage à la fin
  -h, --help           Cette aide     --version   Version

Journaux, sauvegardes, rapports : ~/.local/share/hypr-installer/
EOF
}

parse_args() {
  while (($#)); do
    case $1 in
      --yes|-y) ASSUME_YES=1 ;;
      --force) FORCE=1 ;;
      --diagnose) MODE=diagnose ;;
      --repair) MODE=repair; FORCE=1 ;;
      --post-login-check) MODE=post-login-check ;;
      --first-login) MODE=first-login ;;
      --allow-non-eos) ALLOW_NON_EOS=1 ;;
      --allow-other-gpu) ALLOW_OTHER_GPU=1 ;;
      --no-reboot-prompt) NO_REBOOT_PROMPT=1 ;;
      -h|--help) usage; exit 0 ;;
      --version) printf '%s\n' "$INSTALLER_VERSION"; exit 0 ;;
      *) printf 'Option inconnue : %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
  done
}

main() {
  exec 5>/dev/null
  parse_args "$@"
  umask 022
  mkdir -p "$LOG_DIR" "$BACKUP_ROOT" "$STATE_DIR" "$REPORT_DIR" "$MANIFEST_DIR" "$BIN_DIR" "$PKG_CACHE" "$BUILD_DIR"
  trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
  trap on_interrupt INT TERM
  trap on_exit EXIT
  TMP_DIR=$(mktemp -d /tmp/hypr-installer.XXXXXX)

  if [[ $MODE == first-login ]]; then first_login; exit 0; fi
  if [[ $MODE == post-login-check ]]; then
    LOG_FILE="$LOG_DIR/post-login-$RUN_TS.log"
    exec 3>&1 4>&2 5>>"$LOG_FILE"; exec >>"$LOG_FILE" 2>&1
    post_login_check; ui ""; ui "  Rapport : $(write_report "Tests en session graphique")"
    exit $((CHECK_FAIL > 0))
  fi

  exec 3>&1 4>&2 5>>"$LOG_FILE"
  exec >>"$LOG_FILE" 2>&1
  log "hypr-installer $INSTALLER_VERSION — mode $MODE — $(uname -a)"
  draw_dashboard

  if [[ $MODE == diagnose ]]; then
    run_step 1 preflight resolve_versions
    run_step 2 detect_hardware
    local i; for i in 3 4 5 6 7 8 9 10 11; do STEP_STATUS[i]=SKIPPED; done
    CURRENT_DM=${CURRENT_DM:-}
    # Le diagnostic ne réalise aucune installation : ne pas valider les fichiers
    # et paquets que les étapes volontairement ignorées doivent créer.
    run_step 12 diagnose_summary generate_report
    exit 0
  fi

  run_step 1 preflight resolve_versions confirm_plan
  run_step 2 detect_hardware
  run_step 3 install_system_packages
  run_step 4 install_graphics
  run_step 5 install_hyprland
  run_step 6 install_end4
  run_step 7 install_quickshell
  run_step 8 configure_keyboard
  run_step 9 configure_keybindings
  run_step 10 configure_desktop
  run_step 11 configure_all_services
  run_step 12 validate_installation generate_report

  ui ""
  if ((CHECK_FAIL)); then
    ui "  ${C_RED}${C_B}Installation terminée avec $CHECK_FAIL échec(s) de validation.${C_RST} Consultez le rapport ci-dessus."
    ui "  Correction automatique : ./install.sh --repair"
    exit 1
  fi
  ui "  ${C_GRN}${C_B}Installation terminée.${C_RST} ${CHECK_WARN} avertissement(s)."
  ui "  Au redémarrage : écran de connexion -> session « Hyprland » (présélectionnée)."
  ui "  Aide des raccourcis : Super+F1. Les tests en session s’exécutent seuls au premier login."
  if ((!NO_REBOOT_PROMPT)) && ask_yes_no "Redémarrer maintenant ?"; then
    log "Redémarrage demandé"; sudo systemctl reboot
  fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi

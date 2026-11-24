#!/usr/bin/env bash
# =============================================================================
#  HYPRLAND AUTOMATED INSTALLER — install.sh
#  EndeavourOS × Hyprland (dépôts Arch, configuration Lua) × end-4/dots-hyprland (main 2026-11-15)
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

readonly INSTALLER_VERSION="3.3.0"
# Schéma des points de reprise : à incrémenter si la signification d'une étape change.
readonly CHECKPOINT_SCHEMA=4
readonly MAIN_PID=$$
SCRIPT_SELF="$(readlink -f -- "${BASH_SOURCE[0]}")"
readonly SCRIPT_SELF

# =============================================================================
# 0. MANIFESTE DES VERSIONS (déterminé pendant l'audit — voir README §Matrice)
# =============================================================================
# --- end-4 / illogical-impulse ---------------------------------------------
readonly END4_REPO="https://github.com/end-4/dots-hyprland.git"
# 3.0 : la release 2026.05.11 (Hyprland 0.54, hyprlang) ne fonctionnait pas sur un
# système de novembre 2026 (plantage de Hyprland 0.54.3 au démarrage, Quickshell
# incompatible Qt 6.12). On suit désormais Hyprland des dépôts Arch et la
# branche main d'end-4 (configuration Lua), épinglée à un commit précis.
readonly END4_TAG="main-2026-11-15"                               # libellé (pas de tag plus récent que 2026.05.11)
readonly END4_COMMIT="21733c3ca7f4edc20faafedea844dc96002c6f7f"   # branche main, 2026-11-15
readonly END4_SHAPES_COMMIT="e31ec4cb4ebf6a46b267f5c42eabf6874916fa16" # sous-module rounded-polygon-qmljs
# --- Quickshell (épinglé par end-4 dans illogical-impulse-quickshell-git) ----
readonly QS_COMMIT="4f508be500dea6e5732cc3d50382a0048b17e7b1"   # v0.3.2, épinglé par end-4 main
# Qt 6.12 a cassé la compilation du commit épinglé par end-4 (constaté sur la
# machine cible : échec dans src/wayland/hyprland/ipc). Le correctif amont est
# 5d5d498 « all: use MOC includes … Fixes linking issues and Qt 6.12
# compatibility » (2026-08-26), absent de 7511545 et de v0.3.0/v0.3.1.
readonly QS_QT_FIX_MIN="6.12"            # Qt à partir duquel le commit épinglé ne compile plus
readonly -a QS_FALLBACKS=(
  "9b0f339b19057f4731bf3b48293307d7ef241671|master 2026-10-17"   # + 1c1cc91 (types MOC qualifiés)
)
readonly QS_MIRROR_URL="https://github.com/quickshell-mirror/quickshell.git"
# --- Étape 12 : applications, développement, IA (liste modifiable) ----------
readonly -a DEV_PKGS=(
  nodejs npm pnpm python python-pip python-pipx git-lfs github-cli
  jq ripgrep fd bat neovim tmux code docker docker-compose docker-buildx
)
# Paquets AUR suivis à leur DERNIÈRE version (un navigateur doit recevoir ses
# correctifs de sécurité) ; mises à jour ultérieures : yay -Syu.
readonly -a AUR_LATEST=("brave-bin|brave-bin")
readonly -a NPM_GLOBAL=(freebuff)                     # installés dans ~/.local (sans sudo)
readonly CLAUDE_INSTALL_URL="https://claude.ai/install.sh"   # installateur officiel (mises à jour automatiques)
readonly SKILLS_REPO="https://github.com/anthropics/skills.git"
readonly SKILLS_COMMIT="e4bb5d960d87126ff3b3a8af1a104b7db67560ba"   # 2026-11-16
readonly SKILLS_DIR="$HOME/.claude/skills"
readonly SKILL_MARK=".hypr-installer-managed"
# --- Police Google Sans Flex (end-4 la clone sur "main" : on l'épingle) -------
readonly GSF_REPO="https://github.com/end-4/google-sans-flex.git"
readonly GSF_COMMIT="251aa5abd30496368f634e54ce2a508fe5a2fdfa"
# --- Pile Hyprland épinglée : instantané Arch Linux du 2026-05-08 ------------
#     (dernier jour où Arch distribuait hyprland 0.54.3-4, avant 0.55.0)
readonly SNAPSHOT_DATE="2026-05-08"
readonly ALA_URL="https://archive.archlinux.org/packages"
readonly ARCH_PKG_GIT="https://gitlab.archlinux.org/archlinux/packaging/packages"
# Ordre = ordre de dépendance (utilisé pour les reconstructions).
# 3.0 : plus aucune version épinglée — PIN_ORDER est vide (les fonctions de la
# pile épinglée deviennent sans effet). LEGACY_PIN_PKGS sert uniquement à
# remplacer, sur une installation 2.x, les versions épinglées/recompilées par
# celles des dépôts.
readonly -a PIN_ORDER=()
readonly -a LEGACY_PIN_PKGS=(
  hyprutils hyprlang hyprwayland-scanner hyprwire hyprgraphics hyprcursor
  aquamarine hyprtoolkit hyprland-guiutils hyprland hypridle hyprlock
  hyprpicker hyprsunset xdg-desktop-portal-hyprland
)
# Paquets Hyprland installés depuis les dépôts (bibliothèques tirées en dépendances).
readonly -a HYPR_PKGS=(hyprland hypridle hyprlock hyprpicker hyprsunset xdg-desktop-portal-hyprland hyprland-guiutils)
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
# Modes :
#   src     : toujours recompilé dans le chroot (binaire archivé incompatible avec
#             le système actuel : hyprgraphics, hyprlock, xdph — compilation
#             confirmée sur la machine cible) ;
#   srcpref : recompilé contre le système actuel (Mesa, libglvnd, GCC récents) ;
#             si la compilation échoue, repli sur le binaire archivé vérifié ;
#   bin     : binaire archivé uniquement. Hyprland 0.54.3 ne se recompile plus :
#             hyprpm exige glaze 7.x, introuvable dans les dépôts actuels, et le
#             téléchargement de secours est impossible dans le chroot (constaté).
declare -Ar PIN_MODE=(
  [hyprutils]=srcpref [hyprlang]=srcpref [hyprwayland-scanner]=srcpref [hyprwire]=srcpref
  [hyprgraphics]=src  [hyprcursor]=srcpref [aquamarine]=srcpref [hyprtoolkit]=srcpref
  [hyprland-guiutils]=srcpref [hyprland]=bin [hypridle]=srcpref [hyprlock]=src
  [hyprpicker]=srcpref [hyprsunset]=srcpref [xdg-desktop-portal-hyprland]=src
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
# Compléments : 32 bits (jeux, Steam, Wine — si le dépôt multilib est activé),
# panneau de contrôle de la carte (LACT, équivalent du logiciel AMD Windows), amdgpu_top (moniteur).
readonly -a GRAPHICS_EXTRA_PKGS=(lact amdgpu_top)
readonly -a GRAPHICS_LIB32_PKGS=(lib32-mesa lib32-vulkan-radeon)
# YouTube : la RX 550 (Polaris) décode H.264/HEVC en matériel, mais ni VP9 ni AV1,
# formats envoyés par défaut -> décodage logiciel et saccades. L'extension
# enhanced-h264ify fait servir du H.264 ; les navigateurs utilisent VA-API.
readonly H264IFY_FIREFOX_ID="{9a41dee2-b924-4161-a971-7fb35c053a4a}"
readonly H264IFY_CHROME_ID="omkfmpieigblcllmkgbflkikinpkodlk"
readonly -a AUDIO_PKGS=(pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils pavucontrol-qt)
readonly -a FONT_PKGS=(noto-fonts noto-fonts-cjk noto-fonts-emoji otf-font-awesome ttf-nerd-fonts-symbols ttf-jetbrains-mono-nerd fontconfig)
readonly -a NET_PKGS=(networkmanager)
readonly -a BT_PKGS=(bluez bluez-utils)
readonly -a WALL_PKGS=(archlinux-wallpaper)
# Paquet local construit par l'installateur : fournit « otf-space-grotesk », dépendance
# du méta-paquet end-4 fonts-themes, depuis l'archive 38C3 vérifiée par SHA-256
# (le paquet AUR 38c3-styles tire des convertisseurs HTML inutiles).
readonly SPACE_GROTESK_PKG="hypr-installer-space-grotesk"
readonly SPACE_GROTESK_VER="1.1.4"
# Miroir GitHub officiel de l'AUR (une branche par pkgbase, mêmes commits).
readonly AUR_GITHUB_MIRROR="https://github.com/archlinux/aur.git"

# =============================================================================
# 0 bis. CHEMINS SYSTÈME
# =============================================================================
# SYSROOT est TOUJOURS vide en production. Il n'est lu que si HYPR_INSTALLER_TEST=1,
# pour que la simulation de bout en bout (tests/e2e-simulation.sh) n'écrive que
# dans un répertoire temporaire.
SYSROOT=""
if [[ ${HYPR_INSTALLER_TEST:-0} == 1 ]]; then SYSROOT=${HYPR_INSTALLER_SYSROOT:-}; fi
readonly SYSROOT
readonly OS_RELEASE="$SYSROOT/etc/os-release"
readonly PACMAN_CONF="$SYSROOT/etc/pacman.conf"
readonly PACMAN_LOCK="$SYSROOT/var/lib/pacman/db.lck"
readonly SYSTEMD_RUNDIR="$SYSROOT/run/systemd/system"
readonly DM_LINK="$SYSROOT/etc/systemd/system/display-manager.service"
readonly WAYLAND_SESSION="$SYSROOT/usr/share/wayland-sessions/hyprland.desktop"
readonly START_HYPRLAND="$SYSROOT/usr/bin/start-hyprland"
readonly HYPR_PORTAL="$SYSROOT/usr/share/xdg-desktop-portal/portals/hyprland.portal"
readonly SDDM_STATE="$SYSROOT/var/lib/sddm/state.conf"
readonly ACCOUNTS_DIR="$SYSROOT/var/lib/AccountsService/users"
readonly I2C_MODULE_CONF="$SYSROOT/etc/modules-load.d/i2c-dev.conf"
readonly USER_UNIT_DIR="$SYSROOT/usr/lib/systemd/user"
readonly WALLPAPER_DIR="$SYSROOT/usr/share/backgrounds/archlinux"
readonly DEFAULT_WALLPAPER="$WALLPAPER_DIR/mountain.jpg"
readonly VCONSOLE_CONF="$SYSROOT/etc/vconsole.conf"
readonly FIREFOX_POLICY="$SYSROOT/etc/firefox/policies/policies.json"
readonly BRAVE_POLICY="$SYSROOT/etc/brave/policies/managed/hypr-installer-video.json"
readonly X11_KEYBOARD_CONF="$SYSROOT/etc/X11/xorg.conf.d/00-keyboard.conf"
readonly PIPEWIRE_GLOBAL_WANTS="$SYSROOT/etc/systemd/user/sockets.target.wants/pipewire.socket"
readonly PIPEWIRE_VENDOR_WANTS="$SYSROOT/usr/lib/systemd/user/sockets.target.wants/pipewire.socket"

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
readonly HOOK_SCRIPT="$SYSROOT/usr/local/lib/hypr-installer/pin-check.sh"
readonly HOOK_FILE="$SYSROOT/etc/pacman.d/hooks/zz-hypr-installer-pin-check.hook"
RUN_TS="$(date '+%Y%m%d-%H%M%S')"; readonly RUN_TS
LOG_FILE="$LOG_DIR/install-$RUN_TS.log"
BACKUP_DIR="$BACKUP_ROOT/$RUN_TS"
TMP_DIR=""

MODE="install"          # install | diagnose | repair | first-login | post-login-check
ASSUME_YES=0 FORCE=0 ALLOW_NON_EOS=0 ALLOW_OTHER_GPU=0 NO_REBOOT_PROMPT=0 NO_DEV=0 DOTFILES_URL=""
SUDO_KEEPALIVE_PID="" SPIN_PID=""
CURRENT_STEP=0
PINS_RESTORED=0          # 1 dès que la pile épinglée installée est conforme au verrou
LAST_ERROR=""            # cause de l'échec en cours (die / erreur Bash / interruption)
LAST_CAUSE=""            # cause précise extraite de la sortie de la dernière commande échouée
SPIN_OUTPUT_FILE=""      # sortie complète de la dernière commande lancée par spin
FAILURE_HANDLED=0        # sortie volontaire déjà commentée : on_exit n'ajoute rien
INTERRUPTED=0
declare -a VERIFY_PROBLEMS=() VERIFY_MISSING=()
declare -a WARNINGS=() CHECK_LINES=()
declare -i CHECK_FAIL=0 CHECK_WARN=0 CHECK_PASS=0

readonly -a STEP_TITLES=("" "System verification" "Hardware detection" "Package installation"
  "AMD graphics setup" "Hyprland installation" "End-4 installation" "Quickshell setup"
  "AZERTY configuration" "Keyboard shortcuts" "Desktop configuration"
  "Services configuration" "Apps, dev & AI tools" "Final validation")
readonly LAST_STEP=13
declare -a STEP_STATUS=("" WAITING WAITING WAITING WAITING WAITING WAITING WAITING WAITING WAITING WAITING WAITING WAITING WAITING)
declare -a STEP_WARN=(0 0 0 0 0 0 0 0 0 0 0 0 0 0)

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
# Arrêt contrôlé. La cause est mémorisée (y compris depuis un sous-shell, via un
# fichier) pour que on_exit puisse l'enregistrer dans l'état de l'étape.
die() {
  LAST_ERROR="$*"
  log "FATAL $*"
  if [[ -n ${TMP_DIR:-} && -d $TMP_DIR ]]; then printf '%s\n' "$*" >"$TMP_DIR/last-error" 2>/dev/null || true; fi
  printf '\n  %s✖ %s%s\n' "$C_RED" "$*" "$C_RST" >&3
  exit 1
}
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
    NOTRUN)  printf '%sNON EXÉCUTÉE%s' "$C_DIM" "$C_RST" ;;
    INCOMPLETE) printf '%s%sINCOMPLÈTE%s' "$C_B" "$C_YEL" "$C_RST" ;;
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
  for i in $(seq 1 "$LAST_STEP"); do
    case ${STEP_STATUS[i]} in DONE|CACHED|WARN) ((done_count+=1)) ;; esac
  done
  printf '  %sÉtapes terminées :%s %s/%s\n\n' "$C_DIM" "$C_RST" "$done_count" "$LAST_STEP" >&3
  for i in $(seq 1 "$LAST_STEP"); do
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
  local command_text="$*" offset=0
  log "EXEC  $command_text"
  # Position du journal avant la commande : sa sortie exacte pourra être analysée.
  case ${1:-} in sudo|makechrootpkg|mkarchroot|arch-nspawn) ensure_sudo ;; esac
  offset=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
  LAST_CAUSE=""
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
  # Sortie de cette commande seulement (et non la fin du journal global).
  # Chemin fixe : reste lisible par le shell principal même si spin a tourné
  # dans un sous-shell « (cd dir && spin …) ».
  SPIN_OUTPUT_FILE="${TMP_DIR:-${TMPDIR:-/tmp}}/last-command.out"
  tail -c +"$((offset + 1))" "$LOG_FILE" >"$SPIN_OUTPUT_FILE" 2>/dev/null || : >"$SPIN_OUTPUT_FILE"
  if ((rc == 0)); then
    rm -f -- "$SPIN_OUTPUT_FILE.failed"
    ok "$msg"
  else
    printf '%s\n' "$rc" >"$SPIN_OUTPUT_FILE.failed" 2>/dev/null || true
    log "ÉCHEC ($rc) : $msg"
    printf '\n  %s✖ Échec :%s %s (code %s)\n' "$C_RED" "$C_RST" "$msg" "$rc" >&3
    if [[ $command_text == *makepkg* ]]; then
      printf '  %sCode makepkg %s : %s%s\n' "$C_YEL" "$rc" "$(makepkg_code_meaning "$rc")" "$C_RST" >&3
    fi
    local -a causes=()
    mapfile -t causes < <(explain_failure_output "$SPIN_OUTPUT_FILE")
    if ((${#causes[@]})); then
      LAST_CAUSE=${causes[0]}
      printf '  %sCause(s) identifiée(s) dans la sortie de la commande :%s\n' "$C_B" "$C_RST" >&3
      printf '    • %s\n' "${causes[@]}" >&3
      printf '%s\n' "${causes[@]}" | sed 's/^/CAUSE /' >&5
    fi
    printf '  %sDernières lignes de la commande :%s\n' "$C_DIM" "$C_RST" >&3
    grep -v '^\[[0-9-]* [0-9:]*\] ' "$SPIN_OUTPUT_FILE" | tail -n 25 | sed 's/^/    /' >&3 || true
    printf '\n' >&3
  fi
  return "$rc"
}

makepkg_code_meaning() {   # codes de sortie documentés de makepkg (makepkg(8))
  case $1 in
    1) printf 'erreur inconnue' ;;
    2) printf 'erreur dans la configuration makepkg.conf' ;;
    3) printf 'option invalide' ;;
    4) printf 'une fonction du PKGBUILD (prepare/build/check/package) a échoué' ;;
    5) printf 'création du paquet impossible' ;;
    6) printf 'source ou fichier auxiliaire manquant' ;;
    7) printf 'PKGDIR absent' ;;
    8) printf 'installation des dépendances impossible (pacman a refusé : voir la cause ci-dessous)' ;;
    9) printf 'suppression des dépendances impossible' ;;
    10) printf 'makepkg lancé en root' ;;
    11) printf 'droits utilisateur insuffisants' ;;
    12) printf 'erreur de syntaxe dans le PKGBUILD' ;;
    13) printf 'un paquet déjà construit existe' ;;
    14) printf 'le paquet construit n’a pas pu être installé' ;;
    15) printf 'dépendances manquantes (sans -s)' ;;
    16) printf 'échec de la vérification PGP' ;;
    *) printf 'code non documenté' ;;
  esac
}

# Traduit la sortie de pacman / makepkg / git / curl en causes lisibles (une par ligne).
explain_failure_output() {
  local f=$1
  [[ -s $f ]] || return 0
  LC_ALL=C awk '
    function out(s) { if (!(s in seen)) { seen[s] = 1; print s; n++ } }
    /error: target not found: /          { sub(/.*target not found: /, ""); out("Paquet introuvable dans les dépôts : " $0 " (nom erroné, dépôt non synchronisé ou paquet AUR non pris en charge)") }
    /unable to satisfy dependency/       { line = $0; sub(/.*unable to satisfy dependency /, "", line); out("Dépendance impossible à satisfaire : " line) }
    /breaks dependency/                  { line = $0; sub(/^.*:: /, "", line); sub(/^.*warning: /, "", line); out("Rupture de dépendance : " line) }
    /are in conflict/                    { line = $0; sub(/^:: /, "", line); sub(/\. Remove.*/, "", line); out("Conflit de paquets : " line) }
    /unresolvable package conflicts/     { out("Conflit de paquets non résolu automatiquement (--noconfirm répond « non » à la suppression)") }
    /exists in filesystem/               { line = $0; sub(/^error: /, "", line); out("Fichier déjà présent sur le disque (installé hors pacman ?) : " line) }
    /(invalid or corrupted package|signature from .* is (unknown trust|invalid|marginal trust)|key .* could not be (looked up|imported)|keyring is not writable)/ \
                                         { out("Signature / trousseau pacman : " $0 " -> pacman-key --populate archlinux endeavouros ; mise à jour de archlinux-keyring") }
    /unable to lock database/            { out("Base pacman verrouillée (db.lck) : une autre opération pacman est en cours ou s’est interrompue") }
    /(failed retrieving file|Could not resolve host|Failed to connect|Connection timed out|Operation too slow|failure while downloading|Failure while downloading)/ \
                                         { out("Téléchargement impossible (réseau ou miroir) : " $0) }
    /No space left on device/            { out("Espace disque insuffisant") }
    /did not pass the validity check/    { out("Somme de contrôle d’une source invalide (source modifiée en amont)") }
    /One or more PGP signatures could not be verified/ { out("Signature PGP d’une source non vérifiable (clé absente du trousseau utilisateur)") }
    /A failure occurred in (prepare|build|check|package)\(\)/ { line = $0; sub(/^.*A failure occurred in /, "", line); out("Échec dans la fonction " line " du PKGBUILD (voir les lignes de compilation)") }
    /Could not download sources|Failure while downloading/ { out("Sources du paquet non téléchargées") }
    /^==> ERROR:/                        { line = $0; sub(/^==> ERROR: /, "", line); out("makepkg : " line) }
    /^==> Missing dependencies:/         { miss = 1; next }
    miss && /^  -> /                     { line = $0; sub(/^  -> /, "", line); out("Dépendance manquante : " line); next }
    { miss = 0 }
    /^fatal: /                           { out("git : " substr($0, 8)) }
    /^curl: \([0-9]+\)/                  { out($0) }
  ' "$f" | head -n 8
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
# Gestion centralisée : on_error et on_interrupt se contentent de qualifier
# l'erreur puis de sortir ; on_exit (toujours exécuté) enregistre l'échec de
# l'étape, affiche le résumé et écrit le rapport. Un « die » passe par le même
# chemin : aucune sortie en échec n'est silencieuse ni non enregistrée.
on_error() {
  local rc=$1 line=$2 cmd=$3
  if [[ $BASHPID != "$MAIN_PID" ]]; then exit "$rc"; fi
  trap - ERR
  log "ERREUR : code $rc, ligne $line, commande : $cmd"
  [[ -n $LAST_ERROR ]] || LAST_ERROR="Commande en échec : $cmd (code $rc, ligne $line de install.sh)"
  exit "$rc"
}

on_interrupt() {
  trap - INT TERM
  INTERRUPTED=1
  LAST_ERROR="Installation interrompue (Ctrl+C ou signal TERM)"
  log "INTERRUPTION reçue"
  # Laisser une transaction pacman en cours se terminer proprement plutôt que de
  # quitter en laissant tourner un processus qui détient le verrou pacman.
  if [[ -n $SPIN_PID ]] && kill -0 "$SPIN_PID" 2>/dev/null; then
    printf '\n  %sInterruption : attente de la fin propre de la commande en cours (120 s max)…%s\n' "$C_YEL" "$C_RST" >&3
    local i
    for ((i = 0; i < 240; i++)); do kill -0 "$SPIN_PID" 2>/dev/null || break; sleep 0.5; done
    if kill -0 "$SPIN_PID" 2>/dev/null; then
      command -v pkill >/dev/null && pkill -TERM -P "$SPIN_PID" 2>/dev/null
      kill -TERM "$SPIN_PID" 2>/dev/null
    fi
  fi
  exit 130
}

on_exit() {
  local rc=$?
  set +e
  trap - ERR
  [[ -n $SPIN_PID ]] && kill "$SPIN_PID" 2>/dev/null
  [[ -n $SUDO_KEEPALIVE_PID ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
  if ((rc != 0 && FAILURE_HANDLED == 0)) && [[ $BASHPID == "$MAIN_PID" ]] \
     && [[ $MODE == install || $MODE == repair ]]; then
    handle_failure "$rc"
  elif ((rc != 0)) && [[ $BASHPID == "$MAIN_PID" && $MODE == dotfiles* && -n ${LOG_FILE:-} ]]; then
    printf '\n  Journal complet : %s\n  Rien à moitié appliqué n’est perdu : ./install.sh --dotfiles-restore annule la dernière application.\n' "${LOG_FILE/#$HOME/\~}" >&3
  fi
  # Suppression uniquement du répertoire temporaire créé par mktemp (chemin vérifié).
  if [[ -n $TMP_DIR && $TMP_DIR == "${TMPDIR:-/tmp}"/hypr-installer.* && -d $TMP_DIR ]]; then
    rm -rf -- "$TMP_DIR"
  fi
  log "Fin (code $rc)"
  return "$rc"
}

handle_failure() {
  local rc=$1 step=$CURRENT_STEP
  if [[ -z $LAST_ERROR && -n ${TMP_DIR:-} && -s $TMP_DIR/last-error ]]; then LAST_ERROR=$(<"$TMP_DIR/last-error"); fi
  [[ -n $LAST_ERROR ]] || LAST_ERROR="Arrêt inattendu (code $rc)"
  if ((step > 0)); then
    STEP_STATUS[step]=FAILED
    failure_record "$step" "$rc" "$LAST_ERROR" "$LAST_CAUSE"
  fi
  draw_dashboard
  {
    if ((INTERRUPTED)); then
      printf '\n  %s%s■ INTERROMPU pendant l’étape %02d (%s)%s\n' "$C_B" "$C_YEL" "$step" "${STEP_TITLES[step]:-}" "$C_RST"
    else
      printf '\n  %s%s✖ ÉCHEC à l’étape %02d (%s)%s\n' "$C_B" "$C_RED" "$step" "${STEP_TITLES[step]:-}" "$C_RST"
    fi
    printf '    Raison : %s\n' "$LAST_ERROR"
    [[ -n $LAST_CAUSE && $LAST_ERROR != *"$LAST_CAUSE"* ]] && printf '    Cause  : %s\n' "$LAST_CAUSE"
    printf '    Code   : %s\n' "$rc"
    # Le tableau de bord vient d'effacer l'écran : réafficher la sortie utile.
    if [[ -n $SPIN_OUTPUT_FILE && -f $SPIN_OUTPUT_FILE.failed && -s $SPIN_OUTPUT_FILE ]]; then
      local -a causes=()
      mapfile -t causes < <(explain_failure_output "$SPIN_OUTPUT_FILE")
      ((${#causes[@]} > 1)) && printf '    Autres causes : %s\n' "${causes[@]:1}"
      printf '\n  %sDernières lignes de la commande en échec :%s\n' "$C_DIM" "$C_RST"
      grep -v '^\[[0-9-]* [0-9:]*\] ' "$SPIN_OUTPUT_FILE" | tail -n 15 | sed 's/^/    /'
    else
      # Erreur hors commande suivie (rsync, cp, mkdir…) : son message est dans le journal.
      printf '\n  %sDernières lignes du journal :%s\n' "$C_DIM" "$C_RST"
      grep -vE '^\[[0-9-]* [0-9:]*\] (INFO|OK|EXEC|---)' "$LOG_FILE" 2>/dev/null | tail -n 8 | sed 's/^/    /'
    fi
    printf '\n    Journal complet : %s\n' "${LOG_FILE/#$HOME/\~}"
    printf '\n  Les étapes terminées sont mémorisées et revérifiées : relancez ./install.sh pour reprendre.\n'
    printf '  Diagnostic : ./install.sh --diagnose     Réparation : ./install.sh --repair\n'
  } >&3
  write_report "ÉCHEC à l’étape $step : $LAST_ERROR (code $rc)" >/dev/null 2>&1
}

# --- Points de reprise --------------------------------------------------------
# Un point de reprise ne suffit jamais : une étape n'est sautée que si son point
# de reprise est présent ET que la vérification de l'état réel (verify_step_N)
# réussit. Le script lui-même n'entre pas dans la clé (une correction du script
# ne doit pas tout relancer) ; la vérification réelle protège contre la dérive.
checkpoint_key() {
  printf '%s|%s|%s' "$CHECKPOINT_SCHEMA" "$END4_COMMIT" "$QS_COMMIT" \
    | sha256sum | cut -c1-16
}
checkpoint_done() { [[ -f $STATE_DIR/step-$1.done && "$(<"$STATE_DIR/step-$1.done")" == "$(checkpoint_key)" ]]; }
checkpoint_set()  { checkpoint_key >"$STATE_DIR/step-$1.done"; }
# Une étape réexécutée invalide les étapes suivantes, qui en dépendent.
checkpoint_clear_from() {
  local i
  for ((i = $1; i <= LAST_STEP; i++)); do rm -f -- "$STATE_DIR/step-$i.done"; done
}
state_set() { printf '%s\n' "$2" >"$STATE_DIR/$1"; }
state_get() { [[ -f $STATE_DIR/$1 ]] && cat "$STATE_DIR/$1" || true; }

failure_record() {   # failure_record <étape> <code> <raison> [cause]
  [[ -d $STATE_DIR ]] || return 0
  {
    printf 'date=%s\n' "$(date '+%F %T')"
    printf 'code=%s\n' "$2"
    printf 'raison=%s\n' "${3//$'\n'/ }"
    printf 'cause=%s\n' "${4//$'\n'/ }"
    printf 'interrompu=%s\n' "$INTERRUPTED"
    printf 'journal=%s\n' "$LOG_FILE"
    printf 'version=%s\n' "$INSTALLER_VERSION"
  } >"$STATE_DIR/step-$1.failed"
}
failure_get() {   # failure_get <étape> <clé>
  [[ -f $STATE_DIR/step-$1.failed ]] || return 0
  awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$STATE_DIR/step-$1.failed"
}

# --- Vérification de l'état réel --------------------------------------------
vp() { VERIFY_PROBLEMS+=("$*"); }                 # problème constaté
vp_pkg() { VERIFY_MISSING+=("$1"); vp "paquet absent : $1"; }
step_verify() {
  VERIFY_PROBLEMS=(); VERIFY_MISSING=()
  if declare -F "verify_step_$1" >/dev/null; then "verify_step_$1"; fi
  ((${#VERIFY_PROBLEMS[@]} == 0))
}

# Étapes toujours réexécutées (lecture seule ou contrôles).
readonly ALWAYS_RUN=" 1 2 13 "

run_step() {
  local idx=$1 fn; shift
  CURRENT_STEP=$idx
  if [[ $MODE == install && $FORCE -eq 0 && $ALWAYS_RUN != *" $idx "* ]] && checkpoint_done "$idx"; then
    if step_verify "$idx"; then
      STEP_STATUS[idx]=CACHED; log "Étape $idx déjà terminée (point de reprise + état réel vérifié)"; draw_dashboard; return 0
    fi
    log "Étape $idx : point de reprise présent mais état réel incomplet : ${VERIFY_PROBLEMS[*]}"
    WARNINGS+=("Étape $idx réexécutée : état réel incomplet (${VERIFY_PROBLEMS[0]})")
  fi
  [[ $ALWAYS_RUN == *" $idx "* || $MODE == diagnose ]] || checkpoint_clear_from "$idx"
  STEP_STATUS[idx]=RUNNING; draw_dashboard
  section "Étape $idx — ${STEP_TITLES[idx]}"
  for fn in "$@"; do log "--- $fn"; "$fn"; done
  if [[ ${STEP_STATUS[idx]} != FAILED ]]; then
    # Aucune fausse réussite : l'état réel doit être conforme avant le point de reprise.
    if ! step_verify "$idx"; then
      LAST_CAUSE=${VERIFY_PROBLEMS[0]}
      die "Étape $idx (${STEP_TITLES[idx]}) : la vérification après exécution échoue — ${VERIFY_PROBLEMS[*]}"
    fi
    if ((STEP_WARN[idx])); then STEP_STATUS[idx]=WARN; else STEP_STATUS[idx]=DONE; fi
    if [[ $MODE != diagnose ]]; then
      checkpoint_set "$idx"
      rm -f -- "$STATE_DIR/step-$idx.failed"
    fi
  fi
  draw_dashboard
}

# =============================================================================
# 4. OUTILS : sudo, pacman, fichiers gérés, sauvegardes
# =============================================================================
start_sudo_keepalive() {
  ensure_sudo
  # set +e : un échec ponctuel de « sudo -n -v » ne doit pas tuer la boucle
  # (sous set -e hérité, la 1re erreur arrêtait silencieusement le maintien).
  ( set +e; trap - ERR; while kill -0 "$MAIN_PID" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 30; done ) &
  SUDO_KEEPALIVE_PID=$!
}

# Garantit des droits sudo valides AVANT de lancer une commande en arrière-plan.
# Sinon sudo demanderait le mot de passe pendant que l'indicateur d'activité
# l'efface de l'écran : invite invisible, puis « sudo: timed out reading password ».
ensure_sudo() {
  [[ $MODE == install || $MODE == repair || $MODE == dotfiles ]] || return 0
  sudo -n true 2>/dev/null && return 0
  printf '\n  %sAuthentification administrateur (sudo) requise :%s\n' "$C_YEL" "$C_RST" >&3
  local i
  for i in 1 2 3; do
    # shellcheck disable=SC2024  # l'invite sudo doit rester sur le terminal (voulu)
    sudo -v </dev/tty >&3 2>&3 && return 0
  done
  die "Authentification sudo refusée."
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
  if [[ ${PIN_MODE[$n]} == src || ${PIN_MODE[$n]} == srcpref ]]; then
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

# La pile épinglée est-elle installée et conforme au verrou ? (lecture seule)
pinned_stack_installed() {
  [[ -f $PINS_LOCK ]] || return 1
  local n
  for n in "${PIN_ORDER[@]}"; do
    [[ $(pkg_version "$n") == "$(expected_pin_version "$n")" ]] || return 1
  done
  return 0
}

# Dépendances non satisfaites parmi les arguments (gère les « provides » et les
# contraintes de version, contrairement à pacman -Qq).
pkgs_missing() {
  (($#)) || return 0
  if ! command -v pacman >/dev/null; then printf '%s\n' "$@"; return 0; fi
  pacman -T "$@" 2>/dev/null || true
}

# Paquets installés à retirer pour débloquer une transaction, d'après la sortie
# de pacman : « breaks dependency … required by X », « Remove X? », ou une
# dépendance insatisfaisable exigée par un paquet DÉJÀ installé.
pacman_blockers() {
  local f=${1:-$SPIN_OUTPUT_FILE} p
  [[ -s $f ]] || return 0
  LC_ALL=C sed -nE \
    -e "s/.*breaks dependency '[^']*' required by ([^ ]+).*/\1/p" \
    -e "s/.*unable to satisfy dependency '[^']*' required by ([^ ]+).*/\1/p" \
    -e 's/.* are in conflict.*Remove ([^?]+)\?.*/\1/p' "$f" | sort -u | while IFS= read -r p; do
      [[ -n $p ]] && pkg_installed "$p" && printf '%s\n' "$p"
    done
  return 0
}

# Exécute une transaction pacman ; en cas de conflit ou de rupture de dépendance
# imputable à un paquet installé hors pile épinglée, propose de le retirer puis
# réessaie (2 fois au plus). Jamais de retrait silencieux.
pacman_tx() {
  local label=$1; shift
  local attempt v
  local -a victims=() pinned=()
  for attempt in 1 2 3; do
    if spin "$label" "$@"; then assert_pins_intact; return 0; fi
    mapfile -t victims < <(pacman_blockers "$SPIN_OUTPUT_FILE")
    ((${#victims[@]})) && ((attempt < 3)) \
      || die "$label : échec de la transaction pacman. ${LAST_CAUSE:-Voir les lignes affichées ci-dessus.}"
    pinned=()
    for v in "${victims[@]}"; do is_pinned "$v" && pinned+=("$v"); done
    if ((${#pinned[@]})); then
      die "$label : bloqué par la pile Hyprland épinglée (${pinned[*]}). ${LAST_CAUSE:-} Lancez ./install.sh --repair."
    fi
    for v in "${victims[@]}"; do remove_conflict "$v" "transaction « $label »"; done
  done
}

# Installe des paquets des dépôts officiels (jamais de paquet épinglé).
pac_install() {
  local -a flags=() wanted=() pkgs=() p
  for p in "$@"; do
    if [[ $p == --* ]]; then flags+=("$p"); continue; fi
    is_pinned "${p%%[<>=]*}" && die "Erreur interne : $p doit passer par la pile épinglée."
    wanted+=("$p")
  done
  mapfile -t pkgs < <(pkgs_missing "${wanted[@]}")
  ((${#pkgs[@]})) || { log "Déjà satisfaits : ${wanted[*]}"; return 0; }
  guard_targets "${pkgs[@]}"
  local more=""; ((${#pkgs[@]} > 8)) && more=" (+$((${#pkgs[@]} - 8)))"
  pacman_tx "pacman : ${pkgs[*]:0:8}$more" \
    sudo pacman -S --needed --noconfirm "${flags[@]}" "${pkgs[@]}"
  local -a still=()
  mapfile -t still < <(pkgs_missing "${pkgs[@]}")
  ((${#still[@]} == 0)) || die "pacman a terminé sans erreur mais ces paquets restent absents : ${still[*]}"
}

# Retire, après confirmation, un paquet en conflit avec un paquet à installer.
remove_conflict() {
  local victim=$1 reason=$2
  pkg_installed "$victim" || return 0
  is_pinned "$victim" && die "Erreur interne : retrait du paquet épinglé $victim refusé ($reason)."
  ask_yes_no "« $victim » est en conflit avec « $reason » et doit être retiré. Continuer ?" \
    || die "Conflit non résolu : $victim / $reason"
  spin "Retrait de $victim (conflit)" sudo pacman -Rdd --noconfirm "$victim" \
    || die "Impossible de retirer $victim (${LAST_CAUSE:-voir journal})."
}

# Lit un champ du .PKGINFO d'un paquet (précis, contrairement à pacman -Qip
# dont les listes longues sont coupées sur plusieurs lignes).
pkgfile_field() {   # pkgfile_field <fichier> <clé>
  bsdtar -xOqf "$1" .PKGINFO 2>/dev/null | awk -v k="$2" '$1 == k && $2 == "=" { sub(/^[^=]*= /, ""); print }'
}

# Installe des fichiers de paquets après résolution explicite des conflits.
install_pkgfiles() {
  local f name c cname
  local -a names=()
  (($#)) || die "Erreur interne : install_pkgfiles sans paquet."
  for f in "$@"; do
    [[ -f $f ]] || die "Paquet construit introuvable : $f"
    name=$(pkgfile_field "$f" pkgname | head -n1)
    [[ -n $name ]] || die "Paquet illisible (pas de .PKGINFO) : $f"
    names+=("$name")
    while IFS= read -r c; do
      cname=${c%%[<>=]*}
      [[ -z $cname || $cname == "$name" ]] && continue
      remove_conflict "$cname" "$name"
    done < <(pkgfile_field "$f" conflict)
  done
  pacman_tx "Installation locale : ${names[*]}" sudo pacman -U --needed --noconfirm "$@"
  for name in "${names[@]}"; do pkg_installed "$name" || die "Paquet $name absent après pacman -U."; done
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

# Récupère un dépôt git au commit exact demandé. Si l'URL principale échoue, un
# miroir optionnel (URL + branche) est essayé ; le commit vérifié reste le même,
# donc le contenu est identique quelle que soit la source.
git_checkout_pinned() {   # git_checkout_pinned <url> <dir> <commit> [miroir] [branche-miroir]
  local url=$1 dir=$2 commit=$3 mirror=${4:-} mbranch=${5:-} name
  name=$(basename "$url" .git)
  if [[ -d $dir && ! -d $dir/.git ]] || { [[ -d $dir/.git ]] && ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; }; then
    log "Clone incomplet ou corrompu, suppression : $dir"; rm -rf -- "${dir:?}"
  fi
  if [[ ! -d $dir/.git ]]; then
    mkdir -p "$(dirname "$dir")"
    if ! spin "git clone $name" git clone --quiet "$url" "$dir"; then
      rm -rf -- "${dir:?}"
      [[ -n $mirror ]] || die "Clonage impossible : $url (${LAST_CAUSE:-voir journal})."
      spin "git clone $name (miroir $mirror)" git clone --quiet --single-branch --branch "$mbranch" "$mirror" "$dir" \
        || { rm -rf -- "${dir:?}"; die "Clonage impossible depuis $url et depuis le miroir (${LAST_CAUSE:-voir journal})."; }
    fi
  fi
  if ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
    spin "git fetch $name" git -C "$dir" fetch --quiet --tags origin || true
    if ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null && [[ -n $mirror ]]; then
      spin "git fetch $name (miroir)" git -C "$dir" fetch --quiet "$mirror" "$mbranch" || true
    fi
    git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null \
      || die "Commit épinglé $commit introuvable pour $name (dépôt réécrit ou réseau indisponible)."
  fi
  git -C "$dir" checkout --quiet --force --detach "$commit" || die "git checkout $commit impossible dans $dir"
  git -C "$dir" clean -fdxq
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$commit" ]] || die "Commit inattendu dans $dir"
}

enable_user_unit() {   # active une unité systemd utilisateur (même hors session)
  local unit=$1 src want
  if systemctl --user enable "$unit" 2>/dev/null; then log "systemctl --user enable $unit"; return 0; fi
  src="$USER_UNIT_DIR/$unit"
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
  # shellcheck source=/dev/null
  OS_ID=$(. "$OS_RELEASE" && printf '%s' "${ID:-}")
  # shellcheck source=/dev/null
  OS_NAME=$(. "$OS_RELEASE" && printf '%s' "${PRETTY_NAME:-inconnu}")
  info "Distribution : $OS_NAME"
  if [[ $OS_ID != endeavouros ]]; then
    if ((ALLOW_NON_EOS)) && grep -qw arch "$OS_RELEASE"; then warn "Distribution non EndeavourOS ($OS_ID) acceptée (--allow-non-eos)"
    else die "EndeavourOS requis (détecté : $OS_NAME). Option : --allow-non-eos pour une base Arch."; fi
  fi
  [[ $(uname -m) == x86_64 ]] || die "Architecture x86_64 requise (détectée : $(uname -m))."
  command -v pacman >/dev/null || die "pacman introuvable."
  command -v systemctl >/dev/null && [[ -d $SYSTEMD_RUNDIR ]] || die "systemd requis."
  EXISTING_HYPR=$(pkg_version hyprland); EXISTING_QS=$(pkg_version illogical-impulse-quickshell-git)
  [[ -z $EXISTING_QS ]] && EXISTING_QS=$(pkg_version quickshell)
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then IN_SESSION="Hyprland"; elif [[ -n ${XDG_CURRENT_DESKTOP:-} ]]; then IN_SESSION=$XDG_CURRENT_DESKTOP; else IN_SESSION="TTY/autre"; fi
  CURRENT_DM=$(basename "$(readlink -f "$DM_LINK" 2>/dev/null || true)" .service)
  [[ $CURRENT_DM == display-manager ]] && CURRENT_DM=""
  return 0
}

preflight() {
  [[ $EUID -ne 0 ]] || die "Ne lancez pas ce script en root ni avec sudo : lancez ./install.sh (sudo sera demandé)."
  command -v sudo >/dev/null || die "sudo est requis."
  detect_system
  check_pacman_lock
  local need
  for need in curl git; do command -v "$need" >/dev/null || die "Commande requise absente : $need"; done
  # Réseau : Archive, GitHub et GitLab Arch sont indispensables ; l'AUR a un
  # miroir GitHub officiel utilisé automatiquement en secours.
  local host
  for host in https://archive.archlinux.org https://github.com https://gitlab.archlinux.org; do
    net_reachable "$host" \
      || die "Réseau : ${host#https://} ne répond pas (${NET_LAST_ERROR:-aucune réponse}). Testez : curl -v $host"
  done
  if net_reachable https://aur.archlinux.org; then
    ok "Réseau : dépôts Arch, Archive, AUR, GitHub joignables"
  else
    warn "AUR injoignable : les paquets AUR épinglés seront récupérés via le miroir GitHub officiel (mêmes commits)."
  fi
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

# --- Réseau -------------------------------------------------------------------
# Un serveur est « joignable » dès qu'il renvoie une réponse HTTP, quel que soit
# son code : une page d'accueil en 403/404/405 (fréquent en HEAD sur les serveurs
# Arch) prouve que le réseau fonctionne. Seule l'absence totale de réponse
# (DNS, connexion, TLS, délai) est un échec réseau. En cas d'échec, un second
# essai force l'IPv4 (IPv6 annoncé mais non routé : cas courant sur les box).
NET_LAST_ERROR=""
CURL_IPV4=()   # rempli avec -4 si seul l'IPv4 fonctionne
http_status() {   # http_status <url> [options curl…] -> code HTTP (000 si aucune réponse)
  local url=$1; shift
  curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 15 --max-time 40 --retry 2 --retry-delay 2 \
    -A "hypr-installer/$INSTALLER_VERSION" "$@" "$url" 2>"${TMP_DIR:-/tmp}/curl.err" || true
}
net_reachable() {   # net_reachable <url> : 0 si le serveur répond (n'importe quel code HTTP)
  local url=$1 code
  NET_LAST_ERROR=""
  code=$(http_status "$url" "${CURL_IPV4[@]}")
  [[ $code =~ ^[1-5][0-9][0-9]$ ]] && { log "Réseau : $url -> HTTP $code"; return 0; }
  if ((${#CURL_IPV4[@]} == 0)); then
    code=$(http_status "$url" -4)
    if [[ $code =~ ^[1-5][0-9][0-9]$ ]]; then
      log "Réseau : $url joignable uniquement en IPv4 (HTTP $code) : IPv4 forcé pour la suite"
      CURL_IPV4=(-4); return 0
    fi
  fi
  NET_LAST_ERROR=$(tail -n1 "${TMP_DIR:-/tmp}/curl.err" 2>/dev/null)
  log "Réseau : $url injoignable : ${NET_LAST_ERROR:-aucune réponse}"
  return 1
}
# Un fichier précis existe-t-il ? (HEAD puis GET partiel, redirections suivies)
url_exists() {
  local code
  code=$(http_status "$1" "${CURL_IPV4[@]}" -L -I)
  [[ $code == 2* ]] && return 0
  code=$(http_status "$1" "${CURL_IPV4[@]}" -L -r 0-0)
  [[ $code == 2* ]] && return 0
  NET_LAST_ERROR="HTTP $code $(tail -n1 "${TMP_DIR:-/tmp}/curl.err" 2>/dev/null)"
  return 1
}

# Verrou pacman : un verrou laissé par une transaction interrompue empêche toute
# reprise. Il n'est retiré que si aucun processus pacman ne tourne, et après accord.
pacman_running() {
  command -v pgrep >/dev/null || return 1
  pgrep -x pacman >/dev/null 2>&1 || pgrep -x pacman-key >/dev/null 2>&1 || pgrep -x packagekitd >/dev/null 2>&1
}
check_pacman_lock() {
  [[ -e $PACMAN_LOCK ]] || return 0
  if pacman_running; then
    die "pacman est en cours d’exécution (verrou $PACMAN_LOCK). Attendez la fin de l’autre opération puis relancez."
  fi
  ask_yes_no "Verrou pacman orphelin détecté ($PACMAN_LOCK, aucun pacman en cours — probablement une installation interrompue). Le supprimer ?" \
    || die "Verrou pacman présent : $PACMAN_LOCK. Supprimez-le (sudo rm $PACMAN_LOCK) si aucune opération pacman n’est en cours."
  sudo rm -f -- "$PACMAN_LOCK"
  [[ ! -e $PACMAN_LOCK ]] || die "Impossible de supprimer $PACMAN_LOCK."
  ok "Verrou pacman orphelin supprimé"
}

resolve_versions() {
  # end-4 : la branche main doit être joignable ; le commit épinglé est vérifié
  # au clonage (étape 6). Aucun tag plus récent que 2026.05.11 n'existe.
  local lsr
  lsr=$(git ls-remote "$END4_REPO" refs/heads/main 2>&1) \
    || die "Impossible d’interroger $END4_REPO (git ls-remote) : $(tail -n1 <<<"$lsr")"
  ok "end-4 joignable — commit épinglé ${END4_COMMIT:0:12} (main, 2026-11-15)"
  local repo_hypr qt n
  repo_hypr=$(LC_ALL=C pacman -Si hyprland 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}' | xargs || true)
  qt=$(LC_ALL=C pacman -Si qt6-base 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}' | xargs || true)
  [[ -n $repo_hypr ]] || die "Le paquet hyprland est introuvable dans les dépôts (pacman -Sy nécessaire ?)."
  ok "Hyprland des dépôts Arch : ${repo_hypr} (qt6-base ${qt:-?})"
  mkdir -p "$MANIFEST_DIR"
  {
    printf '+-----------------------------------------------------------------+\n'
    printf '|                    VERSION MANIFEST                             |\n'
    printf '+-----------------------------------------------------------------+\n'
    printf '| %-28s : %-32s |\n' "EndeavourOS" "$OS_NAME"
    printf '| %-28s : %-32s |\n' "end-4 dots-hyprland" "$END4_TAG (${END4_COMMIT:0:12})"
    printf '| %-28s : %-32s |\n' "Quickshell (épinglé end-4)" "${QS_COMMIT:0:12}"
    printf '| %-28s : %-32s |\n' "hyprland (dépôts Arch)" "${repo_hypr:-?}"
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
  ui "   • Hyprland des dépôts Arch (à jour, configuration Lua) ; une ancienne pile figée"
  ui "     (versions 2.x : IgnorePkg, paquets recompilés) est retirée et remplacée."
  ui "   • end-4 $END4_TAG (${END4_COMMIT:0:12}) déployé dans ~/.config (sauvegarde horodatée)."
  ui "   • AZERTY (fr), raccourcis end-4 adaptés à l’AZERTY, services, gestionnaire de connexion."
  ui "   • Aucune opération sur les disques, partitions, EFI, chargeur de démarrage ou Windows."
  [[ -n $EXISTING_HYPR ]] && ui "   • ${C_YEL}Hyprland $EXISTING_HYPR installé sera mis à jour vers la version des dépôts.${C_RST}"
  if ! ask_yes_no "Lancer l’installation ?"; then
    ui "  Annulé par l’utilisateur. Aucune modification effectuée."
    FAILURE_HANDLED=1; exit 1
  fi
  start_sudo_keepalive
}

# Nettoie les restes des exécutions précédentes (versions antérieures comprises)
# AVANT de reprendre, pour qu'aucun vestige ne perturbe la nouvelle exécution.
# Ne supprime JAMAIS : les configurations sauvegardées (backups/), les paquets
# utiles, ni quoi que ce soit hors des dossiers de l'installateur, sauf les
# paquets obsolètes listés ci-dessous, et seulement après confirmation.
readonly -a OBSOLETE_PKGS=(38c3-styles html2markdown otf-space-grotesk)
cleanup_previous_runs() {
  local n=0 f key i base keep
  key=$(checkpoint_key)
  # 1. États obsolètes : points de reprise d'une autre version, échecs anciens.
  for f in "$STATE_DIR"/step-*.done; do
    [[ $(<"$f") == "$key" ]] || { rm -f -- "$f"; n=$((n + 1)); }
  done
  for f in "$STATE_DIR"/step-*.failed; do
    grep -qx "version=$INSTALLER_VERSION" "$f" || { rm -f -- "$f"; n=$((n + 1)); }
  done
  rm -f -- "$STATE_DIR/chroot.prepared-run" "$PINS_LOCK.tmp"
  # 2. Dossiers temporaires d'exécutions interrompues.
  for f in "${TMPDIR:-/tmp}"/hypr-installer.*; do
    [[ -d $f && -O $f && $f != "$TMP_DIR" ]] || continue
    rm -rf -- "$f"; n=$((n + 1))
  done
  # 3. Téléchargements partiels et constructions régénérables.
  while IFS= read -r f; do rm -f -- "$f"; n=$((n + 1)); done < <(find "$CACHE_DIR" -name '*.part' -type f 2>/dev/null)
  for f in "$BUILD_DIR/meta" "$BUILD_DIR/local"; do
    [[ -d $f ]] && { rm -rf -- "$f"; n=$((n + 1)); }
  done
  # 4. Dépôts AUR / Arch qui ne font plus partie de la configuration actuelle.
  for f in "$BUILD_DIR"/aur/*; do
    [[ -d $f ]] || continue
    base=${f##*/}; keep=0
    for i in "${AUR_PINS[@]}"; do [[ ${i%%|*} == "$base" ]] && keep=1; done
    ((keep)) || { rm -rf -- "$f"; n=$((n + 1)); log "Nettoyage : ancien dépôt AUR $base"; }
  done
  for f in "$BUILD_DIR"/arch/*; do
    [[ -d $f ]] || continue
    is_pinned "${f##*/}" || { rm -rf -- "$f"; n=$((n + 1)); }
  done
  # 5. Paquets recompilés pour d'autres versions que celles épinglées.
  for f in "$PKG_CACHE"/built/*.pkg.tar*; do
    [[ -f $f ]] || continue
    keep=0
    for i in "${PIN_ORDER[@]}"; do [[ ${f##*/} == "$i-${PIN_VER[$i]}${LOCAL_REL_SUFFIX}-"* ]] && keep=1; done
    ((keep)) || { rm -f -- "$f"; n=$((n + 1)); }
  done
  # 6. Journaux et rapports : on garde les 20 plus récents ; sauvegardes vides.
  for f in "$LOG_DIR" "$REPORT_DIR"; do
    while IFS= read -r i; do rm -f -- "$i"; n=$((n + 1)); done \
      < <(find "$f" -maxdepth 1 -type f -name '*-2*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | tail -n +21 | cut -d' ' -f2-)
  done
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true
  # 7. Ancienne copie utilisateur de Space Grotesk (versions ≤ 1.2.9).
  local legacy="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/space-grotesk"
  if [[ -f $legacy/OFL.txt ]] && ! find "$legacy" -type f ! -name '*.otf' ! -name OFL.txt | grep -q .; then
    rm -rf -- "${legacy:?}"; n=$((n + 1))
  fi
  # 8. Paquets installés par d'anciennes versions et devenus inutiles.
  local -a old=()
  for i in "${OBSOLETE_PKGS[@]}"; do pkg_installed "$i" && old+=("$i"); done
  if ((${#old[@]})) && ask_yes_no "Paquets installés par une ancienne version de l’installateur, devenus inutiles : ${old[*]}. Les retirer ?"; then
    if spin "Retrait des paquets obsolètes : ${old[*]}" sudo pacman -Rns --noconfirm "${old[@]}"; then n=$((n + ${#old[@]}))
    else warn "Paquets obsolètes non retirés (encore requis par un autre paquet) : ${old[*]}"; fi
  fi
  if ((n)); then ok "Restes des exécutions précédentes nettoyés ($n élément(s))"; else log "Aucun reste d’exécution précédente"; fi
  return 0
}

# =============================================================================
# 6. ÉTAPE 02 — DÉTECTION MATÉRIELLE
# =============================================================================
detect_hardware() {
  if ! command -v lspci >/dev/null; then pac_install_early pciutils; fi
  probe_hardware
  check_hardware_requirements
}

# Détection seule (aucune modification, aucun arrêt) : utilisée aussi par --diagnose.
probe_hardware() {
  CPU_MODEL=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)
  RAM_GB=$(( ($(awk '/^MemTotal/{print $2}' /proc/meminfo) + 524288) / 1048576 ))
  command -v lspci >/dev/null || { GPU_LINES=""; return 0; }
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
  return 0
}

check_hardware_requirements() {
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
pac_install_early() {
  spin "pacman : $*" sudo pacman -S --needed --noconfirm "$@" || die "Installation de $* impossible (${LAST_CAUSE:-voir journal})."
}

# =============================================================================
# 7. ÉTAPE 03 — PAQUETS SYSTÈME
# =============================================================================
ensure_ignorepkg() {
  local line="IgnorePkg = ${PIN_ORDER[*]}"
  if grep -qF "# hypr-installer: pile Hyprland 0.54.3 épinglée" "$PACMAN_CONF"; then
    if grep -qxF "$line" "$PACMAN_CONF"; then log "IgnorePkg déjà présent"; return 0; fi
  fi
  grep -q '^\[options\]' "$PACMAN_CONF" || die "$PACMAN_CONF sans section [options] : configuration inattendue."
  backup_path "$PACMAN_CONF"
  local tmp; tmp=$(mktemp "$TMP_DIR/pacman.conf.XXXXXX")
  awk -v line="$line" '
    /^# hypr-installer: pile Hyprland 0.54.3 épinglée/ {skip=1; next}
    skip==1 {skip=0; next}
    {print}
    /^\[options\]/ && !done {print "# hypr-installer: pile Hyprland 0.54.3 épinglée (ne pas retirer, voir README)"; print line; done=1}
  ' "$PACMAN_CONF" >"$tmp"
  sudo install -m 644 "$tmp" "$PACMAN_CONF"
  grep -qxF "$line" "$PACMAN_CONF" || die "IgnorePkg absent de $PACMAN_CONF après écriture."
  ok "IgnorePkg ajouté à $PACMAN_CONF (sauvegarde : $BACKUP_DIR)"
}


install_system_packages() {
  # Dépendants incompatibles d'abord (ils bloqueraient la transaction).
  remove_incompatible_dependents
  # 3.0 : plus de versions figées. L'ancien IgnorePkg est retiré AVANT -Syu, et
  # les paquets Hyprland déjà installés sont mis à jour dans la MÊME transaction
  # (sinon un Hyprland 0.54 restant bloquerait la mise à jour de ses bibliothèques).
  remove_legacy_pinning
  local -a keyring_pkgs=(archlinux-keyring)
  pkg_installed endeavouros-keyring && keyring_pkgs+=(endeavouros-keyring)
  pacman_tx "Mise à jour des trousseaux de clés" sudo pacman -Sy --needed --noconfirm "${keyring_pkgs[@]}"
  local -a hypr_installed=() n
  for n in "${LEGACY_PIN_PKGS[@]}"; do pkg_installed "$n" && hypr_installed+=("$n"); done
  system_upgrade "${hypr_installed[@]}"
  # PulseAudio est remplacé par PipeWire (conflit avec pipewire-pulse).
  if pkg_installed pulseaudio; then remove_conflict pulseaudio pipewire-pulse; fi
  if pkg_installed pulseaudio-bluetooth; then remove_conflict pulseaudio-bluetooth pipewire-pulse; fi
  pac_install "${BASE_PKGS[@]}"
  pac_install "${AUDIO_PKGS[@]}" "${FONT_PKGS[@]}" "${NET_PKGS[@]}" "${BT_PKGS[@]}" "${WALL_PKGS[@]}"
  # Navigateur : uniquement si aucun n’est présent (EndeavourOS fournit Firefox).
  local b found=0
  for b in firefox chromium google-chrome-stable brave zen-browser librewolf microsoft-edge-stable; do command -v "$b" >/dev/null && found=1; done
  ((found)) || pac_install firefox
  install_aur_packages
  install_space_grotesk_font
}

# pacman -Syu, avec traitement explicite du seul blocage prévisible : un paquet de
# la pile épinglée lié à une ancienne version d'une bibliothèque que la mise à
# jour remplace. Il est alors retiré (après accord) puis recompilé à l'étape 5
# contre la nouvelle bibliothèque.
system_upgrade() {   # system_upgrade [paquets à (ré)installer depuis les dépôts dans la même transaction]
  local attempt v
  local -a extra=("$@")
  local -a blockers=() pinned=() other=()
  for attempt in 1 2 3; do
    if spin "Mise à jour complète du système (pacman -Syu)" sudo pacman -Syu --noconfirm "${extra[@]}"; then
      assert_pins_intact; return 0
    fi
    mapfile -t blockers < <(pacman_blockers "$SPIN_OUTPUT_FILE")
    ((${#blockers[@]})) && ((attempt < 3)) || die "pacman -Syu a échoué. ${LAST_CAUSE:-Voir les lignes affichées ci-dessus.}"
    pinned=(); other=()
    for v in "${blockers[@]}"; do if is_pinned "$v"; then pinned+=("$v"); else other+=("$v"); fi; done
    if ((${#pinned[@]})); then
      [[ $IN_SESSION == Hyprland ]] && warn "Session Hyprland active : retirer ${pinned[*]} peut perturber la session en cours."
      ask_yes_no "La mise à jour est bloquée par la pile épinglée (${pinned[*]}), liée à d’anciennes bibliothèques. Retirer ces paquets maintenant ? Ils seront recompilés contre les nouvelles bibliothèques à l’étape 5." \
        || die "Mise à jour bloquée par ${pinned[*]} (${LAST_CAUSE:-voir journal}). Relancez ./install.sh --repair et acceptez la recompilation."
      local -a force=()
      mapfile -t force < <({ state_get pins.force-src; printf '%s\n' "${pinned[@]}"; } | grep -v '^$' | sort -u)
      state_set pins.force-src "$(printf '%s\n' "${force[@]}")"
      PINS_RESTORED=0
      spin "Retrait temporaire de ${pinned[*]} (recompilés à l’étape 5)" sudo pacman -Rdd --noconfirm "${pinned[@]}" \
        || die "Retrait de ${pinned[*]} impossible (${LAST_CAUSE:-voir journal})."
    fi
    for v in "${other[@]}"; do remove_conflict "$v" "mise à jour du système"; done
  done
}

install_aur_packages() {
  local entry base commit wants want all_installed
  for entry in "${AUR_PINS[@]}"; do
    IFS='|' read -r base commit wants <<<"$entry"
    all_installed=1
    for want in ${wants//,/ }; do
      pkg_installed "$want" || { all_installed=0; continue; }
      # En réparation, ne recompiler que ce qui est réellement cassé.
      [[ $MODE == repair ]] && pkg_has_broken_libs "$want" && all_installed=0
    done
    if ((all_installed)); then log "AUR $base déjà installé"; continue; fi
    aur_build_install "$base" "$commit" "$wants"
  done
  return 0
}

# Compile et installe un paquet AUR à un commit donné (sans makepkg -s, sans
# sudo en arrière-plan) ; source AUR, ou miroir GitHub officiel en secours.
aur_build_install() {   # aur_build_install <pkgbase> <commit> <paquets,séparés,par,virgules>
  local base=$1 commit=$2 wants=$3 dir want f
  local -a files=() pkglist=()
  dir="$BUILD_DIR/aur/$base"
  git_checkout_pinned "https://aur.archlinux.org/$base.git" "$dir" "$commit" "$AUR_GITHUB_MIRROR" "$base"
  check_aur_dependencies "$dir" "$base" || die "AUR $base : dépendances non résolues (liste ci-dessus) — compilation non lancée."
  if [[ $base == wlogout ]] && ! gpg --list-keys F4FDB18A9937358364B276E9E25D679AF73C6D2F &>/dev/null; then
    gpg --keyserver hkps://keys.openpgp.org --recv-keys F4FDB18A9937358364B276E9E25D679AF73C6D2F \
      || gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys F4FDB18A9937358364B276E9E25D679AF73C6D2F \
      || warn "Clé PGP de wlogout non récupérée : vérification par somme de contrôle seule."
  fi
  install_build_deps "$dir" "$base"
  local -a mkflags=(--noconfirm -f -c --log)
  [[ $base == wlogout ]] && ! gpg --list-keys F4FDB18A9937358364B276E9E25D679AF73C6D2F &>/dev/null && mkflags+=(--skippgpcheck)
  if ! (cd "$dir" && spin "AUR : $base (compilation)" env LC_ALL=C makepkg "${mkflags[@]}"); then
    LAST_CAUSE=$(explain_failure_output "$SPIN_OUTPUT_FILE" | head -n1)
    die "AUR $base : makepkg a échoué. ${LAST_CAUSE:-Voir les lignes affichées ci-dessus.}"
  fi
  mapfile -t pkglist < <(cd "$dir" && makepkg --packagelist)
  for want in ${wants//,/ }; do
    for f in "${pkglist[@]}"; do
      [[ $(basename "$f") =~ ^${want}-[^-]+-[^-]+-[^-]+\.pkg\.tar(\.[[:alnum:]]+)?$ && -f $f ]] && files+=("$f")
    done
  done
  ((${#files[@]})) || die "AUR $base : paquet(s) $wants introuvable(s) après compilation (PKGDEST ou PKGEXT inattendus ?)."
  install_pkgfiles "${files[@]}"
}

# Space Grotesk est le seul élément utile de 38c3-styles. Il est empaqueté dans un
# paquet local « hypr-installer-space-grotesk » qui FOURNIT otf-space-grotesk :
# pacman et makepkg peuvent ainsi satisfaire la dépendance du méta-paquet end-4
# fonts-themes (sans paquet, makepkg -s échouait avec le code 8).
install_space_grotesk_font() {
  local archive="$BUILD_DIR/38c3-styleguide-full-v2.zip"
  local pdir="$BUILD_DIR/local/$SPACE_GROTESK_PKG"
  local legacy="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/space-grotesk"
  local -a files=()

  if pkg_installed "$SPACE_GROTESK_PKG"; then
    log "$SPACE_GROTESK_PKG déjà installé"
  else
    mkdir -p "$BUILD_DIR"
    if [[ ! -f $archive ]] || ! sha256sum -c --status <<<"$SPACE_GROTESK_SHA256  $archive"; then
      rm -f -- "$archive.part"
      spin "Téléchargement de Space Grotesk (archive 38C3)" curl -fL "${CURL_IPV4[@]}" --retry 3 --retry-delay 3 --connect-timeout 20 --max-time 600 -o "$archive.part" "$SPACE_GROTESK_URL" \
        || die "Téléchargement de l’archive 38C3 impossible (${LAST_CAUSE:-voir journal})."
      sha256sum -c --status <<<"$SPACE_GROTESK_SHA256  $archive.part" || { rm -f -- "$archive.part"; die "Archive 38C3 invalide : somme SHA-256 incorrecte."; }
      mv -f -- "$archive.part" "$archive"
    fi
    sha256sum -c --status <<<"$SPACE_GROTESK_SHA256  $archive" || die "Archive 38C3 invalide : somme SHA-256 incorrecte."
    rm -rf -- "${pdir:?}"; mkdir -p "$pdir"
    cp -f -- "$archive" "$pdir/"
    write_space_grotesk_pkgbuild >"$pdir/PKGBUILD"
    (cd "$pdir" && spin "Paquet local $SPACE_GROTESK_PKG (fournit otf-space-grotesk)" env LC_ALL=C makepkg -f -c --noconfirm) \
      || die "Construction du paquet $SPACE_GROTESK_PKG impossible (${LAST_CAUSE:-voir journal})."
    mapfile -t files < <(cd "$pdir" && makepkg --packagelist)
    install_pkgfiles "${files[@]}"
  fi
  # Ancienne installation (versions ≤ 1.2.9) dans le dossier utilisateur : doublon.
  if [[ -f $legacy/OFL.txt ]] && ! find "$legacy" -type f ! -name '*.otf' ! -name OFL.txt | grep -q .; then
    rm -rf -- "${legacy:?}"; log "Ancienne copie utilisateur de Space Grotesk retirée : $legacy"
  fi
  pacman -T otf-space-grotesk >/dev/null 2>&1 || die "otf-space-grotesk toujours non satisfait après installation de $SPACE_GROTESK_PKG."
  spin "Actualisation du cache des polices" fc-cache -f || warn "fc-cache a échoué (cache des polices non actualisé)."
  ok "Space Grotesk installé (paquet $SPACE_GROTESK_PKG, archive 38C3 vérifiée)"
}

write_space_grotesk_pkgbuild() {
  cat <<EOF
# $MANAGED_MARK — généré par install.sh, ne pas modifier.
pkgname=$SPACE_GROTESK_PKG
pkgver=$SPACE_GROTESK_VER
pkgrel=1
pkgdesc='Police Space Grotesk (archive 38C3 vérifiée) pour end-4 — fournit otf-space-grotesk'
arch=(any)
url='https://events.ccc.de/congress/2024/infos/styleguide.html'
license=(OFL-1.1)
provides=(otf-space-grotesk)
conflicts=(otf-space-grotesk)
source=("38c3-styleguide-full-v2.zip")
sha256sums=('$SPACE_GROTESK_SHA256')

package() {
  local otf lic
  otf=\$(find "\$srcdir" -type d -path '*space-grotesk*' -name otf | head -n1)
  [[ -n \$otf ]] || { echo "Dossier OTF de Space Grotesk introuvable dans l'archive" >&2; return 1; }
  compgen -G "\$otf/*.otf" >/dev/null || { echo "Aucun fichier OTF Space Grotesk" >&2; return 1; }
  install -Dm644 -t "\$pkgdir/usr/share/fonts/OTF" "\$otf"/*.otf
  lic=\$(find "\$srcdir" -path '*space-grotesk*' -name 'OFL.txt' | head -n1)
  [[ -n \$lic ]] && install -Dm644 "\$lic" "\$pkgdir/usr/share/licenses/\$pkgname/OFL.txt"
  return 0
}
EOF
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
  local -a extra=() skipped=()
  for p in "${GRAPHICS_EXTRA_PKGS[@]}"; do if pkg_installed "$p" || repo_available "$p"; then extra+=("$p"); else skipped+=("$p"); fi; done
  if grep -qE '^[[:space:]]*\[multilib\]' "$PACMAN_CONF"; then
    for p in "${GRAPHICS_LIB32_PKGS[@]}"; do if pkg_installed "$p" || repo_available "$p"; then extra+=("$p"); else skipped+=("$p"); fi; done
  else
    info "Dépôt multilib désactivé : pilotes 32 bits (Steam, Wine) non installés."
  fi
  ((${#extra[@]})) && pac_install "${extra[@]}"
  ((${#skipped[@]})) && info "Absents des dépôts, ignorés : ${skipped[*]}"
  state_set graphics.extra "${extra[*]}"
  if pkg_installed lact && ! systemctl is-enabled --quiet lactd.service 2>/dev/null; then
    spin "Activation de lactd (LACT)" sudo systemctl enable --now lactd.service || warn "lactd non activé (${LAST_CAUSE:-voir journal})."
  fi
  ok "Pilote AMD : amdgpu (noyau) + Mesa RADV (Vulkan), VA-API ; ${extra[*]:-aucun complément}"
  configure_video_playback
  info "libva-mesa-driver et mesa-vdpau n’existent plus : VA-API est fourni par « mesa » (VDPAU abandonné par Mesa)."
  if [[ -d /sys/module/amdgpu ]]; then ok "Module noyau amdgpu chargé"; else warn "Module amdgpu non chargé (sera vérifié après redémarrage)."; fi
  if [[ -e /dev/dri/renderD128 ]]; then ok "Nœud de rendu /dev/dri/renderD128 présent"; fi
  local vk; vk=$(vulkaninfo --summary 2>/dev/null | grep -m1 -E 'deviceName' | sed 's/.*= //' || true)
  if [[ $vk == *RADV* || $vk == *AMD* ]]; then ok "Vulkan : $vk"; else warn "Vulkan : périphérique RADV non confirmé hors session (${vk:-aucune sortie})."; fi
  local va; va=$(vainfo --display drm --device /dev/dri/renderD128 2>&1 | grep -m1 -i 'Driver version' || true)
  if [[ -n $va ]]; then ok "VA-API : ${va#*: }"; else warn "VA-API : non confirmé hors session."; fi
}

# =============================================================================
# 9. ÉTAPE 05 — HYPRLAND (dépôts Arch) ; anciens éléments de la pile épinglée 2.x
# =============================================================================
ala_fetch() {   # télécharge + vérifie séparément l'archive et sa signature
  local n=$1 fn url dest
  fn="$n-${PIN_VER[$n]}-x86_64.pkg.tar.zst"; url="$ALA_URL/${n:0:1}/$n/$fn"; dest="$PKG_CACHE/ala/$fn"
  mkdir -p "$PKG_CACHE/ala"
  if [[ ! -f $dest ]] || ! sha256sum -c --status <<<"${PIN_SHA256[$n]}  $dest"; then
    rm -f -- "$dest.part"
    curl -fL "${CURL_IPV4[@]}" --retry 3 --retry-delay 3 --connect-timeout 20 --max-time 900 -o "$dest.part" "$url" || { rm -f -- "$dest.part"; die "Téléchargement impossible : $fn"; }
    sha256sum -c --status <<<"${PIN_SHA256[$n]}  $dest.part" || { rm -f -- "$dest.part"; die "SHA-256 invalide pour $fn"; }
    mv -f -- "$dest.part" "$dest"
  fi
  # Une archive valide en cache ne garantit pas que son .sig soit encore présent.
  if [[ ! -s $dest.sig ]]; then
    rm -f -- "$dest.sig.part"
    curl -fL "${CURL_IPV4[@]}" --retry 3 --retry-delay 3 --connect-timeout 20 --max-time 120 -o "$dest.sig.part" "$url.sig" || { rm -f -- "$dest.sig.part"; die "Signature Arch introuvable pour $fn"; }
    [[ -s $dest.sig.part ]] || die "Signature Arch vide pour $fn"
    mv -f -- "$dest.sig.part" "$dest.sig"
  fi
  sha256sum -c --status <<<"${PIN_SHA256[$n]}  $dest" || { rm -f -- "$dest"; die "SHA-256 invalide pour $fn"; }
  sudo pacman-key --verify "$dest.sig" "$dest" >/dev/null 2>&1 || die "Signature Arch invalide pour $fn"
  printf '%s' "$dest"
}

prepare_chroot() {
  if [[ -n $(state_get chroot.ready) && -d $CHROOT_DIR/root ]]; then
    spin "Mise à jour du chroot de compilation" arch-nspawn "$CHROOT_DIR/root" pacman -Syu --noconfirm \
      || die "Mise à jour du chroot de compilation impossible (${LAST_CAUSE:-voir journal})."
    return 0
  fi
  # Chroot partiel (création interrompue) : mkarchroot refuse un dossier existant.
  if [[ -e $CHROOT_DIR/root && $CHROOT_DIR == "$CACHE_DIR/chroot" ]]; then
    log "Chroot incomplet supprimé : $CHROOT_DIR/root"
    sudo rm -rf --one-file-system -- "${CHROOT_DIR:?}/root" || true
    [[ ! -e $CHROOT_DIR/root ]] || die "Chroot incomplet impossible à supprimer : $CHROOT_DIR/root (supprimez-le manuellement, puis relancez)."
  fi
  mkdir -p "$CHROOT_DIR"
  spin "Création du chroot de compilation propre (devtools)" mkarchroot "$CHROOT_DIR/root" base-devel \
    || die "Création du chroot impossible (${LAST_CAUSE:-voir journal})."
  state_set chroot.ready 1
}

# Correctifs ajoutés au PKGBUILD d'aquamarine 0.11.0 (exécutés dans prepare()).
# Sur la machine cible, Hyprland s'arrêtait dans aquamarine
# (« basic_string: construction from null is not valid ») juste après la création
# du contexte EGL : une chaîne C nulle (glGetString/eglQueryString) convertie en
# std::string. Correctifs, sans changer l'API ni l'ABI (même soname) :
#  1. lien sur OpenGL::GLES3 au lieu de OpenGL::OpenGL (correctif amont 892622d) ;
#  2. chaînes GL/EGL nulles tolérées ; si GL_EXTENSIONS est nul, le contexte est
#     déclaré inutilisable (erreur journalisée) au lieu d'arrêter Hyprland.
pin_patch_aquamarine() {
  cat <<'PATCH'

# --- hypr-installer : correctifs aquamarine (voir install.sh, pin_patch_aquamarine) ---
if declare -F prepare >/dev/null; then
  eval "_hypr_installer_orig_prepare() $(declare -f prepare | tail -n +2)"
else
  _hypr_installer_orig_prepare() { :; }
fi
prepare() {
  _hypr_installer_orig_prepare
  local r root
  r=$(find "$srcdir" -path '*/src/backend/drm/Renderer.cpp' -print -quit)
  [[ -n $r ]] || { echo "hypr-installer : Renderer.cpp introuvable" >&2; return 1; }
  root=${r%/src/backend/drm/Renderer.cpp}
  sed -i 's/OpenGL::EGL OpenGL::OpenGL/OpenGL::EGL OpenGL::GLES3/' "$root/CMakeLists.txt"
  grep -q 'OpenGL::EGL OpenGL::GLES3' "$root/CMakeLists.txt" || { echo "hypr-installer : correctif CMake non appliqué" >&2; return 1; }
  sed -i '0,/^#include/s//static inline const char* aqNullSafe(const char* s) { return s ? s : ""; }\n#include/' "$r"
  sed -i -E 's/= eglQueryString\(([^;]*)\);/= aqNullSafe(eglQueryString(\1));/' "$r"
  sed -i -E 's/\(char\*\)glGetString\((GL_[A-Z_]+)\)/aqNullSafe((const char*)glGetString(\1))/g' "$r"
  sed -i 's|EGLEXTENSIONS = (const char\*)glGetString(GL_EXTENSIONS);|{ const char* aqExt = (const char*)glGetString(GL_EXTENSIONS); if (!aqExt) { backend->log(AQ_LOG_ERROR, "CDRMRenderer: glGetString(GL_EXTENSIONS) a renvoyé NULL, moteur de rendu désactivé"); eglDestroyContext(egl.display, egl.context); egl.context = EGL_NO_CONTEXT; return; } EGLEXTENSIONS = aqExt; }|' "$r"
  grep -q 'const char\* aqExt' "$r" && grep -q 'aqNullSafe(eglQueryString' "$r" \
    || { echo "hypr-installer : correctif Renderer.cpp non appliqué (source inattendue)" >&2; return 1; }
}
PATCH
}

# Paquet construit (extension quelconque, signature exclue) le plus probable.
find_built_pkg() {   # find_built_pkg <dossier> <nom> <version-pkgrel>
  local f
  for f in "$1/$2-$3-"*.pkg.tar*; do
    [[ -f $f && $f != *.sig ]] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

# Reconstruit un paquet épinglé depuis le PKGBUILD officiel Arch, au commit épinglé,
# dans le chroot, en injectant les autres paquets épinglés (-I).
build_pin_src() {
  local n=$1 dir pkgrel out="" f
  local -a inject=()
  shift
  inject=("$@")
  dir="$BUILD_DIR/arch/$n"
  git_checkout_pinned "$ARCH_PKG_GIT/$n.git" "$dir" "${PIN_GITREF[$n]}"
  pkgrel=$(awk -F= '/^pkgrel=/{print $2; exit}' "$dir/PKGBUILD")
  [[ "$(awk -F= '/^pkgver=/{print $2; exit}' "$dir/PKGBUILD")-$pkgrel" == "${PIN_VER[$n]}" ]] || die "PKGBUILD $n ne correspond pas à ${PIN_VER[$n]}"
  sed -i "s/^pkgrel=.*/pkgrel=${pkgrel}${LOCAL_REL_SUFFIX}/" "$dir/PKGBUILD"
  if declare -F "pin_patch_$n" >/dev/null; then "pin_patch_$n" >>"$dir/PKGBUILD"; log "Correctif appliqué au PKGBUILD de $n"; fi
  local -a iargs=()
  for f in "${inject[@]}"; do iargs+=(-I "$f"); done
  (cd "$dir" && spin "Compilation propre de $n ${PIN_VER[$n]} (chroot)" makechrootpkg -c -r "$CHROOT_DIR" "${iargs[@]}") \
    || die "Compilation de $n en chroot impossible (${LAST_CAUSE:-voir journal})."
  # makechrootpkg dépose le paquet dans PKGDEST (s'il est défini) ou dans le dossier.
  out=$(cd "$dir" && makepkg --packagelist 2>/dev/null | grep -E "/$n-[^-]+-[^-]+-[^-]+\.pkg\.tar(\.[[:alnum:]]+)?$" | head -n1 || true)
  if [[ -z $out || ! -f $out ]]; then
    out=$(find_built_pkg "$(dirname "${out:-$dir/x}")" "$n" "${PIN_VER[$n]}${LOCAL_REL_SUFFIX}" \
          || find_built_pkg "$dir" "$n" "${PIN_VER[$n]}${LOCAL_REL_SUFFIX}" || true)
  fi
  [[ -n $out && -f $out ]] || die "Paquet $n introuvable après compilation"
  mkdir -p "$PKG_CACHE/built"; cp -f "$out" "$PKG_CACHE/built/"
  printf '%s' "$PKG_CACHE/built/$(basename "$out")"
}

# Un paquet installé a-t-il un binaire ou une bibliothèque dont une dépendance
# dynamique est introuvable (rupture d'ABI après une mise à jour) ?
pkg_has_broken_libs() {
  local f
  while IFS= read -r f; do
    [[ -f $f && ! -L $f && ( $f == /usr/bin/* || $f == /usr/lib/* ) ]] || continue
    [[ "$(od -An -tx1 -N4 "$f" 2>/dev/null | tr -d ' ')" == 7f454c46 ]] || continue
    if contains 'not found' "$(LC_ALL=C ldd "$f" 2>/dev/null || true)"; then return 0; fi
  done < <(pacman -Qlq "$1" 2>/dev/null)
  return 1
}

# Paquets épinglés installés dont l'ABI est cassée.
pin_broken_list() {
  local n
  for n in "${PIN_ORDER[@]}"; do
    pkg_installed "$n" || continue
    if pkg_has_broken_libs "$n"; then printf '%s\n' "$n"; fi
  done
  return 0
}

# Paquets installés (hors pile) qui exigent une version plus récente des bibliothèques épinglées.
package_requires_incompatible_pin() {
  local package=$1 token n actual dep_list pattern
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
  # Agent polkit redondant : Quickshell (end-4) fournit le sien.
  if pkg_installed hyprpolkitagent; then remove_conflict hyprpolkitagent "end-4 (agent polkit intégré à Quickshell)"; fi
  return 0
}

# Retire tout ce que les versions 2.x ont mis en place pour figer Hyprland 0.54.3
# (IgnorePkg, hook pacman, verrou, chroot de compilation). Idempotent.
remove_legacy_pinning() {
  local tmp
  if grep -qF '# hypr-installer: pile Hyprland' "$PACMAN_CONF" 2>/dev/null; then
    backup_path "$PACMAN_CONF"
    tmp="$TMP_DIR/pacman.conf"
    awk '/^# hypr-installer: pile Hyprland/ {skip=1; next} skip==1 && /^IgnorePkg[[:space:]]*=/ {skip=0; next} {skip=0; print}' "$PACMAN_CONF" >"$tmp"
    sudo install -m 644 "$tmp" "$PACMAN_CONF"
    ! grep -qF '# hypr-installer: pile Hyprland' "$PACMAN_CONF" || die "Impossible de retirer l’ancien IgnorePkg de $PACMAN_CONF."
    ok "Ancien blocage des versions Hyprland (IgnorePkg) retiré de pacman.conf"
  fi
  if [[ -e $HOOK_FILE || -e $HOOK_SCRIPT ]]; then
    sudo rm -f -- "$HOOK_FILE" "$HOOK_SCRIPT"
    ok "Ancien hook pacman de surveillance retiré"
  fi
  rm -f -- "$PINS_LOCK" "$STATE_DIR/pins.force-src" "$STATE_DIR/aquamarine.fallback" "$STATE_DIR/chroot.ready" "$STATE_DIR/chroot.prepared-run"
  if [[ -d $CHROOT_DIR && $CHROOT_DIR == "$CACHE_DIR/chroot" ]]; then
    sudo rm -rf --one-file-system -- "${CHROOT_DIR:?}" 2>/dev/null || warn "Ancien chroot de compilation non supprimé : $CHROOT_DIR"
  fi
  rm -rf -- "${PKG_CACHE:?}/built" "${BUILD_DIR:?}/arch"
  return 0
}

# Paquets installés qui viennent d'une version 2.x (épinglée ou recompilée
# localement) et doivent être remplacés par la version des dépôts.
legacy_hypr_packages() {
  local n v repo
  for n in "${LEGACY_PIN_PKGS[@]}"; do
    pkg_installed "$n" || continue
    v=$(pkg_version "$n")
    repo=$(LC_ALL=C pacman -Si "$n" 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}' | xargs || true)
    [[ -n $repo && $v != "$repo" ]] && printf '%s\n' "$n"
  done
  return 0
}

install_hyprland() {
  remove_legacy_pinning
  remove_incompatible_dependents
  local -a legacy=() libs=() apps=() n
  mapfile -t legacy < <(legacy_hypr_packages)
  if ((${#legacy[@]})); then
    for n in "${legacy[@]}"; do
      if [[ " ${HYPR_PKGS[*]} " == *" $n "* ]]; then apps+=("$n"); else libs+=("$n"); fi
    done
    info "Remplacement des versions 2.x par celles des dépôts : ${legacy[*]}"
    # Une seule transaction : bibliothèques et applications restent cohérentes.
    ((${#apps[@]})) && pacman_tx "Hyprland : versions des dépôts" sudo pacman -S --noconfirm "${apps[@]}"
    ((${#libs[@]})) && pacman_tx "Bibliothèques Hyprland : versions des dépôts" sudo pacman -S --noconfirm --asdeps "${libs[@]}"
  fi
  pac_install "${HYPR_PKGS[@]}"
  local -a still=()
  mapfile -t still < <(legacy_hypr_packages)
  ((${#still[@]} == 0)) || die "Versions locales encore installées (attendu : dépôts) : ${still[*]}"
  local hv; hv=$(Hyprland --version 2>/dev/null | head -n1 || true)
  [[ -n $hv ]] || die "Hyprland --version ne répond pas après installation."
  local broken=""
  for n in "${LEGACY_PIN_PKGS[@]}"; do pkg_installed "$n" && pkg_has_broken_libs "$n" && broken+="$n "; done
  [[ -z $broken ]] || die "Bibliothèques manquantes pour : $broken(mise à jour système incomplète ?)."
  ok "Hyprland des dépôts Arch installé : $(awk '{print $2}' <<<"$hv") (configuration Lua)"
}


# =============================================================================
# 10. ÉTAPE 06 — END-4 (release 2026.05.11)
# =============================================================================
fetch_end4() {
  git_checkout_pinned "$END4_REPO" "$END4_DIR" "$END4_COMMIT"
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
    # awk a déjà isolé la valeur : « cmake>=3.30 », « glibc »… (ne pas couper sur « = »,
    # sinon « cmake>=3.30 » deviendrait « 3.30 »).
    dep=$(xargs <<<"$line")
    pkg=${dep%%[<>=]*}
    [[ -n $pkg ]] || continue
    if [[ $pkg == otf-space-grotesk ]]; then
      # Fourni par le paquet local hypr-installer-space-grotesk (étape 3).
      pacman -T "$dep" >/dev/null 2>&1 && continue
      unresolved+=("$dep (fourni par $SPACE_GROTESK_PKG, installé à l’étape 3 : relancez l’installation complète)")
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
        # Dépendance virtuelle (ex. « ttf-font » de brave-bin) : un paquet des
        # dépôts la fournit-il ? pacman -S choisira ce fournisseur.
        LC_ALL=C pacman -Sp --print-format %n "$pkg" >/dev/null 2>&1 || unresolved+=("$dep")
      else
        repo_version=$(awk -F': ' '/^Version[[:space:]]*:/ {print $2; exit}' <<<"$repo_info")
        if [[ -n $repo_version ]] && ! dependency_version_satisfied "$dep" "$repo_version"; then
          unresolved+=("$dep (version dépôt $repo_version insuffisante)")
        fi
      fi
    fi
  done < <(awk -F' = ' '/^[[:space:]]*(depends|makedepends|checkdepends)(_[[:alnum:]_]+)? = /{print $2}' "$srcinfo")
  if (( ${#aur_missing[@]} > 0 || ${#pinned_missing[@]} > 0 || ${#unresolved[@]} > 0 )); then
    local -a all_missing=("${aur_missing[@]}" "${pinned_missing[@]}" "${unresolved[@]}")
    local m
    for m in "${all_missing[@]}"; do
      printf '  %s- %s%s\n' "$C_YEL" "$m" "$C_RST" >&3
      log "DÉPENDANCE MANQUANTE ($base) : $m"
    done
    LAST_CAUSE="Dépendance non résolue pour $base : ${all_missing[0]}"
    warn "$base : dépendances non résolues avant compilation."
    return 1
  fi
  return 0
}

# Installe NOUS-MÊMES (sudo au premier plan, pacman gardé) les dépendances de
# compilation lues dans le .SRCINFO, puis makepkg est lancé SANS -s : il
# n'appelle donc jamais sudo en arrière-plan. Si une dépendance manque encore,
# makepkg s'arrête avec un message clair au lieu d'attendre un mot de passe.
install_build_deps() {   # install_build_deps <dossier contenant .SRCINFO> <nom>
  local dir=$1 base=$2 dep pkg
  local -a deps=() repo=() unbuildable=()
  [[ -f $dir/.SRCINFO ]] || (cd "$dir" && makepkg --printsrcinfo) >"$dir/.SRCINFO" \
    || die "$base : génération de .SRCINFO impossible."
  mapfile -t deps < <(awk -F' = ' '/^[[:space:]]*(depends|makedepends|checkdepends)(_x86_64)? = /{print $2}' "$dir/.SRCINFO" | xargs -n1 | sort -u)
  ((${#deps[@]})) || return 0
  while IFS= read -r dep; do
    [[ -n $dep ]] || continue
    pkg=${dep%%[<>=]*}
    if is_pinned "$pkg" || aur_provided "$pkg" || [[ $pkg == otf-space-grotesk ]]; then unbuildable+=("$dep"); else repo+=("$dep"); fi
  done < <(pkgs_missing "${deps[@]}")
  ((${#unbuildable[@]} == 0)) || die "$base : dépendances non installables depuis les dépôts : ${unbuildable[*]}"
  ((${#repo[@]} == 0)) || pac_install --asdeps "${repo[@]}"
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
      # otf-space-grotesk : fourni par le paquet local hypr-installer-space-grotesk.
      if [[ $d == otf-space-grotesk ]]; then
        pacman -T "$d" >/dev/null 2>&1 || die "Dépendance $d non satisfaite : le paquet $SPACE_GROTESK_PKG (étape 3) est absent."
        continue
      fi
      if is_pinned "$d"; then pkg_installed "$d" || die "Dépendance épinglée absente : $d"; continue; fi
      if aur_provided "$d"; then pkg_installed "$d" || die "Dépendance AUR épinglée absente : $d"; continue; fi
      repo+=("$d")
    done
    pac_install --asdeps "${repo[@]}"
    bdir="$BUILD_DIR/meta/illogical-impulse-$m"
    rm -rf -- "${bdir:?}"; mkdir -p "$bdir"; cp -a "$dir/." "$bdir/"
    install_build_deps "$bdir" "illogical-impulse-$m"
    if ! (cd "$bdir" && spin "end-4 : illogical-impulse-$m" env LC_ALL=C makepkg -Af --noconfirm); then
      if [[ $END4_OPTIONAL_METAS == *" $m "* ]]; then warn "illogical-impulse-$m non compilé (fonction secondaire : rendu LaTeX du panneau IA)."; continue; fi
      LAST_CAUSE=$(explain_failure_output "$SPIN_OUTPUT_FILE" | head -n1)
      die "Échec de compilation du méta-paquet end-4 $m. ${LAST_CAUSE:-Voir les lignes affichées ci-dessus.}"
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

# Copie un dossier en créant TOUS les dossiers parents (rsync ne crée que le
# dernier niveau) ; l'erreur exacte de rsync est reportée en cas d'échec.
sync_tree() {   # sync_tree <source/> <destination/> [options rsync…]
  local src=$1 dst=$2 out=""; shift 2
  [[ -d $src ]] || die "Dossier source absent : $src (release end-4 incomplète ?)"
  mkdir -p -- "$dst" || die "Création impossible de $dst (droits ? espace disque ?)"
  if ! out=$(rsync -a "$@" -- "$src" "$dst" 2>&1); then
    log "rsync : $out"
    LAST_CAUSE=$(grep -m1 -E 'rsync:|error' <<<"$out" || tail -n1 <<<"$out")
    die "Copie impossible de $src vers $dst : $LAST_CAUSE"
  fi
}

# Reproduit sdata/subcmd-install/3.files-legacy.sh (sans invite interactive),
# + correctif : hypr/hyprlock/ est aussi déployé (référencé par hyprlock.conf).
deploy_end4_files() {
  local src="$END4_DIR/dots" item name firstrun=0 f
  [[ -f $CFG/illogical-impulse/installed_true ]] || firstrun=1
  mkdir -p "$CFG/hypr" "${XDG_DATA_HOME:-$HOME/.local/share}" "$HOME/.local/bin" "${XDG_CACHE_HOME:-$HOME/.cache}"
  for item in "$src"/.config/*; do
    name=$(basename "$item")
    case $name in quickshell|fish|hypr|fontconfig) continue ;; esac
    if [[ -d $item ]]; then sync_tree "$item/" "$CFG/$name/" --delete; else cp -f -- "$item" "$CFG/$name"; fi
  done
  sync_tree "$src/.local/share/konsole/" "${XDG_DATA_HOME:-$HOME/.local/share}/konsole/"
  sync_tree "$src/.config/quickshell/" "$CFG/quickshell/" --delete
  sync_tree "$src/.config/fish/" "$CFG/fish/" --delete --exclude conf.d
  sync_tree "$src/.config/fontconfig/" "$CFG/fontconfig/" --delete
  # ~/.config/hypr n'existe pas sur un système neuf : rsync ne crée que le
  # dernier niveau de dossier (cause du code 11 « mkdir failed » en 2.0.2).
  sync_tree "$src/.config/hypr/hyprland/" "$CFG/hypr/hyprland/" --delete
  sync_tree "$src/.config/hypr/hyprlock/" "$CFG/hypr/hyprlock/" --delete
  for f in hyprlock.conf hypridle.conf; do
    if [[ -f $CFG/hypr/$f ]] && ! cmp -s "$src/.config/hypr/$f" "$CFG/hypr/$f"; then
      if ((firstrun)); then mv -f "$CFG/hypr/$f" "$CFG/hypr/$f.old"; cp -f "$src/.config/hypr/$f" "$CFG/hypr/$f"
      else cp -f "$src/.config/hypr/$f" "$CFG/hypr/$f.new"; fi
    else cp -f "$src/.config/hypr/$f" "$CFG/hypr/$f"; fi
  done
  cp -f "$src/.config/hypr/hyprland.lua" "$CFG/hypr/hyprland.lua"
  # Ancienne configuration hyprlang (versions 2.x, Hyprland ≤ 0.54) : ignorée par
  # Hyprland ≥ 0.55 ; sauvegardée par backup_existing_config puis retirée.
  local old
  for old in hyprland.conf monitors.conf workspaces.conf; do
    [[ -f $CFG/hypr/$old ]] && mv -f -- "$CFG/hypr/$old" "$CFG/hypr/$old.hyprlang-old"
  done
  for old in "$HYPR_CUSTOM"/*.conf; do
    grep -qF "$MANAGED_MARK" "$old" 2>/dev/null && rm -f -- "$old"
  done
  # Fichiers personnels end-4 (custom/*.lua) : créés s'ils manquent, jamais écrasés.
  mkdir -p "$HYPR_CUSTOM"
  for f in "$src"/.config/hypr/custom/*; do
    [[ -e $HYPR_CUSTOM/$(basename "$f") ]] || cp -a -- "$f" "$HYPR_CUSTOM/"
  done
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
  sync_tree "$dir/" "$target/" --exclude .git
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
  printf 'i2c-dev\n' | sudo_write "$I2C_MODULE_CONF" 644
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
  pac_install hyprshot
  install_end4_metas
  backup_existing_config
  install_google_sans_flex
  setup_python_venv
  deploy_end4_files
  end4_setups
  # Original des raccourcis end-4 conservé pour référence.
  mkdir -p "$MANIFEST_DIR"
  cp -f "$END4_DIR/dots/.config/hypr/hyprland/keybinds.lua" "$MANIFEST_DIR/end4-keybinds.upstream.lua"
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
  install_build_deps "$bdir" "illogical-impulse-quickshell-git"
  (cd "$bdir" && spin "Compilation de Quickshell ${commit:0:12}" env LC_ALL=C makepkg -Af --noconfirm)
}

install_quickshell() {
  if pkg_installed illogical-impulse-quickshell-git && [[ $MODE != repair ]] && quickshell --private-check-compat >/dev/null 2>&1; then
    ok "Quickshell déjà installé et compatible avec Qt"; return 0
  fi
  local qcheck="$BUILD_DIR/meta/quickshell-preflight" qt entry commit label rc=0 used=""
  rm -rf -- "${qcheck:?}"; mkdir -p "$qcheck"
  cp -a "$END4_DIR/sdata/dist-arch/illogical-impulse-quickshell-git/." "$qcheck/"
  check_aur_dependencies "$qcheck" "illogical-impulse-quickshell-git" || die "Quickshell : dépendances de compilation non résolues (liste ci-dessus)."
  qt=$(pkg_version qt6-base); qt=${qt#*:}
  # Candidats : commit épinglé par end-4 (v0.3.2, compatible Qt 6.12), puis plus récent.
  local -a candidates=("$QS_COMMIT|épinglé par end-4")
  candidates+=("${QS_FALLBACKS[@]}")
  for entry in "${candidates[@]}"; do
    commit=${entry%%|*}; label=${entry#*|}
    rc=0
    if [[ $commit == "$QS_COMMIT" ]]; then
      build_quickshell "$commit" || rc=$?
      if ((rc != 0 && rc != 4 && rc != 8)); then
        warn "Quickshell : source officielle indisponible (code $rc) ; nouvel essai via le miroir GitHub."
        rc=0; build_quickshell "$commit" "$QS_MIRROR_URL" || rc=$?
      fi
    else
      build_quickshell "$commit" "$QS_MIRROR_URL" || rc=$?
    fi
    # Code 8/15 (dépendances) : changer de version ne changerait rien.
    ((rc != 8 && rc != 15)) || die "Quickshell : dépendances de compilation manquantes. ${LAST_CAUSE:-Voir les lignes affichées ci-dessus.}"
    if ((rc == 0)); then used=$commit; break; fi
    warn "Quickshell $label (${commit:0:12}) ne compile pas avec Qt ${qt%%-*} (code $rc) ; essai de la version suivante."
  done
  [[ -n $used ]] || die "Aucune version de Quickshell ne compile avec Qt ${qt%%-*}. ${LAST_CAUSE:-Voir journal.}"
  local -a files; mapfile -t files < <(cd "$BUILD_DIR/meta/illogical-impulse-quickshell-git" && makepkg --packagelist)
  install_pkgfiles "${files[@]}"
  state_set quickshell.commit "$used"
  quickshell --private-check-compat >/dev/null 2>&1 || warn "quickshell --private-check-compat signale une incompatibilité Qt"
  if [[ $used != "$QS_COMMIT" ]]; then
    warn "Quickshell ${used:0:12} utilisé à la place du commit épinglé par end-4 (incompatible avec Qt ${qt%%-*})."
  fi
  ok "Quickshell installé (commit ${used:0:12})"
}

# =============================================================================
# 12. ÉTAPE 08 — CLAVIER AZERTY
# =============================================================================
configure_keyboard() {
  write_managed "$HYPR_CUSTOM/general.lua" <<EOF
-- $MANAGED_MARK — clavier AZERTY + réglages RX 550
-- Vos réglages personnels : ~/.config/hypr/custom/general_user.lua (jamais écrasé)
hl.config({
    input = {
        kb_layout = "fr",
        numlock_by_default = true,
    },
    -- RX 550 : flou allégé (end-4 utilise 3 passes) ; l'apparence reste celle d'end-4.
    decoration = {
        blur = {
            passes = 2,
        },
    },
})

if is_file_exists(HOME .. "/.config/hypr/custom/general_user.lua") then
    require("custom.general_user")
end
EOF
  [[ -f $HYPR_CUSTOM/general_user.lua ]] || printf -- '-- Réglages personnels (chargé après custom/general.lua)\n' >"$HYPR_CUSTOM/general_user.lua"
  # Console (TTY) et X11 (écran de connexion SDDM/X11, applications XWayland).
  local vc x11
  vc=$(localectl status | awk -F': ' '/VC Keymap/{print $2}' | xargs)
  x11=$(localectl status | awk -F': ' '/X11 Layout/{print $2}' | xargs)
  if [[ $vc != fr* ]]; then
    backup_path "$VCONSOLE_CONF"
    sudo localectl set-keymap --no-convert fr
  fi
  if [[ $x11 != fr ]]; then
    [[ -e $X11_KEYBOARD_CONF ]] && backup_path "$X11_KEYBOARD_CONF"
    sudo localectl set-x11-keymap --no-convert fr pc105
  fi
  ok "AZERTY : Hyprland (kb_layout = \"fr\"), console ($(localectl status | awk -F': ' '/VC Keymap/{print $2}' | xargs)), X11/écran de connexion (fr)"
  containsi 'utf-8' "$(locale)" || warn "La locale système n’est pas UTF-8 : les caractères accentués peuvent mal s’afficher."
}

# =============================================================================
# 13. ÉTAPE 09 — RACCOURCIS (pensés pour AZERTY)
# =============================================================================
# Hyprland ≥ 0.55 : configuration Lua. On garde les raccourcis d'end-4 (déjà
# basés sur les codes physiques pour Super+1…0) et on corrige ce qui ne
# fonctionne pas, ou fonctionne mal, sur un clavier AZERTY :
#  - Super+Alt+chiffre et Super+Maj+chiffre : les chiffres demandent Maj en
#    AZERTY -> liaisons par code physique (touches & é " ' ( - è _ ç à) ;
#  - Super+- (touche 6) et Super+' (touche 4) déclenchaient À LA FOIS le bureau
#    6/4 et le zoom / le ratio : retirés, déplacés sur des touches libres ;
#  - Super+/ (aide) et Super+. (émojis) demandent Maj en AZERTY -> touches
#    physiques équivalentes (! et :).
configure_keybindings() {
  write_managed "$HYPR_CUSTOM/keybinds.lua" <<EOF
-- $MANAGED_MARK — adaptation AZERTY des raccourcis end-4
-- Vos raccourcis personnels : ~/.config/hypr/custom/keybinds_user.lua (jamais écrasé)

-- Bureaux : Super+Alt / Super+Maj + touche du chiffre (codes physiques 10 à 19)
for i = 1, 10 do
    hl.bind("SUPER + ALT + code:" .. (9 + i), function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
    end, { description = "Fenêtre : envoyer au bureau " .. i .. " (AZERTY)" })
    hl.bind("SUPER + SHIFT + code:" .. (9 + i), function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i) }))
    end, { description = "Fenêtre : déplacer vers le bureau " .. i .. " (AZERTY)" })
end

-- Conflits AZERTY : « - » est sur la touche 6, « ' » sur la touche 4
hl.unbind("SUPER + Minus")
hl.unbind("SUPER + Apostrophe")
hl.bind("SUPER + ugrave", hl.dsp.layout("splitratio +0.1"), { repeating = true, description = "Fenêtre : agrandir la part (touche ù)" })

-- Symboles qui demandent Maj en AZERTY : touches physiques équivalentes
hl.bind("SUPER + code:61", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Aide des raccourcis (touche !)" })
hl.bind("SUPER + code:60", hl.dsp.global("quickshell:overviewEmojiToggle"), { description = "Émojis (touche :)" })
hl.bind("CTRL + SUPER + code:51", hl.dsp.window.resize({ x = 640, y = 480, "exact" }))

-- Aides ajoutées par l'installateur
hl.bind("SUPER + F1", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Aide : liste des raccourcis" })
hl.bind("SUPER + F2", hl.dsp.exec_cmd(HOME .. "/.local/share/hypr-installer/bin/install.sh --monitors"), { description = "Écrans : résolution et fréquence (Hz)" })

if is_file_exists(HOME .. "/.config/hypr/custom/keybinds_user.lua") then
    require("custom.keybinds_user")
end
EOF
  [[ -f $HYPR_CUSTOM/keybinds_user.lua ]] || printf -- '-- Vos raccourcis (chargé après custom/keybinds.lua), ex. :\n-- hl.bind("SUPER + Return", hl.dsp.exec_cmd("kitty"))\n' >"$HYPR_CUSTOM/keybinds_user.lua"
  write_keybind_doc
  ok "Raccourcis end-4 adaptés à l’AZERTY (bureaux, symboles, conflits des touches 4 et 6)"
}

write_keybind_doc() {
  mkdir -p "$MANIFEST_DIR"
  cat >"$MANIFEST_DIR/raccourcis-azerty.txt" <<'EOF'
RACCOURCIS (end-4, adaptés AZERTY) — aide à l'écran : Super+F1 (ou Super+!)
Super+F2 : écrans (résolution, fréquence en Hz)
Super seul : recherche/lanceur | Super+Tab : vue d'ensemble | Super+A / Super+N : panneaux
Super+& é " ' ( - è _ ç à : bureaux 1…10
Super+Maj+(même touche) : déplacer la fenêtre et suivre | Super+Alt+(même touche) : envoyer sans suivre
Super+: émojis | Super+V presse-papiers | Super+Maj+S capture de zone | Super+L verrouiller
Super+ù / Super+; : ratio de la fenêtre | Zoom : Super+= (avant), pavé numérique +/-
Ctrl+Super+R : redémarrer les widgets | Ctrl+Alt+Suppr : menu de session
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
  write_managed "$HYPR_CUSTOM/env.lua" <<EOF
-- $MANAGED_MARK
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
if is_file_exists(HOME .. "/.config/hypr/custom/env_user.lua") then
    require("custom.env_user")
end
EOF
  [[ -f $HYPR_CUSTOM/env_user.lua ]] || printf -- '-- Variables d’environnement personnelles : hl.env("NOM", "valeur")\n' >"$HYPR_CUSTOM/env_user.lua"
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
  for f in "$WALLPAPER_DIR"/*.{jpg,png}; do
    [[ -e $pics/Wallpapers/$(basename "$f") ]] || cp "$f" "$pics/Wallpapers/"
  done
  [[ -f $DEFAULT_WALLPAPER ]] || die "Fond d’écran par défaut absent : $DEFAULT_WALLPAPER"
  state_set default-wallpaper "$pics/Wallpapers/$(basename "$DEFAULT_WALLPAPER")"
  ok "Fonds d’écran disponibles dans ${pics/#$HOME/\~}/Wallpapers (appliqué au premier démarrage)"
}

configure_startup() {
  mkdir -p "$BIN_DIR"
  # Copie stable utilisée par le premier démarrage et le hook pacman (sauf si
  # c'est déjà cette copie qui s'exécute, p. ex. « --repair » depuis le hook).
  if [[ $(readlink -f "$BIN_DIR/install.sh" 2>/dev/null) != "$SCRIPT_SELF" ]] && ! cmp -s "$SCRIPT_SELF" "$BIN_DIR/install.sh"; then
    install -m 755 "$SCRIPT_SELF" "$BIN_DIR/install.sh"
  fi
  write_managed "$HYPR_CUSTOM/execs.lua" <<EOF
-- $MANAGED_MARK
-- Premier démarrage : détection des écrans, fond d'écran + couleurs, tests de session.
hl.on("hyprland.start", function()
    hl.exec_cmd(HOME .. "/.local/share/hypr-installer/bin/install.sh --first-login")
end)
if is_file_exists(HOME .. "/.config/hypr/custom/execs_user.lua") then
    require("custom.execs_user")
end
EOF
  [[ -f $HYPR_CUSTOM/execs_user.lua ]] || printf -- '-- Vos programmes au démarrage :\n-- hl.on("hyprland.start", function() hl.exec_cmd("mon-programme") end)\n' >"$HYPR_CUSTOM/execs_user.lua"
  # Une seule instance de chaque composant : hypridle est lancé par end-4 (exec-once).
  if systemctl --user is-enabled hypridle.service &>/dev/null; then
    systemctl --user disable hypridle.service; info "hypridle.service (utilisateur) désactivé : lancé une seule fois par end-4"
  fi
  local n; n=$(cat "$CFG/hypr/hyprland/execs.lua" "$HYPR_CUSTOM"/*.lua 2>/dev/null | grep -cE '^[[:space:]]*hl\.exec_cmd\("(qs|quickshell) ' || true)
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
  [[ -f $WAYLAND_SESSION ]] || die "Session $WAYLAND_SESSION absente (paquet hyprland incomplet ?)"
  case $CURRENT_DM in
    sddm)
      local st=$SDDM_STATE tmp
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
      local acc="$ACCOUNTS_DIR/$USER"
      if [[ -d $ACCOUNTS_DIR ]]; then
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
# 15 bis. ÉTAT RÉEL DE CHAQUE ÉTAPE (lecture seule)
# =============================================================================
# Utilisé (1) pour décider si un point de reprise est encore valable, (2) après
# chaque étape pour refuser toute fausse réussite, (3) par --diagnose.
verify_pkgs() { local p; while IFS= read -r p; do [[ -n $p ]] && vp_pkg "$p"; done < <(pkgs_missing "$@"); return 0; }

verify_step_3() {
  verify_pkgs "${BASE_PKGS[@]}" "${AUDIO_PKGS[@]}" "${FONT_PKGS[@]}" "${NET_PKGS[@]}" "${BT_PKGS[@]}" "${WALL_PKGS[@]}"
  local entry base commit wants want
  for entry in "${AUR_PINS[@]}"; do
    IFS='|' read -r base commit wants <<<"$entry"
    for want in ${wants//,/ }; do pkg_installed "$want" || vp_pkg "$want"; done
  done
  pkg_installed "$SPACE_GROTESK_PKG" || vp_pkg "$SPACE_GROTESK_PKG"
  return 0
}

verify_step_4() {
  verify_pkgs "${GRAPHICS_PKGS[@]}"
  grep -qF "$H264IFY_FIREFOX_ID" "$FIREFOX_POLICY" 2>/dev/null || vp "vidéo matérielle Firefox non configurée"
  grep -qF "$H264IFY_CHROME_ID" "$BRAVE_POLICY" 2>/dev/null || vp "vidéo matérielle Brave non configurée"
  local p
  [[ -f $STATE_DIR/graphics.extra ]] || vp "compléments graphiques (32 bits, LACT) non installés"
  for p in $(state_get graphics.extra); do pkg_installed "$p" || vp_pkg "$p"; done
  return 0
}

verify_step_5() {
  verify_pkgs "${HYPR_PKGS[@]}"
  local legacy; legacy=$(legacy_hypr_packages | xargs)
  [[ -z $legacy ]] || vp "versions 2.x (épinglées/recompilées) encore installées : $legacy"
  grep -qF '# hypr-installer: pile Hyprland' "$PACMAN_CONF" 2>/dev/null && vp "ancien IgnorePkg encore présent dans $PACMAN_CONF"
  return 0
}

verify_step_6() {
  local rel="" m
  rel=$(cat "$CFG/illogical-impulse/hypr-installer-release" 2>/dev/null || true)
  [[ $rel == "$END4_TAG $END4_COMMIT" ]] || vp "fichiers end-4 $END4_TAG non déployés"
  [[ -f $CFG/quickshell/ii/shell.qml ]] || vp "configuration Quickshell end-4 absente"
  [[ -f $CFG/hypr/hyprland.lua ]] || vp "hyprland.lua absent"
  for m in "${END4_METAS[@]}"; do
    [[ $END4_OPTIONAL_METAS == *" $m "* ]] && continue
    pkg_installed "illogical-impulse-$m" || vp_pkg "illogical-impulse-$m"
  done
  pkg_installed hyprshot || vp_pkg hyprshot
  [[ -x $VENV_DIR/bin/python ]] || vp "environnement Python des widgets absent ($VENV_DIR)"
  return 0
}

verify_step_7() {
  pkg_installed illogical-impulse-quickshell-git || vp_pkg illogical-impulse-quickshell-git
  command -v qs >/dev/null || vp "commande qs absente"
  [[ -n $(state_get quickshell.commit) ]] || vp "commit Quickshell installé non enregistré"
  return 0
}

verify_step_8() {
  grep -q 'kb_layout = "fr"' "$HYPR_CUSTOM/general.lua" 2>/dev/null || vp "kb_layout = \"fr\" absent de $HYPR_CUSTOM/general.lua"
  if command -v localectl >/dev/null; then
    contains 'X11 Layout: fr' "$(localectl status 2>/dev/null || true)" || vp "disposition X11 (écran de connexion) différente de fr"
  fi
  return 0
}

verify_step_9() {
  grep -qF "$MANAGED_MARK" "$HYPR_CUSTOM/keybinds.lua" 2>/dev/null || vp "adaptation AZERTY absente ($HYPR_CUSTOM/keybinds.lua)"
  grep -qF '"SUPER + F2"' "$HYPR_CUSTOM/keybinds.lua" 2>/dev/null || vp "raccourcis d’aide (Super+F1/F2) absents"
  return 0
}

verify_step_10() {
  grep -q -- '--first-login' "$HYPR_CUSTOM/execs.lua" 2>/dev/null || vp "démarrage automatique (--first-login) absent"
  [[ -x $BIN_DIR/install.sh ]] || vp "copie de l’installateur absente ($BIN_DIR/install.sh)"
  [[ -f $HYPR_CUSTOM/env.lua ]] || vp "custom/env.lua absent"
  [[ -f $HOME/.icons/default/index.theme ]] || vp "thème de curseur par défaut absent"
  return 0
}

verify_step_11() {
  verify_pkgs "${AUDIO_PKGS[@]}" "${NET_PKGS[@]}" "${BT_PKGS[@]}"
  local dm
  dm=$(basename "$(readlink -f "$DM_LINK" 2>/dev/null || true)" .service)
  [[ -n $dm && $dm != display-manager ]] || vp "aucun gestionnaire de connexion activé"
  [[ -f $WAYLAND_SESSION ]] || vp "session $WAYLAND_SESSION absente"
  return 0
}

# =============================================================================
# 15. ÉTAPE 12 — APPLICATIONS, DÉVELOPPEMENT, IA (désactivable : --no-dev)
# =============================================================================
# Ajouts à la carte : un échec ici n'abîme jamais le bureau configuré aux étapes
# précédentes. Les paquets des dépôts et Brave sont obligatoires pour l'étape
# (échec = étape en échec, reprise possible) ; Claude Code, freebuff et les
# skills dépendent de services en ligne : un échec devient un avertissement
# explicite ; l’élément manquant est retenté à chaque relance.
repo_available() { pacman -Si -- "$1" &>/dev/null; }
DEV_SOFT_FAIL=0   # un ajout en ligne a échoué PENDANT cette exécution (déjà signalé)
dev_soft_fail() { DEV_SOFT_FAIL=1; warn "$@"; }

ensure_local_bin_path() {
  local d="$HOME/.local/bin"
  mkdir -p "$d"
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH"; export PATH ;; esac
  write_managed "$CFG/environment.d/90-hypr-installer-path.conf" <<EOF
# $MANAGED_MARK — outils installés par l'utilisateur (Claude Code, npm -g)
PATH=\$HOME/.local/bin:\${PATH}
EOF
  mkdir -p "$CFG/fish/conf.d"
  write_managed "$CFG/fish/conf.d/hypr-installer-path.fish" <<EOF
# $MANAGED_MARK
fish_add_path -g \$HOME/.local/bin
EOF
  if ! grep -qF '# hypr-installer: ~/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    [[ -f $HOME/.bashrc ]] && backup_path "$HOME/.bashrc"
    printf '\n# hypr-installer: ~/.local/bin\ncase ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac\n' >>"$HOME/.bashrc"
  fi
}

install_dev_packages() {
  local p
  local -a avail=() unavail=()
  for p in "${DEV_PKGS[@]}"; do
    if pkg_installed "$p" || repo_available "$p"; then avail+=("$p"); else unavail+=("$p"); fi
  done
  state_set dev.unavailable "${unavail[*]}"
  ((${#unavail[@]} == 0)) || warn "Absents des dépôts, ignorés : ${unavail[*]}"
  pac_install "${avail[@]}"
  ok "Outils de développement : ${avail[*]}"
}

aur_head() {   # aur_head <pkgbase> : dernier commit AUR (ou miroir GitHub)
  local base=$1 c=""
  c=$(git ls-remote "https://aur.archlinux.org/$base.git" HEAD 2>/dev/null | awk 'NR==1{print $1}') || true
  [[ $c =~ ^[0-9a-f]{40}$ ]] || c=$(git ls-remote "$AUR_GITHUB_MIRROR" "refs/heads/$base" 2>/dev/null | awk 'NR==1{print $1}') || true
  [[ $c =~ ^[0-9a-f]{40}$ ]] && printf '%s\n' "$c"
  return 0
}

install_aur_latest() {
  local entry base wants want missing commit
  for entry in "${AUR_LATEST[@]}"; do
    IFS='|' read -r base wants <<<"$entry"
    missing=0
    for want in ${wants//,/ }; do pkg_installed "$want" || missing=1; done
    if ((!missing)); then log "AUR $base déjà installé (mises à jour : yay -Syu)"; continue; fi
    commit=$(aur_head "$base")
    [[ -n $commit ]] || die "AUR $base : dépôt injoignable (aur.archlinux.org et miroir GitHub). Relancez plus tard, ou ./install.sh --no-dev."
    aur_build_install "$base" "$commit" "$wants"
    ok "$base installé (version AUR ${commit:0:12})"
  done
}

install_npm_globals() {
  command -v npm >/dev/null || { dev_soft_fail "npm absent : ${NPM_GLOBAL[*]} non installé(s)."; return 0; }
  local prefix p
  prefix=$(npm config get prefix 2>/dev/null || true)
  # npm -g sans sudo : préfixe utilisateur (~/.local), jamais /usr.
  if [[ $prefix != "$HOME"/* ]]; then
    npm config set prefix "$HOME/.local" || { warn "npm : préfixe utilisateur non configurable."; return 0; }
    log "npm prefix : $prefix -> $HOME/.local"
  fi
  for p in "${NPM_GLOBAL[@]}"; do
    if npm ls -g --depth=0 "$p" &>/dev/null; then log "npm $p déjà installé"; continue; fi
    if spin "npm : $p" npm install -g --no-fund --no-audit "$p"; then ok "$p installé (npm, ~/.local)"
    else dev_soft_fail "npm : installation de $p impossible (${LAST_CAUSE:-voir journal}). Réessayé à la prochaine relance."; fi
  done
}

install_claude_code() {
  local v
  if [[ -x $HOME/.local/bin/claude ]] || command -v claude >/dev/null; then
    log "Claude Code déjà installé (mises à jour automatiques)"
  elif ! spin "Claude Code (installateur officiel)" bash -c 'set -o pipefail; curl -fsSL "$1" | bash' _ "$CLAUDE_INSTALL_URL"; then
    dev_soft_fail "Claude Code non installé (${LAST_CAUSE:-voir journal}). Manuel : curl -fsSL $CLAUDE_INSTALL_URL | bash"
    return 0
  fi
  v=$(claude --version 2>/dev/null | head -1 || true)
  if [[ -n $v ]]; then ok "Claude Code : $v (commande « claude »)"; else warn "Claude Code installé mais « claude --version » ne répond pas."; fi
}

# Skills officielles (github.com/anthropics/skills) -> ~/.claude/skills/<nom>/.
# Les skills marquées $SKILL_MARK sont gérées ici ; les vôtres ne sont jamais touchées.
install_ai_skills() {
  local dir="$BUILD_DIR/skills" s name dest n=0 kept=0
  rm -rf -- "${dir:?}.tmp"
  if [[ ! -d $dir/.git ]] || ! git -C "$dir" cat-file -e "$SKILLS_COMMIT^{commit}" 2>/dev/null; then
    rm -rf -- "${dir:?}"
    if ! spin "git clone skills" git clone --quiet "$SKILLS_REPO" "$dir"; then
      rm -rf -- "${dir:?}"; dev_soft_fail "Skills IA non installées : dépôt $SKILLS_REPO injoignable."; return 0
    fi
  fi
  if ! git -C "$dir" checkout --quiet --force --detach "$SKILLS_COMMIT" 2>/dev/null; then
    warn "Skills IA : commit $SKILLS_COMMIT introuvable, dernière version utilisée."
    git -C "$dir" checkout --quiet --force origin/HEAD 2>/dev/null || true
  fi
  mkdir -p "$SKILLS_DIR"
  for s in "$dir"/skills/*/SKILL.md; do
    name=$(basename "$(dirname "$s")"); dest="$SKILLS_DIR/$name"
    if [[ -e $dest && ! -f $dest/$SKILL_MARK ]]; then log "Skill personnelle conservée : $dest"; kept=$((kept + 1)); continue; fi
    sync_tree "$(dirname "$s")/" "$dest/" --delete --exclude "$SKILL_MARK"
    printf '%s %s\n' "$SKILLS_REPO" "$SKILLS_COMMIT" >"$dest/$SKILL_MARK"
    n=$((n + 1))
  done
  # Skills gérées retirées du dépôt officiel : supprimées (les vôtres restent).
  for dest in "$SKILLS_DIR"/*/; do
    dest=${dest%/}
    [[ -f $dest/$SKILL_MARK && ! -f $dir/skills/$(basename "$dest")/SKILL.md ]] && rm -rf -- "${dest:?}"
  done
  ((n)) || { dev_soft_fail "Skills IA : aucune skill trouvée dans $SKILLS_REPO."; return 0; }
  state_set skills.count "$n"
  ok "Skills IA : $n installée(s) dans ~/.claude/skills$( ((kept)) && echo " ($kept skill(s) personnelle(s) conservée(s))")"
}

# Vidéo fluide (YouTube) : stratégies système des navigateurs, modifiables par
# l'utilisateur (Status « default »), fichiers existants fusionnés et sauvegardés.
configure_video_playback() {
  pac_install ffmpeg jq
  local ff tmp
  ff=$(jq -n --arg id "$H264IFY_FIREFOX_ID" '{policies: {
      ExtensionSettings: {($id): {installation_mode: "normal_installed",
        install_url: "https://addons.mozilla.org/firefox/downloads/latest/enhanced-h264ify/latest.xpi"}},
      Preferences: {
        "media.ffmpeg.vaapi.enabled": {Value: true, Status: "default"},
        "media.hardware-video-decoding.force-enabled": {Value: true, Status: "default"},
        "gfx.webrender.all": {Value: true, Status: "default"}}}}')
  if [[ -s $FIREFOX_POLICY ]]; then
    tmp=$(jq -s '.[0] * .[1]' "$FIREFOX_POLICY" - <<<"$ff" 2>/dev/null) \
      || { warn "Firefox : $FIREFOX_POLICY illisible (JSON invalide), laissé tel quel."; tmp=""; }
    [[ -n $tmp ]] && sudo_write "$FIREFOX_POLICY" 644 <<<"$tmp"
  else
    sudo_write "$FIREFOX_POLICY" 644 <<<"$ff"
  fi
  sudo_write "$BRAVE_POLICY" 644 <<<"$(jq -n --arg id "$H264IFY_CHROME_ID" \
    '{ExtensionInstallForcelist: [($id + ";https://clients2.google.com/service/update2/crx")]}')"
  ok "YouTube : H.264 décodé par la carte (enhanced-h264ify) dans Firefox et Brave — redémarrez le navigateur"
}

# Brave : Wayland natif + décodage vidéo matériel (VA-API, RX 550). Lu par le
# lanceur de brave-bin ; jamais écrasé s'il existe déjà.
configure_brave() {
  pkg_installed brave-bin || return 0
  [[ -f $CFG/brave-flags.conf ]] && { log "brave-flags.conf existant conservé"; return 0; }
  printf '%s\n' "--ozone-platform-hint=auto" \
    "--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder" \
    >"$CFG/brave-flags.conf"
  ok "Brave : Wayland + accélération vidéo matérielle"
}

configure_docker() {
  pkg_installed docker || return 0
  if ! systemctl is-enabled --quiet docker.socket 2>/dev/null; then
    spin "Activation de docker.socket" sudo systemctl enable --now docker.socket || warn "docker.socket non activé (${LAST_CAUSE:-voir journal})."
  fi
  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    if ask_yes_no "Autoriser $USER à utiliser Docker sans sudo (groupe docker, équivalent à un accès administrateur) ?"; then
      sudo gpasswd -a "$USER" docker >/dev/null && info "Groupe docker ajouté (effectif à la prochaine connexion)"
    else
      info "Docker utilisable avec sudo (groupe docker non ajouté)"
    fi
  fi
}

install_apps_and_dev() {
  if ((NO_DEV)); then info "Étape ignorée (--no-dev)"; state_set dev.skipped 1; return 0; fi
  rm -f -- "$STATE_DIR/dev.skipped"
  ensure_local_bin_path
  install_dev_packages
  install_aur_latest
  configure_brave
  configure_docker
  install_npm_globals
  install_claude_code
  install_ai_skills
}

verify_step_12() {
  ((NO_DEV)) && return 0
  [[ $MODE == diagnose && -f $STATE_DIR/dev.skipped ]] && return 0
  local p unavail
  unavail=" $(state_get dev.unavailable) "
  for p in "${DEV_PKGS[@]}"; do
    [[ $unavail == *" $p "* ]] && continue
    pkg_installed "$p" || vp_pkg "$p"
  done
  local entry base wants want
  for entry in "${AUR_LATEST[@]}"; do
    IFS='|' read -r base wants <<<"$entry"
    for want in ${wants//,/ }; do pkg_installed "$want" || vp_pkg "$want"; done
  done
  [[ -f $CFG/environment.d/90-hypr-installer-path.conf ]] || vp "PATH ~/.local/bin non configuré"
  # Ajouts en ligne : absents -> l'étape est rejouée à la prochaine exécution ;
  # un échec déjà signalé pendant CETTE exécution n'invalide pas l'étape.
  if ((!DEV_SOFT_FAIL)); then
    [[ -x $HOME/.local/bin/claude ]] || command -v claude >/dev/null || vp "Claude Code absent"
    for p in "${NPM_GLOBAL[@]}"; do [[ -e $HOME/.local/bin/$p ]] || command -v "$p" >/dev/null || vp "$p (npm) absent"; done
    compgen -G "$SKILLS_DIR/*/$SKILL_MARK" >/dev/null || vp "skills IA absentes (~/.claude/skills)"
  fi
  return 0
}

# =============================================================================
# 15 bis. MODE --dotfiles <lien> / --dotfiles-restore
# =============================================================================
# Remplace l'apparence (Hyprland, barre, terminal, lanceur…) par celle d'un dépôt
# de dotfiles. Garanties :
#  - tout élément remplacé est d'abord DÉPLACÉ dans une sauvegarde (manifeste) :
#    --dotfiles-restore remet exactement l'état précédent ;
#  - aucun script du dépôt n'est exécuté (install.sh, setup.sh… sont signalés) ;
#  - seuls ~/.config, ~/.local/share, ~/.local/bin et les fichiers cachés du
#    dossier personnel sont concernés (jamais .ssh, .gnupg, ni hors de $HOME) ;
#  - aucun paquet de noyau, de chargeur de démarrage ou de partitionnement
#    n'est installé, même s'il figure dans une liste du dépôt ;
#  - une configuration Hyprland refusée par Hyprland --verify-config est
#    annulée aussitôt (pas de boucle de connexion) ;
#  - le clavier AZERTY est ré-appliqué par-dessus la nouvelle configuration.
readonly DOTFILES_DIR="$DATA_DIR/dotfiles"
readonly DOTFILES_BACKUPS="$DATA_DIR/dotfiles-backups"
readonly AZERTY_LUA_NAME="hypr-installer-azerty.lua"
readonly AZERTY_LUA_HOOK='pcall(dofile, (os.getenv("HOME") or "") .. "/.config/hypr/hypr-installer-azerty.lua") -- hypr-installer : AZERTY'
# Dossier de configuration -> paquet des dépôts qui l'utilise.
declare -grA DF_PKG_MAP=(
  [waybar]=waybar [rofi]=rofi [wofi]=wofi [fuzzel]=fuzzel [tofi]=tofi [walker]=walker
  [dunst]=dunst [mako]=mako [swaync]=swaync [eww]=eww
  [kitty]=kitty [alacritty]=alacritty [foot]=foot [wezterm]=wezterm [ghostty]=ghostty
  [fastfetch]=fastfetch [hyprpaper]=hyprpaper [swww]=swww [waypaper]=waypaper
  [hyprlock]=hyprlock [hypridle]=hypridle [swaylock]=swaylock [wlogout]=wlogout
  [cava]=cava [btop]=btop [htop]=htop [nwg-look]=nwg-look [nwg-dock-hyprland]=nwg-dock-hyprland
  [starship.toml]=starship [fish]=fish [nvim]=neovim [yazi]=yazi [ranger]=ranger [lf]=lf
  [zathura]=zathura [mpv]=mpv [imv]=imv [Thunar]=thunar [qt5ct]=qt5ct [qt6ct]=qt6ct
  [kvantum]=kvantum [Kvantum]=kvantum [wal]=python-pywal [matugen]=matugen
  [.zshrc]=zsh [.tmux.conf]=tmux [tmux]=tmux
)
# Jamais installés depuis un dépôt de dotfiles (démarrage, noyau, disques, pilotes).
readonly DF_PKG_DENY='^(grub.*|efibootmgr|os-prober|refind.*|limine.*|syslinux|shim.*|sbctl|systemd-boot.*|mkinitcpio.*|dracut.*|booster|kernel-install.*|linux|linux-.*|.*-dkms|nvidia.*|parted|gparted|gptfdisk|fdisk|util-linux|e2fsprogs|btrfs-progs|dosfstools|ntfs-3g|cryptsetup|lvm2|mdadm|pacman|pacman-.*|archlinux-keyring|endeavouros-keyring|base|filesystem|glibc|systemd)$'
DF_SRC=() DF_DST=() DF_PKGS=() DF_LIST_PKGS=() DF_SCRIPTS=()

df_add() {   # df_add <source> <destination>
  local i
  [[ -e $1 || -L $1 ]] || return 0
  [[ $2 == "$HOME"/?* && $2 != "$DATA_DIR"* ]] || return 0
  for i in "${!DF_DST[@]}"; do [[ ${DF_DST[i]} == "$2" ]] && { DF_SRC[i]=$1; return 0; }; done
  DF_SRC+=("$1"); DF_DST+=("$2")
}

df_add_home_root() {   # dossier reproduisant $HOME (.config, .local, fichiers cachés)
  local root=$1 e n
  for e in "$root"/.config/* "$root"/.config/.[!.]*; do df_add "$e" "$CFG/$(basename "$e")"; done
  for e in "$root"/.local/share/*; do
    n=$(basename "$e"); [[ $n == hypr-installer ]] && continue
    df_add "$e" "${XDG_DATA_HOME:-$HOME/.local/share}/$n"
  done
  for e in "$root"/.local/bin/*; do df_add "$e" "$HOME/.local/bin/$(basename "$e")"; done
  for e in "$root"/.[!.]*; do
    n=$(basename "$e")
    case $n in .config|.local|.git|.github|.gitignore|.gitmodules|.gitattributes|.ssh|.gnupg|.claude|.cache|.DS_Store|.stow-local-ignore|.editorconfig|.vscode|.idea|.pre-commit-config.yaml|.prettierrc*|.luarc.json|.stylua.toml|.envrc) continue ;; esac
    df_add "$e" "$HOME/$n"
  done
}

df_add_config_root() {   # dossier reproduisant ~/.config (sous-dossiers seulement)
  local e n
  for e in "$1"/*/ "$1"/starship.toml; do
    e=${e%/}; n=$(basename "$e")
    case ${n,,} in screenshots|screenshot|assets|images|img|preview|previews|docs|doc|wallpapers|walls|scripts|install|setup|.github) continue ;; esac
    df_add "$e" "$CFG/$n"
  done
}

dotfiles_plan() {   # remplit DF_SRC/DF_DST selon l'organisation du dépôt
  local drepo=$1 r d n known=0
  DF_SRC=(); DF_DST=()
  for r in "$drepo" "$drepo/dots" "$drepo/home" "$drepo/dotfiles" "$drepo/files"; do
    [[ -d $r/.config ]] && df_add_home_root "$r"
  done
  if ((${#DF_DST[@]} == 0)); then   # GNU Stow : un dossier par programme contenant .config/…
    for d in "$drepo"/*/; do [[ -d $d/.config || -f $d/.zshrc || -f $d/.bashrc ]] && df_add_home_root "${d%/}"; done
  fi
  if ((${#DF_DST[@]} == 0)) && [[ -d $drepo/config ]]; then df_add_config_root "$drepo/config"; fi
  if ((${#DF_DST[@]} == 0)); then   # le dépôt EST un ~/.config
    for d in "$drepo"/*/; do n=$(basename "$d"); [[ -n ${DF_PKG_MAP[$n]:-} || $n == hypr ]] && known=1; done
    ((known)) && df_add_config_root "$drepo"
  fi
  ((${#DF_DST[@]})) || die "Organisation du dépôt non reconnue : ni .config/, ni dots/.config, ni home/, ni paquets stow, ni dossiers de configuration (hypr, waybar, kitty…) à la racine."
  # Scripts du dépôt : signalés, jamais exécutés.
  mapfile -t DF_SCRIPTS < <(find "$drepo" -maxdepth 2 -type f \( -iname 'install*' -o -iname 'setup*' -o -iname 'bootstrap*' \) -not -path '*/.git/*' -printf '%P\n' | sort | head -n 10)
}

dotfiles_packages() {   # paquets à installer : connus d'après les dossiers + listes du dépôt
  local drepo=$1 d n p f
  local -a cand=() list=()
  DF_PKGS=(); DF_LIST_PKGS=()
  for d in "${DF_DST[@]}"; do n=$(basename "$d"); [[ -n ${DF_PKG_MAP[$n]:-} ]] && cand+=("${DF_PKG_MAP[$n]}"); done
  for f in packages.txt pkglist.txt packages.lst pkglist packages pacman.txt pkgs.txt; do
    [[ -f $drepo/$f ]] || continue
    mapfile -t -O "${#list[@]}" list < <(sed -e 's/#.*//' "$drepo/$f" | awk '{print $1}' | grep -E '^[a-z0-9@._+-]+$' || true)
  done
  for p in "${cand[@]}"; do
    [[ $p =~ $DF_PKG_DENY ]] && continue
    pkg_installed "$p" || ! repo_available "$p" || DF_PKGS+=("$p")
  done
  local -a denied=() aur=()
  for p in "${list[@]}"; do
    if [[ $p =~ $DF_PKG_DENY ]]; then denied+=("$p"); continue; fi
    pkg_installed "$p" && continue
    if repo_available "$p"; then DF_LIST_PKGS+=("$p"); else aur+=("$p"); fi
  done
  mapfile -t DF_PKGS < <(printf '%s\n' "${DF_PKGS[@]}" | sort -u | sed '/^$/d')
  mapfile -t DF_LIST_PKGS < <(printf '%s\n' "${DF_LIST_PKGS[@]}" | sort -u | sed '/^$/d')
  ((${#denied[@]})) && info "Paquets système de la liste ignorés (démarrage/noyau/disques) : $(printf '%s\n' "${denied[@]}" | sort -u | xargs)"
  ((${#aur[@]})) && info "Paquets de la liste absents des dépôts (AUR ?), non installés : $(printf '%s\n' "${aur[@]}" | sort -u | head -n 15 | xargs)$( ((${#aur[@]} > 15)) && echo ' …')"
  return 0
}

hypr_config_ok() {   # hypr_config_ok <hyprland.lua>
  command -v Hyprland >/dev/null || return 0
  local out; out=$(Hyprland --verify-config -c "$1" 2>&1 || true)
  log "verify-config ($1) : $out"
  grep -qi 'config ok' <<<"$out"
}

dotfiles_azerty() {   # ré-applique l'AZERTY par-dessus la configuration Hyprland installée
  local main="$CFG/hypr/hyprland.lua" binds=1
  [[ -f $main ]] || return 0
  grep -rqsE 'code:1[0-9]\b' "$CFG/hypr" && binds=0
  {
    printf -- '-- %s — clavier AZERTY par-dessus vos dotfiles (supprimez la ligne\n' "$MANAGED_MARK"
    printf -- '-- « hypr-installer : AZERTY » de hyprland.lua pour le désactiver)\n'
    printf 'hl.config({ input = { kb_layout = "fr" } })\n'
    if ((binds)); then
      cat <<'EOF'
-- Bureaux 1-10 par touches physiques (& é " ' ( - è _ ç à) : les chiffres
-- demandent Maj en AZERTY, les raccourcis « SUPER + 1 » ne marchent donc pas.
for i = 1, 10 do
    hl.bind("SUPER + code:" .. (9 + i), function() hl.dispatch(hl.dsp.focus({ workspace = i })) end)
    hl.bind("SUPER + SHIFT + code:" .. (9 + i), function() hl.dispatch(hl.dsp.window.move({ workspace = i })) end)
end
EOF
    fi
  } >"$CFG/hypr/$AZERTY_LUA_NAME"
  grep -qF "$AZERTY_LUA_HOOK" "$main" || printf '\n%s\n' "$AZERTY_LUA_HOOK" >>"$main"
  log "AZERTY ré-appliqué (raccourcis bureaux : $binds)"
}

apply_dotfiles() {
  local url=${DOTFILES_URL%%#*} ref="" name drepo commit i n dst bk hyi=-1
  [[ $DOTFILES_URL == *#* ]] && ref=${DOTFILES_URL#*#}
  if [[ ! $url =~ ^(https?://|git@|ssh://|file://) && ! -d $url ]]; then
    die "Lien invalide : $url (attendu : https://github.com/utilisateur/depot, éventuellement suivi de #branche)."
  fi
  command -v git >/dev/null || die "git est requis."
  name=$(basename "${url%/}" .git); name=${name//[^A-Za-z0-9._-]/_}
  drepo="$DOTFILES_DIR/$name"
  rm -rf -- "${drepo:?}"; mkdir -p "$DOTFILES_DIR"
  spin "Téléchargement des dotfiles ($name)" git clone --quiet --recurse-submodules "$url" "$drepo" \
    || die "Téléchargement impossible : $url (${LAST_CAUSE:-dépôt privé, lien erroné ou réseau}). "
  if [[ -n $ref ]]; then
    git -C "$drepo" checkout --quiet --force "$ref" 2>/dev/null || die "Branche, tag ou commit introuvable : $ref"
    git -C "$drepo" submodule update --init --recursive --quiet 2>/dev/null || true
  fi
  commit=$(git -C "$drepo" rev-parse HEAD)
  dotfiles_plan "$drepo"

  # Hyprland ≥ 0.55 ne lit plus que hyprland.lua : une configuration hyprland.conf
  # seule donnerait un bureau sans réglages (ou une boucle de connexion).
  for i in "${!DF_DST[@]}"; do [[ ${DF_DST[i]} == "$CFG/hypr" ]] && hyi=$i; done
  if ((hyi >= 0)) && [[ ! -f ${DF_SRC[hyi]}/hyprland.lua ]]; then
    warn "Ces dotfiles fournissent hyprland.conf (ancien format) : Hyprland ≥ 0.55 n’accepte que hyprland.lua. Votre configuration Hyprland actuelle est conservée ; le reste (barre, terminal, lanceur…) est appliqué."
    unset 'DF_SRC[hyi]' 'DF_DST[hyi]'; DF_SRC=("${DF_SRC[@]}"); DF_DST=("${DF_DST[@]}"); hyi=-1
    ((${#DF_DST[@]})) || die "Rien d’applicable dans ce dépôt (seulement une configuration Hyprland incompatible)."
  fi
  dotfiles_packages "$drepo"

  ui ""; ui "  ${C_B}Dotfiles : $url${ref:+ ($ref)}${C_RST} ${C_DIM}commit ${commit:0:12}${C_RST}"
  ui "  Éléments remplacés (${#DF_DST[@]}) — l’existant est sauvegardé :"
  for dst in "${DF_DST[@]}"; do ui "    • ${dst/#$HOME/\~}"; done
  ((${#DF_PKGS[@]})) && ui "  Paquets nécessaires (dépôts officiels) : ${DF_PKGS[*]}"
  ((${#DF_SCRIPTS[@]})) && ui "  ${C_DIM}Scripts du dépôt NON exécutés : ${DF_SCRIPTS[*]}${C_RST}"
  ask_yes_no "Appliquer ces dotfiles ? (annulable avec ./install.sh --dotfiles-restore)" || { ui "  Annulé, rien n’a été modifié."; return 0; }

  if ((${#DF_PKGS[@]} + ${#DF_LIST_PKGS[@]})); then
    ensure_sudo
    ((${#DF_PKGS[@]})) && pac_install "${DF_PKGS[@]}"
    if ((${#DF_LIST_PKGS[@]})) && ask_yes_no "Installer aussi les ${#DF_LIST_PKGS[@]} paquet(s) listé(s) par le dépôt (${DF_LIST_PKGS[*]:0:10}$( ((${#DF_LIST_PKGS[@]} > 10)) && echo ' …')) ?"; then
      pac_install "${DF_LIST_PKGS[@]}"
    fi
  fi

  mkdir -p "$DOTFILES_BACKUPS"
  bk=$(mktemp -d "$DOTFILES_BACKUPS/$RUN_TS.XXXX")
  mkdir -p "$bk/items"
  printf '%s\t%s\n' "$url${ref:+#$ref}" "$commit" >"$bk/SOURCE"
  : >"$bk/MANIFEST.tsv"
  printf '%s\n' "$bk" >>"$DOTFILES_BACKUPS/stack"
  n=0
  for i in "${!DF_DST[@]}"; do
    dst=${DF_DST[i]}
    if [[ -e $dst || -L $dst ]]; then
      mv -- "$dst" "$bk/items/$i"
      printf '%s\t%s\n' "$dst" "$bk/items/$i" >>"$bk/MANIFEST.tsv"
    else
      printf '%s\t-\n' "$dst" >>"$bk/MANIFEST.tsv"
    fi
    mkdir -p -- "$(dirname "$dst")"
    cp -a -- "${DF_SRC[i]}" "$dst" || die "Copie impossible : ${DF_SRC[i]} -> $dst (sauvegarde : $bk)"
    [[ -e $dst/.git ]] && rm -rf -- "${dst:?}/.git"
    n=$((n + 1))
  done
  if ((hyi >= 0)) && [[ -f $CFG/hypr/hyprland.lua ]]; then
    dotfiles_azerty
    if ! hypr_config_ok "$CFG/hypr/hyprland.lua"; then
      warn "La configuration Hyprland de ces dotfiles est refusée par Hyprland --verify-config : l’ancienne est remise (pas de boucle de connexion). Le reste est appliqué."
      rm -rf -- "${CFG:?}/hypr"
      [[ -e $bk/items/$hyi ]] && mv -- "$bk/items/$hyi" "$CFG/hypr"
      sed -i "\#^$CFG/hypr\t#d" "$bk/MANIFEST.tsv"
    fi
  fi
  state_set dotfiles.active "$url${ref:+#$ref} ${commit:0:12}"
  ok "$n élément(s) appliqué(s) depuis $name. Sauvegarde : ${bk/#$HOME/\~}"
  ui "  Déconnectez-vous puis reconnectez-vous pour voir le nouveau bureau."
  ui "  Revenir en arrière : ./install.sh --dotfiles-restore   ·   Revenir à end-4 : ./install.sh --repair"
}

restore_dotfiles() {
  local bk dst b src
  local -a lines=() stack=()
  [[ -s $DOTFILES_BACKUPS/stack ]] || die "Aucune application de dotfiles à annuler."
  mapfile -t stack <"$DOTFILES_BACKUPS/stack"
  bk=${stack[-1]}
  [[ -f $bk/MANIFEST.tsv ]] || die "Sauvegarde introuvable ou incomplète : $bk"
  src=$(cut -f1 "$bk/SOURCE" 2>/dev/null || echo '?')
  mapfile -t lines < <(tac "$bk/MANIFEST.tsv")
  ui ""; ui "  ${C_B}Annulation des dotfiles $src${C_RST} (${#lines[@]} élément(s), état du $(basename "$bk"))"
  ask_yes_no "Remettre la configuration d’avant ?" || { ui "  Annulé."; return 0; }
  for b in "${lines[@]}"; do
    dst=${b%%$'\t'*}; b=${b#*$'\t'}
    [[ $dst == "$HOME"/?* ]] || { warn "Entrée ignorée (hors du dossier personnel) : $dst"; continue; }
    rm -rf -- "$dst"
    if [[ $b != - ]]; then
      [[ -e $b || -L $b ]] || { warn "Sauvegarde manquante pour $dst"; continue; }
      mkdir -p -- "$(dirname "$dst")"; mv -- "$b" "$dst"
    fi
  done
  unset 'stack[-1]'
  printf '%s\n' "${stack[@]}" | sed '/^$/d' >"$DOTFILES_BACKUPS/stack"
  mv -- "$bk" "$(mktemp -u "$bk.restored.XXXX")"
  if ((${#stack[@]})); then state_set dotfiles.active "$(cut -f1 "${stack[-1]}/SOURCE" 2>/dev/null)"; else rm -f -- "$STATE_DIR/dotfiles.active"; fi
  ok "Configuration précédente restaurée (${#lines[@]} élément(s)). Les paquets installés sont conservés."
  ui "  Déconnectez-vous puis reconnectez-vous pour appliquer."
}

# =============================================================================
# 15 ter. MODE --diagnose (aucune modification du système)
# =============================================================================
diagnose_prereqs() {
  CHECK_LINES=(); CHECK_FAIL=0; CHECK_WARN=0; CHECK_PASS=0
  ui ""; ui "  ${C_B}Prérequis${C_RST}"
  local id="" name="inconnu"
  if [[ -r $OS_RELEASE ]]; then
    # shellcheck source=/dev/null
    id=$(. "$OS_RELEASE" && printf '%s' "${ID:-}")
    # shellcheck source=/dev/null
    name=$(. "$OS_RELEASE" && printf '%s' "${PRETTY_NAME:-inconnu}")
  fi
  OS_ID=$id OS_NAME=$name
  chk_if "Distribution EndeavourOS" '[[ $id == endeavouros ]]' "$name" FAIL "$name (EndeavourOS requis, ou --allow-non-eos)"
  chk_if "Architecture x86_64" '[[ $(uname -m) == x86_64 ]]' "$(uname -m)"
  chk_if "pacman disponible" 'command -v pacman >/dev/null' "pacman"
  chk_if "systemd actif" '[[ -d $SYSTEMD_RUNDIR ]] && command -v systemctl >/dev/null' "systemd"
  chk_if "sudo disponible" 'command -v sudo >/dev/null' "sudo"
  chk_if "Lancé en utilisateur normal" '[[ $EUID -ne 0 ]]' "$(id -un)" FAIL "ne pas lancer en root"
  local c miss=""; for c in curl git; do command -v "$c" >/dev/null || miss+="$c "; done
  chk_if "Commandes curl et git" '[[ -z $miss ]]' "présentes" FAIL "absentes : $miss"
  if [[ -e $PACMAN_LOCK ]]; then
    if pacman_running; then chk WARN "Verrou pacman" "une opération pacman est en cours"
    else chk FAIL "Verrou pacman" "verrou orphelin $PACMAN_LOCK (installation interrompue) : ./install.sh proposera de le retirer"; fi
  else chk PASS "Verrou pacman" "libre"; fi
  local host net=1
  for host in https://archive.archlinux.org https://github.com https://gitlab.archlinux.org; do
    if net_reachable "$host"; then chk PASS "Réseau : ${host#https://}" "joignable${CURL_IPV4[*]:+ (IPv4 uniquement)}"
    else chk FAIL "Réseau : ${host#https://}" "ne répond pas : ${NET_LAST_ERROR:-aucune réponse} (indispensable)"; net=0; fi
  done
  if net_reachable https://aur.archlinux.org; then chk PASS "Réseau : aur.archlinux.org" "joignable"
  else chk WARN "Réseau : aur.archlinux.org" "injoignable : miroir GitHub utilisé en secours"; fi
  local free_root free_home
  free_root=$(LC_ALL=C df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9'); free_root=${free_root:-0}
  free_home=$(LC_ALL=C df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9'); free_home=${free_home:-0}
  chk_if "Espace disque /" '((free_root >= 25))' "${free_root} Go libres" FAIL "${free_root} Go libres (25 Go requis)"
  chk_if "Espace disque $HOME" '((free_home >= 20))' "${free_home} Go libres" FAIL "${free_home} Go libres (20 Go requis)"
  if ((net)); then
    local lsr
    lsr=$(git ls-remote "$END4_REPO" refs/heads/main 2>/dev/null | awk '{print $1}' || true)
    chk_if "Dépôt end-4 joignable" '[[ -n $lsr ]]' "commit épinglé ${END4_COMMIT:0:12}" FAIL "git ls-remote a échoué"
    local hv; hv=$(LC_ALL=C pacman -Si hyprland 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}' | xargs || true)
    chk_if "Hyprland disponible dans les dépôts" '[[ -n $hv ]]' "${hv:-?}" FAIL "introuvable (pacman -Sy ?)"
  else
    chk INFO "Versions distantes" "non vérifiées (réseau indisponible)"
  fi
  ((CHECK_FAIL == 0)) || STEP_STATUS[CURRENT_STEP]=FAILED
  return 0
}

diagnose_hardware() {
  ui ""; ui "  ${C_B}Matériel${C_RST}"
  local before=$CHECK_FAIL
  if ! command -v lspci >/dev/null; then
    chk WARN "Détection du GPU" "lspci absent (pciutils) : installé automatiquement par ./install.sh"
  else
    probe_hardware
    if ((HAS_AMD_GPU)); then chk PASS "GPU AMD" "pilote ${GPU_DRIVER:-?}"
    elif ((ALLOW_OTHER_GPU)); then chk WARN "GPU AMD" "absent (--allow-other-gpu)"
    else chk FAIL "GPU AMD" "aucun GPU AMD détecté (option --allow-other-gpu)"; fi
    if ((HAS_AMD_GPU)) && [[ -n $GPU_DRIVER && $GPU_DRIVER != amdgpu ]]; then chk WARN "Pilote noyau" "$GPU_DRIVER (amdgpu attendu)"; fi
  fi
  ((CHECK_FAIL == before)) || STEP_STATUS[CURRENT_STEP]=FAILED
  return 0
}

declare -a DIAG_MISSING=()
diagnose_steps() {
  ui ""; ui "  ${C_B}État des étapes d’installation (vérification de l’état réel)${C_RST}"
  local i date code reason cause intr label
  DIAG_MISSING=()
  if ! command -v pacman >/dev/null; then
    chk FAIL "États des étapes" "pacman absent : état des paquets impossible à vérifier"
    return 0
  fi
  for i in 3 4 5 6 7 8 9 10 11 12; do
    label="Étape $(printf '%02d' "$i") — ${STEP_TITLES[i]}"
    if step_verify "$i"; then
      STEP_STATUS[i]=DONE
      chk PASS "$label" "terminée, état réel conforme"
      continue
    fi
    DIAG_MISSING+=("${VERIFY_MISSING[@]}")
    if [[ -f $STATE_DIR/step-$i.failed ]]; then
      date=$(failure_get "$i" date); code=$(failure_get "$i" code); reason=$(failure_get "$i" raison)
      cause=$(failure_get "$i" cause); intr=$(failure_get "$i" interrompu)
      STEP_STATUS[i]=FAILED
      if [[ $intr == 1 ]]; then chk FAIL "$label" "interrompue le $date ; à reprendre avec ./install.sh"
      else chk FAIL "$label" "ÉCHEC le $date (code $code) : $reason${cause:+ — cause : $cause}"; fi
    elif checkpoint_done "$i"; then
      STEP_STATUS[i]=INCOMPLETE
      chk FAIL "$label" "terminée auparavant mais état réel dégradé : ${VERIFY_PROBLEMS[*]:0:3}"
    else
      STEP_STATUS[i]=NOTRUN
      chk INFO "$label" "non exécutée (${#VERIFY_PROBLEMS[@]} élément(s) à installer/configurer)"
    fi
  done
  if ((${#DIAG_MISSING[@]})); then
    local -a uniq=()
    mapfile -t uniq < <(printf '%s\n' "${DIAG_MISSING[@]}" | sort -u)
    ui ""; ui "  ${C_B}Paquets absents${C_RST} ${C_DIM}(normal pour une étape non exécutée)${C_RST}"
    chk INFO "Paquets absents (${#uniq[@]})" "$(printf '%s ' "${uniq[@]:0:20}")$( ((${#uniq[@]} > 20)) && echo '…')"
  fi
  ui ""
  if ((CHECK_FAIL)); then
    ui "  Action conseillée : ${C_B}./install.sh${C_RST} (reprise automatique) ; si une étape terminée est dégradée : ${C_B}./install.sh --repair${C_RST}"
  elif [[ " ${STEP_STATUS[*]:3:10} " == *" NOTRUN "* ]]; then
    ui "  Installation non terminée : lancez ${C_B}./install.sh${C_RST} pour continuer."
  else
    ui "  Toutes les étapes sont terminées et conformes. Tests en session : ./install.sh --post-login-check"
  fi
  return 0
}

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

validate_installation() {
  ui ""; ui "  ${C_B}Contrôles hors session graphique${C_RST}"
  CHECK_LINES=(); CHECK_FAIL=0; CHECK_WARN=0; CHECK_PASS=0
  chk_if "EndeavourOS détecté" '[[ $OS_ID == endeavouros ]]' "$OS_NAME" WARN
  local hv; hv=$(Hyprland --version 2>/dev/null | head -1 || true)
  chk_if "Hyprland installé (dépôts Arch)" '[[ -n $hv ]] && pkg_installed hyprland' "${hv:-absent}"
  local legacy; legacy=$(legacy_hypr_packages | xargs)
  chk_if "Pile Hyprland cohérente (dépôts)" '[[ -z $legacy ]]' "aucune version épinglée/recompilée restante" FAIL "à remplacer : $legacy"
  chk_if "Aucun blocage de versions (IgnorePkg)" '! grep -qF "# hypr-installer: pile Hyprland" "$PACMAN_CONF"' "pacman.conf"
  local vout; vout=$(Hyprland --verify-config -c "$CFG/hypr/hyprland.lua" 2>&1 || true)
  log "verify-config : $vout"
  chk_if "Configuration Lua valide" 'grep -qi "config ok" <<<"$vout"' "Hyprland --verify-config" FAIL "$(grep -im1 -E 'error|erreur' <<<"$vout" || echo 'voir journal')"
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
  chk_if "Quickshell installé" 'pkg_installed illogical-impulse-quickshell-git && command -v qs >/dev/null' "commit ${qsc:0:12}$([[ -n $qsc && $qsc != "$QS_COMMIT" ]] && echo ' (version corrigée pour Qt récent)')"
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
  chk_if "Session Wayland Hyprland" '[[ -f $WAYLAND_SESSION && -x $START_HYPRLAND ]]' "hyprland.desktop -> start-hyprland"
  chk_if "Portails XDG" 'pkg_installed xdg-desktop-portal && [[ -f $HYPR_PORTAL && -f $CFG/xdg-desktop-portal/hyprland-portals.conf ]]' "hyprland + gtk + kde"
  chk_if "Polkit" 'pkg_installed polkit && ! pkg_installed hyprpolkitagent' "agent : Quickshell (PolkitService)"
  chk_if "Audio (PipeWire activé)" '[[ -e $PIPEWIRE_GLOBAL_WANTS || -e $PIPEWIRE_VENDOR_WANTS ]] && pkg_installed wireplumber && pkg_installed pipewire-pulse' "pipewire, pulse, wireplumber"
  chk_if "Réseau (NetworkManager)" 'systemctl is-active --quiet NetworkManager' "$(nmcli -t networking connectivity 2>/dev/null || echo '?')" WARN
  if ((BT_ADAPTER)); then chk_if "Bluetooth" 'systemctl is-active --quiet bluetooth' "adaptateur détecté" WARN
  else chk INFO "Bluetooth" "aucun adaptateur (service activé, démarrage conditionnel)"; fi
  chk_if "GPU AMD détecté" '((HAS_AMD_GPU))' "pilote ${GPU_DRIVER:-?}"
  local vk; vk=$(vulkaninfo --summary 2>/dev/null | grep -m1 deviceName | sed 's/.*= //' || true)
  chk_if "Vulkan (RADV)" '[[ $vk == *RADV* ]]' "${vk:-non confirmé hors session}" WARN
  local fm="" fams; fams=$(fc-list : family); for c in "Google Sans Flex" "Material Symbols Rounded" "JetBrainsMono Nerd Font" "Noto Sans" "Font Awesome"; do containsi "$c" "$fams" || fm+="$c, "; done
  chk_if "Polices installées" '[[ -z $fm ]]' "end-4 + Noto + Nerd + Font Awesome" WARN "manquantes : ${fm%, }"
  chk_if "AZERTY configuré" "grep -q 'kb_layout = \"fr\"' \"\$HYPR_CUSTOM/general.lua\" && contains 'X11 Layout: fr' \"\$(localectl status)\"" "Hyprland, console, X11"
  chk_if "Raccourcis AZERTY configurés" 'grep -qF "$MANAGED_MARK" "$HYPR_CUSTOM/keybinds.lua" && grep -q "SUPER + ALT + code:" "$HYPR_CUSTOM/keybinds.lua"' "end-4 + adaptation AZERTY"
  chk_if "Bureaux 1-10 par touches physiques" 'grep -q "\"SUPER + code:\" .. numberkey" "$CFG/hypr/hyprland/keybinds.lua"' "Super+& é \" ' ( - è _ ç à"
  chk_if "Gestionnaire de connexion" '[[ -n $CURRENT_DM ]] && systemctl is-enabled --quiet "$CURRENT_DM.service"' "${CURRENT_DM:-aucun}"
  chk_if "Autostart configuré" 'grep -q -- "--first-login" "$HYPR_CUSTOM/execs.lua" && [[ -x $BIN_DIR/install.sh ]]' "hyprland.start (end-4 + premier démarrage)"
  if ((NO_DEV)) || [[ -f $STATE_DIR/dev.skipped ]]; then
    chk INFO "Applications et outils de développement" "non installés (--no-dev)"
  else
    chk_if "Brave" 'command -v brave >/dev/null' "brave-bin (AUR, mises à jour : yay -Syu)"
    chk_if "Node.js, Python, git" 'command -v node >/dev/null && command -v python3 >/dev/null && command -v git >/dev/null' "$(node --version 2>/dev/null || echo '?') / $(python3 --version 2>/dev/null | cut -d' ' -f2)"
    chk_if "Claude Code" '[[ -x $HOME/.local/bin/claude ]] || command -v claude >/dev/null' "commande « claude »" WARN "absent : curl -fsSL $CLAUDE_INSTALL_URL | bash"
    chk_if "freebuff" 'PATH="$HOME/.local/bin:$PATH" command -v freebuff >/dev/null' "npm (~/.local)" WARN "absent : npm install -g freebuff"
    local nsk; nsk=$(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name "$SKILL_MARK" 2>/dev/null | wc -l)
    chk_if "Skills IA (~/.claude/skills)" '((nsk > 0))' "$nsk skill(s) officielle(s)" WARN "aucune"
  fi
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
    printf 'Étapes :\n'; local i; for i in $(seq 1 "$LAST_STEP"); do printf '  [%02d/%s] %-27s %s\n' "$i" "$LAST_STEP" "${STEP_TITLES[i]}" "${STEP_STATUS[i]}"; done
    for i in $(seq 1 "$LAST_STEP"); do
      [[ -f $STATE_DIR/step-$i.failed ]] || continue
      printf '\nDernier échec enregistré, étape %02d :\n' "$i"; sed 's/^/  /' "$STATE_DIR/step-$i.failed"
    done
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

session_monitors() {   # session_monitors [force]
  # end-4 charge ~/.config/hypr/monitors.lua s'il existe (format nwg-displays).
  local conf="$CFG/hypr/monitors.lua" out=""
  if [[ ${1:-} != force ]] && grep -q 'hl.monitor' "$conf" 2>/dev/null; then log "monitors.lua déjà configuré"; return 0; fi
  while IFS=$'\t' read -r name w h modes; do
    local best="" bestr=0 m r scale=1
    for m in $modes; do
      [[ $m == "${w}x${h}@"* ]] || continue
      r=${m#*@}; r=${r%Hz}
      if awk -v a="$r" -v b="$bestr" 'BEGIN{exit !(a>b)}'; then bestr=$r; best=$m; fi
    done
    [[ -n $best ]] || continue
    ((w >= 3840)) && scale='"auto"'
    out+="hl.monitor({ output = \"$name\", mode = \"${best%Hz}\", position = \"auto\", scale = $scale })"$'\n'
    log "Écran $name : ${best%Hz} (modes : $modes)"
  done < <(hyprctl monitors all -j | jq -r '.[] | [.name, (.width|tostring), (.height|tostring), (.availableModes|join(" "))] | @tsv')
  [[ -n $out ]] || return 0
  printf -- '-- %s — détecté au premier démarrage (résolution native, fréquence max.)\n%s' "$MANAGED_MARK" "$out" >"$conf.tmp"
  mv -f "$conf.tmp" "$conf"
  hyprctl reload >/dev/null 2>&1 || true
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
  chk_if "Hyprland en cours d’exécution" '[[ -n $v ]]' "$v"
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
  chk_if "Raccourcis chargés" '((nb > 50))' "$nb liaisons actives"
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
  [[ ${HYPR_INSTALLER_SESSION_TEST:-0} == 1 ]] && { log "Lancement d’essai (--session-debug) : premier démarrage différé"; return 0; }
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
# 17 ter. MODE --monitors (Super+F2) : résolution et fréquence de chaque écran
# =============================================================================
# Menu fuzzel (ou terminal) ; le choix est écrit dans ~/.config/hypr/monitors.lua
# (chargé par end-4), appliqué aussitôt, puis CONFIRMÉ : sans réponse sous 20 s
# (écran noir, mode refusé…), l'ancien réglage revient automatiquement.
pick() {   # pick <invite> : choix d'une ligne de stdin (fuzzel en session, sinon terminal)
  local prompt=$1 n=0 l a
  local -a items=()
  mapfile -t items
  if [[ -n ${WAYLAND_DISPLAY:-} ]] && command -v fuzzel >/dev/null; then
    printf '%s\n' "${items[@]}" | timeout "${PICK_TIMEOUT:-120}" fuzzel --dmenu --prompt "$prompt " --width 72 --lines 15 2>/dev/null || true
    return 0
  fi
  [[ -r /dev/tty ]] || return 0
  for l in "${items[@]}"; do n=$((n + 1)); printf '  %2d) %s\n' "$n" "$l" >&3; done
  printf '  %s ' "$prompt" >&3
  read -r -t "${PICK_TIMEOUT:-120}" a </dev/tty || return 0
  [[ $a =~ ^[0-9]+$ ]] && ((a >= 1 && a <= n)) && printf '%s\n' "${items[a - 1]}"
  return 0
}

monitor_lines() {   # une ligne par mode : « SORTIE │ LxH @ F Hz[ (actuel)] │ description »
  hyprctl monitors all -j | jq -r '.[] | [.name, (.description // ""), ("\(.width)x\(.height)@\(.refreshRate * 100 | round / 100)"), (.availableModes | join(" "))] | @tsv' |
  while IFS=$'\t' read -r name desc cur modes; do
    printf '%s\n' $modes | sed 's/Hz$//' | awk -F'[x@]' '!seen[$0]++ {printf "%d\t%s\t%s\n", $1*$2, $3, $0}' | sort -t$'\t' -k1,1nr -k2,2gr |
    while IFS=$'\t' read -r _ rate mode; do
      local tag=""; awk -v a="${mode#*@}" -v b="${cur#*@}" -v r1="${mode%@*}" -v r2="${cur%@*}" 'BEGIN{exit !(r1==r2 && (a-b)^2 < 0.01)}' && tag=" (actuel)"
      printf '%s │ %s @ %s Hz%s │ %s\n' "$name" "${mode%@*}" "$(printf '%.2f' "$rate" | sed 's/\.00$//')" "$tag" "${desc:0:40}"
    done
  done
}

monitors_write() {   # monitors_write <sortie> <mode LxH@F>  (les autres écrans sont conservés)
  local name=$1 mode=$2 conf="$CFG/hypr/monitors.lua" scale=1 w
  w=${mode%%x*}; ((w >= 3840)) && scale='"auto"'
  local old; old=$(grep -E "output = \"$name\"" "$conf" 2>/dev/null | head -1 || true)
  [[ $old =~ scale\ =\ ([^ }]+) ]] && scale=${BASH_REMATCH[1]}
  {
    printf -- '-- %s — écrans (Super+F2 pour changer)\n' "$MANAGED_MARK"
    grep -E '^hl\.monitor\(' "$conf" 2>/dev/null | grep -vF "output = \"$name\"" || true
    printf 'hl.monitor({ output = "%s", mode = "%s", position = "auto", scale = %s })\n' "$name" "$mode" "$scale"
  } >"$conf.tmp"
  mv -f "$conf.tmp" "$conf"
}

monitors_menu() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || die "À lancer depuis la session Hyprland (raccourci Super+F2)."
  command -v jq >/dev/null || die "jq est requis."
  local conf="$CFG/hypr/monitors.lua" choice name res rate keep auto="★ Automatique : résolution native et fréquence maximale (tous les écrans)"
  local -a lines=()
  mapfile -t lines < <(monitor_lines)
  ((${#lines[@]})) || die "Aucun écran détecté par hyprctl."
  choice=$(printf '%s\n' "$auto" "${lines[@]}" | pick "Écran / fréquence >")
  [[ -n $choice ]] || { log "Aucun choix"; return 0; }
  mkdir -p "$CFG/hypr"
  if [[ -f $conf ]]; then cp -f "$conf" "$conf.previous"; else rm -f "$conf.previous"; fi
  if [[ $choice == "$auto" ]]; then
    session_monitors force
    name="tous les écrans"; res="auto"
  else
    name=$(awk -F' │ ' '{print $1}' <<<"$choice")
    res=$(awk -F' │ ' '{print $2}' <<<"$choice" | sed -E 's/ \(actuel\)//; s/ Hz$//; s/ @ /@/')
    rate=${res#*@}
    # Fréquence exacte annoncée par l'écran (ex. 143.98 et non 144).
    res=$(hyprctl monitors all -j | jq -r --arg n "$name" --arg r "${res%@*}" --argjson f "$rate" \
      '.[] | select(.name == $n) | .availableModes[] | sub("Hz$"; "") | select(startswith($r + "@")) | select(((split("@")[1] | tonumber) - $f) | fabs < 0.01)' | head -1)
    [[ -n $res ]] || die "Mode introuvable pour $name."
    monitors_write "$name" "$res"
    hyprctl reload >/dev/null 2>&1 || true
  fi
  log "Écran $name -> $res"
  sleep 2
  keep=$(printf '%s\n' "Garder ce réglage" "Annuler (revenir à l’ancien)" | PICK_TIMEOUT=20 pick "Garder ? (retour automatique dans 20 s)")
  if [[ $keep == "Garder ce réglage" ]]; then
    rm -f "$conf.previous"
    notify-send -a "Écrans" "Réglage enregistré" "$name : ${res/@/ à } Hz" 2>/dev/null || true
    ui "  Réglage enregistré : $name ${res}"
  else
    if [[ -f $conf.previous ]]; then mv -f "$conf.previous" "$conf"; else rm -f "$conf"; fi
    hyprctl reload >/dev/null 2>&1 || true
    notify-send -a "Écrans" "Ancien réglage remis" 2>/dev/null || true
    ui "  Ancien réglage remis."
  fi
}

# =============================================================================
# 17 bis. MODE --session-debug : pourquoi la session Hyprland se ferme-t-elle ?
# =============================================================================
# À lancer depuis un TTY (Ctrl+Alt+F3) quand l'écran de connexion revient après
# le mot de passe. Rassemble tout ce qui existe sur le dernier démarrage de
# session, en tire les causes connues, et peut tenter un lancement contrôlé.
# Lance Hyprland (sans start-hyprland) avec une configuration donnée pendant
# quelques secondes. 0 = toujours en vie, 1 = arrêt/plantage.
hypr_trial() {   # hypr_trial <fichier de configuration> <journal>
  local rc=0
  HYPR_INSTALLER_SESSION_TEST=1 timeout 10 Hyprland -c "$1" >"$2" 2>&1 </dev/tty || rc=$?
  ((rc == 124))
}

# Isole la cause d'un plantage : configuration vide, puis recherche par
# dichotomie du fichier « source = » qui déclenche l'arrêt.
session_bisect_config() {   # session_bisect_config <rapport> <nom du tableau d'indices>
  local out=$1; local -n ev=$2
  local dir="$CFG/hypr" main="$CFG/hypr/hyprland.lua" t="$CFG/hypr/.hypr-installer-trial.lua" tl="$TMP_DIR/trial.log" cm="--" re='^[[:space:]]*require\('
  if [[ ! -f $main ]]; then main="$CFG/hypr/hyprland.conf" t="$CFG/hypr/.hypr-installer-trial.conf" cm="#" re='^[[:space:]]*source[[:space:]]*='; fi
  local -a srcs=(); local n lo hi mid i culprit="" line
  ui "  Recherche de la cause (plusieurs lancements de 10 s, l’écran va basculer)…"
  if [[ $cm == "--" ]]; then printf -- '-- configuration vide (test)\n' >"$t"; else printf 'monitor = , preferred, auto, 1\n' >"$t"; fi
  if ! hypr_trial "$t" "$tl"; then
    ev+=("Hyprland plante même avec une configuration VIDE : binaire ou bibliothèques en cause -> ./install.sh --repair")
    { printf '\n--- essai configuration vide : plantage ---\n'; tail -n 30 "$tl"; } >>"$out"
    rm -f -- "$t"; return 0
  fi
  ev+=("Hyprland fonctionne avec une configuration vide : la cause est dans la configuration.")
  mapfile -t srcs < <(grep -nE "$re" "$main" | cut -d: -f1)
  n=${#srcs[@]}
  trial_upto() {   # n'active que les k premiers « source = »
    local k=$1 j
    cp -f -- "$main" "$t"
    for ((j = k; j < n; j++)); do sed -i "${srcs[j]}s/^/$cm hypr-installer-test: /" "$t"; done
    hypr_trial "$t" "$tl"
  }
  if ! trial_upto 0; then
    ev+=("Plantage causé par ${main##*/} lui-même (hors fichiers inclus).")
  else
    lo=1; hi=$n
    while ((lo < hi)); do
      mid=$(( (lo + hi) / 2 ))
      if trial_upto "$mid"; then lo=$((mid + 1)); else hi=$mid; fi
    done
    line=$(sed -n "${srcs[lo-1]}p" "$main")
    culprit=$(sed -E 's/^[[:space:]]*(source[[:space:]]*=[[:space:]]*|require\(")//; s/"\).*//' <<<"$line")
    ev+=("Fichier qui provoque le plantage : $culprit (ligne ${srcs[lo-1]} de ${main##*/})")
    { printf '\n--- fichier en cause : %s ---\n' "$culprit"; cat "$dir/$culprit" 2>&1 | head -n 120
      printf '\n--- journal de l’essai fautif ---\n'; trial_upto "$lo" || true; grep -m1 -B25 -E 'terminate called|received signal' "$tl" || tail -n 25 "$tl"; } >>"$out" 2>&1
  fi
  rm -f -- "$t"
  return 0
}

newest_file() {   # le fichier le plus récent parmi les arguments existants
  local f best=""
  for f in "$@"; do [[ -f $f ]] || continue; [[ -z $best || $f -nt $best ]] && best=$f; done
  printf '%s' "$best"
}
session_debug() {
  local out="$REPORT_DIR/session-debug-$RUN_TS.txt" f found=0 crash="" sessionlog="" hlog=""
  local -a evidence=()
  # Mode de collecte en lecture seule : une commande absente ou en échec ne doit
  # pas interrompre l'analyse.
  set +e; trap - ERR
  ui ""; ui "  ${C_B}Analyse de l’échec de démarrage de la session Hyprland${C_RST}"
  {
    printf '=== hypr-installer %s — session-debug %s ===\n' "$INSTALLER_VERSION" "$(date '+%F %T')"
    printf '\n--- Paquets ---\n'; pacman -Q hyprland aquamarine hyprutils hyprlang hyprgraphics hyprcursor sddm mesa 2>&1
    printf '\n--- Session déclarée ---\n'; cat "$WAYLAND_SESSION" 2>&1; ls -l "$START_HYPRLAND" 2>&1
    printf '\n--- État SDDM ---\n'; sudo cat "$SDDM_STATE" 2>/dev/null || echo "(illisible)"
  } >"$out" 2>&1

  # 1. Sortie de la session capturée par SDDM.
  for f in "${XDG_DATA_HOME:-$HOME/.local/share}/sddm/wayland-session.log" "$HOME/.local/share/sddm/wayland-session.log"; do
    [[ -s $f ]] && { sessionlog=$f; break; }
  done
  # 2. Rapports de plantage Hyprland (le plus récent).
  # (nullglob est actif : un motif sans correspondance disparaît ; jamais de « ls » sans argument.)
  crash=$(newest_file "${XDG_CACHE_HOME:-$HOME/.cache}"/hyprland/hyprlandCrashReport*.txt \
                      "${XDG_DATA_HOME:-$HOME/.local/share}"/hyprland/hyprlandCrashReport*.txt)
  # 3. Dernier journal Hyprland encore présent.
  hlog=$(newest_file "${XDG_RUNTIME_DIR:-/run/user/$UID}"/hypr/*/hyprland.log "$HOME"/.local/share/hyprland/hyprland.log*)
  {
    printf '\n--- %s ---\n' "${sessionlog:-wayland-session.log absent}"; [[ -n $sessionlog ]] && tail -n 80 "$sessionlog"
    printf '\n--- %s ---\n' "${crash:-aucun rapport de plantage}"; [[ -n $crash ]] && head -n 60 "$crash"
    printf '\n--- %s ---\n' "${hlog:-aucun journal Hyprland}"; [[ -n $hlog ]] && tail -n 60 "$hlog"
    printf '\n--- journal système (sddm, Hyprland) ---\n'
    journalctl -b --no-pager -o short -u sddm 2>/dev/null | tail -n 40
    journalctl -b --no-pager -o short _COMM=Hyprland _COMM=start-hyprland 2>/dev/null | tail -n 40
    printf '\n--- plantages (coredumpctl) ---\n'; coredumpctl list --no-pager 2>/dev/null | grep -iE 'hypr|aquamarine' | tail -n 5
    printf '\n--- bibliothèques ---\n'; LC_ALL=C ldd /usr/bin/Hyprland 2>&1 | grep -i 'not found' || echo "aucune bibliothèque manquante"
    printf '\n--- vérification de la configuration ---\n'; Hyprland --verify-config -c "$CFG/hypr/hyprland.lua" 2>&1 | tail -n 15
  } >>"$out" 2>&1

  # Lancement contrôlé depuis ce TTY : montre l'erreur exacte si Hyprland meurt.
  if [[ -t 0 && -z ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] \
     && ask_yes_no "Tenter un lancement de Hyprland depuis ce TTY pendant 20 s (l’écran basculera, il reviendra seul) ?"; then
    local lt="$TMP_DIR/hyprland-tty.log" bin=Hyprland
    [[ -x $START_HYPRLAND ]] && bin=$START_HYPRLAND
    log "Lancement de test : $bin"
    local trc=0
    # HYPR_INSTALLER_SESSION_TEST : le premier démarrage (--first-login) ne doit
    # pas se dérouler pendant ce lancement d'essai.
    HYPR_INSTALLER_SESSION_TEST=1 timeout 20 "$bin" >"$lt" 2>&1 </dev/tty || trc=$?
    { printf '\n--- lancement de test depuis le TTY (%s, code %s ; 124 = toujours en vie après 20 s) ---\n' "$bin" "$trc"; tail -n 60 "$lt"; } >>"$out"
    if ((trc == 124)); then evidence+=("Hyprland démarre normalement depuis un TTY : le problème vient du lancement par l’écran de connexion (SDDM).")
    else
      evidence+=("Hyprland s’arrête aussi depuis un TTY (code $trc) : le problème est dans Hyprland ou sa configuration.")
      # Ce que Hyprland faisait juste avant de s'arrêter.
      { printf '\n--- contexte avant l’arrêt ---\n'
        grep -m1 -B25 -E 'terminate called|received signal|Segmentation' "$lt" || tail -n 25 "$lt"; } >>"$out"
      session_bisect_config "$out" evidence
    fi
  fi

  # Causes connues, par ordre de probabilité.
  local txt; txt=$(cat "$out")
  contains 'not found' "$(grep -A2 -- '--- bibliothèques' <<<"$txt")" && evidence+=("Bibliothèque manquante pour Hyprland -> ./install.sh --repair (recompilation de la pile).")
  grep -qiE 'undefined symbol|symbol lookup error' <<<"$txt" && evidence+=("Symbole introuvable dans une bibliothèque (ABI) : $(grep -m1 -iE 'undefined symbol|symbol lookup error' <<<"$txt") -> ./install.sh --repair")
  grep -qiE 'error while loading shared libraries' <<<"$txt" && evidence+=("$(grep -m1 -i 'error while loading shared libraries' <<<"$txt")")
  grep -qiE "start-hyprland: (command )?not found|No such file or directory.*start-hyprland|cannot access '[^']*start-hyprland'" <<<"$txt" && evidence+=("Le lanceur start-hyprland est introuvable alors que la session l’appelle.")
  grep -qiE 'segmentation fault|SIGSEGV|SIGABRT|core dumped' <<<"$txt" && evidence+=("Hyprland plante (signal) : voir le rapport de plantage ci-dessous.")
  # (« Wayland backend cannot start » est normal depuis un TTY : ce n'est pas une panne GPU.)
  grep -qiE 'failed to open drm|no gpus|couldn.t find a suitable gpu|CBackend::create\(\) failed' <<<"$txt" && evidence+=("Le GPU n’a pas pu être ouvert : $(grep -m1 -iE 'failed to open drm|no gpus|suitable gpu|CBackend::create' <<<"$txt")")
  local what; what=$(grep -m1 -A1 'terminate called' <<<"$txt" | grep -m1 'what()' | sed 's/^[[:space:]]*//')
  [[ -n $what ]] && evidence+=("Exception C++ : $what")
  grep -qiE 'libseat|seatd|logind.*(fail|denied)|couldn.t (take|open) .*seat' <<<"$txt" && evidence+=("Accès au siège (logind/libseat) refusé : $(grep -m1 -iE 'libseat|seatd|seat' <<<"$txt")")
  grep -qiE 'config error|error in config|parse error' <<<"$(grep -A15 -- '--- vérification de la configuration' <<<"$txt")" && evidence+=("Erreur de configuration hyprlang : $(grep -A15 -- '--- vérification de la configuration' <<<"$txt" | grep -m1 -iE 'error')")
  grep -qiE 'uwsm' <<<"$(grep -A5 'Session déclarée' <<<"$txt")" && evidence+=("La session choisie passe par uwsm : choisissez « Hyprland » (sans uwsm).")
  [[ -z $sessionlog && -z $crash && -z $hlog ]] && evidence+=("Aucune trace de la session : elle s’arrête avant même de lancer Hyprland (script de session SDDM, shell de connexion).")
  found=${#evidence[@]}

  ui ""
  if ((found)); then
    ui "  ${C_B}Causes probables :${C_RST}"; printf '    • %s\n' "${evidence[@]}" >&3
  else
    ui "  Aucune cause connue reconnue automatiquement : voir les extraits du rapport."
  fi
  ui ""
  if grep -q -- '--- contexte avant l’arrêt' "$out"; then
    ui "  ${C_B}Dernières actions de Hyprland avant l’arrêt :${C_RST}"
    sed -n '/--- contexte avant l’arrêt ---/,/^--- /p' "$out" | grep -v '^---' | tail -n 12 | cut -c1-150 | sed 's/^/    /' >&3
    ui ""
  fi
  if [[ -n $crash ]]; then
    ui "  ${C_B}Pile d’appels du dernier plantage (${crash/#$HOME/\~}) :${C_RST}"
    sed -n '/[Bb]acktrace/,$p' "$crash" | head -n 22 | cut -c1-160 | sed 's/^/    /' >&3
    ui ""
  fi
  ui "  ${C_B}Extraits utiles :${C_RST}"
  grep -iE 'error|fail|fatal|not found|undefined|abort|segfault|signal|cannot|couldn|what\(\)' "$out" | grep -viE 'warning|0 errors|Creating the CHyprError|wl_display_connect|Implementation wayland failed|context extensions' | tail -n 15 | sed 's/^/    /' >&3 || true
  ui ""
  ui "  Rapport complet : ${out/#$HOME/\~}"
  ui "  En attendant : à l’écran de connexion, une autre session (ex. Plasma) reste utilisable si elle est installée."
  printf '%s\n' "${evidence[@]}" | sed 's/^/CAUSE /' >>"$out"
  return 0
}

# =============================================================================
# 18. PROGRAMME PRINCIPAL
# =============================================================================
usage() {
  cat <<EOF
HYPRLAND AUTOMATED INSTALLER $INSTALLER_VERSION
EndeavourOS × Hyprland (dépôts Arch, Lua) × end-4/dots-hyprland $END4_TAG

Usage : ./install.sh [options]

  (sans option)        Installation complète, avec reprise automatique après interruption
  --yes                Ne pas demander la confirmation initiale
  --force              Réexécuter toutes les étapes (ignore les points de reprise)
  --diagnose           Mode diagnostic : contrôles et rapport, aucune modification
  --repair             Réparation : revérifie et réinstalle ce qui est
                       cassé (ex. après une mise à jour de bibliothèque), redéploie
  --post-login-check   Tests à exécuter DANS la session Hyprland
  --session-debug      Depuis un TTY : explique pourquoi la session Hyprland se
                       ferme après la connexion (rapport + causes probables)
  --allow-non-eos      Autoriser une base Arch autre qu’EndeavourOS
  --allow-other-gpu    Autoriser l’absence de GPU AMD
  --no-reboot-prompt   Ne pas proposer le redémarrage à la fin
  --no-dev             Ne pas installer Brave, les outils de développement et d’IA (étape 12)
  --dotfiles <lien>    Remplace l’apparence par les dotfiles d’un dépôt git (GitHub…) :
                       sauvegarde, copie, dépendances connues, AZERTY conservé.
                       Ex. : ./install.sh --dotfiles https://github.com/user/dots#branche
  --dotfiles-restore   Annule le dernier --dotfiles (restaure la configuration précédente)
  --monitors           Choisir résolution et fréquence de chaque écran (aussi : Super+F2)
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
      --monitors) MODE=monitors ;;
      --session-debug) MODE=session-debug ;;
      --first-login) MODE=first-login ;;
      --allow-non-eos) ALLOW_NON_EOS=1 ;;
      --allow-other-gpu) ALLOW_OTHER_GPU=1 ;;
      --no-reboot-prompt) NO_REBOOT_PROMPT=1 ;;
      --no-dev) NO_DEV=1 ;;
      --dotfiles) MODE=dotfiles; shift; DOTFILES_URL=${1:-}; [[ -n $DOTFILES_URL ]] || { echo "--dotfiles : lien du dépôt manquant" >&2; exit 2; } ;;
      --dotfiles-restore) MODE=dotfiles-restore ;;
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
  TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hypr-installer.XXXXXX")
  SPIN_OUTPUT_FILE="$TMP_DIR/last-command.out"

  if [[ $MODE == first-login ]]; then first_login; exit 0; fi
  if [[ $MODE == session-debug ]]; then
    LOG_FILE="$LOG_DIR/session-debug-$RUN_TS.log"
    exec 3>&1 4>&2 5>>"$LOG_FILE"; exec >>"$LOG_FILE" 2>&1
    session_debug
    exit 0
  fi
  if [[ $MODE == monitors ]]; then
    LOG_FILE="$LOG_DIR/monitors-$RUN_TS.log"
    exec 3>&1 4>&2 5>>"$LOG_FILE"; exec >>"$LOG_FILE" 2>&1
    monitors_menu
    exit 0
  fi
  if [[ $MODE == dotfiles || $MODE == dotfiles-restore ]]; then
    LOG_FILE="$LOG_DIR/$MODE-$RUN_TS.log"
    exec 3>&1 4>&2 5>>"$LOG_FILE"; exec >>"$LOG_FILE" 2>&1
    log "hypr-installer $INSTALLER_VERSION — mode $MODE ${DOTFILES_URL}"
    if [[ $MODE == dotfiles ]]; then apply_dotfiles; else restore_dotfiles; fi
    exit 0
  fi
  if [[ $MODE == post-login-check ]]; then
    LOG_FILE="$LOG_DIR/post-login-$RUN_TS.log"
    exec 3>&1 4>&2 5>>"$LOG_FILE"; exec >>"$LOG_FILE" 2>&1
    post_login_check; ui ""; ui "  Rapport : $(write_report "Tests en session graphique")"
    exit $((CHECK_FAIL > 0))
  fi

  exec 3>&1 4>&2 5>>"$LOG_FILE"
  exec >>"$LOG_FILE" 2>&1
  log "hypr-installer $INSTALLER_VERSION — mode $MODE — $(uname -a)"
  # Garde-fou de dérive actif dès le départ si la pile épinglée est déjà en place.
  if pinned_stack_installed; then PINS_RESTORED=1; fi
  draw_dashboard

  if [[ $MODE == diagnose ]]; then
    # Aucune installation ni modification du système : seulement des constats.
    run_step 1 diagnose_prereqs
    run_step 2 diagnose_hardware
    run_step 13 diagnose_steps generate_report
    exit $((CHECK_FAIL > 0))
  fi

  local active; active=$(state_get dotfiles.active)
  if [[ -n $active ]]; then
    ui "  ${C_YEL}Des dotfiles sont appliqués : $active${C_RST}"
    ui "  Continuer réinstalle la configuration end-4 (Hyprland, Quickshell…) par-dessus."
    ui "  Pour seulement annuler les dotfiles : ./install.sh --dotfiles-restore"
    ask_yes_no "Réinstaller la configuration end-4 ?" || { ui "  Rien n’a été modifié."; FAILURE_HANDLED=1; exit 0; }
    rm -f -- "$STATE_DIR/dotfiles.active"
    checkpoint_clear_from 6
  fi
  run_step 1 preflight resolve_versions confirm_plan cleanup_previous_runs
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
  run_step 12 install_apps_and_dev
  run_step 13 validate_installation generate_report

  ui ""
  if ((CHECK_FAIL)); then
    ui "  ${C_RED}${C_B}Installation terminée avec $CHECK_FAIL échec(s) de validation.${C_RST} Consultez le rapport ci-dessus."
    ui "  Correction automatique : ./install.sh --repair"
    FAILURE_HANDLED=1
    exit 1
  fi
  ui "  ${C_GRN}${C_B}Installation terminée.${C_RST} ${CHECK_WARN} avertissement(s)."
  ui "  Au redémarrage : écran de connexion -> session « Hyprland » (présélectionnée)."
  ui "  Aide des raccourcis : Super+F1. Les tests en session s’exécutent seuls au premier login."
  # Jamais de redémarrage automatique, même avec --yes.
  if ((!NO_REBOOT_PROMPT && !ASSUME_YES)) && ask_yes_no "Redémarrer maintenant ?"; then
    log "Redémarrage demandé"; sudo systemctl reboot
  fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi

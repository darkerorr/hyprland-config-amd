#!/usr/bin/env bash
# =============================================================================
# Simulation de bout en bout de install.sh (sans EndeavourOS réel).
#
# Toutes les commandes système (pacman, makepkg, git, curl, sudo, systemctl…)
# sont remplacées par des simulacres qui tiennent une base de paquets fictive.
# Les chemins système passent par HYPR_INSTALLER_SYSROOT (honoré uniquement si
# HYPR_INSTALLER_TEST=1). Rien n'est écrit hors d'un répertoire temporaire ; en
# root, le test se relance en utilisateur « nobody » pour le garantir.
#
# Ce test valide l'ORCHESTRATION : enchaînement des étapes, gestion des erreurs,
# reprise, invalidation, diagnostic, réparation. Il ne prouve PAS que les paquets
# réels se compilent ni qu'Hyprland démarre sur le matériel.
#
# Variables : E2E_END4_DIR=<clone end-4 au commit épinglé> (sinon arbre minimal
# synthétique) ; E2E_KEEP=1 pour conserver le répertoire de travail.
# =============================================================================
# shellcheck disable=SC1112,SC2016  # apostrophes typographiques voulues ; simulacres écrits entre apostrophes
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -eq 0 ]]; then
  command -v setpriv >/dev/null || { echo "SKIP: root sans setpriv"; exit 0; }
  W=$(mktemp -d); chmod 755 "$W"
  cp -a "$ROOT_DIR/install.sh" "$ROOT_DIR/tests" "$W/"
  if [[ -n ${E2E_END4_DIR:-} ]]; then cp -a "$E2E_END4_DIR" "$W/end4-fixture"; export E2E_END4_DIR="$W/end4-fixture"; fi
  chown -R 65534:65534 "$W"
  rc=0
  setpriv --reuid=65534 --regid=65534 --clear-groups env HOME="$W" USER=nobody \
    E2E_END4_DIR="${E2E_END4_DIR:-}" E2E_KEEP="${E2E_KEEP:-0}" bash "$W/tests/e2e-simulation.sh" "$@" || rc=$?
  [[ ${E2E_KEEP:-0} == 1 ]] || rm -rf -- "$W"
  exit "$rc"
fi

T=$(mktemp -d)
cleanup() { [[ ${E2E_KEEP:-0} == 1 ]] && echo "Répertoire conservé : $T" || rm -rf -- "$T"; }
trap cleanup EXIT
export USER=${USER:-$(id -un)}
MOCK="$T/mock"; SR="$T/sysroot"; BIN="$T/bin"; H="$T/home"
mkdir -p "$MOCK/db" "$SR" "$BIN" "$H"
cp "$ROOT_DIR/install.sh" "$T/install.sh"

PASS=0; FAILN=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAILN=$((FAILN + 1)); }
check() { local label=$1; shift; if "$@"; then pass "$label"; else fail "$label"; fi; return 0; }

# --- Valeurs épinglées lues dans install.sh (sans l'exécuter) ------------------
eval "$(sed -n '/^readonly END4_TAG=/p;/^readonly END4_COMMIT=/p;/^readonly END4_SHAPES_COMMIT=/p;/^readonly QS_COMMIT=/p' "$ROOT_DIR/install.sh")"
eval "$(sed -n '/^declare -Ar PIN_VER=(/,/^)/p' "$ROOT_DIR/install.sh" | sed 's/declare -Ar/declare -A/')"
export E2E_END4_TAG="$END4_TAG" E2E_END4_COMMIT="$END4_COMMIT" E2E_SHAPES_COMMIT="$END4_SHAPES_COMMIT"
for n in "${!PIN_VER[@]}"; do printf '%s\n' "${PIN_VER[$n]}" >"$MOCK/pinver.$n"; done

# --- Arborescence système simulée ----------------------------------------------
mk_sysroot() {
  rm -rf -- "$SR"; mkdir -p "$SR"
  mkdir -p "$SR/etc/systemd/system" "$SR/run/systemd/system" "$SR/var/lib/pacman" "$SR/usr/bin" \
    "$SR/usr/share/wayland-sessions" "$SR/usr/share/xdg-desktop-portal/portals" "$SR/usr/lib/systemd/system" \
    "$SR/usr/lib/systemd/user/sockets.target.wants" "$SR/usr/share/backgrounds/archlinux" "$SR/var/lib/sddm"
  printf 'NAME="EndeavourOS"\nPRETTY_NAME="EndeavourOS"\nID=endeavouros\nID_LIKE=arch\n' >"$SR/etc/os-release"
  printf '[options]\nHoldPkg = pacman glibc\nArchitecture = auto\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' >"$SR/etc/pacman.conf"
  : >"$SR/usr/share/wayland-sessions/hyprland.desktop"
  printf '#!/bin/sh\n' >"$SR/usr/bin/start-hyprland"; chmod +x "$SR/usr/bin/start-hyprland"
  : >"$SR/usr/share/xdg-desktop-portal/portals/hyprland.portal"
  : >"$SR/usr/lib/systemd/user/sockets.target.wants/pipewire.socket"
  printf '[Install]\nWantedBy=default.target\n' >"$SR/usr/lib/systemd/user/ydotool.service"
  : >"$SR/usr/lib/systemd/system/sddm.service"
  ln -s "$SR/usr/lib/systemd/system/sddm.service" "$SR/etc/systemd/system/display-manager.service"
  printf 'jpg' >"$SR/usr/share/backgrounds/archlinux/mountain.jpg"
}

# --- Fixture end-4 ------------------------------------------------------------
END4_FIX="$T/end4-fixture"
if [[ -n ${E2E_END4_DIR:-} && -d $E2E_END4_DIR/sdata/dist-arch ]]; then
  mkdir -p "$END4_FIX"; (cd "$E2E_END4_DIR" && tar --exclude=.git -cf - .) | (cd "$END4_FIX" && tar -xf -)
  FIXTURE_KIND="end-4 réel ($E2E_END4_DIR)"
else
  FIXTURE_KIND="arbre end-4 synthétique minimal"
  d="$END4_FIX/dots/.config"
  mkdir -p "$d/quickshell/ii/modules/common/widgets/shapes" "$d/hypr/hyprland/scripts" "$d/hypr/hyprlock" "$d/hypr/custom/scripts" \
    "$d/fish" "$d/fontconfig" "$d/kitty" "$d/xdg-desktop-portal" "$END4_FIX/dots/.local/share/konsole" "$END4_FIX/dots/.local/share/icons" "$END4_FIX/sdata/uv"
  echo 'ShellRoot {}' >"$d/quickshell/ii/shell.qml"
  printf 'source=hyprland/execs.conf\n' >"$d/hypr/hyprland.conf"
  printf 'exec-once = qs -c $qsConfig &\n' >"$d/hypr/hyprland/execs.conf"
  echo 'bind = Super, Q, killactive,' >"$d/hypr/hyprland/keybinds.conf"
  for f in hyprlock.conf monitors.conf workspaces.conf hypridle.conf; do echo "# $f" >"$d/hypr/$f"; done
  echo '# custom' >"$d/hypr/custom/general.conf"
  echo 'x' >"$d/kitty/kitty.conf"; echo 'x' >"$d/fish/config.fish"; echo 'x' >"$d/fontconfig/fonts.conf"
  echo '[preferred]' >"$d/xdg-desktop-portal/hyprland-portals.conf"
  echo 'x' >"$END4_FIX/dots/.local/share/konsole/a.profile"; echo '<svg/>' >"$END4_FIX/dots/.local/share/icons/illogical-impulse.svg"
  echo 'loguru==0.7.3' >"$END4_FIX/sdata/uv/requirements.txt"
  mkmeta() {
    local m=$1; shift
    mkdir -p "$END4_FIX/sdata/dist-arch/illogical-impulse-$m"
    { printf "pkgname=illogical-impulse-%s\npkgver=1.0\npkgrel=1\narch=(any)\ndepends=(" "$m"; printf ' %s' "$@"; printf ' )\n'; } \
      >"$END4_FIX/sdata/dist-arch/illogical-impulse-$m/PKGBUILD"
  }
  mkmeta audio cava pavucontrol-qt wireplumber
  mkmeta backlight brightnessctl ddcutil
  mkmeta basic jq rsync go-yq
  mkmeta bibata-modern-classic-bin
  mkmeta fonts-themes adw-gtk-theme-git breeze-plus darkly-bin matugen otf-space-grotesk ttf-material-symbols-variable-git ttf-readex-pro ttf-rubik-vf ttf-twemoji
  mkmeta hyprland hyprland hyprsunset wl-clipboard
  mkmeta kde dolphin systemsettings
  mkmeta microtex-git tinyxml2
  mkmeta portal xdg-desktop-portal xdg-desktop-portal-hyprland
  mkmeta python uv gtk4
  mkmeta screencapture hyprshot slurp
  mkmeta toolkit ydotool
  mkmeta widgets fuzzel hypridle hyprlock hyprpicker songrec wlogout
  mkdir -p "$END4_FIX/sdata/dist-arch/illogical-impulse-quickshell-git"
  cat >"$END4_FIX/sdata/dist-arch/illogical-impulse-quickshell-git/PKGBUILD" <<EOF
_commit='$QS_COMMIT'
pkgname=illogical-impulse-quickshell-git
pkgver=0.1.0.r1
pkgrel=8
arch=(x86_64)
url='https://git.outfoxxed.me/quickshell/quickshell'
depends=(qt6-base qt6-declarative qt6-avif-image-plugin)
makedepends=(cmake ninja 'cli11>=2.0')
provides=(quickshell)
conflicts=(quickshell)
EOF
fi

# --- Simulacres ----------------------------------------------------------------
mock() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$BIN/$1"; chmod +x "$BIN/$1"; }
LOGCALL='printf "%s %s @%s\n" "${0##*/}" "$*" "${PWD##*/}" >>"$MOCK/calls.log"'

mock pacman "$LOGCALL"'
db=$MOCK/db
inst() { printf "%s\n" "${2:-1.0-1}" >"$db/$1"; }
args=(); for a in "$@"; do case $a in --print-format) skipnext=1; continue;; esac; if [[ ${skipnext:-0} == 1 ]]; then skipnext=0; continue; fi; [[ $a == -* ]] || args+=("$a"); done
case $1 in
  -Qq) if (( ${#args[@]} == 0 )); then ls "$db" | grep -v "^provides-" || true; else [[ -f $db/${args[0]} ]]; fi ;;
  -Q) [[ -f $db/${args[0]} ]] && printf "%s %s\n" "${args[0]}" "$(<"$db/${args[0]}")" ;;
  -Qi) [[ -f $db/${args[0]} ]] || exit 1; printf "Name            : %s\nDepends On      : None\nRequired By     : None\n" "${args[0]}" ;;
  -Qlq) exit 0 ;;
  -T) rc=0; for d in "${args[@]}"; do n=${d%%[<>=]*}; [[ -f $db/$n || -f $db/provides-$n ]] || { echo "$d"; rc=127; }; done; exit $rc ;;
  -Si) grep -qx "${args[0]}" "$MOCK/norepo" 2>/dev/null && exit 1; printf "Version         : 99.0-1\n" ;;
  -Sp) for p in "${args[@]}"; do grep -qx "$p" "$MOCK/norepo" 2>/dev/null && { echo "error: target not found: $p"; exit 1; }; echo "$p"; done ;;
  -Syu)
    cp "$HYPR_INSTALLER_SYSROOT/etc/pacman.conf" "$MOCK/pacman.conf.at-syu"
    if [[ -s $MOCK/syu-block ]]; then b=$(<"$MOCK/syu-block")
      if [[ -f $db/$b ]]; then
        echo "error: failed to prepare transaction (could not satisfy dependencies)"
        echo ":: installing libjxl (0.13.1-1) breaks dependency '"'"'libjxl.so=0.11-64'"'"' required by $b"; exit 1
      fi
    fi; echo ":: Starting full system upgrade..." ;;
  -S|-Sy)
    for p in "${args[@]}"; do grep -qx "$p" "$MOCK/norepo" 2>/dev/null && { echo "error: target not found: $p"; exit 1; }; done
    for p in "${args[@]}"; do inst "${p%%[<>=]*}"; done ;;
  -U)
    for f in "${args[@]}"; do
      [[ -f $f ]] || { echo "error: $f: could not find or read package"; exit 1; }
      b=${f##*/}; stem=${b%%.pkg.tar*}; r=${stem%-*}; rel=${r##*-}; r=${r%-*}; ver=${r##*-}; name=${r%-*}
      inst "$name" "$ver-$rel"
      if [[ -f $f.provides ]]; then while read -r p; do if [[ -n $p ]]; then : >"$db/provides-$p"; fi; done <"$f.provides"; fi
    done; exit 0 ;;
  -R*) for p in "${args[@]}"; do rm -f "$db/$p"; done ;;
  *) exit 0 ;;
esac'

mock makepkg "$LOGCALL"'
set -e
src() { ( source ./PKGBUILD >/dev/null 2>&1; "$@" ); }
pl() { source ./PKGBUILD >/dev/null 2>&1; local a=x86_64; [[ " ${arch[*]} " == *" any "* ]] && a=any
       for n in "${pkgname[@]}"; do echo "$PWD/$n-$pkgver-$pkgrel-$a.pkg.tar.zst"; done; }
case " $* " in
  *" --printsrcinfo "*) ( source ./PKGBUILD >/dev/null 2>&1; echo "pkgbase = ${pkgbase:-$pkgname}"
      for d in "${depends[@]}"; do printf "\tdepends = %s\n" "$d"; done
      for d in "${makedepends[@]}"; do printf "\tmakedepends = %s\n" "$d"; done ); exit 0 ;;
  *" --packagelist "*) ( pl ); exit 0 ;;
esac
base=$(basename "$PWD")
if [[ -f $MOCK/interrupt-$base ]]; then rm -f "$MOCK/interrupt-$base"; kill -TERM "$(<"$MOCK/main.pid")"; sleep 2; fi
if [[ -s $MOCK/fail-makepkg-$base ]]; then
  echo "==> Making package: $base"; echo "==> Installing missing dependencies..."
  echo "error: target not found: $(<"$MOCK/fail-makepkg-$base")"
  echo "==> ERROR: '"'"'pacman'"'"' failed to install missing dependencies."
  exit 8
fi
deps=$( source ./PKGBUILD >/dev/null 2>&1; printf "%s\n" "${depends[@]}" "${makedepends[@]}" )
miss=$(pacman -T $deps || true)
if [[ " $* " =~ \ -[A-Za-z]*s ]]; then
  # makepkg -s : appellerait sudo en arrière-plan (comportement interdit, signalé).
  echo "MAKEPKG_SYNCDEPS $base" >>"$MOCK/forbidden.log"
  if [[ -n $miss ]]; then pacman -S --asdeps --noconfirm $miss || { echo "==> ERROR: '"'"'pacman'"'"' failed to install missing dependencies."; exit 8; }; fi
elif [[ -n $miss && " $* " != *" -d "* ]]; then
  echo "==> Missing dependencies:"; for m in $miss; do echo "  -> $m"; done
  echo "==> ERROR: Could not resolve all dependencies."; exit 15
fi
while read -r f; do
  echo "pkg" >"$f"
  ( source ./PKGBUILD >/dev/null 2>&1; printf "%s\n" "${provides[@]}" ) >"$f.provides"
  ( source ./PKGBUILD >/dev/null 2>&1; printf "%s\n" "${conflicts[@]}" ) >"$f.conflicts"
done < <(pl)
echo "==> Finished making"'

mock makechrootpkg "$LOGCALL"'
source ./PKGBUILD >/dev/null 2>&1
echo pkg >"$PWD/$pkgname-$pkgver-$pkgrel-x86_64.pkg.tar.zst"'
mock mkarchroot "$LOGCALL"'; mkdir -p "$1"'
mock arch-nspawn "$LOGCALL"

mock bsdtar "$LOGCALL"'
f=""; for a in "$@"; do [[ $a == *.pkg.tar* ]] && f=$a; done
b=${f##*/}; stem=${b%%.pkg.tar*}; r=${stem%-*}; r=${r%-*}; r=${r%-*}
echo "pkgname = $r"; echo "pkgver = x"
[[ -f $f.conflicts ]] && while read -r c; do [[ -n $c && $c != "$r" ]] && echo "conflict = $c"; done <"$f.conflicts"
exit 0'

mock git "$LOGCALL"'
if [[ $1 == ls-remote ]]; then printf "%s\trefs/tags/%s^{}\n" "$E2E_END4_COMMIT" "$E2E_END4_TAG"; exit 0; fi
if [[ $1 == clone ]]; then
  shift; branch=""; pos=()
  while (($#)); do case $1 in --branch) branch=$2; shift 2;; -*) shift;; *) pos+=("$1"); shift;; esac; done
  url=${pos[0]}; dir=${pos[1]}
  if [[ $url == https://aur.archlinux.org/* && -f $MOCK/aur-down ]]; then echo "fatal: unable to access '"'"'$url'"'"': Could not resolve host"; exit 128; fi
  mkdir -p "$dir/.git"
  case $url in
    *dots-hyprland*) cp -a "$END4_FIX/." "$dir/" ;;
    *aur.archlinux.org/*|*archlinux/aur.git)
      base=${branch:-$(basename "$url" .git)}
      case $base in
        material-symbols-git) names="ttf-material-symbols-variable-git" ;;
        qt5-avif-image-plugin) names="qt5-avif-image-plugin qt6-avif-image-plugin" ;;
        *) names=$base ;;
      esac
      deps=""; [[ $base == wlogout ]] && deps="gtk3 gtk-layer-shell"
      mk=""; [[ $base == wlogout ]] && mk="meson scdoc"; [[ $base == adw-gtk-theme-git ]] && mk="dart-sass meson"
      printf "pkgbase=%s\npkgname=(%s)\npkgver=1.0\npkgrel=1\narch=(any)\ndepends=(%s)\nmakedepends=(%s)\n" "$base" "$names" "$deps" "$mk" >"$dir/PKGBUILD" ;;
    *gitlab.archlinux.org*)
      n=$(basename "$url" .git); v=$(<"$MOCK/pinver.$n")
      printf "pkgname=%s\npkgver=%s\npkgrel=%s\narch=(x86_64)\n" "$n" "${v%-*}" "${v##*-}" >"$dir/PKGBUILD" ;;
    *google-sans-flex*) echo font >"$dir/GoogleSansFlex.ttf" ;;
  esac
  # Contenu suivi par « git » : restauré par checkout --force / clean -fdx.
  mkdir -p "$dir/.git/orig"; (cd "$dir" && tar --exclude=./.git -cf "$dir/.git/orig.tar" .)
  exit 0
fi
dir=.; if [[ $1 == -C ]]; then dir=$2; shift 2; fi
case $1 in
  rev-parse)
    case $2 in
      --git-dir) [[ -d $dir/.git ]] ;;
      HEAD) if [[ $dir == */shapes ]]; then echo "$E2E_SHAPES_COMMIT"; else cat "$dir/.git/MOCK_HEAD"; fi ;;
      *) echo "$E2E_END4_COMMIT" ;;
    esac ;;
  checkout) for a in "$@"; do c=$a; done; echo "$c" >"$dir/.git/MOCK_HEAD"
    find "$dir" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    (cd "$dir" && tar -xf .git/orig.tar) ;;
  *) exit 0 ;;
esac'

mock curl "$LOGCALL"'
out=""; url=""; head=0; w=""; v4=0
while (($#)); do case $1 in -o) out=$2; shift 2;; -I) head=1; shift;; -w) w=$2; shift 2;; -4) v4=1; shift;;
  --max-time|--retry|--retry-delay|--connect-timeout|-A|-r) shift 2;; -*) shift;; *) url=$1; shift;; esac; done
host=${url#https://}; host=${host%%/*}
if grep -qx "$host" "$MOCK/net-down" 2>/dev/null || { [[ -f $MOCK/ipv6-broken && $v4 == 0 ]]; }; then
  [[ -n $w ]] && printf 000; echo "curl: (6) Could not resolve host: $host" >&2; exit 6; fi
code=200
# Racine de l’Archive Arch : répond 403 en HEAD (cas réel signalé) — le réseau marche pourtant.
[[ $url == https://archive.archlinux.org && $head == 1 ]] && code=403
[[ $url == https://archive.archlinux.org && -f $MOCK/archive-root-403 ]] && code=403
[[ -n $out && $out != /dev/null ]] && echo data >"$out"
[[ -n $w ]] && printf "%s" "$code"
exit 0'

mock sha256sum 'for a in "$@"; do [[ $a == -c ]] && exit 0; done; exec /usr/bin/sha256sum "$@"'
mock sudo "$LOGCALL"'
case $1 in -n) [[ ${2:-} == true || ${2:-} == -v ]] && exit 0;; -v) exit 0;; esac
exec "$@"'
mock vercmp '[[ $1 == "$2" ]] && { echo 0; exit; }; [[ $(printf "%s\n%s\n" "$1" "$2" | sort -V | head -n1) == "$1" ]] && echo -1 || echo 1'
mock Hyprland '
case " $* " in
  *" --version "*) v=$(cat "$MOCK/db/hyprland" 2>/dev/null || echo 0.57.2-1); echo "Hyprland ${v%-*} built from branch"; ;;
  *" --verify-config "*) echo "config ok" ;;
esac'
mock quickshell 'exit 0'; mock qs 'exit 0'
mock lspci 'printf "%s\n" "06:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Lexa PRO [Radeon 540/540X/550/550X / RX 540X/550/550X] [1002:699f] (rev c7)" "	Kernel driver in use: amdgpu"'
mock localectl "$LOGCALL"'
st=$MOCK/locale; [[ -f $st ]] || printf "us\nus\n" >"$st"
case $1 in
  status) printf "   System Locale: LANG=fr_FR.UTF-8\n       VC Keymap: %s\n      X11 Layout: %s\n" "$(sed -n 1p "$st")" "$(sed -n 2p "$st")" ;;
  set-keymap) for a; do k=$a; done; printf "%s\n%s\n" "$k" "$(sed -n 2p "$st")" >"$st" ;;
  set-x11-keymap) shift; while [[ $1 == --* ]]; do shift; done; printf "%s\n%s\n" "$(sed -n 1p "$st")" "$1" >"$st" ;;
esac'
mock systemctl "$LOGCALL"'
case " $* " in *" --user is-enabled hypridle"*) exit 1;; esac; exit 0'
mock uv "$LOGCALL"'
if [[ $1 == venv ]]; then for a; do d=$a; done
  for a in "$@"; do [[ $a == */.venv ]] && d=$a; done
  mkdir -p "$d/bin"; printf "#!/bin/sh\ncase \"\$*\" in *version_info*) exit 0;; *) echo ok;; esac\n" >"$d/bin/python"; chmod +x "$d/bin/python"; fi
exit 0'
mock dbus-run-session 'shift; exec "$@"'
mock fc-list 'printf "%s\n" "Google Sans Flex" "Material Symbols Rounded" "JetBrainsMono Nerd Font" "Readex Pro" "Space Grotesk" "Rubik" "Twemoji" "Noto Sans" "Noto Sans CJK JP" "Font Awesome 6 Free"'
mock fc-match 'echo "Space Grotesk"'
mock xdg-user-dir 'echo "$HOME/Pictures"'
mock rsync '
del=0; ex=(); pos=()
while (($#)); do case $1 in --delete) del=1; shift;; --exclude) ex+=("$2"); shift 2;; --) shift;; -*) shift;; *) pos+=("$1"); shift;; esac; done
s=${pos[0]}; d=${pos[1]}
# Comme le vrai rsync : seul le dernier niveau du dossier cible est créé.
if [[ ! -d ${d%/} && ! -d $(dirname "${d%/}") ]]; then
  echo "rsync: [Receiver] mkdir \"${d%/}\" failed: No such file or directory (2)" >&2
  echo "rsync error: error in file IO (code 11)" >&2; exit 11; fi
((del)) && rm -rf "$d"; mkdir -p "$d"; cp -a "$s/." "$d/"
for e in "${ex[@]}"; do rm -rf "$d/$e"; done'
mock df 'printf "Avail\n 200G\n"'
mock pgrep 'exit 1'
mock locale 'echo LANG=fr_FR.UTF-8'
mock vulkaninfo 'echo "deviceName = AMD Radeon RX 550 Series (RADV POLARIS12)"'
mock vainfo 'echo "vainfo: Driver version: Mesa Gallium driver"'
mock nmcli 'echo full'
for c in pacman-key gpg fc-cache xdg-user-dirs-update kwriteconfig6 groupadd usermod gsettings notify-send ldd \
         matugen cliphist wl-paste grim slurp hyprpicker fuzzel ydotool cava kdialog tesseract wf-recorder swappy hyprshot \
         trans songrec qalc ddcutil brightnessctl playerctl wpctl kitty dolphin firefox; do
  mock "$c" "$LOGCALL"'; exit 0'
done
mock getent 'exit 2'
# Commandes interdites (dual boot) : tout appel est consigné et fait échouer le test.
for c in parted fdisk cfdisk sfdisk mkfs mkfs.ext4 mkfs.fat mkfs.btrfs wipefs sgdisk gdisk grub-install grub-mkconfig \
         efibootmgr bootctl os-prober mount umount mkinitcpio dracut; do
  mock "$c" 'printf "FORBIDDEN %s %s\n" "${0##*/}" "$*" >>"$MOCK/forbidden.log"; exit 1'
done

# Paquets présents sur une EndeavourOS fraîche (simplifié).
fresh_db() {
  rm -rf -- "$MOCK/db"; mkdir -p "$MOCK/db"
  for p in base linux pacman sudo git curl networkmanager firefox endeavouros-keyring archlinux-keyring sddm; do echo 1.0-1 >"$MOCK/db/$p"; done
  rm -f "$MOCK"/{archive-root-403,ipv6-broken,locale,syu-block,aur-down,net-down,norepo,calls.log,forbidden.log,pacman.conf.at-syu} "$MOCK"/fail-makepkg-* "$MOCK"/interrupt-*
}
reset_all() { fresh_db; mk_sysroot; rm -rf -- "$H"; mkdir -p "$H"; }

RUN_N=0
run_installer() {   # run_installer <options…> ; RC et OUT définis
  RUN_N=$((RUN_N + 1)); OUT="$T/out-$RUN_N.txt"; RC=0
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$H" USER="$USER" LANG=C.UTF-8 TMPDIR="$T" \
    HYPR_INSTALLER_TEST=1 HYPR_INSTALLER_SYSROOT="$SR" MOCK="$MOCK" END4_FIX="$END4_FIX" \
    E2E_END4_COMMIT="$E2E_END4_COMMIT" E2E_END4_TAG="$E2E_END4_TAG" E2E_SHAPES_COMMIT="$E2E_SHAPES_COMMIT" \
    bash -c 'echo $$ >"$MOCK/main.pid"; exec bash "$0" "$@"' "$T/install.sh" "$@" >"$OUT" 2>&1 </dev/null || RC=$?
}
STATE="$H/.local/share/hypr-installer/state"
calls() { grep -c -E "$1" "$MOCK/calls.log" 2>/dev/null || true; }
inst_ver() { cat "$MOCK/db/$1" 2>/dev/null || true; }
show_out() { printf -- '----- sortie (%s) -----\n' "$OUT"; tail -n 40 "$OUT"; printf -- '---------------\n'; }

echo "Fixture : $FIXTURE_KIND"

# =============================================================================
# S1. Installation complète depuis une EndeavourOS fraîche
# =============================================================================
reset_all
run_installer --yes
check "S1 installation complète : code 0" test "$RC" -eq 0
((RC == 0)) || show_out
check "S1 hyprland 0.54.3-4 installé" test "$(inst_ver hyprland)" = "${PIN_VER[hyprland]}"
check "S1 hyprgraphics recompilé (.1)" test "$(inst_ver hyprgraphics)" = "${PIN_VER[hyprgraphics]}.1"
check "S1 paquet local Space Grotesk installé et fournit otf-space-grotesk" test -f "$MOCK/db/provides-otf-space-grotesk"
check "S1 méta fonts-themes installé (dépendance otf-space-grotesk satisfaite)" test -f "$MOCK/db/illogical-impulse-fonts-themes"
check "S1 IgnorePkg écrit dans pacman.conf" grep -q '^IgnorePkg = hyprutils' "$SR/etc/pacman.conf"
check "S1 IgnorePkg ajouté APRÈS pacman -Syu (pile non encore installée)" \
  bash -c "[[ -f '$MOCK/pacman.conf.at-syu' ]] && ! grep -q 'IgnorePkg' '$MOCK/pacman.conf.at-syu'"
check "S1 points de reprise 3 à 11 écrits" bash -c "for i in 3 4 5 6 7 8 9 10 11; do [[ -f '$STATE'/step-\$i.done ]] || exit 1; done"
check "S1 aucun échec enregistré" bash -c "! ls '$STATE'/step-*.failed 2>/dev/null | grep -q ."
check "S1 rapport généré" test -f "$H/.local/share/hypr-installer/reports/latest-install.txt"
check "S1 validation sans échec" grep -q 'Installation terminée\.' "$OUT"
check "S1 aucune commande disque/chargeur de démarrage, jamais makepkg -s" test ! -s "$MOCK/forbidden.log"
check "S1 jamais de redémarrage automatique avec --yes" bash -c "! grep -q 'systemctl reboot' '$MOCK/calls.log'"

# =============================================================================
# S2. Relance après succès : tout est repris, rien n'est recompilé
# =============================================================================
: >"$MOCK/calls.log"
run_installer --yes
check "S2 relance : code 0" test "$RC" -eq 0
check "S2 étapes 3-11 reprises (aucun makepkg, aucun pacman -S/-U)" test "$(calls '^makepkg |^makechrootpkg |^pacman -(S|U|Syu) ')" -eq 0
check "S2 tableau : 12/12" grep -q 'Étapes terminées : 12/12' "$OUT"

# =============================================================================
# S3. Échec makepkg code 8 à l'étape 3 (cas signalé), puis reprise
# =============================================================================
reset_all
echo "scdoc" >"$MOCK/fail-makepkg-wlogout"
run_installer --yes
check "S3 échec makepkg : code de sortie 1 (arrêt contrôlé)" test "$RC" -eq 1
((RC == 1)) || show_out
check "S3 étape 3 marquée en échec" grep -q 'ÉCHEC à l’étape 03' "$OUT"
check "S3 cause précise affichée (scdoc introuvable)" grep -q 'Paquet introuvable dans les dépôts : scdoc' "$OUT"
check "S3 signification du code 8 affichée" grep -q 'Code makepkg 8' "$OUT"
check "S3 échec persistant (code + cause)" grep -q 'cause=.*scdoc' "$STATE/step-3.failed"
check "S3 aucun point de reprise pour 3+" bash -c "! ls '$STATE'/step-{3,4,5,6,7,8,9,10,11}.done 2>/dev/null | grep -q ."
check "S3 rapport d'échec écrit" grep -q 'Dernier échec enregistré, étape 03' "$H/.local/share/hypr-installer/reports/latest-install.txt"
run_installer --diagnose
check "S3 --diagnose : étape 3 signalée en ÉCHEC avec la cause" grep -q 'Étape 03 .*ÉCHEC .*scdoc' "$OUT"
check "S3 --diagnose : étapes 4-11 « non exécutée », pas en échec" bash -c "grep -q 'INFO.*Étape 05 .*non exécutée' '$OUT' && ! grep -q 'FAIL.*Étape 05' '$OUT'"
check "S3 --diagnose n'a rien installé" test "$(inst_ver hyprland)" = ""
rm -f "$MOCK/fail-makepkg-wlogout"
pkgs_before=$(ls "$MOCK/db" | wc -l)
: >"$MOCK/calls.log"
run_installer --yes
check "S3 reprise après correction : code 0" test "$RC" -eq 0
((RC == 0)) || show_out
check "S3 reprise : AUR déjà compilés non recompilés" test "$(calls '^makepkg --noconfirm -f -c --log')" -eq 1
check "S3 reprise : enregistrement d'échec effacé" test ! -f "$STATE/step-3.failed"
check "S3 paquets présents avant la reprise conservés" test "$(ls "$MOCK/db" | wc -l)" -ge "$pkgs_before"

# =============================================================================
# S4. Dérive de l'état réel : un paquet retiré => étape réexécutée + suivantes
# =============================================================================
rm -f "$MOCK/db/kitty"
: >"$MOCK/calls.log"
run_installer --yes
check "S4 dérive : code 0" test "$RC" -eq 0
check "S4 kitty réinstallé" test -f "$MOCK/db/kitty"
check "S4 étape 3 réexécutée (point de reprise non aveugle)" grep -q 'Étape 3 réexécutée : état réel incomplet' "$H/.local/share/hypr-installer/reports/latest-install.txt"

# =============================================================================
# S5. Interruption (SIGTERM) pendant une compilation AUR, puis reprise
# =============================================================================
reset_all
: >"$MOCK/interrupt-breeze-plus"
run_installer --yes
check "S5 interruption : code 130" test "$RC" -eq 130
((RC == 130)) || show_out
check "S5 interruption enregistrée" grep -q '^interrompu=1' "$STATE/step-3.failed"
run_installer --diagnose
check "S5 --diagnose : étape 3 « interrompue »" grep -q 'Étape 03 .*interrompue' "$OUT"
run_installer --yes
check "S5 reprise après interruption : code 0" test "$RC" -eq 0
((RC == 0)) || show_out

# =============================================================================
# S6. --diagnose : système frais, réseau coupé, installation terminée
# =============================================================================
reset_all
run_installer --diagnose
check "S6 diagnostic système frais : pas d'échec, code 0" test "$RC" -eq 0
check "S6 diagnostic : étapes « NON EXÉCUTÉE »" grep -q 'NON EXÉCUTÉE' "$OUT"
check "S6 diagnostic : paquets absents listés" grep -q 'Paquets absents' "$OUT"
printf '%s\n' github.com archive.archlinux.org >"$MOCK/net-down"
run_installer --diagnose
check "S6 diagnostic hors réseau : pas d'arrêt brutal, prérequis en échec" bash -c "[[ $RC -eq 1 ]] && grep -q 'Réseau : github.com .*ne répond pas' '$OUT' && grep -q 'Rapport' '$OUT'"
rm -f "$MOCK/net-down"
run_installer --yes
run_installer --diagnose
check "S6 diagnostic après installation : tout conforme" bash -c "[[ $RC -eq 0 ]] && grep -q 'Toutes les étapes sont terminées' '$OUT'"

# =============================================================================
# S7. -Syu bloqué par la pile épinglée (bibliothèque mise à jour), mode --repair
# =============================================================================
echo hyprgraphics >"$MOCK/syu-block"
: >"$MOCK/calls.log"
run_installer --repair --yes
check "S7 réparation avec blocage -Syu : code 0" test "$RC" -eq 0
((RC == 0)) || show_out
check "S7 paquet bloquant retiré puis -Syu relancé" test "$(calls '^pacman -Syu')" -ge 2
check "S7 hyprgraphics recompilé en chroot" test "$(calls '^makechrootpkg')" -ge 1
check "S7 hyprgraphics réinstallé à la bonne version" test "$(inst_ver hyprgraphics)" = "${PIN_VER[hyprgraphics]}.1"
check "S7 état pins.force-src nettoyé" test ! -f "$STATE/pins.force-src"
check "S7 pile déjà installée : IgnorePkg actif PENDANT -Syu" grep -q '^IgnorePkg' "$MOCK/pacman.conf.at-syu"
check "S7 réparation : AUR intacts non recompilés" test "$(calls '^makepkg --noconfirm -f -c --log')" -eq 0
rm -f "$MOCK/syu-block"

# =============================================================================
# S8. AUR injoignable : miroir GitHub officiel utilisé
# =============================================================================
reset_all
: >"$MOCK/aur-down"; echo aur.archlinux.org >"$MOCK/net-down"
run_installer --yes
check "S8 AUR indisponible : installation terminée via le miroir" test "$RC" -eq 0
check "S8 clonage via github.com/archlinux/aur" grep -q 'git clone .*--branch wlogout https://github.com/archlinux/aur.git' "$MOCK/calls.log"

# =============================================================================
# S10. Racine de l'Archive en 403 et IPv6 cassé : le réseau doit être reconnu
# =============================================================================
reset_all
: >"$MOCK/archive-root-403"; : >"$MOCK/ipv6-broken"
run_installer --yes
check "S10 archive 403 + IPv6 cassé : installation terminée" test "$RC" -eq 0
((RC == 0)) || show_out
check "S10 IPv4 forcé pour les téléchargements" grep -q '^curl .*-4' "$MOCK/calls.log"

# =============================================================================
# S11. Restes d'une ancienne version : nettoyés avant la reprise
# =============================================================================
reset_all
C="$H/.cache/hypr-installer"; mkdir -p "$STATE" "$C/build/aur/38c3-styles/.git" "$C/build/meta/illogical-impulse-fonts-themes" "$C/pkgs/built" "$C/pkgs/ala" "$H/.local/share/fonts/space-grotesk" "$T/hypr-installer.OLD123"
echo ancienne-cle >"$STATE/step-6.done"; printf 'version=1.2.9\ncode=8\n' >"$STATE/step-3.failed"
echo x >"$C/pkgs/built/hyprgraphics-0.4.0-1.1-x86_64.pkg.tar.zst"; echo x >"$C/pkgs/ala/hyprland-0.54.3-4-x86_64.pkg.tar.zst.part"
echo x >"$H/.local/share/fonts/space-grotesk/OFL.txt"; echo x >"$H/.local/share/fonts/space-grotesk/SpaceGrotesk.otf"
echo 1.0-1 >"$MOCK/db/html2markdown"; echo 1.0-1 >"$MOCK/db/38c3-styles"
run_installer --yes
check "S11 installation après restes d'une ancienne version : code 0" test "$RC" -eq 0
((RC == 0)) || show_out
check "S11 ancien dépôt AUR 38c3-styles supprimé" test ! -e "$C/build/aur/38c3-styles"
check "S11 paquet recompilé obsolète supprimé" test ! -e "$C/pkgs/built/hyprgraphics-0.4.0-1.1-x86_64.pkg.tar.zst"
check "S11 téléchargement partiel supprimé" test ! -e "$C/pkgs/ala/hyprland-0.54.3-4-x86_64.pkg.tar.zst.part"
check "S11 dossier temporaire orphelin supprimé" test ! -e "$T/hypr-installer.OLD123"
check "S11 ancienne police utilisateur supprimée" test ! -e "$H/.local/share/fonts/space-grotesk"
check "S11 paquets obsolètes retirés" bash -c "[[ ! -f '$MOCK/db/html2markdown' && ! -f '$MOCK/db/38c3-styles' ]]"
check "S11 nettoyage annoncé" grep -q 'Restes des exécutions précédentes nettoyés' "$OUT"

# =============================================================================
# S9. Dépendance AUR absente des dépôts : arrêt AVANT makepkg, cause explicite
# =============================================================================
reset_all
echo scdoc >"$MOCK/norepo"
run_installer --yes
check "S9 dépendance absente : arrêt contrôlé" test "$RC" -eq 1
check "S9 dépendance nommée dans le message" grep -q 'scdoc' "$OUT"
check "S9 makepkg non lancé pour wlogout" bash -c "! grep -q '^makepkg --noconfirm.*@wlogout$' '$MOCK/calls.log'"

echo
echo "Résultat : $PASS réussis, $FAILN échoués"
((FAILN == 0))

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
  printf 'require("hyprland.lib")\nrequire("hyprland.execs")\nrequire("hyprland.keybinds")\n' >"$d/hypr/hyprland.lua"
  printf 'hl.on("hyprland.start", function ()\n    hl.exec_cmd("qs -c $qsConfig")\nend)\n' >"$d/hypr/hyprland/execs.lua"
  printf 'for i = 1, 10 do\n    local numberkey = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }\n    hl.bind("SUPER + code:" .. numberkey[i], function() end)\nend\n' >"$d/hypr/hyprland/keybinds.lua"
  for f in hyprlock.conf hypridle.conf; do echo "# $f" >"$d/hypr/$f"; done
  for f in env execs general keybinds rules variables; do echo "-- custom $f" >"$d/hypr/custom/$f.lua"; done
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
inst() { printf "%s\n" "${2:-50.0-1}" >"$db/$1"; }
args=(); for a in "$@"; do case $a in --print-format) skipnext=1; continue;; esac; if [[ ${skipnext:-0} == 1 ]]; then skipnext=0; continue; fi; [[ $a == -* ]] || args+=("$a"); done
case $1 in
  -Qq) if (( ${#args[@]} == 0 )); then ls "$db" | grep -v "^provides-" || true; else [[ -f $db/${args[0]} ]]; fi ;;
  -Q) [[ -f $db/${args[0]} ]] && printf "%s %s\n" "${args[0]}" "$(<"$db/${args[0]}")" ;;
  -Qi) [[ -f $db/${args[0]} ]] || exit 1; printf "Name            : %s\nDepends On      : None\nRequired By     : None\n" "${args[0]}" ;;
  -Qlq) exit 0 ;;
  -T) rc=0; for d in "${args[@]}"; do n=${d%%[<>=]*}; [[ -f $db/$n || -f $db/provides-$n ]] || { echo "$d"; rc=127; }; done; exit $rc ;;
  -Si) grep -qx "${args[0]}" "$MOCK/norepo" 2>/dev/null && exit 1; printf "Version         : 50.0-1\n" ;;
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
qc=$(grep -m1 "^_commit=" PKGBUILD 2>/dev/null | cut -d= -f2 | tr -d "\047\042" || true)
if [[ -n $qc ]] && grep -qx "$qc" "$MOCK/fail-qs-commits" 2>/dev/null; then
  echo "src/wayland/hyprland/ipc/../../../core/model.hpp:169:25: error: Qt 6.12"; echo "==> ERROR: A failure occurred in build()."; exit 4
fi
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
if [[ -f $MOCK/fail-chroot-$pkgname ]]; then echo "CMake step for glaze failed: 1"; echo "==> ERROR: A failure occurred in build()."; exit 4; fi
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
    *anthropics/skills*)
      for k in pdf docx skill-creator; do mkdir -p "$dir/skills/$k"; printf -- "---\nname: %s\n---\n" "$k" >"$dir/skills/$k/SKILL.md"; done
      mkdir -p "$dir/template"; echo x >"$dir/template/SKILL.md" ;;
    *)
      if [[ -d $url ]]; then (cd "$url" && tar --exclude=./.git -cf - .) | (cd "$dir" && tar -xf -); fi ;;
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
      HEAD) if [[ $dir == */shapes ]]; then echo "$E2E_SHAPES_COMMIT"; else cat "$dir/.git/MOCK_HEAD" 2>/dev/null || echo 0123456789abcdef0123456789abcdef01234567; fi ;;
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
# Installateur officiel de Claude Code : script envoyé sur la sortie standard.
[[ $url == https://claude.ai/install.sh && -z $out ]] && cat "$MOCK/claude-install.sh"
[[ -n $w ]] && printf "%s" "$code"
exit 0'

mock sha256sum 'for a in "$@"; do [[ $a == -c ]] && exit 0; done; exec /usr/bin/sha256sum "$@"'
mock sudo "$LOGCALL"'
case $1 in -n) [[ ${2:-} == true || ${2:-} == -v ]] && exit 0;; -v) exit 0;; esac
exec "$@"'
mock vercmp '[[ $1 == "$2" ]] && { echo 0; exit; }; [[ $(printf "%s\n%s\n" "$1" "$2" | sort -V | head -n1) == "$1" ]] && echo -1 || echo 1'
mock Hyprland '
case " $* " in
  *" --version "*) [[ -f $MOCK/db/hyprland ]] || exit 1; v=$(cat "$MOCK/db/hyprland"); echo "Hyprland ${v%-*} built from branch"; ;;
  *" --verify-config "*) if [[ -f $MOCK/verify-fail ]]; then echo "error: hyprland.lua:3: attempt to call a nil value"; else echo "config ok"; fi ;;
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
case " $* " in *" --user is-enabled hypridle"*|*" is-enabled --quiet lactd.service "*) exit 1;; esac; exit 0'
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
cat >"$MOCK/claude-install.sh" <<'EOS'
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\necho "2.1.0 (Claude Code)"\n' >"$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"
EOS
mock npm "$LOGCALL"'
pf=$MOCK/npm-prefix
case "$1 $2" in
  "config get") cat "$pf" 2>/dev/null || echo /usr ;;
  "config set") echo "$4" >"$pf" ;;
  "ls -g") for a; do p=$a; done; [[ -f $MOCK/npm-$p ]] ;;
  "install -g")
    [[ -f $MOCK/npm-fail ]] && { echo "npm error code E404"; exit 1; }
    for a; do p=$a; done; [[ $(cat "$pf" 2>/dev/null) == /usr ]] && { echo "npm error EACCES"; exit 243; }
    : >"$MOCK/npm-$p"; d=$(cat "$pf")/bin; mkdir -p "$d"; printf "#!/bin/sh\nexit 0\n" >"$d/$p"; chmod +x "$d/$p" ;;
esac'
mock hyprctl "$LOGCALL"'
case "$1 $2" in
  "monitors all") cat "$MOCK/monitors.json" ;;
  "version "*|"version") echo "Hyprland 0.57.2" ;;
  *) exit 0 ;;
esac'
# fuzzel --dmenu : choisit la 1re ligne contenant le motif de $MOCK/fuzzel-N (N = n° d'appel) ;
# sans fichier de motif : aucune réponse (comme un délai dépassé).
mock fuzzel '
n=$(( $(cat "$MOCK/fuzzel-count" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$MOCK/fuzzel-count"
in=$(cat); [[ -f $MOCK/fuzzel-$n ]] || exit 1
grep -F -m1 -- "$(cat "$MOCK/fuzzel-$n")" <<<"$in"'
for c in node brave gpasswd; do mock "$c" "$LOGCALL"'; echo v22.0.0'; done
# Commandes interdites (dual boot) : tout appel est consigné et fait échouer le test.
for c in parted fdisk cfdisk sfdisk mkfs mkfs.ext4 mkfs.fat mkfs.btrfs wipefs sgdisk gdisk grub-install grub-mkconfig \
         efibootmgr bootctl os-prober mount umount mkinitcpio dracut; do
  mock "$c" 'printf "FORBIDDEN %s %s\n" "${0##*/}" "$*" >>"$MOCK/forbidden.log"; exit 1'
done

# Paquets présents sur une EndeavourOS fraîche (simplifié).
fresh_db() {
  rm -rf -- "$MOCK/db"; mkdir -p "$MOCK/db"
  for p in base linux pacman sudo git curl networkmanager firefox endeavouros-keyring archlinux-keyring sddm; do echo 1.0-1 >"$MOCK/db/$p"; done
  rm -f "$MOCK"/fail-chroot-* "$MOCK"/{fail-qs-commits,archive-root-403,ipv6-broken,locale,syu-block,aur-down,net-down,norepo,calls.log,forbidden.log,pacman.conf.at-syu} "$MOCK"/fail-makepkg-* "$MOCK"/interrupt-* "$MOCK"/npm-* "$MOCK"/verify-fail "$MOCK"/fuzzel-*
}
reset_all() { fresh_db; mk_sysroot; rm -rf -- "$H"; mkdir -p "$H"; }

RUN_N=0; RUN_ENV=()
run_installer() {   # run_installer <options…> ; RC et OUT définis
  RUN_N=$((RUN_N + 1)); OUT="$T/out-$RUN_N.txt"; RC=0
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$H" USER="$USER" LANG=C.UTF-8 TMPDIR="$T" "${RUN_ENV[@]}" \
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
check "S1 Hyprland installé depuis les dépôts" test "$(inst_ver hyprland)" = "50.0-1"
check "S1 aucune compilation de la pile Hyprland (ni chroot, ni archive)" bash -c "! grep -qE '^(makechrootpkg|mkarchroot)' '$MOCK/calls.log' && ! grep -q 'archive.archlinux.org/packages' '$MOCK/calls.log'"
check "S1 configuration Lua d'end-4 déployée" test -f "$H/.config/hypr/hyprland.lua"
check "S1 AZERTY : kb_layout fr (Lua)" grep -q 'kb_layout = "fr"' "$H/.config/hypr/custom/general.lua"
check "S1 AZERTY : bureaux par touches physiques + conflits 4/6 retirés" bash -c "grep -q 'SUPER + ALT + code:' '$H/.config/hypr/custom/keybinds.lua' && grep -q 'hl.unbind(\"SUPER + Minus\")' '$H/.config/hypr/custom/keybinds.lua'"
check "S1 premier démarrage branché (Lua)" grep -q -- '--first-login' "$H/.config/hypr/custom/execs.lua"
check "S1 paquet local Space Grotesk installé et fournit otf-space-grotesk" test -f "$MOCK/db/provides-otf-space-grotesk"
check "S1 méta fonts-themes installé (dépendance otf-space-grotesk satisfaite)" test -f "$MOCK/db/illogical-impulse-fonts-themes"
check "S1 aucun IgnorePkg dans pacman.conf" bash -c "! grep -q 'IgnorePkg' '$SR/etc/pacman.conf'"
check "S1 points de reprise 3 à 11 écrits" bash -c "for i in 3 4 5 6 7 8 9 10 11; do [[ -f '$STATE'/step-\$i.done ]] || exit 1; done"
check "S1 aucun échec enregistré" bash -c "! ls '$STATE'/step-*.failed 2>/dev/null | grep -q ."
check "S1 rapport généré" test -f "$H/.local/share/hypr-installer/reports/latest-install.txt"
check "S1 validation sans échec" grep -q 'Installation terminée\.' "$OUT"
check "S1 aucune commande disque/chargeur de démarrage, jamais makepkg -s" test ! -s "$MOCK/forbidden.log"
check "S1 jamais de redémarrage automatique avec --yes" bash -c "! grep -q 'systemctl reboot' '$MOCK/calls.log'"
check "S1 outils de dev installés (node, python, docker, code…)" bash -c "for p in nodejs npm python python-pipx docker code github-cli; do [[ -f '$MOCK/db/'\$p ]] || exit 1; done"
check "S1 Brave installé (AUR, dernière version)" bash -c "[[ -f '$MOCK/db/brave-bin' ]] && grep -q '^git ls-remote https://aur.archlinux.org/brave-bin.git HEAD' '$MOCK/calls.log'"
check "S1 Claude Code installé (installateur officiel)" test -x "$H/.local/bin/claude"
check "S1 freebuff installé via npm dans ~/.local (sans sudo)" bash -c "[[ -x '$H/.local/bin/freebuff' && \$(cat '$MOCK/npm-prefix') == '$H/.local' ]] && ! grep -q '^sudo npm' '$MOCK/calls.log'"
check "S1 skills IA installées (3) avec marqueur, modèle exclu" bash -c "for k in pdf docx skill-creator; do [[ -f '$H/.claude/skills/'\$k/SKILL.md && -f '$H/.claude/skills/'\$k/.hypr-installer-managed ]] || exit 1; done; [[ ! -e '$H/.claude/skills/template' ]]"
check "S1 ~/.local/bin dans le PATH (environment.d, bash, fish)" bash -c "[[ -f '$H/.config/environment.d/90-hypr-installer-path.conf' && -f '$H/.config/fish/conf.d/hypr-installer-path.fish' ]] && grep -q 'hypr-installer: ~/.local/bin' '$H/.bashrc'"
check "S1 docker.socket activé, groupe docker ajouté" bash -c "grep -q 'gpasswd -a' '$MOCK/calls.log'"
check "S1 point de reprise 12 écrit" test -f "$STATE/step-12.done"
check "S1 YouTube : h264ify + VA-API (Firefox)" bash -c "jq -e '.policies.ExtensionSettings[\"{9a41dee2-b924-4161-a971-7fb35c053a4a}\"].install_url and .policies.Preferences[\"media.ffmpeg.vaapi.enabled\"].Value' '$SR/etc/firefox/policies/policies.json' >/dev/null"
check "S1 YouTube : h264ify (Brave)" grep -q 'omkfmpieigblcllmkgbflkikinpkodlk;https://clients2.google.com' "$SR/etc/brave/policies/managed/hypr-installer-video.json"

# =============================================================================
# S2. Relance après succès : tout est repris, rien n'est recompilé
# =============================================================================
: >"$MOCK/calls.log"
run_installer --yes
check "S2 relance : code 0" test "$RC" -eq 0
((RC == 0)) || show_out
check "S2 étapes 3-11 reprises (aucun makepkg, aucun pacman -S/-U)" test "$(calls '^makepkg |^makechrootpkg |^pacman -(S|U|Syu) ')" -eq 0
check "S2 tableau : 13/13" grep -q 'Étapes terminées : 13/13' "$OUT"

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
check "S3 reprise : AUR déjà compilés non recompilés" test "$(grep -E '^makepkg --noconfirm -f -c --log' "$MOCK/calls.log" | grep -vc '@brave-bin$')" -eq 1
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
# S7. Mise à jour d'une installation 2.x (pile 0.54.3 figée) vers les dépôts
# =============================================================================
reset_all
run_installer --yes
# État laissé par la 2.1.x : versions figées/recompilées, IgnorePkg, hook, verrou, chroot.
echo 0.54.3-4 >"$MOCK/db/hyprland"; echo 0.11.0-2.1 >"$MOCK/db/aquamarine"; echo 0.13.1-1.1 >"$MOCK/db/hyprutils"
awk '/^\[options\]/{print "# hypr-installer: pile Hyprland 0.54.3 épinglée (ne pas retirer, voir README)"; print "IgnorePkg = hyprutils hyprland aquamarine"} {print}' "$SR/etc/pacman.conf" >"$SR/etc/pacman.conf.n" && mv "$SR/etc/pacman.conf.n" "$SR/etc/pacman.conf"
mkdir -p "$SR/etc/pacman.d/hooks" "$SR/usr/local/lib/hypr-installer" "$H/.cache/hypr-installer/chroot/root" "$H/.cache/hypr-installer/pkgs/built"
echo x >"$SR/etc/pacman.d/hooks/zz-hypr-installer-pin-check.hook"; echo x >"$SR/usr/local/lib/hypr-installer/pin-check.sh"
echo "hyprland 0.54.3-4" >"$STATE/pins.lock"; echo x >"$H/.cache/hypr-installer/pkgs/built/aquamarine-0.11.0-2.1-x86_64.pkg.tar.zst"
for f in "$STATE"/step-*.done; do echo cle-schema-3 >"$f"; done   # points de reprise d'une 2.x (schéma 3)
printf 'source = hyprland/env.conf\n' >"$H/.config/hypr/hyprland.conf"
printf '# MANAGED-BY: hypr-installer\ninput {\n kb_layout = fr\n}\n' >"$H/.config/hypr/custom/general.conf"
: >"$MOCK/calls.log"
run_installer --yes
check "S7 migration 2.x : code 0" test "$RC" -eq 0
((RC == 0)) || show_out
check "S7 IgnorePkg retiré AVANT pacman -Syu" bash -c "! grep -q 'IgnorePkg' '$MOCK/pacman.conf.at-syu' && ! grep -q 'IgnorePkg' '$SR/etc/pacman.conf'"
check "S7 paquets Hyprland mis à jour dans la même transaction que -Syu" grep -qE '^pacman -Syu --noconfirm .*hyprland' "$MOCK/calls.log"
check "S7 hyprland, aquamarine, hyprutils = versions des dépôts" bash -c "[[ \$(cat '$MOCK/db/hyprland') == 50.0-1 && \$(cat '$MOCK/db/aquamarine') == 50.0-1 && \$(cat '$MOCK/db/hyprutils') == 50.0-1 ]]"
check "S7 hook, verrou et chroot de la 2.x supprimés" bash -c "[[ ! -e '$SR/etc/pacman.d/hooks/zz-hypr-installer-pin-check.hook' && ! -e '$STATE/pins.lock' && ! -e '$H/.cache/hypr-installer/chroot' && ! -e '$H/.cache/hypr-installer/pkgs/built' ]]"
check "S7 ancienne config hyprlang mise de côté, fichiers gérés .conf retirés" bash -c "[[ ! -e '$H/.config/hypr/hyprland.conf' && -e '$H/.config/hypr/hyprland.conf.hyprlang-old' && ! -e '$H/.config/hypr/custom/general.conf' ]]"

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
# S12. Quickshell : commit épinglé par end-4 qui ne compile pas -> repli
# =============================================================================
reset_all
echo 6.12.0-5 >"$MOCK/db/qt6-base"
run_installer --yes
check "S12 Qt 6.12 : commit d'end-4 (v0.3.2) utilisé" bash -c "[[ $RC -eq 0 && \$(cat '$STATE/quickshell.commit') == 4f508be* ]]"
reset_all
printf '%s\n' "$QS_COMMIT" >"$MOCK/fail-qs-commits"
run_installer --yes
check "S12 échec du commit épinglé : repli sur le commit plus récent" bash -c "[[ $RC -eq 0 && \$(cat '$STATE/quickshell.commit') == 9b0f339* ]]"
rm -f "$MOCK/fail-qs-commits"

# =============================================================================
# S9. Dépendance AUR absente des dépôts : arrêt AVANT makepkg, cause explicite
# =============================================================================
reset_all
echo scdoc >"$MOCK/norepo"
run_installer --yes
check "S9 dépendance absente : arrêt contrôlé" test "$RC" -eq 1
check "S9 dépendance nommée dans le message" grep -q 'scdoc' "$OUT"
check "S9 makepkg non lancé pour wlogout" bash -c "! grep -q '^makepkg --noconfirm.*@wlogout$' '$MOCK/calls.log'"

# =============================================================================
# S13. Étape 12 : relance idempotente, skills personnelles préservées
# =============================================================================
reset_all
mkdir -p "$H/.claude/skills/pdf"; echo "ma skill" >"$H/.claude/skills/pdf/SKILL.md"
run_installer --yes
check "S13 installation avec skill personnelle : code 0" test "$RC" -eq 0
check "S13 skill personnelle « pdf » jamais écrasée" grep -qx 'ma skill' "$H/.claude/skills/pdf/SKILL.md"
check "S13 conservation annoncée" grep -q 'personnelle(s) conservée(s)' "$OUT"
: >"$MOCK/calls.log"
run_installer --yes
check "S13 relance : rien de réinstallé (ni Brave, ni npm, ni Claude Code)" bash -c "[[ $RC -eq 0 ]] && ! grep -qE '^(makepkg --noconfirm|npm install|curl .*claude.ai)' '$MOCK/calls.log'"
check "S13 .bashrc : une seule ligne PATH" test "$(grep -c 'hypr-installer: ~/.local/bin' "$H/.bashrc")" -eq 1
rm -rf "$H/.local/bin/claude"
run_installer --yes
check "S13 Claude Code supprimé : réinstallé à la relance" bash -c "[[ $RC -eq 0 && -x '$H/.local/bin/claude' ]]"

# =============================================================================
# S14. --no-dev, et échec npm non bloquant
# =============================================================================
reset_all
run_installer --yes --no-dev
check "S14 --no-dev : code 0, rien d'installé" bash -c "[[ $RC -eq 0 && ! -f '$MOCK/db/brave-bin' && ! -f '$MOCK/db/nodejs' && ! -e '$H/.local/bin/claude' ]]"
check "S14 --no-dev : signalé dans la validation" grep -q 'non installés (--no-dev)' "$OUT"
run_installer --diagnose
check "S14 --diagnose après --no-dev : étape 12 non signalée en échec" test "$RC" -eq 0
reset_all
: >"$MOCK/npm-fail"
run_installer --yes
check "S14 échec npm : installation terminée (avertissement)" bash -c "[[ $RC -eq 0 ]] && grep -q 'installation de freebuff impossible' '$OUT'"
rm -f "$MOCK/npm-fail"
reset_all
echo claude.ai >"$MOCK/net-down"
run_installer --yes
check "S14 claude.ai injoignable : installation terminée, avertissement clair" bash -c "[[ $RC -eq 0 ]] && grep -q 'Claude Code non installé' '$OUT' && [[ -f '$STATE/step-12.done' ]]"
rm -f "$MOCK/net-down"
run_installer --yes
check "S14 réseau revenu : Claude Code installé à la relance" bash -c "[[ $RC -eq 0 && -x '$H/.local/bin/claude' ]]"

# =============================================================================
# S15. --dotfiles <dépôt> puis --dotfiles-restore
# =============================================================================
DF="$T/dots-repo"
mk_dots() {
  rm -rf "$DF"; mkdir -p "$DF/.config/hypr" "$DF/.config/waybar" "$DF/.config/kitty" "$DF/.git"
  printf 'hl.config({ general = { gaps_in = 3 } })\n' >"$DF/.config/hypr/hyprland.lua"
  echo '{"layer":"top"}' >"$DF/.config/waybar/config.jsonc"
  echo 'font_size 13' >"$DF/.config/kitty/kitty.conf"
  echo 'export DOTS=1' >"$DF/.zshrc"
  printf '#!/bin/sh\ntouch "%s"\n' "$MOCK/dots-script-ran" >"$DF/install.sh"; chmod +x "$DF/install.sh"
  printf 'waybar\n# commentaire\ngrub\nlinux-zen\nyay-bin\n' >"$DF/packages.txt"
}
reset_all
run_installer --yes
kitty_before=$(cat "$H/.config/kitty/kitty.conf")
mk_dots; echo yay-bin >"$MOCK/norepo"
run_installer --yes --dotfiles "$DF"
check "S15 dotfiles : code 0" test "$RC" -eq 0
((RC == 0)) || show_out
check "S15 waybar, kitty, hypr, .zshrc appliqués" bash -c "[[ -f '$H/.config/waybar/config.jsonc' && \$(cat '$H/.config/kitty/kitty.conf') == 'font_size 13' && -f '$H/.zshrc' ]] && grep -q gaps_in '$H/.config/hypr/hyprland.lua'"
check "S15 AZERTY ré-appliqué par-dessus les dotfiles" bash -c "grep -qF 'hypr-installer : AZERTY' '$H/.config/hypr/hyprland.lua' && grep -q 'kb_layout = \"fr\"' '$H/.config/hypr/hypr-installer-azerty.lua' && grep -q 'SUPER + code:' '$H/.config/hypr/hypr-installer-azerty.lua'"
check "S15 paquets nécessaires installés (waybar, zsh)" bash -c "[[ -f '$MOCK/db/waybar' && -f '$MOCK/db/zsh' ]]"
check "S15 jamais de paquet de démarrage/noyau (grub, linux-zen)" bash -c "[[ ! -f '$MOCK/db/grub' && ! -f '$MOCK/db/linux-zen' ]]"
check "S15 script du dépôt NON exécuté" test ! -e "$MOCK/dots-script-ran"
check "S15 aucune commande disque/chargeur de démarrage" test ! -s "$MOCK/forbidden.log"
check "S15 install.sh du dépôt non copié dans ~" test ! -e "$H/install.sh"
run_installer --yes --dotfiles-restore
check "S15 restauration : code 0" test "$RC" -eq 0
check "S15 restauration : kitty d'origine, waybar et .zshrc retirés" bash -c "[[ \$(cat '$H/.config/kitty/kitty.conf') == '$kitty_before' && ! -e '$H/.config/waybar' && ! -e '$H/.zshrc' ]]"
check "S15 restauration : configuration Hyprland end-4 d'origine" bash -c "grep -q 'hyprland.lib' '$H/.config/hypr/hyprland.lua' && ! grep -q 'hypr-installer : AZERTY' '$H/.config/hypr/hyprland.lua' && [[ -f '$H/.config/hypr/custom/keybinds.lua' ]]"
check "S15 restauration : état « dotfiles actifs » effacé" test ! -e "$STATE/dotfiles.active"
run_installer --yes --dotfiles-restore
check "S15 seconde restauration : refus explicite" bash -c "[[ $RC -ne 0 ]] && grep -q 'Aucune application de dotfiles' '$OUT'"

# =============================================================================
# S16. Dotfiles incompatibles ou refusés par Hyprland : bureau préservé
# =============================================================================
mk_dots; rm "$DF/.config/hypr/hyprland.lua"; echo 'general { gaps_in = 3 }' >"$DF/.config/hypr/hyprland.conf"
run_installer --yes --dotfiles "$DF"
check "S16 hyprland.conf seul : config Hyprland conservée, reste appliqué" bash -c "[[ $RC -eq 0 && ! -e '$H/.config/hypr/hyprland.conf' && -f '$H/.config/waybar/config.jsonc' ]] && grep -q 'hyprland.lib' '$H/.config/hypr/hyprland.lua'"
check "S16 avertissement hyprland.lua" grep -q 'n’accepte que hyprland.lua' "$OUT"
check "S16 config end-4 conservée intacte (pas de crochet AZERTY ajouté)" bash -c "! grep -q 'hypr-installer : AZERTY' '$H/.config/hypr/hyprland.lua' && [[ ! -e '$H/.config/hypr/hypr-installer-azerty.lua' ]]"
run_installer --yes --dotfiles-restore
mk_dots; : >"$MOCK/verify-fail"
run_installer --yes --dotfiles "$DF"
rm -f "$MOCK/verify-fail"
check "S16 config refusée par --verify-config : ancienne remise" bash -c "[[ $RC -eq 0 ]] && grep -q 'hyprland.lib' '$H/.config/hypr/hyprland.lua' && ! grep -q gaps_in '$H/.config/hypr/hyprland.lua'"
check "S16 refus annoncé" grep -q 'refusée par Hyprland --verify-config' "$OUT"
run_installer --yes --dotfiles-restore
check "S16 restauration après refus : code 0, waybar retiré" bash -c "[[ $RC -eq 0 && ! -e '$H/.config/waybar' ]] && grep -q 'hyprland.lib' '$H/.config/hypr/hyprland.lua'"

# =============================================================================
# S17. Réinstallation d'end-4 par-dessus des dotfiles ; dépôts stow et « .config »
# =============================================================================
mk_dots
run_installer --yes --dotfiles "$DF"
run_installer --yes
check "S17 relance de l'installateur : end-4 remis par-dessus les dotfiles" bash -c "[[ $RC -eq 0 ]] && grep -q 'hyprland.lib' '$H/.config/hypr/hyprland.lua' && [[ ! -e '$STATE/dotfiles.active' ]]"
check "S17 avertissement dotfiles actifs" grep -q 'Des dotfiles sont appliqués' "$OUT"
rm -rf "$DF"; mkdir -p "$DF/waybar/.config/waybar" "$DF/kitty/.config/kitty"
echo stow >"$DF/waybar/.config/waybar/config.jsonc"; echo 'font_size 9' >"$DF/kitty/.config/kitty/kitty.conf"
run_installer --yes --dotfiles "$DF"
check "S17 dépôt GNU Stow reconnu" bash -c "[[ $RC -eq 0 ]] && grep -qx stow '$H/.config/waybar/config.jsonc' && grep -q 'font_size 9' '$H/.config/kitty/kitty.conf'"
run_installer --yes --dotfiles-restore
rm -rf "$DF"; mkdir -p "$DF/waybar" "$DF/screenshots"; echo bar >"$DF/waybar/config"; echo png >"$DF/screenshots/a.png"; echo '# README' >"$DF/README.md"
run_installer --yes --dotfiles "$DF"
check "S17 dépôt = ~/.config reconnu, captures et README ignorés" bash -c "[[ $RC -eq 0 && -f '$H/.config/waybar/config' && ! -e '$H/.config/screenshots' && ! -e '$H/.config/README.md' ]]"
rm -rf "$DF"; mkdir -p "$DF/random"; echo x >"$DF/random/file"
run_installer --yes --dotfiles "$DF"
check "S17 organisation inconnue : refus sans rien modifier" bash -c "[[ $RC -ne 0 ]] && grep -q 'Organisation du dépôt non reconnue' '$OUT' && [[ ! -e '$H/.config/random' ]]"
run_installer --yes --dotfiles "ftp://exemple/x"
check "S17 lien invalide refusé" bash -c "[[ $RC -ne 0 ]] && grep -q 'Lien invalide' '$OUT'"

# =============================================================================
# S18. Super+F2 : choix de la fréquence, confirmation, retour automatique ;
#      Super+F1 ; compléments graphiques (multilib, LACT)
# =============================================================================
reset_all
printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>"$SR/etc/pacman.conf"
mkdir -p "$SR/etc/firefox/policies"; echo '{"policies":{"DisableTelemetry":true}}' >"$SR/etc/firefox/policies/policies.json"
run_installer --yes
check "S18 Super+F1 (aide) et Super+F2 (écrans) définis" bash -c "grep -q '\"SUPER + F1\", hl.dsp.global(\"quickshell:cheatsheetToggle\")' '$H/.config/hypr/custom/keybinds.lua' && grep -q '\"SUPER + F2\".*--monitors' '$H/.config/hypr/custom/keybinds.lua'"
check "S18 pilotes 32 bits (multilib) + LACT installés, lactd activé" bash -c "[[ -f '$MOCK/db/lib32-vulkan-radeon' && -f '$MOCK/db/lib32-mesa' && -f '$MOCK/db/lact' ]] && grep -q 'enable --now lactd.service' '$MOCK/calls.log'"
check "S18 stratégie Firefox existante fusionnée (rien de perdu)" bash -c "jq -e '.policies.DisableTelemetry == true and (.policies.ExtensionSettings | length) == 1' '$SR/etc/firefox/policies/policies.json' >/dev/null"
check "S18 Brave : accélération vidéo + Wayland" grep -q 'AcceleratedVideoDecodeLinuxGL' "$H/.config/brave-flags.conf"
cat >"$MOCK/monitors.json" <<'EOJ'
[{"name":"DP-1","description":"BenQ XL2411","width":1920,"height":1080,"refreshRate":60.0,
  "availableModes":["1920x1080@143.98Hz","1920x1080@119.98Hz","1920x1080@60.00Hz","1280x720@60.00Hz"]},
 {"name":"HDMI-A-1","description":"Samsung","width":1920,"height":1080,"refreshRate":60.0,
  "availableModes":["1920x1080@75.00Hz","1920x1080@60.00Hz"]}]
EOJ
RUN_ENV=(HYPRLAND_INSTANCE_SIGNATURE=test WAYLAND_DISPLAY=wayland-1)
rm -f "$MOCK"/fuzzel-*; echo '143.98 Hz' >"$MOCK/fuzzel-1"; echo 'Garder' >"$MOCK/fuzzel-2"
run_installer --monitors
check "S18 144 Hz choisi et gardé" bash -c "[[ $RC -eq 0 ]] && grep -q 'output = \"DP-1\", mode = \"1920x1080@143.98\"' '$H/.config/hypr/monitors.lua' && grep -q '^hyprctl reload' '$MOCK/calls.log'"
rm -f "$MOCK"/fuzzel-*; echo 'HDMI-A-1 │ 1920x1080 @ 75 Hz' >"$MOCK/fuzzel-1"; echo 'Garder' >"$MOCK/fuzzel-2"
run_installer --monitors
check "S18 second écran réglé, premier conservé" bash -c "grep -q 'mode = \"1920x1080@143.98\"' '$H/.config/hypr/monitors.lua' && grep -q 'output = \"HDMI-A-1\", mode = \"1920x1080@75.00\"' '$H/.config/hypr/monitors.lua'"
cp "$H/.config/hypr/monitors.lua" "$T/monitors.before"
rm -f "$MOCK"/fuzzel-*; echo '1280x720 @ 60 Hz' >"$MOCK/fuzzel-1"
run_installer --monitors
check "S18 sans confirmation : ancien réglage remis automatiquement" bash -c "[[ $RC -eq 0 ]] && cmp -s '$H/.config/hypr/monitors.lua' '$T/monitors.before' && [[ ! -e '$H/.config/hypr/monitors.lua.previous' ]]"
rm -f "$MOCK"/fuzzel-*; echo 'Automatique' >"$MOCK/fuzzel-1"; echo 'Garder' >"$MOCK/fuzzel-2"; rm -f "$H/.config/hypr/monitors.lua"
run_installer --monitors
check "S18 automatique : fréquence maximale de chaque écran" bash -c "grep -q '1920x1080@143.98' '$H/.config/hypr/monitors.lua' && grep -q '1920x1080@75.00' '$H/.config/hypr/monitors.lua'"
RUN_ENV=()
run_installer --monitors
check "S18 hors session : refus clair" bash -c "[[ $RC -ne 0 ]] && grep -q 'Super+F2' '$OUT'"

echo
echo "Résultat : $PASS réussis, $FAILN échoués"
((FAILN == 0))

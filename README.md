# Hyprland One-Click Installer

**EndeavourOS × Hyprland des dépôts Arch (configuration Lua) × end-4/dots-hyprland (main, commit `21733c3` du 2026-11-15)**

> **Version 3.0.0 — changement d’architecture.** Les versions 2.x figeaient Hyprland 0.54.3 (mars 2026). Sur la machine cible, à jour en novembre 2026, cette version plantait dès le démarrage (`std::logic_error` dans aquamarine, retour à l’écran de connexion), même avec une configuration vide et après recompilation. La 3.0 installe donc Hyprland **des dépôts Arch**, testé par Arch avec les pilotes actuels, et la branche `main` d’end-4 (configuration **Lua**), épinglée à un commit précis. Les raccourcis d’end-4 sont conservés et adaptés à l’AZERTY dans `~/.config/hypr/custom/keybinds.lua` : bureaux par touches physiques, Super+Alt/Maj + touche du chiffre, conflits des touches 4 et 6 corrigés, aide sur Super+!, émojis sur Super+:. Une installation 2.x est migrée automatiquement : IgnorePkg, hook, paquets recompilés et ancienne configuration hyprlang sont retirés ou mis de côté. Les sections ci-dessous qui décrivent la pile 0.54.3 épinglée concernent les versions 2.x.
Cible : AMD Ryzen 5 4500 · Radeon RX 550 · 32 Go · clavier AZERTY français · dual boot Windows.

```bash
chmod +x install.sh
./install.sh          # puis redémarrer
```

Le script demande **une** confirmation puis le mot de passe sudo, et fait tout le reste. Au redémarrage, l’écran de connexion propose la session **Hyprland**, déjà présélectionnée. Au premier login, il s’occupe seul de trois choses : détecter les écrans (résolution native et fréquence maximale), appliquer le fond d’écran et les couleurs dynamiques, puis lancer les tests de session. Une notification résume le résultat.

---

## 1. Le problème central, et comment il est résolu

Arch Linux est en *rolling release*. Le 23/11/2026, ses dépôts distribuent **Hyprland 0.57.2** (ère Lua), et non 0.54.3. L’installateur officiel d’end-4 exécute `pacman -Syu` puis `yay -S --noconfirm hyprland …`. Avec `--noconfirm`, la question « hyprland est dans IgnorePkg, installer quand même ? » est répondue **Oui** par défaut : Hyprland finirait donc en 0.57.2. **On ne peut pas lancer l’étape « dépendances » d’end-4 telle quelle.**

Une simple rétrogradation de `hyprland` ne marche pas non plus. Depuis mai 2026, Arch a recompilé Hyprland contre de nouvelles versions incompatibles (ABI) de `aquamarine`, `hyprutils`, `hyprgraphics` et `glslang`. Le binaire 0.54.3 seul ne trouverait plus ses bibliothèques.

**Solution retenue : épingler tout l’écosystème hypr\* dans l’état exact où Arch le distribuait le 2026‑05‑08.** C’est le dernier jour où `hyprland 0.54.3-4` était la version officielle (0.55.0 est arrivé le 09/05). La release end-4 a été figée le même jour (commit du 08/05).

| Méthode | Paquets | Justification |
|---|---|---|
| **Binaire officiel signé** de l’[Arch Linux Archive](https://archive.archlinux.org/packages/) (SHA‑256 + signature pacman vérifiés) | 12 | ABI vérifiée pendant l’audit : les `DT_NEEDED` des 67 sonames, et les versions de symboles, ont été comparés aux listes de fichiers des dépôts actuels → tout est résolu. |
| **Recompilé** depuis le PKGBUILD officiel Arch au commit épinglé, dans un **chroot propre** (`devtools`/`makechrootpkg`) | 3 | `hyprgraphics` : `libjxl.so.0.11` n’existe plus (0.13). `hyprlock` et `xdg-desktop-portal-hyprland` : sdbus‑cpp 2.3 (Arch a dû recompiler hyprlock). |

Les 15 paquets sont installés **en une seule transaction**, ce qui garantit la cohérence ABI. Ils sont ensuite protégés par une ligne `IgnorePkg` dans `/etc/pacman.conf` (fichier sauvegardé au préalable). Le reste du système continue à se mettre à jour normalement : `pacman -Syu` complet, sans rétrogradation globale.

Garde-fous :
- avant chaque transaction, `pacman -Sp` vérifie qu’aucun paquet hypr\* ne serait tiré des dépôts ;
- après chaque transaction, les versions épinglées sont comparées à `state/pins.lock`, et l’installation s’arrête en cas de dérive ;
- un **hook pacman** (`/etc/pacman.d/hooks/zz-hypr-installer-pin-check.hook`) vérifie après chaque mise à jour future qu’aucune bibliothèque requise par la pile n’a disparu. Si c’est le cas, il demande de lancer `--repair`, qui recompile automatiquement les paquets concernés.

Paquets **volontairement non installés**, car end-4 les remplace par Quickshell et les installer créerait des conflits : Waybar, Rofi, SwayNC/dunst/mako (conflit sur le nom D‑Bus des notifications), hyprpaper (le fond d’écran est rendu par Quickshell), hyprpolkitagent et polkit-kde-agent en démarrage automatique (Quickshell fournit **son propre agent polkit** ; deux agents entreraient en conflit), uwsm (end-4 : « DO NOT SELECT UWSM »).

---

## 2. Matrice de compatibilité (versions retenues)

| Composant | Version | Source | Compatibilité |
|---|---|---|---|
| **Hyprland** | **0.54.3-4** | Arch Linux Archive (signé) | ✅ exigée ; `Hyprland --version` vérifié |
| aquamarine | 0.11.0-2 | ALA | ✅ version utilisée par 0.54.3-4 (« rebuild with aquamarine 0.11.0 ») |
| hyprutils | 0.13.1-1 | ALA | ✅ 0.54.3-4 compilé contre 0.13.0, 0.13.1 de même ABI (aucune recompilation Arch) |
| hyprlang | 0.6.8-4 | ALA | ✅ |
| hyprcursor | 0.1.13-6 | ALA | ✅ |
| hyprgraphics | 0.5.1-2**.1** | PKGBUILD Arch `4ef2d0b` → chroot | ✅ recompilé contre libjxl 0.13 |
| hyprwire | 0.3.1-2 | ALA | ✅ |
| hyprwayland-scanner | 0.4.6-1 | ALA | ✅ identique à la version actuelle |
| hyprtoolkit / hyprland-guiutils | 0.5.4-1 / 0.2.1-5 | ALA | ✅ dépendances de hyprland 0.54.3 |
| hypridle | 0.1.7-9 | ALA | ✅ |
| hyprlock | 0.9.5-2**.1** | PKGBUILD Arch `43ae18d` → chroot | ✅ recompilé contre sdbus-cpp 2.3 |
| hyprpicker / hyprsunset | 0.4.7-1 / 0.3.3-7 | ALA | ✅ |
| xdg-desktop-portal-hyprland | 1.3.12-2**.1** | PKGBUILD Arch `1220c33` → chroot | ✅ recompilé contre sdbus-cpp 2.3 / Qt 6.12 |
| **end-4 dots-hyprland** | **2026.05.11** = `bebf66da89cd2afa4738da47fb3a0a9fa5af7035` | GitHub (tag léger, vérifié via `git ls-remote` à chaque exécution) | ✅ « If your distro has not shipped Hyprland 0.55, stick to this release » |
| sous-module rounded-polygon-qmljs | `e31ec4cb4ebf…` | GitHub | ✅ vérifié |
| **Quickshell** | commit `7511545ee206…` (épinglé par end-4) | git.outfoxxed.me (repli : miroir GitHub, même commit) | ⚠️ compilé contre Qt 6.12 ; repli automatique et signalé sur **v0.3.0** (`59e9c47b`, descendant direct, antérieur à la release end-4) si le commit ne compile pas |
| Google Sans Flex | `251aa5abd304…` | GitHub end-4 (upstream clone `main` → épinglé ici) | ✅ |
| Space Grotesk | archive 38C3 v2, SHA-256 vérifiée | archive officielle du styleguide | installée directement, sans paquet AUR `38c3-styles` |
| Paquets Python des widgets | `sdata/uv/requirements.txt` (33 versions `==`) | PyPI via uv, Python 3.12 | ✅ comme upstream |
| Mesa / vulkan-radeon | dépôts actuels (26.3.x) | Arch | ✅ RX 550 = Polaris 12, pilote `amdgpu`, Vulkan RADV. `libva-mesa-driver` est désormais intégré à `mesa` ; `mesa-vdpau` n’existe plus (VDPAU abandonné par Mesa ; VA‑API utilisé) |
| PipeWire / WirePlumber / portails / Qt 6.12 / KDE | dépôts actuels | Arch | ✅ ABI stable vis-à-vis de la pile épinglée (vérifié) |
| Waybar | — | — | non utilisé par end-4 (barre Quickshell) |
| 9 paquets AUR (thèmes, icônes, wlogout…) | commits AUR épinglés (voir `AUR_PINS` dans le script) | AUR | ✅ PKGBUILD audités : sources upstream officielles avec sommes de contrôle |

Le manifeste exact est régénéré à chaque exécution dans `~/.local/share/hypr-installer/manifests/versions-latest.txt`.

---

## 3. Architecture

Un seul script, `install.sh`, découpé en fonctions qui suivent le schéma demandé :

```
preflight → detect_system / resolve_versions → detect_hardware
→ install_system_packages (+AUR épinglé) → install_graphics → install_hyprland (pile épinglée)
→ install_end4 (méta-paquets end-4, sauvegarde, fichiers, venv Python, réglages)
→ install_quickshell → configure_keyboard → configure_keybindings
→ configure_desktop (thèmes, polices, fonds d’écran, démarrage)
→ configure_all_services (audio, réseau, bluetooth, polkit, gestionnaire de connexion)
→ validate_installation → generate_report
```

- **Reproduction fidèle d’end-4** : les listes de dépendances sont lues dans les PKGBUILD `sdata/dist-arch/illogical-impulse-*` du commit épinglé. Les méta-paquets sont installés, ce qui assure la traçabilité (`pacman -Qi illogical-impulse-*`). Le déploiement reprend `3.files-legacy.sh` et `2.setups.sh`, sans leurs invites interactives. Leur fonction `x()` boucle à l’infini sur `read` en cas d’échec, d’où la réimplémentation.
- **Correctif upstream** : `hypr/hyprlock/` (scripts référencés par `hyprlock.conf`) est déployé. Le script legacy d’end-4 l’oubliait ; leur variante YAML le fait.
- **Adaptations séparées** : toutes les personnalisations vont dans `~/.config/hypr/custom/`, le mécanisme prévu par end-4, que leurs mises à jour ne touchent pas. Les fichiers générés portent l’en-tête `# MANAGED-BY: hypr-installer`. Vos ajouts vont dans les fichiers `*.user.conf`, jamais écrasés.
- **Points de reprise** : `state/step-NN.done`. Une relance reprend après la dernière étape réussie.
- **Journaux** : tout est consigné, horodaté, dans `logs/`. L’écran n’affiche que le tableau de progression et l’activité en cours.
- **Dépendances AUR** : chaque PKGBUILD AUR épinglé **et chaque méta-paquet end-4** est converti en `.SRCINFO` avant compilation. Les dépendances déjà installées sont vérifiées avec `pacman -T`, celles des dépôts sont validées avant `makepkg -s`, et toute dépendance AUR absente/non épinglée est signalée explicitement avec son nom.
- **Archives Arch** : les fichiers `.pkg.tar.zst` et leurs signatures `.sig` sont vérifiés indépendamment ; une archive présente en cache ne masque plus une signature manquante.
- **Erreurs** : `set -Eeuo pipefail`, plus des traps `ERR`/`INT`/`TERM`/`EXIT`. En cas d’échec, l’étape passe à FAILED, la commande fautive, son code et les 15 dernières lignes du journal s’affichent, et un rapport d’échec est écrit.

Fichiers produits sur la machine :

```
~/.local/share/hypr-installer/
├── logs/        install-*.log, first-login-*.log, post-login-*.log
├── backups/     <horodatage>/home/… et system/… + MANIFEST.tsv (source → copie)
├── state/       points de reprise, pins.lock, commit Quickshell utilisé
├── reports/     report-*.txt, latest-<mode>.txt
├── manifests/   versions-*.txt, hardware-*.txt, raccourcis-azerty.txt, end4-keybinds.upstream.conf
├── end4/        checkout vérifié de la release
└── bin/install.sh   (copie, utilisée au premier login et par --repair)
~/.cache/hypr-installer/   paquets archivés vérifiés, compilations, chroot devtools (~1–2 Go)
```

---

## 4. Clavier AZERTY

- **Hyprland** : `custom/general.conf` contient `input { kb_layout = fr  kb_variant =  kb_model = pc105 }` et le pavé numérique est activé.
- **Console (TTY)** : `localectl set-keymap fr`, seulement si la disposition n’est pas déjà en `fr*`.
- **X11 / écran de connexion SDDM / XWayland** : `localectl set-x11-keymap fr pc105`.
- **OCR** : `tesseract-data-fra` est ajouté, pour une reconnaissance en `fra+eng`.

### Conception des raccourcis

Les **lettres** sont liées par symbole, c’est-à-dire par la lettre imprimée sur la touche AZERTY. **Super+Q** est donc bien la touche marquée Q.

La **rangée des chiffres** est liée par **code physique** (`code:10…19`). **Super+&**, **Super+é**, … **Super+à** donnent ainsi les bureaux 1…10 **sans Maj**.

Problèmes AZERTY corrigés par rapport à end-4 (détectés par l’analyse automatique) :

| end-4 (QWERTY) | Problème en AZERTY | Remplacement |
|---|---|---|
| Super+`-` zoom arrière | `-` est la touche **6** → zoome **et** va au bureau 6 | **Super+)** |
| Super+`'` ratio de découpe | `'` est la touche **4** → change le ratio **et** va au bureau 4 | supprimé (Super+Ctrl+flèches) |
| Super+`/` aide | `/` nécessite Maj → inaccessible | **Super+F1** |
| Super+`.` émojis | `.` nécessite Maj → inaccessible | **Super+;** (touche `; .`) |
| Super+`[` `]`, Ctrl+Super+`\` | AltGr → inaccessibles | supprimés (alternatives existantes) |
| Super+S bloc-notes, Super+B panneau, Super+V presse-papiers, Super+C éditeur, Super+P épingler, Ctrl+Super+flèches bureaux | conflits avec votre schéma | déplacés (voir tableau) |

### Tableau complet (aide à l’écran : **Super+F1**)

| Raccourci | Action |
|---|---|
| **Super+R** | Terminal (kitty) — aussi Super+Entrée |
| **Super+E** | Gestionnaire de fichiers (Dolphin) |
| **Super+Espace** · Super (appui court) | Lanceur d’applications (Quickshell ; repli fuzzel) |
| **Super+Q** · Alt+F4 | Fermer la fenêtre |
| **Super+F** / Super+D | Plein écran / maximiser |
| **Super+L** | Verrouiller la session |
| **Super+S** | Capture d’une zone (outil end-4 : copier, enregistrer, annoter) |
| **Super+B** | Navigateur |
| **Super+C** | Calculatrice (Qalculate) |
| **Super+Échap** · Ctrl+Alt+Suppr | Menu système : verrouiller, **déconnexion (confirmation par le menu)**, veille, redémarrer, éteindre |
| Super+flèches | Déplacer le focus |
| Super+Maj+flèches | Déplacer la fenêtre |
| Super+Ctrl+flèches | Redimensionner |
| Super+clic gauche / droit | Déplacer / redimensionner à la souris |
| **Super+V** | Flottant ↔ mosaïque (Super+Alt+V : centrer) |
| **Super+P** | Pseudo-mosaïque (Super+Alt+P : épingler sur tous les bureaux) |
| Super+Maj+J | Inverser le sens de découpe |
| Alt+Tab / Alt+Maj+Tab | Fenêtre suivante / précédente |
| **Super+& é " ' ( - è _ ç à** | Bureaux 1 → 10 (pavé numérique aussi) |
| **Super+Maj+(même touche)** | Déplacer la fenêtre vers le bureau 1 → 10 (et la suivre) |
| Super+Alt+(même touche) | Envoyer la fenêtre sans la suivre |
| Super+PgPréc / PgSuiv · Super+Alt+← / → · Super+molette | Bureau précédent / suivant (les bureaux vides sont accessibles) |
| Super+Maj+PgPréc / PgSuiv · Super+Maj+Alt+← / → | Déplacer la fenêtre vers le bureau précédent / suivant |
| Ctrl+Super+Alt+← / → | Bureau **occupé** précédent / suivant |
| Super+Ctrl+E / Super+Ctrl+Maj+E | Aller / envoyer la fenêtre au premier bureau **vide** |
| Ctrl+Super+S / Super+Alt+S | Bureau spécial (bloc-notes) : afficher / y envoyer |
| Super+Tab | Vue d’ensemble des bureaux et fenêtres |
| Super+N / Super+A | Panneau droit (notifications, réglages rapides) / panneau gauche (IA, traduction) |
| Super+Maj+V | Historique du presse-papiers |
| Super+; | Émojis |
| Super+M / Super+K / Super+G / Super+J | Contrôles multimédia / clavier virtuel / overlay / barre |
| Ctrl+Super+T (+Alt) | Choisir un fond d’écran (aléatoire) |
| Ctrl+Super+P | Changer de style de panneaux |
| **Impr** / **Ctrl+Impr** / **Maj+Impr** | Écran complet → presse-papiers / → fichier + presse-papiers / zone → fichier |
| Super+Maj+X / Super+Maj+T / Super+Maj+A | OCR / traduire l’écran / recherche visuelle |
| Super+Maj+C | Pipette de couleur |
| Super+Maj+R · Ctrl+Alt+R · Super+Maj+Alt+R | Enregistrer zone / écran / écran avec son |
| Super+= / Super+) | Zoom avant / arrière |
| Touches multimédia | Volume, muet, micro, lecture, piste suivante/précédente, luminosité — **sans Super**, actives même écran verrouillé, avec OSD Quickshell |
| Super+Maj+M / Super+Alt+M | Couper le son / le micro |
| Super+Maj+P / N / B | Lecture-pause / suivant / précédent |
| Ctrl+Super+V | Mixeur de volume |
| **Super+F5** | Recharger la configuration Hyprland |
| **Ctrl+Super+R** | Redémarrer Quickshell (widgets) |
| **Ctrl+Maj+Échap** | Gestionnaire de tâches |
| Super+I | Paramètres |
| Super+Maj+L | Mise en veille |
| Super+Alt+F1 | Désactiver/réactiver les raccourcis (machines virtuelles) |
| Super+F1 | Cette aide |

Vos raccourcis : `~/.config/hypr/custom/keybinds.user.conf`. Le fichier QWERTY d’origine d’end-4 est désactivé (`$dontLoadDefaultKeybinds = true`). Il est conservé dans `manifests/end4-keybinds.upstream.conf`.

---

## 5. Services et démarrage

| Service | Configuration |
|---|---|
| PipeWire, pipewire-pulse, WirePlumber | `systemctl --global enable` ; PulseAudio retiré s’il est présent (avec confirmation) |
| NetworkManager | activé, sauf si un autre gestionnaire réseau est actif (on ne coupe jamais la connexion) |
| Bluetooth | `bluez` activé ; démarrage conditionnel à la présence d’un adaptateur |
| Polkit | agent fourni par Quickshell ; aucun second agent |
| Portails | xdg-desktop-portal + hyprland + gtk + kde (`hyprland-portals.conf` d’end-4) |
| Connexion | gestionnaire existant conservé (SDDM, GDM, LightDM…) ; **SDDM installé** s’il n’y en a aucun ; session Hyprland présélectionnée |
| Quickshell, hypridle, presse-papiers, trousseau | `exec-once` d’end-4, **une seule fois** (vérifié ; `hypridle.service` désactivé s’il faisait doublon) |
| ydotool, i2c-dev, groupes video/i2c/input | comme `2.setups.sh` d’end-4 |

**Dual boot** : le script n’exécute aucune commande sur les disques, partitions, la table GPT, l’EFI, les entrées UEFI, GRUB/systemd-boot ou Windows. Les seuls fichiers système modifiés sont `/etc/pacman.conf` (ligne IgnorePkg), `/etc/modules-load.d/i2c-dev.conf`, la disposition clavier (`localectl`), `/var/lib/sddm/state.conf` (ou AccountsService) et le hook pacman. Tous sont sauvegardés au préalable dans `backups/<horodatage>/system/`.

---

## 6. Utilisation

```bash
./install.sh                 # installation complète (reprise automatique après interruption)
./install.sh --yes           # sans la confirmation initiale
./install.sh --diagnose      # mode diagnostic : contrôles + rapport, aucune modification
./install.sh --repair        # revérifie et recompile ce qui est cassé, redéploie (sauvegarde avant)
./install.sh --force         # réexécute toutes les étapes
~/.local/share/hypr-installer/bin/install.sh --post-login-check   # tests dans la session Hyprland
```

Prérequis : EndeavourOS fraîchement installé, à jour ou non ; Internet ; ≥ 25 Go libres sur `/` et ≥ 20 Go dans `$HOME` (compilations et chroot inclus). Lancez le script depuis un TTY (Ctrl+Alt+F3) ou depuis votre session actuelle. Durée typique : 30 à 60 min, essentiellement en compilations (Quickshell, chroot, AUR).


### Version 2.0.0 — audit de fiabilité

Défauts corrigés (tous constatés dans le code de la 1.2.9) :

- **Dépendances versionnées rejetées à tort.** La pré-vérification coupait chaque ligne du `.SRCINFO` au premier `=` : `cmake>=3.30` devenait `3.30`, déclaré introuvable, et l’installation s’arrêtait avant `makepkg`. La suite de tests du dépôt échouait d’ailleurs déjà sur ce point.
- **Échec certain de l’étape 6 (makepkg, code 8).** Le méta-paquet end-4 `illogical-impulse-fonts-themes` dépend de `otf-space-grotesk`. La police était copiée dans `~/.local/share/fonts`, mais aucun paquet ne la *fournissait* : `makepkg -s` puis `pacman -U` ne pouvaient pas satisfaire cette dépendance. L’installateur construit désormais un petit paquet local `hypr-installer-space-grotesk` (archive 38C3 vérifiée par SHA-256, `provides=(otf-space-grotesk)`).
- **Points de reprise aveugles.** Une étape marquée comme terminée était sautée sans vérifier le système. Désormais, chaque étape 3 à 11 a une fonction `verify_step_N` en lecture seule : l’étape n’est sautée que si son point de reprise existe **et** que l’état réel est conforme. Après exécution, la même vérification doit réussir avant d’écrire le point de reprise (aucune fausse réussite). Une étape réexécutée invalide les suivantes, qui en dépendent. Modifier le script ne relance plus tout.
- **Échecs non enregistrés.** Un `die` ne marquait pas l’étape en échec et n’écrivait aucun rapport. La gestion est maintenant centralisée (`on_exit`) : étape, raison, cause et code sont conservés dans `state/step-N.failed`, affichés, et repris par le rapport et par `--diagnose`.
- **Causes illisibles.** La sortie de chaque commande en échec est analysée : paquet introuvable, conflit, rupture de dépendance, trousseau, réseau, verrou, somme de contrôle, échec de `build()`… Le code `makepkg` est traduit (8 = dépendances impossibles à installer, avec le paquet en cause).
- **Mise à jour du système bloquée par la pile épinglée.** Si `pacman -Syu` remplace une bibliothèque dont dépend un paquet épinglé, le paquet bloquant est identifié, retiré (avec confirmation), puis recompilé à l’étape 5 contre la nouvelle bibliothèque. `IgnorePkg` n’est posé avant `-Syu` que si la pile épinglée est déjà installée.
- **Conflits pacman.** Avec `--noconfirm`, pacman répond « non » aux suppressions. Les paquets bloquants sont maintenant identifiés dans la sortie et retirés après confirmation, puis la transaction est relancée (2 fois au plus). Les conflits sont lus dans le `.PKGINFO` exact de chaque paquet.
- **Verrou pacman orphelin** après une interruption : détecté, et retiré après accord uniquement si aucun pacman ne tourne. Une interruption laisse la commande en cours se terminer proprement.
- **AUR indisponible** : repli automatique sur le miroir GitHub officiel (`github.com/archlinux/aur`, mêmes commits vérifiés).
- **`--diagnose` refait** : il ne modifie rien et ne s’arrête plus en cas de réseau absent. Il distingue prérequis manquants, étapes terminées (état vérifié), échouées (avec cause), interrompues, non exécutées, terminées mais dégradées, ainsi que les paquets absents.
- `--repair` ne recompile plus les paquets AUR intacts. `--yes` ne redémarre plus jamais la machine. `install.sh` est exécutable dans le dépôt.

Aucune commande touchant aux partitions, systèmes de fichiers, EFI, GRUB ou au chargeur Windows n’existe dans le script. La CI et la simulation de bout en bout le vérifient.

## 7. Validation

Hors session (étape 12), avec PASS/WARN/FAIL dans le rapport :
- EndeavourOS ; Hyprland 0.54.3 (`pacman -Q` + `Hyprland --version`) ;
- pile épinglée intacte, ABI (`ldd`), IgnorePkg ;
- **configuration hyprlang valide** (`Hyprland --verify-config`) ;
- release end-4 et fichiers Quickshell identiques à la release ;
- Quickshell installé et compatible Qt (`quickshell --private-check-compat`), venv Python ;
- 24 outils des widgets, session Wayland, portails, polkit, audio, réseau, Bluetooth ;
- GPU AMD + pilote, Vulkan RADV, polices ;
- AZERTY, raccourcis (> 100), 20 liaisons de bureaux, gestionnaire de connexion, autostart ;
- absence de conflit de démarrage.

En session, automatiquement au premier login (notification + rapport) :
- Hyprland 0.54.3 en cours d’exécution, Wayland ;
- Quickshell joignable par IPC et **en une seule instance**, widgets ;
- portails D‑Bus, sortie audio par défaut, connectivité réseau ;
- **disposition active « French »** ;
- raccourcis chargés (Super+R, Super+1…0 par code physique) ;
- écrans détectés et moteur de rendu OpenGL.

Le test polkit reste manuel : `pkexec true` doit ouvrir la fenêtre Quickshell.

## 8. Résultats des tests réalisés (honnêtement)

### Tests de la version 2.0.0 (exécutés dans un conteneur Linux, sans EndeavourOS)

| Test | Résultat |
|---|---|
| `bash -n` sur les trois scripts | ✅ |
| ShellCheck 0.10.0, niveau `warning`, sur `install.sh` et les tests | ✅ 0 avertissement |
| `tests/test-installer.sh` — 20 tests unitaires (analyse `.SRCINFO`, otf-space-grotesk, dépendants inverses, analyse des sorties pacman/makepkg, points de reprise, fausse réussite, enregistrement des échecs, dérive de la pile) | ✅ 20/20 |
| `tests/e2e-simulation.sh` — `install.sh` exécuté **en entier** avec pacman, makepkg, git, curl, sudo, systemctl… simulés (base de paquets fictive, racine système temporaire, utilisateur non privilégié). 9 scénarios : installation complète, relance, échec `makepkg` code 8 puis reprise, dérive de l’état réel, interruption SIGTERM puis reprise, `--diagnose` (système frais, hors réseau, terminé), `-Syu` bloqué + `--repair`, AUR indisponible, dépendance absente des dépôts | ✅ 54/54 avec l’arbre end-4 synthétique ; ✅ 54/54 avec le **vrai** end-4 au commit `bebf66d` |
| Vérification des 9 paquets AUR épinglés au commit exact (via le miroir GitHub officiel) : dépendances relues, toutes présentes dans les dépôts officiels | ✅ |
| `--private-check-compat` existe bien au commit Quickshell épinglé `7511545` | ✅ |

La simulation valide l’enchaînement, les erreurs, la reprise et le diagnostic. Elle **ne prouve pas** que les paquets réels se compilent, ni que pacman réagit exactement comme les simulacres, ni qu’Hyprland démarre sur la RX 550.

### Audit initial (versions 1.x)

L’environnement de développement est **Windows sans virtualisation** (WSL2/Docker indisponibles). **Aucune exécution réelle sur EndeavourOS ni session graphique n’a pu être faite.**

Ce qui **a** été testé :

| Test | Résultat |
|---|---|
| Release end-4 : tag `2026.05.11` → `bebf66d…` (tag léger), date, notes de release, sous-module | ✅ vérifié |
| Les 15 paquets épinglés existent dans l’ALA ; SHA‑256 recalculés | ✅ 15/15 |
| Commits de packaging Arch : `pkgver-pkgrel` de chaque PKGBUILD = version épinglée | ✅ 15/15 |
| ABI des binaires archivés vs dépôts du 22/11/2026 : `DT_NEEDED` (67 sonames) et versions de symboles Qt/libstdc++ | ✅ sauf les 3 paquets recompilés (raison documentée) |
| 66 dépendances « dépôt » des méta-paquets end-4 présentes dans core/extra ; 9 AUR épinglés | ✅ |
| `bash -n` + **ShellCheck 0.11 au niveau le plus strict (style)** sur `install.sh` et le hook généré | ✅ 0 remarque |
| Banc de test exécutant les **vraies fonctions** dans un HOME factice : IgnorePkg (idempotent, préserve l’existant), déploiement end-4, AZERTY, raccourcis (2 passages, idempotent), sauvegardes, SDDM, détection d’écrans (2560×1440 → 143.97 Hz), démarrage | ✅ (un faux positif corrigé grâce au banc) |
| Raccourcis analysés par le **parseur réel de l’aide end-4** (`get_keybinds.py`) | ✅ 3 colonnes, 76 entrées |
| Analyseur de conflits/accessibilité AZERTY + exigences du cahier des charges | ✅ 0 problème (il détecte bien les 2 conflits et 9 touches inaccessibles du fichier d’origine) |

Ce qui **n’a pas pu** être testé ici, donc vérifié par le script lui-même sur la machine :
- les compilations en chroot (hyprgraphics, hyprlock, xdph) et celle de Quickshell contre Qt 6.12 ;
- `Hyprland --verify-config` sur la configuration finale ;
- le fonctionnement des widgets dans une vraie session.

## 9. Limites connues

1. **Quickshell × Qt 6.12** : le commit épinglé par end-4 date de mars 2026 (Qt 6.11). Rien dans l’historique ne signale d’incompatibilité de compilation, mais ce n’est pas vérifiable ici. Si la compilation échoue, le script bascule sur v0.3.0 et le **signale** dans le rapport. Quickshell utilise l’API privée de Qt : après une future mise à jour de Qt, le hook d’end-4 vous préviendra, et `./install.sh --repair` recompile.
2. **Mises à jour futures** : la pile hypr\* est figée. Une future mise à jour d’Arch peut changer le soname d’une bibliothèque utilisée (comme libjxl). Le hook pacman le signale immédiatement, et `--repair` recompile depuis les PKGBUILD officiels épinglés. Cette recompilation n’est pas garantie si l’API de la bibliothèque a changé : il faudrait alors rester sur une version antérieure de cette bibliothèque, ou passer à la release Lua d’end-4.
3. Les paquets AUR `*-git` (adw-gtk-theme-git, material-symbols-git) et le méta-paquet MicroTeX suivent la branche principale de leur projet, comme chez end-4. MicroTeX (rendu LaTeX du panneau IA) est **non bloquant** en cas d’échec de compilation.
4. Le **clavier virtuel** d’end-4 n’a qu’une disposition QWERTY : les étiquettes sont QWERTY, mais les caractères tapés suivent la disposition AZERTY active.
5. L’appartenance au groupe `input` (exigée par ydotool chez end-4) permet de lire les événements clavier : c’est un choix de sécurité d’end-4, conservé.
6. Pas de connexion automatique : le gestionnaire de connexion demande le mot de passe, ce qui déverrouille aussi le trousseau.

## 10. Récupération

- **Reprendre après interruption ou échec** : relancer `./install.sh`. Les étapes dont l’état réel est conforme sont sautées ; les autres sont refaites. Un verrou pacman laissé par l’interruption est proposé à la suppression.
- **Diagnostiquer** : `./install.sh --diagnose` (aucune modification). Il classe chaque étape : terminée et conforme, en échec (date, code, cause), interrompue, non exécutée, ou terminée mais dégradée. Il liste aussi les paquets absents. Rapport : `~/.local/share/hypr-installer/reports/latest-diagnose.txt` ; dernier échec d’une étape : `~/.local/share/hypr-installer/state/step-N.failed`.
- **Réparer** (après une mise à jour qui casse la pile, ou Quickshell incompatible) : `~/.local/share/hypr-installer/bin/install.sh --repair`.
- **Restaurer une configuration** : chaque sauvegarde liste `source → copie` dans `backups/<horodatage>/MANIFEST.tsv`. Par exemple :
  `cp -a ~/.local/share/hypr-installer/backups/<horodatage>/home/.config/kitty ~/.config/`
- **Hyprland ne démarre pas** : depuis un TTY (Ctrl+Alt+F3), lancer `--diagnose`, puis consulter `~/.local/share/hyprland/` et les journaux. Vous pouvez toujours choisir une autre session à l’écran de connexion.
- **Rendre la pile hypr\* aux dépôts** (abandon de 0.54.3) : retirer les deux lignes `hypr-installer` de `/etc/pacman.conf` (une copie d’origine se trouve dans `backups/*/system/etc/pacman.conf`) et `/etc/pacman.d/hooks/zz-hypr-installer-pin-check.hook`, puis lancer `sudo pacman -Syu`. Attention : cela installe Hyprland 0.57+, **incompatible avec cette release d’end-4**.

## 11. Sources

- end-4 : <https://github.com/end-4/dots-hyprland/releases/tag/2026.05.11> · installateur `setup`, `sdata/dist-arch/*/PKGBUILD`, `sdata/subcmd-install/*.sh`
- Arch Linux Archive : <https://archive.archlinux.org/packages/> · packaging Arch : <https://gitlab.archlinux.org/archlinux/packaging/packages/>
- Quickshell : <https://git.outfoxxed.me/quickshell/quickshell> (miroir <https://github.com/quickshell-mirror/quickshell>)
- AUR : <https://aur.archlinux.org/> (commits listés dans `AUR_PINS`)
- Hyprland : <https://github.com/hyprwm/Hyprland/releases/tag/v0.54.3>

Licence : GPL-3.0-or-later (identique à end-4 ; le fichier de raccourcis est dérivé du leur).
"# hyprland-config-amd" 

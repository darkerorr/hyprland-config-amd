#!/usr/bin/env python3
"""Tests de l'application Paramètres (Super+I) embarquée dans install.sh.

Logique (fichiers Lua/JSON, lecture de hyprctl, annulation) testée réellement ;
interface testée avec un gi/GTK simulé : cela détecte les erreurs du code Python
de l'interface, pas le rendu GTK réel.
"""
import importlib.util
import json
import os
import sys
import tempfile
import types
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
text = open(os.path.join(ROOT, "install.sh"), encoding="utf-8").read()
start = text.index("cat <<'PYAPP'\n") + len("cat <<'PYAPP'\n")
end = text.index("\nPYAPP\n", start)
tmpdir = tempfile.mkdtemp()
src = os.path.join(tmpdir, "hypr-parametres.py")
open(src, "w", encoding="utf-8").write(text[start:end] + "\n")
home = tempfile.mkdtemp(); os.environ["HOME"]=home; os.environ["XDG_CONFIG_HOME"]=home+"/.config"
spec = importlib.util.spec_from_file_location("hp", src); hp = importlib.util.module_from_spec(spec); spec.loader.exec_module(hp)
# --- logique
st = hp.load_state("/nonexistent"); assert st == hp.DEFAULTS
p = home+"/s.json"; json.dump({"sensitivity": 5, "accel_profile":"bad","kb_variant":"bepo","natural_scroll":"yes","repeat_rate":0}, open(p,"w"))
st = hp.load_state(p); assert st["sensitivity"]==1.0 and st["accel_profile"]=="adaptive" and st["kb_variant"]=="bepo" and st["natural_scroll"] is False and st["repeat_rate"]==1, st
lua = hp.settings_lua(dict(hp.DEFAULTS, sensitivity=-0.35, kb_variant='x"y'))
assert 'sensitivity = -0.35,' in lua and 'kb_variant = "x\\"y",' in lua and 'kb_layout = "fr"' in lua and 'numlock_by_default = true' in lua, lua
mons = hp.parse_monitors(json.dumps([{"name":"DP-1","description":"BenQ ","width":1920,"height":1080,"refreshRate":143.981,"scale":1.0,
  "availableModes":["1280x720@60.00Hz","1920x1080@60.00Hz","1920x1080@143.98Hz","1920x1080@143.98Hz"]}]))
m = mons[0]; assert m["modes"][0]=="1920x1080@143.98" and m["current"]=="1920x1080@143.98" and len(m["modes"])==3 and m["desc"]=="BenQ", m
assert hp.mode_label("1920x1080@60.00")=="1920 × 1080  —  60 Hz"
assert hp.best_mode(m["modes"])=="1920x1080@143.98"
f = home+"/m.lua"; open(f,"w").write('-- x\nhl.monitor({ output = "DP-1", mode = "1920x1080@60", position = "auto", scale = 1 })\nhl.monitor({ output = "HDMI-A-1", mode = "3840x2160@60", position = "auto-left", scale = "auto" })\n')
r = hp.read_monitor_rules(f); assert r["HDMI-A-1"]["scale"]=="auto" and r["DP-1"]["mode"]=="1920x1080@60", r
r["DP-1"]["scale"]=1.25; out = hp.monitors_lua(r)
assert 'hl.monitor({ output = "DP-1", mode = "1920x1080@60", position = "auto", scale = 1.25 })' in out and 'scale = "auto" })' in out, out
open(f,"w").write(out); assert hp.read_monitor_rules(f)["DP-1"]["scale"]=="1.25"
# installer's own format (session_monitors) is readable
open(f,"w").write('hl.monitor({ output = "DP-1", mode = "1920x1080@143.98", position = "auto", scale = 1 })\n')
assert hp.read_monitor_rules(f)["DP-1"]["mode"]=="1920x1080@143.98"
# apply_input : refus -> restauration
hp.STATE=home+"/st.json"; hp.SETTINGS_LUA=home+"/st.lua"
open(hp.SETTINGS_LUA,"w").write("old")
seq=iter([True, False])
with mock.patch.object(hp,"config_ok",lambda: next(seq)), mock.patch.object(hp,"run",lambda *a,**k:(0,"")):
    ok,msg = hp.apply_input(dict(hp.DEFAULTS))
assert not ok and open(hp.SETTINGS_LUA).read()=="old" and not os.path.exists(hp.STATE), msg
seq=iter([True, True]); calls=[]
with mock.patch.object(hp,"config_ok",lambda: next(seq)), mock.patch.object(hp,"run",lambda c,**k: calls.append(c) or (0,"")):
    ok,msg = hp.apply_input(dict(hp.DEFAULTS, left_handed=True))
assert ok and "left_handed = true" in open(hp.SETTINGS_LUA).read() and ["hyprctl","reload"] in calls
print("logic OK")

# --- interface avec gi simulé : détecte les erreurs Python du code d'interface
class Any(mock.MagicMock):
    pass
handlers = {}
def fake_app(*a, **k):
    app = mock.MagicMock()
    app.get_windows.return_value = []
    def connect(sig, fn): handlers[sig] = fn
    app.connect.side_effect = connect
    def run(argv): handlers["activate"](app); return 0
    app.run.side_effect = run
    return app
Adw = mock.MagicMock(); Adw.Application.side_effect = fake_app
created = {}
def track(name):
    def f(*a, **k):
        o = mock.MagicMock(name=name); created.setdefault(name, []).append((o,a,k)); return o
    return f
for n in ["ActionRow","SwitchRow","ComboRow","PreferencesGroup","PreferencesPage","AlertDialog"]:
    getattr(Adw, n).side_effect = track(n)
Gtk = mock.MagicMock(); GLib = mock.MagicMock()
Gtk.Button.side_effect = track("Button")
gi = types.ModuleType("gi"); gi.require_version = lambda *a: None
rep = types.ModuleType("gi.repository"); rep.Adw=Adw; rep.Gtk=Gtk; rep.GLib=GLib
sys.modules["gi"]=gi; sys.modules["gi.repository"]=rep
monjson = json.dumps([{"name":"DP-1","description":"BenQ","width":1920,"height":1080,"refreshRate":60.0,"scale":1.0,"availableModes":["1920x1080@143.98Hz","1920x1080@60.00Hz"]},
                      {"name":"HDMI-A-1","description":"","width":1920,"height":1080,"refreshRate":60.0,"scale":1.0,"availableModes":["1920x1080@60.00Hz"]}])
hp.MONITORS_LUA = home+"/mon.lua"
runs=[]
def fake_run(c, **k):
    runs.append(c)
    return (0, monjson) if c[:2]==["hyprctl","monitors"] else (0,"")
with mock.patch.object(hp,"run",fake_run):
    assert hp.run_gui("souris")==0
    # cliquer « Appliquer » de la page Écrans : 1er groupe créé = en-tête
    head = created["PreferencesGroup"][0][0]
    btn = head.set_header_suffix.call_args[0][0]
    clicked = [c for c in btn.connect.call_args_list if c[0][0]=="clicked"][0][0][1]
    # sélections : combos renvoient 0 (MagicMock) -> forcer entiers
    for o,a,k in created["ComboRow"]: o.get_selected.return_value = 0
    clicked()
    txt = open(hp.MONITORS_LUA).read()
    assert 'output = "DP-1", mode = "1920x1080@143.98", position = "auto", scale = 1.0' in txt and 'HDMI-A-1' in txt, txt
    assert ["hyprctl","reload"] in runs
    # dialogue de confirmation : réponse « revert » -> fichier restauré (absent avant)
    dlg = created["AlertDialog"][0][0]
    resp = [c for c in dlg.connect.call_args_list if c[0][0]=="response"][0][0][1]
    resp(dlg, "revert")
    assert not os.path.exists(hp.MONITORS_LUA)
    # minuterie : à 0 -> retour automatique, une seule fois
    clicked(); dlg2 = created["AlertDialog"][1][0]
    tick = GLib.timeout_add_seconds.call_args[0][1]
    for _ in range(hp.CONFIRM_SECONDS): r = tick()
    assert r is False and not os.path.exists(hp.MONITORS_LUA)
    # lignes de la page Système : activer « Wi-Fi » lance gnome-control-center avec XDG_CURRENT_DESKTOP=GNOME
    rows = [ (o,k) for o,a,k in created["ActionRow"] if k.get("title")=="Wi-Fi"]
    act = [c for c in rows[0][0].connect.call_args_list if c[0][0]=="activated"][0][0][1]
    with mock.patch.object(hp.shutil,"which",lambda x:"/usr/bin/"+x), mock.patch.object(hp,"launch",lambda c,e: launched.append((c,e)) or True):
        launched=[]; act(rows[0][0]); assert launched==[(["gnome-control-center","wifi"],{"XDG_CURRENT_DESKTOP":"GNOME"})], launched
    # bouton « Appliquer » de la page Souris -> apply_input avec les valeurs des contrôles
    souris = [o for o,a,k in created["PreferencesGroup"] if k.get("title")=="Souris"][0]
    sbtn = souris.set_header_suffix.call_args[0][0]
    sclick = [c for c in sbtn.connect.call_args_list if c[0][0]=="clicked"][0][0][1]
    got=[]
    with mock.patch.object(hp,"apply_input",lambda st: got.append(st) or (True,"ok")):
        sclick()
    assert got and set(got[0]) == set(hp.DEFAULTS), got
print("gui OK")

#!/bin/bash
# Run: bash test/scripts.test.sh
# Runs scan-binds and add-binding against a temporary HOME and a fake
# hyprctl, so neither the real config nor the real compositor is touched.

here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

check() { # description, condition (0 = pass)
  if (($2 == 0)); then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}

# ------------------------------------------------------------- scan-binds

home="$tmp/home"
mkdir -p "$home/.config/hypr" "$tmp/mods"
cat >"$tmp/mods/sidemod.lua" <<LUA
os.execute("touch $tmp/side-require")
return {}
LUA
cat >"$home/.config/hypr/hyprland.lua" <<LUA
package.path = "$tmp/mods/?.lua;" .. package.path
os.execute("touch $tmp/side-execute")
local pipe = io.popen("touch $tmp/side-popen")
if pipe then pipe:close() end
local out = io.open("$tmp/side-write", "w")
if out then out:write("x"); out:close() end
os.remove("$home/.config/hypr/hyprland.lua.keep")
require("sidemod")
hl.bind("SUPER + K", hl.dsp.exec_cmd("kcmd"), { description = "K" })
LUA
touch "$home/.config/hypr/hyprland.lua.keep"

out=$(HOME="$home" XDG_STATE_HOME="$home/state" "$here/scan-binds" 2>/dev/null)
grep -q $'^B\t64\tK\tK\tkcmd$' <<<"$out"; check "scan reads the bind" $?
tail -1 <<<"$out" | grep -qx $'E\tok'; check "complete scan ends with E ok" $?
[[ ! -e $tmp/side-execute ]]; check "os.execute has no effect" $?
[[ ! -e $tmp/side-popen ]]; check "io.popen of an unknown command has no effect" $?
[[ ! -e $tmp/side-write ]]; check "io.open for writing has no effect" $?
[[ ! -e $tmp/side-require ]]; check "a required module cannot run commands" $?
[[ -e $home/.config/hypr/hyprland.lua.keep ]]; check "os.remove has no effect" $?

cat >"$home/.config/hypr/hyprland.lua" <<'LUA'
hl.bind("SUPER + K", hl.dsp.exec_cmd("kcmd"), { description = "K" })
error("config broke")
LUA
out=$(HOME="$home" XDG_STATE_HOME="$home/state" "$here/scan-binds" 2>/dev/null)
grep -q $'^B\t64\tK' <<<"$out"; check "a broken config still yields the binds before the error" $?
tail -1 <<<"$out" | grep -q $'^E\tpartial'; check "a broken config ends with E partial" $?

cat >"$home/.config/hypr/hyprland.lua" <<'LUA'
while true do end
LUA
out=$(HOME="$home" XDG_STATE_HOME="$home/state" "$here/scan-binds" 2>/dev/null)
tail -1 <<<"$out" | grep -q $'^E\tpartial'; check "a config that never ends is reported partial" $?

rm "$home/.config/hypr/hyprland.lua"
out=$(HOME="$home" XDG_STATE_HOME="$home/state" "$here/scan-binds" 2>/dev/null)
tail -1 <<<"$out" | grep -q $'^E\tpartial'; check "no config is reported partial" $?

# ------------------------------------------------------------ add-binding

mkdir -p "$tmp/bin" "$tmp/fake"
cat >"$tmp/bin/hyprctl" <<'SH'
#!/bin/bash
f=$FAKE
case "$1 $2" in
"binds -j") [[ -e $f/down ]] && exit 2; cat "$f/binds.json" ;;
"reload ") [[ -e $f/reload-fails ]] && exit 1; [[ -e $f/after.json ]] && cp "$f/after.json" "$f/binds.json"; echo ok ;;
"configerrors ") [[ -e $f/errors-fail ]] && exit 1; [[ -e $f/errors ]] && cat "$f/errors" ;;
esac
exit 0
SH
chmod +x "$tmp/bin/hyprctl"

original=$'o.bind("SUPER + Y", "Yazi", { launch = "yazi" })\n'
run_add() { # keys; env FAKE, XDG_* set by caller
  PATH="$tmp/bin:$PATH" FAKE="$tmp/fake" XDG_CONFIG_HOME="$tmp/xdg" XDG_STATE_HOME="$tmp/state" \
    "$here/add-binding" "$1" "Test app" "testapp" >/dev/null 2>&1
}
reset() { # [file content]
  [[ -n $1 ]] && original=$1
  rm -rf "$tmp/fake" && mkdir -p "$tmp/fake" "$tmp/xdg/hypr"
  printf '%s' "$original" >"$tmp/xdg/hypr/bindings.lua"
  echo '[{"modmask":64,"key":"Y"}]' >"$tmp/fake/binds.json"
}
unchanged() { [[ $(cat "$tmp/xdg/hypr/bindings.lua"; echo x) == "${original}x" ]]; }
after_k() { echo '[{"modmask":64,"key":"Y"},{"modmask":65,"key":"K"}]' >"$tmp/fake/after.json"; }

reset; after_k
run_add "SUPER + SHIFT + K"; rc=$?
((rc == 0)) && grep -q 'o.bind("SUPER + SHIFT + K"' "$tmp/xdg/hypr/bindings.lua"; check "adds a free key that becomes active" $?

reset 'o.bind("SUPER + Q", "Close", {})
'; run_add "SUPER + Y"; rc=$?
((rc == 1)) && unchanged; check "refuses a key that is live in Hyprland but not in the file" $?

reset 'o.bind("SUPER + Q", "Close", {})
'; echo '[{"modmask":64,"key":"u"}]' >"$tmp/fake/binds.json"; run_add "SUPER + U"; rc=$?
((rc == 1)) && unchanged; check "key comparison ignores case" $?

reset 'o.bind("SUPER + Z", "x", {})
'; echo '[]' >"$tmp/fake/binds.json"; run_add "SUPER + Z"; rc=$?
((rc == 1)) && unchanged; check "refuses a key that is in the file but not live" $?

reset 'o.bind("SUPER + Y", "Yazi", { launch = "yazi" })
'; touch "$tmp/fake/down"; run_add "SUPER + K"; rc=$?
((rc == 1)) && unchanged; check "refuses when Hyprland does not answer" $?

reset; run_add "SUPER + K"; rc=$?
((rc == 1)) && unchanged; check "rolls back when the new bind never becomes active" $?

reset; after_k; touch "$tmp/fake/reload-fails"; run_add "SUPER + SHIFT + K"; rc=$?
((rc == 1)) && unchanged; check "rolls back when the reload fails" $?

reset; after_k; touch "$tmp/fake/errors-fail"; run_add "SUPER + SHIFT + K"; rc=$?
((rc == 1)) && unchanged; check "rolls back when the config errors cannot be read" $?

reset; after_k; echo "line 3: syntax error" >"$tmp/fake/errors"; run_add "SUPER + SHIFT + K"; rc=$?
((rc == 1)) && unchanged; check "rolls back when Hyprland reports a config error" $?

echo
((failures == 0)) && echo "all passed" || { echo "$failures failed"; exit 1; }

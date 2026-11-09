#!/system/bin/sh
# Reversible tvOS Home-only change for the exact supported AFTMM build.
set -u
STATE=/data/local/tmp/tvos-home-state
TMP=/data/local/tmp/tvos-home-state.tmp
TVOS=com.techgenius.tvoslauncher/.MainActivity
STARTER=com.amazon.firehomestarter
AMAZON_HOME=com.amazon.tv.launcher/.ui.HomeActivity_vNext
OLD_HOME=
STARTER_HIDDEN=0
AMAZON_DISABLED=0
C_STARTER=0
C_AMAZON=0
C_HOME=0
log(){ printf '[TVOS] %s\n' "$*" >&2; }
starter_hidden(){ dumpsys package "$STARTER" | grep -F 'User 0:' | grep -Fq 'installed=true hidden=true'; }
amazon_disabled(){ dumpsys package com.amazon.tv.launcher | sed -n '/disabledComponents:/,/^[^ ]/p' | grep -Fq 'com.amazon.tv.launcher.ui.HomeActivity_vNext'; }
home_is_tvos(){ x=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1); [ "$x" = "$TVOS" ]; }
rollback(){
  bad=0
  [ "$C_HOME" = 1 ] && cmd package set-home-activity "$OLD_HOME" >/dev/null 2>&1 || :
  if [ "$C_AMAZON" = 1 ]; then pm enable "$AMAZON_HOME" >/dev/null 2>&1 || bad=1; fi
  if [ "$C_STARTER" = 1 ]; then pm unhide --user 0 "$STARTER" >/dev/null 2>&1 || bad=1; fi
  if [ "$bad" = 0 ]; then rm -f "$STATE" "$TMP"; log ROLLBACK=PASS; else log ROLLBACK=FAIL; fi
}
fail(){ log "FAIL $1"; rollback; printf 'TVOS_HOME=FAIL\n'; exit 1; }
check(){ [ "$(getprop "$1")" = "$2" ] || fail "identity-$1"; }
check ro.product.manufacturer Amazon
check ro.product.model AFTMM
check ro.product.device mantis
check ro.build.id NS6711
check ro.build.version.incremental 0011644900484
check ro.build.fingerprint 'Amazon/mantis/mantis:6.0/NS6711/5908N:user/amz-p,release-keys'
[ "$(uname -r)" = '4.4.120+' ] || fail kernel-release
[ "$(uname -m)" = armv7l ] || fail kernel-machine
[ "$(id -u)" = 0 ] || fail not-root
[ "$(getenforce)" = Enforcing ] || fail selinux
[ ! -e "$STATE" ] || fail state-already-exists
cmd package path com.techgenius.tvoslauncher >/dev/null 2>&1 || fail tvos-package-missing
cmd package resolve-activity --brief -n "$TVOS" >/dev/null 2>&1 || fail tvos-activity-missing
OLD_HOME=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1)
[ "$OLD_HOME" = "$AMAZON_HOME" ] || fail unexpected-current-home
starter_hidden && STARTER_HIDDEN=1
amazon_disabled && AMAZON_DISABLED=1
umask 077
{
  printf 'VERSION=1\n'
  printf 'OLD_HOME=%s\n' "$OLD_HOME"
  printf 'STARTER_HIDDEN=%s\n' "$STARTER_HIDDEN"
  printf 'AMAZON_DISABLED=%s\n' "$AMAZON_DISABLED"
} > "$TMP" || fail state-write
mv "$TMP" "$STATE" || fail state-commit
log "STATE_SAVED=$STATE"
if [ "$STARTER_HIDDEN" = 0 ]; then
  pm hide --user 0 "$STARTER" >/dev/null 2>&1 || fail hide-firehomestarter
  starter_hidden || fail verify-hidden-firehomestarter
  C_STARTER=1
fi
if [ "$AMAZON_DISABLED" = 0 ]; then
  pm disable "$AMAZON_HOME" >/dev/null 2>&1 || fail disable-stock-home
  amazon_disabled || fail verify-disabled-stock-home
  C_AMAZON=1
fi
cmd package set-home-activity "$TVOS" >/dev/null 2>&1 || fail set-tvos-home
C_HOME=1
home_is_tvos || fail verify-home-resolver
am start -n "$TVOS" >/dev/null 2>&1 || fail launch-tvos
log 'HOME_RESOLVER=PASS'
printf 'TVOS_HOME=PASS\n'
exit 0

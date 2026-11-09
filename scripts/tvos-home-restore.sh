#!/system/bin/sh
# Restore only the three states changed by tvos-home-actions.sh.
set -u
STATE=/data/local/tmp/tvos-home-state
TVOS=com.techgenius.tvoslauncher/.MainActivity
STARTER=com.amazon.firehomestarter
AMAZON_HOME=com.amazon.tv.launcher/.ui.HomeActivity_vNext
OLD_HOME=
STARTER_HIDDEN=
AMAZON_DISABLED=
log(){ printf '[TVOS-RESTORE] %s\n' "$*" >&2; }
fail(){ log "FAIL $1"; printf 'TVOS_RESTORE=FAIL\n'; exit 1; }
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
[ -f "$STATE" ] || fail state-file-missing
while IFS='=' read -r k v; do
  case "$k" in
    VERSION) [ "$v" = 1 ] || fail bad-version ;;
    OLD_HOME) OLD_HOME=$v ;;
    STARTER_HIDDEN) STARTER_HIDDEN=$v ;;
    AMAZON_DISABLED) AMAZON_DISABLED=$v ;;
    *) fail bad-state-key ;;
  esac
done < "$STATE"
[ "$OLD_HOME" = "$AMAZON_HOME" ] || fail bad-original-home
case "$STARTER_HIDDEN" in 0|1) ;; *) fail bad-starter-state ;; esac
case "$AMAZON_DISABLED" in 0|1) ;; *) fail bad-amazon-state ;; esac
# Restore original package states first, then the original HOME resolver.
if [ "$AMAZON_DISABLED" = 0 ]; then
  pm enable "$AMAZON_HOME" >/dev/null 2>&1 || fail enable-stock-home
fi
if [ "$STARTER_HIDDEN" = 0 ]; then
  pm unhide --user 0 "$STARTER" >/dev/null 2>&1 || fail unhide-firehomestarter
fi
cmd package set-home-activity "$OLD_HOME" >/dev/null 2>&1 || fail restore-original-home
# Verify the original stock Home is selectable and the saved package states match.
resolved=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1)
[ "$resolved" = "$OLD_HOME" ] || fail verify-original-home
if [ "$STARTER_HIDDEN" = 0 ]; then
  dumpsys package "$STARTER" | grep -F 'User 0:' | grep -Fq 'installed=true hidden=false' || fail verify-starter-visible
else
  dumpsys package "$STARTER" | grep -F 'User 0:' | grep -Fq 'installed=true hidden=true' || fail verify-starter-hidden
fi
if [ "$AMAZON_DISABLED" = 0 ]; then
  dumpsys package com.amazon.tv.launcher | sed -n '/disabledComponents:/,/^[^ ]/p' | grep -Fq 'com.amazon.tv.launcher.ui.HomeActivity_vNext' && fail verify-stock-home-enabled
else
  dumpsys package com.amazon.tv.launcher | sed -n '/disabledComponents:/,/^[^ ]/p' | grep -Fq 'com.amazon.tv.launcher.ui.HomeActivity_vNext' || fail verify-stock-home-disabled
fi
rm -f "$STATE" || fail remove-state
log 'RESTORE=PASS'
printf 'TVOS_RESTORE=PASS\n'
exit 0

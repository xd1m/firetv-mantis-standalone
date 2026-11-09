#!/system/bin/sh
# Exact-build, one-shot root action for tvOS Launcher only.
# Invoked by GhostLock with UID 0. Does not install apps or alter other packages.
set -u

PKG_TVOS=com.techgenius.tvoslauncher
TVOS_COMPONENT=com.techgenius.tvoslauncher/.MainActivity
PKG_STARTER=com.amazon.firehomestarter
STARTER_COMPONENT=com.amazon.firehomestarter/.HomeStarterActivity
AMAZON_HOME_COMPONENT=com.amazon.tv.launcher/.ui.HomeActivity_vNext
CHANGED_STARTER=0
CHANGED_AMAZON_HOME=0
CHANGED_HOME_DEFAULT=0
OLD_HOME=

log() { printf '[TVOS] %s\n' "$*" >&2; }
fail() { log "FAIL $*"; rollback; printf '%s\n' 'TVOS_HOME=FAIL'; exit 1; }

expect_prop() {
  actual=$(getprop "$1") || fail "getprop-$1"
  [ "$actual" = "$2" ] || fail "identity-$1"
}
starter_hidden() {
  dumpsys package "$PKG_STARTER" | grep -F 'User 0:' | grep -Fq 'installed=true hidden=true'
}
amazon_home_disabled() {
  dumpsys package com.amazon.tv.launcher |
    sed -n '/disabledComponents:/,/^[^ ]/p' |
    grep -Fq 'com.amazon.tv.launcher.ui.HomeActivity_vNext'
}
tvos_resolves() {
  resolved=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1)
  [ "$resolved" = "$TVOS_COMPONENT" ]
}

rollback() {
  rollback_failed=0
  if [ "$CHANGED_HOME_DEFAULT" = 1 ] && [ -n "$OLD_HOME" ]; then
    cmd package set-home-activity "$OLD_HOME" >/dev/null 2>&1 || rollback_failed=1
  fi
  if [ "$CHANGED_AMAZON_HOME" = 1 ]; then
    pm enable "$AMAZON_HOME_COMPONENT" >/dev/null 2>&1 || rollback_failed=1
    amazon_home_disabled && rollback_failed=1
  fi
  if [ "$CHANGED_STARTER" = 1 ]; then
    pm unhide --user 0 "$PKG_STARTER" >/dev/null 2>&1 || rollback_failed=1
    starter_hidden && rollback_failed=1
  fi
  if [ "$rollback_failed" = 0 ]; then log 'ROLLBACK=PASS'; else log 'ROLLBACK=FAIL'; fi
}

expect_prop ro.product.manufacturer Amazon
expect_prop ro.product.model AFTMM
expect_prop ro.product.device mantis
expect_prop ro.build.id NS6711
expect_prop ro.build.version.incremental 0011644900484
expect_prop ro.build.fingerprint 'Amazon/mantis/mantis:6.0/NS6711/5908N:user/amz-p,release-keys'
[ "$(uname -r)" = '4.4.120+' ] || fail kernel-release
[ "$(uname -m)" = armv7l ] || fail kernel-machine
[ "$(id -u)" = 0 ] || fail not-root
[ "$(getenforce)" = Enforcing ] || fail selinux-not-enforcing

# Confirm the intended launcher exists and can be launched before changing Home.
cmd package path "$PKG_TVOS" >/dev/null 2>&1 || fail tvos-package-missing
cmd package resolve-activity --brief -n "$TVOS_COMPONENT" >/dev/null 2>&1 || fail tvos-activity-missing

OLD_HOME=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1)
[ -n "$OLD_HOME" ] || fail cannot-read-current-home
log "ORIGINAL_HOME=$OLD_HOME"

if ! starter_hidden; then
  pm hide --user 0 "$PKG_STARTER" >/dev/null 2>&1 || fail hide-firehomestarter
  starter_hidden || fail verify-hidden-firehomestarter
  CHANGED_STARTER=1
  log "CHANGED hidden $PKG_STARTER"
else
  log "UNCHANGED already-hidden $PKG_STARTER"
fi

if ! amazon_home_disabled; then
  pm disable "$AMAZON_HOME_COMPONENT" >/dev/null 2>&1 || fail disable-amazon-home-activity
  amazon_home_disabled || fail verify-disabled-amazon-home-activity
  CHANGED_AMAZON_HOME=1
  log "CHANGED disabled $AMAZON_HOME_COMPONENT"
else
  log "UNCHANGED already-disabled $AMAZON_HOME_COMPONENT"
fi

cmd package set-home-activity "$TVOS_COMPONENT" >/dev/null 2>&1 || fail set-tvos-home
CHANGED_HOME_DEFAULT=1
tvos_resolves || fail verify-tvos-home-resolver
log "CHANGED default-home $TVOS_COMPONENT"

am start -n "$TVOS_COMPONENT" >/dev/null 2>&1 || fail launch-tvos
log 'DIRECT_LAUNCH=PASS'
log 'HOME_RESOLVER=PASS'
printf '%s\n' 'TVOS_HOME=PASS'
exit 0

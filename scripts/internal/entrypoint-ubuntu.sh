#!/bin/bash
set -e

if [ -n "$APP_UID" ] && [ "$APP_UID" != "0" ]; then
    usermod -u "$APP_UID" app 2>/dev/null || true
    chown -R app:app /home/app 2>/dev/null || true
fi

[ -x /srv/init.sh ] && /srv/init.sh

exec gosu app "$@"

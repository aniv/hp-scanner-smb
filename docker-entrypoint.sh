#!/bin/sh
set -eu

: "${SMB_PASSWORD:?Set SMB_PASSWORD in the Compose environment file}"

SMB_UID="${SMB_UID:-2000}"
SMB_GID="${SMB_GID:-2000}"

if ! getent group scanner >/dev/null 2>&1; then
    groupadd --gid "$SMB_GID" scanner
fi

if ! id scanner >/dev/null 2>&1; then
    useradd --uid "$SMB_UID" --gid scanner --no-create-home --shell /usr/sbin/nologin scanner
fi

mkdir -p /srv/scans /var/run/samba /var/log/samba
chown scanner:scanner /srv/scans
chmod 0770 /srv/scans

printf '%s\n%s\n' "$SMB_PASSWORD" "$SMB_PASSWORD" | smbpasswd -a -s scanner
smbpasswd -e scanner

testparm -s /etc/samba/smb.conf >/dev/null

exec smbd --foreground --no-process-group --debug-stdout

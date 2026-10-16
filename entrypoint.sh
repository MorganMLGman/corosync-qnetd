#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
#
# Starts sshd (needed once, by "pvecm qdevice setup") and then corosync-qnetd.
# Root login is key-only; the keys come from $AUTHORIZED_KEYS or from a mounted
# /root/.ssh/authorized_keys.

set -eu

NSSDB_DIR=/etc/corosync/qnetd/nssdb
KEYS_FILE=/root/.ssh/authorized_keys

fatal() {
    echo "[qnetd-entrypoint] ERROR: $*" >&2
    exit 1
}

# RouterOS mounts directories and passes configuration as environment
# variables, so a key given in the environment must work without any mount.
if [ ! -s "${KEYS_FILE}" ] && [ -n "${AUTHORIZED_KEYS:-}" ]; then
    printf '%s\n' "${AUTHORIZED_KEYS}" > "${KEYS_FILE}"
fi

[ -s "${KEYS_FILE}" ] \
    || fatal "no SSH key: set AUTHORIZED_KEYS or mount ${KEYS_FILE}"

# ssh-keygen -l also accepts a private key, and one passed through an
# environment variable would end up readable in the container's configuration.
if grep -q 'PRIVATE KEY' "${KEYS_FILE}"; then
    fatal "${KEYS_FILE} holds a private key; give the public key"
fi

# Fail here, not later inside "pvecm qdevice setup", when the value is not a key.
ssh-keygen -l -f "${KEYS_FILE}" >/dev/null 2>&1 \
    || fatal "${KEYS_FILE} holds no valid public key"

# A read-only bind mount cannot be chmodded; sshd is fine with that.
chmod 0700 /root/.ssh 2>/dev/null || true
chmod 0600 "${KEYS_FILE}" 2>/dev/null || true

# The CA is created here, not at build time, so no two deployments share one.
# An existing database holds the signed node certificates and must be kept.
if [ ! -f "${NSSDB_DIR}/cert9.db" ]; then
    # Also covers a freshly mounted, empty volume.
    install -d -m 0750 -o root -g coroqnetd "${NSSDB_DIR}"
    echo "[qnetd-entrypoint] initialising a new QNetd CA in ${NSSDB_DIR}"
    corosync-qnetd-certutil -i >/dev/null
fi

# qnetd runs as coroqnetd below. Repeated on every start so a volume written
# by an earlier image, or mounted with another owner, is readable too.
chgrp -R coroqnetd "${NSSDB_DIR}"
chmod -R g+rwX "${NSSDB_DIR}"
install -d -m 0770 -o coroqnetd -g coroqnetd /run/corosync-qnetd

mkdir -p /etc/ssh/sshd_config.d /run/sshd
cat > /etc/ssh/sshd_config.d/10-qnetd.conf <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
EOF

# Generated per container so two deployments do not share a host identity.
ssh-keygen -A >/dev/null
/usr/sbin/sshd

# Same user as Debian's systemd unit. setpriv execs, so qnetd stays PID 1 and
# "stop" reaches it as SIGTERM straight away; runuser would stay as its parent.
exec setpriv --reuid=coroqnetd --regid=coroqnetd --init-groups \
    /usr/bin/corosync-qnetd -f "$@"

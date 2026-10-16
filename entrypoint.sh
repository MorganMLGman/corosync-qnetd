#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
#
# Starts sshd (needed once, by "pvecm qdevice setup") and then corosync-qnetd.
# Root login is key-only. The keys come from a mounted
# /root/.ssh/authorized_keys, or else from $AUTHORIZED_KEYS (separated by ';'
# or newlines).

set -eu

NSSDB_DIR=/etc/corosync/qnetd/nssdb
MOUNTED_KEYS=/root/.ssh/authorized_keys
# The copy sshd actually reads. A mounted file keeps the owner and mode of its
# host, and StrictModes makes sshd refuse one that root does not own.
SSHD_KEYS=/etc/ssh/qnetd_authorized_keys

fatal() {
    echo "[qnetd-entrypoint] ERROR: $*" >&2
    exit 1
}

staged=$(mktemp)
if [ -s "${MOUNTED_KEYS}" ]; then
    cat "${MOUNTED_KEYS}" > "${staged}"
elif [ -n "${AUTHORIZED_KEYS:-}" ]; then
    # A RouterOS environment value is one line of text, so several keys are
    # separated by ';' (newlines work too). ';' never occurs in a key itself.
    printf '%s\n' "${AUTHORIZED_KEYS}" | tr ';' '\n' > "${staged}"
else
    fatal "no SSH key: set AUTHORIZED_KEYS or mount ${MOUNTED_KEYS}"
fi

# ssh-keygen -l also accepts a private key, and one passed through an
# environment variable would end up readable in the container's configuration.
if grep -q 'PRIVATE KEY' "${staged}"; then
    fatal "the SSH keys contain a private key; give the public key"
fi

# Every line must be a key. Checking the file as a whole passes as soon as one
# line is valid, and sshd silently skips the others, so a mistyped second key
# would only show up as a failed "pvecm qdevice setup". Blank and comment lines
# are legal in authorized_keys but ssh-keygen -l rejects them, hence the skip.
probe=$(mktemp)
( umask 077; : > "${SSHD_KEYS}" )
keys=0
lineno=0
while IFS= read -r line || [ -n "${line}" ]; do
    lineno=$((lineno + 1))
    case "$(printf '%s' "${line}" | tr -d '[:space:]')" in
        '' | '#'*) continue ;;
    esac
    printf '%s\n' "${line}" > "${probe}"
    ssh-keygen -l -f "${probe}" >/dev/null 2>&1 \
        || fatal "line ${lineno} of the SSH keys is not a public key"
    printf '%s\n' "${line}" >> "${SSHD_KEYS}"
    keys=$((keys + 1))
done < "${staged}"
rm -f "${probe}" "${staged}"
[ "${keys}" -gt 0 ] || fatal "no public key found in the SSH keys"

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
cat > /etc/ssh/sshd_config.d/10-qnetd.conf <<EOF
PermitRootLogin prohibit-password
PasswordAuthentication no
AuthorizedKeysFile ${SSHD_KEYS}
EOF

# Generated per container so two deployments do not share a host identity.
ssh-keygen -A >/dev/null
/usr/sbin/sshd

# Same user as Debian's systemd unit. setpriv execs, so qnetd stays PID 1 and
# "stop" reaches it as SIGTERM straight away; runuser would stay as its parent.
exec setpriv --reuid=coroqnetd --regid=coroqnetd --init-groups \
    /usr/bin/corosync-qnetd -f "$@"

# SPDX-License-Identifier: AGPL-3.0-only
FROM debian:trixie-slim

LABEL org.opencontainers.image.source="https://github.com/MorganMLGman/corosync-qnetd" \
      org.opencontainers.image.licenses="AGPL-3.0-only"

# Same Debian release as Proxmox VE 9, so qnetd and the nodes' corosync-qdevice
# run the same corosync 3.0.x.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        corosync-qnetd openssh-server \
    && rm -rf /var/lib/apt/lists/*

# The package's postinst creates a CA here. Shipping it would give every pull
# the same private key, so the entrypoint makes the CA on first start instead.
#
# corosync-qnetd-certutil gives every file it creates the owner of
# /etc/corosync/qnetd, including certificates signed later by "pvecm qdevice
# setup". The group must be coroqnetd for qnetd, which runs as that user, to
# read them.
RUN rm -rf /etc/corosync/qnetd/nssdb \
    && chgrp coroqnetd /etc/corosync/qnetd

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

VOLUME /etc/corosync/qnetd/nssdb

# qnetd is TCP; mapped as UDP it never connects and logs nothing.
EXPOSE 22/tcp 5403/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
    CMD corosync-qnetd-tool -s >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

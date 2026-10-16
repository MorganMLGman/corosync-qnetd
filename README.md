# corosync-qnetd

`corosync-qnetd` (external vote for a two-node Proxmox cluster) as a multi-arch
image: `linux/amd64`, `linux/arm64`, `linux/arm/v7`, so it also runs as a
MikroTik RouterOS container.

```
ghcr.io/morganmlgman/corosync-qnetd:0.1.0
```

## Configuration

- `AUTHORIZED_KEYS`: the Proxmox node's `/root/.ssh/id_rsa.pub`; several keys
  separated by `;` or newlines. Or mount `/root/.ssh/authorized_keys`. SSH is
  key-only and the container refuses to start on an invalid key.
- Persist `/etc/corosync/qnetd/nssdb` (the CA and node certificates).
- Ports: 5403/tcp (qnetd), 22/tcp (only for `pvecm qdevice setup`).

## Docker

```sh
docker run -d --name qnetd --restart unless-stopped \
  -p 22:22 -p 5403:5403 \
  -v qnetd-nssdb:/etc/corosync/qnetd/nssdb \
  -e AUTHORIZED_KEYS="$(ssh root@<pve-node> cat /root/.ssh/id_rsa.pub)" \
  ghcr.io/morganmlgman/corosync-qnetd:0.1.0
```

## RouterOS

Needs the `container` package and an **ext4** disk (FAT32 fails).

```
/file add name=usb1/qnetd type=directory
/file add name=usb1/qnetd/nssdb type=directory
/interface veth add name=veth-qnetd address=<container-ip>/24 gateway=<router-ip>
/container mounts add list=qnetd-nssdb src=/usb1/qnetd/nssdb dst=/etc/corosync/qnetd/nssdb
/container envs add list=qnetd key=AUTHORIZED_KEYS value="<pve1 key>;<pve2 key>"
/container add remote-image=ghcr.io/morganmlgman/corosync-qnetd:0.1.0 \
    interface=veth-qnetd envlists=qnetd mountlists=qnetd-nssdb \
    root-dir=usb1/qnetd/root logging=yes start-on-boot=yes comment=qnetd
/container start [find comment=qnetd]
```

## Proxmox

With `corosync-qdevice` installed on every node, from one node:

```sh
pvecm qdevice setup <container-ip>
```

## License

Copyright (C) 2026 MorganMLGman. [AGPL-3.0](LICENSE).

Thanks to [Ali-Shaikh/corosync-qnetd](https://github.com/Ali-Shaikh/corosync-qnetd) for the idea.

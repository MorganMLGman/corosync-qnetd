# corosync-qnetd

`corosync-qnetd` (the external vote for a two-node Proxmox cluster) as a
multi-arch image: `linux/amd64`, `linux/arm64`, `linux/arm/v7`. The `arm/v7`
build is the reason this repository exists — it runs as a container on 32-bit
ARM MikroTik routers such as the L009.

```
ghcr.io/morganmlgman/corosync-qnetd:latest
```

## Configuration

No secret is baked into the image: the CA is generated on first start.

| What | How |
|------|-----|
| Root SSH key (required) | a mounted `/root/.ssh/authorized_keys` (wins when both are given), or the `AUTHORIZED_KEYS` env var with several keys separated by `;` or newlines. Every line must be a public key or the container refuses to start. Whatever owner and mode the mounted file has, the entrypoint copies it to a root-owned file for sshd. It must be the **Proxmox node's** root key (`/root/.ssh/id_rsa.pub`): `pvecm qdevice setup` logs in with it |
| CA and node certificates | persist `/etc/corosync/qnetd/nssdb` — losing it silently stops the QDevice voting |
| Ports | 5403/tcp (qnetd), 22/tcp (only for `pvecm qdevice setup`) |

SSH is key-only; there is no password login. The container refuses to start
without a valid public key.

## Docker

```sh
docker run -d --name qnetd --restart unless-stopped \
  -p 22:22 -p 5403:5403 \
  -v qnetd-nssdb:/etc/corosync/qnetd/nssdb \
  -e AUTHORIZED_KEYS="$(ssh root@<pve-node> cat /root/.ssh/id_rsa.pub)" \
  ghcr.io/morganmlgman/corosync-qnetd:latest
```

Then, from one Proxmox node (all nodes need `corosync-qdevice` installed):

```sh
pvecm qdevice setup <container-ip>
```

## License

Copyright (C) 2026 MorganMLGman. [AGPL-3.0](LICENSE).

Thanks to [Ali-Shaikh/corosync-qnetd](https://github.com/Ali-Shaikh/corosync-qnetd) for the idea.

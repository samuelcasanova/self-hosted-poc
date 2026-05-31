# Self-Hosted Home Server

A Docker Compose-based home server stack. Planned services include NAS (SMB), Home Assistant, Pi-hole, and more.

## Services

### Samba (SMB file sharing)

Shares a local `./media` folder over the network using the SMB protocol.

- **Image**: `ghcr.io/servercontainers/samba`
- **Network**: host mode (required for SMB broadcast/discovery)
- **Share name**: `Media`
- **Credentials**: user `media`, password defined in `ACCOUNT_media`

### Nextcloud

Self-hosted file sync and sharing platform, backed by MariaDB.

- **Image**: `nextcloud`
- **URL**: `http://<server-ip>:8080`
- **Admin credentials**: defined in `NEXTCLOUD_ADMIN_USER` / `NEXTCLOUD_ADMIN_PASSWORD`
- **Media access**: `./media` is mounted at `/media` inside the container

### Pi-hole (DNS ad blocker)

Network-wide ad and tracker blocking via DNS. Point your router's DNS to this server and all devices benefit automatically.

- **Image**: `pihole/pihole`
- **Admin UI**: `http://<server-ip>/admin` (port 80, host network mode)
- **Admin password**: defined in `WEBPASSWORD`
- **DNS port**: 53 (TCP + UDP)
- **DHCP**: enabled, hands out addresses in the range defined by `DHCP_START`/`DHCP_END`
- **Upstream DNS**: Google (8.8.8.8 / 8.8.4.4) — change `PIHOLE_DNS_1/2` to your preference (e.g. 1.1.1.1 for Cloudflare)

#### Router configuration

Disable the DHCP server on your router and let Pi-hole take over:

1. Log into your router admin panel
2. Find the DHCP server settings and **disable** it
3. Pi-hole will now assign IPs and automatically set itself as the DNS server for all devices

#### DHCP range

Adjust these env vars to match your network:

| Variable | Default | Purpose |
|---|---|---|
| `DHCP_START` | `192.168.1.100` | First IP handed out |
| `DHCP_END` | `192.168.1.200` | Last IP handed out |
| `DHCP_ROUTER` | `192.168.1.1` | Your router/gateway IP |
> DHCP uses broadcast packets which cannot traverse Docker NAT, so Pi-hole runs with `network_mode: host`. The server's LAN IP is auto-detected from the network interface.

#### Exposing the media folder in Nextcloud

The media folder is available inside the container at `/media` but must be wired up via the **External Storage** app:

1. Log in as admin and go to **Apps** → enable **External storage support**
2. Go to **Administration settings** → **External storage**
3. Add a new storage: type `Local`, path `/media`, and grant access to the users you want
4. The folder will appear in those users' file browser

## Directory structure

```
.
├── docker-compose.yml
├── media/                          # Shared over SMB as \\<host-ip>\Media and mounted in Nextcloud at /media
├── ignored/
│   ├── nextcloud-db/               # MariaDB data
│   ├── nextcloud-data/             # Nextcloud app data
│   └── pihole/
│       ├── etc-pihole/             # Pi-hole config and blocklists
│       └── etc-dnsmasq.d/          # Custom DNS entries
└── README.md
```

## Usage

### Start all services

```bash
docker compose up -d
```

### Stop all services

```bash
docker compose down
```

### View logs

```bash
docker compose logs -f
```

## Connecting to the SMB share

| Client  | Address                        |
|---------|--------------------------------|
| Windows | `\\<server-ip>\Media`          |
| macOS   | `smb://<server-ip>/Media`      |
| Linux   | `smb://<server-ip>/Media`      |

Login with user `media` and the password set in `ACCOUNT_media`.

## Configuration

Credentials and share settings are controlled via environment variables in `docker-compose.yml`:

| Variable | Purpose |
|---|---|
| `ACCOUNT_<user>` | Sets the password for `<user>` |
| `UID_<user>` / `GID_<user>` | UID/GID the share files are owned by |
| `SAMBA_VOLUME_CONFIG_<name>` | Defines a share (name, path, permissions, valid users) |

## Prerequisites

- Docker and Docker Compose installed
- Ports 139 and 445 not already in use on the host

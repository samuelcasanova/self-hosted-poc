# Self-Hosted Home Server

A Docker Compose-based home server stack. Planned services include NAS (SMB), Home Assistant, Pi-hole, and more.

## Services

### Samba (SMB file sharing)

Shares a local `./media` folder over the network using the SMB protocol.

- **Image**: `ghcr.io/servercontainers/samba`
- **Network**: host mode (required for SMB broadcast/discovery)
- **Share name**: `Media`
- **Credentials**: user `media`, password defined in `ACCOUNT_media`

## Directory structure

```
.
├── docker-compose.yml
├── media/          # Put your media files here — shared over SMB as \\<host-ip>\Media
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

# Entrance-Installer

Bash installer for [Entrance](https://github.com/fcanlnony/Entrance).

This repository provides:

- `install.sh` to install or uninstall Entrance for the current user
- `systemd --user` service templates in `service/entrance.service` and `service/entrance-nocors.service`
- a desktop entry template in `service/entrance.desktop`

## What It Does

`./install.sh` or `./install.sh install` will:

- query the latest GitHub release for `fcanlnony/Entrance`
- prefer a `*.tar.xz` release asset when present
- fall back to the GitHub source tarball if the release has no `*.tar.xz` asset
- extract the release into `~/.entrance`
- create `~/.entrance/.data`
- create `~/.entrance/.data/auth_secret` if it does not already exist
- install Node.js dependencies with `npm ci --omit=dev` or `npm install --omit=dev`
- install both user services at `~/.config/systemd/user/entrance.service` and `~/.config/systemd/user/entrance-nocors.service`
- enable and start `entrance.service` by default
- install a desktop entry at `~/.local/share/applications/entrance.desktop`

`./install.sh --nocors` will do the same installation, but enable and start `entrance-nocors.service` instead.

`./install.sh uninstall` will:

- stop and disable both user services
- remove both user service files
- remove the desktop entry
- remove `~/.entrance`

## Runtime Layout

- Install directory: `~/.entrance`
- Data directory: `~/.entrance/.data`
- Auth secret file: `~/.entrance/.data/auth_secret`
- User service files: `~/.config/systemd/user/entrance.service`, `~/.config/systemd/user/entrance-nocors.service`
- Desktop file: `~/.local/share/applications/entrance.desktop`
- Desktop icon path: `~/.entrance/public/logo.png`

The service starts Entrance with this runtime setup:

```bash
export ENTRANCE_DATA_DIR="$(pwd)/.data"
export AUTH_SECRET="$(tr -d '\n' < ./.data/auth_secret)"
npm start
```

The service `WorkingDirectory` is `~/.entrance`, so `./.data` resolves to `~/.entrance/.data`.

## Requirements

- `bash`
- `curl`
- `tar`
- `openssl`
- `npm`
- `systemctl` with user service support

Optional:

- `update-desktop-database`
- `xdg-open`

## Usage

Install:

```bash
./install.sh
```

Install with CORS disabled:

```bash
./install.sh --nocors
```

Uninstall:

```bash
./install.sh uninstall
```

Check service status:

```bash
systemctl --user status entrance.service
systemctl --user status entrance-nocors.service
```

Restart the service:

```bash
systemctl --user restart entrance.service
systemctl --user restart entrance-nocors.service
```

View logs:

```bash
journalctl --user -u entrance.service -f
journalctl --user -u entrance-nocors.service -f
```

## Notes

- The desktop entry opens `http://localhost:3000` directly.
- The desktop entry icon is fixed to `~/.entrance/public/logo.png`.
- This installer is intended for per-user deployment and does not create a system-wide service.

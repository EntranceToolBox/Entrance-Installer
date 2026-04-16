# Entrance-Installer

Bash installer for [Entrance](https://github.com/fcanlnony/Entrance).

This repository provides:

- `install.sh` to install or uninstall Entrance for the current user
- a `systemd --user` service template in `service/entrance.service`
- a desktop entry template in `service/entrance.desktop`

## What It Does

`./install.sh install` will:

- query the latest GitHub release for `fcanlnony/Entrance`
- prefer a `*.tar.xz` release asset when present
- fall back to the GitHub source tarball if the release has no `*.tar.xz` asset
- extract the release into `~/.entrance`
- create `~/.entrance/.data`
- create `~/.entrance/.data/auth_secret` if it does not already exist
- install Node.js dependencies with `npm ci --omit=dev` or `npm install --omit=dev`
- install and start a user service at `~/.config/systemd/user/entrance.service`
- install a desktop entry at `~/.local/share/applications/entrance.desktop`

`./install.sh uninstall` will:

- stop and disable the user service
- remove the user service file
- remove the desktop entry
- remove `~/.entrance`

## Runtime Layout

- Install directory: `~/.entrance`
- Data directory: `~/.entrance/.data`
- Auth secret file: `~/.entrance/.data/auth_secret`
- User service file: `~/.config/systemd/user/entrance.service`
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
./install.sh install
```

Uninstall:

```bash
./install.sh uninstall
```

Check service status:

```bash
systemctl --user status entrance.service
```

Restart the service:

```bash
systemctl --user restart entrance.service
```

View logs:

```bash
journalctl --user -u entrance.service -f
```

## Notes

- The desktop entry opens `http://localhost:3000` directly.
- The desktop entry icon is fixed to `~/.entrance/public/logo.png`.
- This installer is intended for per-user deployment and does not create a system-wide service.

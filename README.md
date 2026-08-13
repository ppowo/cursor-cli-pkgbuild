# Local Cursor CLI PKGBUILD

This packages only Cursor's official **CLI** archive. It does not run or source
`https://cursor.com/install`.

The recipe is pinned to `2026.07.20-8cc9c0b` with a SHA-256 checksum. Cursor's
built-in auto-updater is disabled so updates stay under pacman control.

## Build without installing

```bash
cd /home/pun/MEGA/cursor-cli-pkgbuild
makepkg -s
```

You can inspect the resulting package before installing it:

```bash
bsdtar -tf cursor-cli-*.pkg.tar.zst
```

Install explicitly when ready:

```bash
sudo pacman -U cursor-cli-*.pkg.tar.zst
```

This installs the self-contained payload under `/opt/cursor-agent` and exposes
both `/usr/bin/agent` and `/usr/bin/cursor-agent`.

## Optional skills

`./link-skills.sh` clones the GitHub repos listed at the top of the script
into `/tmp`, checks that every listed skill path has a `SKILL.md`, then copies
those directories into `~/.cursor/skills/`. Edit `git_sources` and `skills` in
the script to change the set. It writes nothing under `$HOME` until lookup
succeeds, and it refuses to run as root.

```bash
./link-skills.sh
```

Restart `cursor-agent` afterwards. Re-running fetches again and replaces those
skill directories.

## Update to Cursor's latest release

```bash
./update.sh
makepkg -s
```

`update.sh` downloads Cursor's installer **as text only**, extracts the release
URL, downloads the x86_64 archive, validates its layout, and pins its checksum
in `PKGBUILD`. It never executes the installer or the Cursor binary. It also
removes archives left over from previous pins, keeping only the one referenced
by `PKGBUILD`.

A PKGBUILD cannot safely be "always latest" at build time: a moving download
would defeat checksum verification and reproducibility. The updater provides an
explicit refresh step instead. Cursor does not publish a signature for this
archive, so authenticity relies on HTTPS; the pinned checksum protects later
builds from unnoticed changes.

If Cursor was previously installed with its shell installer, a
`~/.local/bin/agent` symlink may shadow `/usr/bin/agent`. Check with:

```bash
type -a agent cursor-agent
```

This recipe currently targets x86_64 Arch Linux only.

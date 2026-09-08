# Echo Codex Arch package

The AUR recipe is in `PKGBUILD` and builds the Linux release from the EchoCodex
GitHub `main` branch.

On Arch or an Arch-based distribution:

```bash
makepkg -si
```

The package installs the app under `/opt/echo-codex` and provides the
`echo-codex` launcher command.

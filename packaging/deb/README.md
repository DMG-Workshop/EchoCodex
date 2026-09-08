# Echo Codex Debian package

Build an amd64 `.deb` from the repository root:

```bash
packaging/deb/build-deb.sh
```

The output is written to `dist/echo-codex_0.5.2~alpha.1-1_amd64.deb`.

Install locally with:

```bash
sudo apt install ./dist/echo-codex_0.5.2~alpha.1-1_amd64.deb
```

The package targets Debian and Ubuntu-family systems with GTK 3 and OpenGL/EGL. It
installs the Flutter bundle under `/opt/echo-codex`, an `echo-codex` launcher under
`/usr/bin`, the desktop entry, and the Echo Codex application icon.

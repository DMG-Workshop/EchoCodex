# Echo Codex Fedora package

Install the RPM and Flutter Linux build dependencies on Fedora:

```bash
sudo dnf install rpm-build patchelf clang cmake ninja-build pkgconf-pkg-config \
  gtk3-devel libstdc++-devel
```

With Flutter available on `PATH`, build an x86_64 RPM from the repository root:

```bash
packaging/fedora/build-rpm.sh
```

To rebuild only the RPM after a Linux release bundle already exists, use
`SKIP_FLUTTER_BUILD=1 packaging/fedora/build-rpm.sh`.

The script builds the Flutter Linux release, packages the bundle, desktop entry,
AppStream metadata, and icon, then writes the RPM to `dist/`. Install it with:

```bash
sudo dnf install ./dist/echo-codex-0.6.0-1*.x86_64.rpm
```

The app is installed under `/opt/echo-codex` and exposed as the `echo-codex`
command. The package accepts either Fedora's `ffmpeg-free` or RPM Fusion's
`ffmpeg` package through their shared `/usr/bin/ffmpeg` path.

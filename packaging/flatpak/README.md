# Echo Codex Flatpak

Build the release bundle from the app directory first:

```bash
cd app
flutter build linux --release
```

Then, from the repository root, build and install locally:

```bash
flatpak-builder --user --install --force-clean build/flatpak packaging/flatpak/com.dmgworkshop.echo_codex_app.yml
flatpak run com.dmgworkshop.echo_codex_app
```

The manifest targets the GNOME 50 runtime and grants microphone/audio access through
PipeWire/PulseAudio, Wayland/X11 display access, network access for user-selected AI
providers, and home-directory access for local recordings and imports.

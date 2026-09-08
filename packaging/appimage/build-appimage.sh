#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
app_dir="$repo_root/app"
out_dir="$repo_root/dist"
appdir="$out_dir/EchoCodex.AppDir"
output="$out_dir/EchoCodex-x86_64.AppImage"

appimagetool_bin="${APPIMAGETOOL:-appimagetool}"
if ! command -v "$appimagetool_bin" >/dev/null 2>&1 &&
  [[ ! -x "$appimagetool_bin" ]]; then
  echo 'appimagetool is required to create the final AppImage.' >&2
  echo 'Install it from https://github.com/AppImage/appimagetool/releases' >&2
  exit 2
fi

(
  cd "$app_dir"
  flutter build linux --release
)

rm -rf "$appdir" "$output"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
  "$appdir/usr/share/icons/hicolor/512x512/apps"
cp -a "$app_dir/build/linux/x64/release/bundle/." "$appdir/usr/bin/"
cp "$repo_root/packaging/flatpak/com.dmgworkshop.echo_codex_app.desktop" \
  "$appdir/usr/share/applications/com.dmgworkshop.echo_codex_app.desktop"
cp "$repo_root/packaging/flatpak/com.dmgworkshop.echo_codex_app.desktop" \
  "$appdir/com.dmgworkshop.echo_codex_app.desktop"
sed -i 's#^Exec=.*#Exec=echo_codex_app#' \
  "$appdir/usr/share/applications/com.dmgworkshop.echo_codex_app.desktop"
sed -i 's#^Exec=.*#Exec=echo_codex_app#' \
  "$appdir/com.dmgworkshop.echo_codex_app.desktop"
cp "$app_dir/icons/android-chrome-512x512.png" \
  "$appdir/usr/share/icons/hicolor/512x512/apps/com.dmgworkshop.echo_codex_app.png"
cp "$appdir/usr/share/icons/hicolor/512x512/apps/com.dmgworkshop.echo_codex_app.png" \
  "$appdir/com.dmgworkshop.echo_codex_app.png"
cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export PATH="$HERE/usr/bin:/usr/bin:/usr/local/bin:${PATH:-}"
exec "$HERE/usr/bin/echo_codex_app" "$@"
EOF
chmod +x "$appdir/AppRun"
"$appimagetool_bin" "$appdir" "$output"
printf 'Built %s\n' "$output"

#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
app_dir="$repo_root/app"
version="0.6.0-1"
arch="$(dpkg --print-architecture)"
package="echo-codex"
out_dir="$repo_root/dist"
stage="$out_dir/${package}_${version}_${arch}"
output="$out_dir/${package}_${version}_${arch}.deb"

flutter_bin="${FLUTTER_BIN:-flutter}"

rm -rf "$stage" "$output"
mkdir -p "$out_dir"
(
  cd "$app_dir"
  "$flutter_bin" build linux --release
)

bundle="$app_dir/build/linux/x64/release/bundle"
mkdir -p \
  "$stage/DEBIAN" \
  "$stage/opt/echo-codex" \
  "$stage/usr/bin" \
  "$stage/usr/share/applications" \
  "$stage/usr/share/icons/hicolor/512x512/apps"

cp -a "$bundle/." "$stage/opt/echo-codex/"
ln -s /opt/echo-codex/echo_codex_app "$stage/usr/bin/echo-codex"
cp "$repo_root/packaging/flatpak/com.dmgworkshop.echo_codex_app.desktop" \
  "$stage/usr/share/applications/com.dmgworkshop.echo_codex_app.desktop"
sed -i 's/^Exec=echo-codex$/Exec=\/usr\/bin\/echo-codex/' \
  "$stage/usr/share/applications/com.dmgworkshop.echo_codex_app.desktop"
cp "$app_dir/icons/android-chrome-512x512.png" \
  "$stage/usr/share/icons/hicolor/512x512/apps/com.dmgworkshop.echo_codex_app.png"

cat > "$stage/DEBIAN/control" <<EOF
Package: $package
Version: $version
Section: sound
Priority: optional
Architecture: $arch
Maintainer: DMG Workshop <hello@echocodex.xyz>
Homepage: https://echocodex.xyz
Depends: libc6, libgcc-s1, libstdc++6, libgtk-3-0 | libgtk-3-0t64, libgl1, libegl1, libasound2 | libasound2t64, ffmpeg
Description: Private recordings turned into structured notes
 Echo Codex records speech and turns it into structured notes, tasks,
 timelines, and calendar exports using AI providers selected by the user.
EOF

cat > "$stage/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
EOF
chmod 755 "$stage/DEBIAN/postinst"

fakeroot dpkg-deb --build --root-owner-group "$stage" "$output"
printf 'Built %s\n' "$output"

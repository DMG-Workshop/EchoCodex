#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
app_dir="$repo_root/app"
package="echo-codex"
version=$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' \
  "$app_dir/pubspec.yaml")
release="${RPM_RELEASE:-1}"
out_dir="$repo_root/dist"
topdir="$out_dir/rpm-build"
source_dir="$topdir/SOURCES/${package}-${version}"
source_archive="$topdir/SOURCES/${package}-${version}.tar.gz"

flutter_bin="${FLUTTER_BIN:-flutter}"
skip_flutter_build="${SKIP_FLUTTER_BUILD:-0}"

if [ -z "$version" ]; then
  echo 'Could not read the package version from app/pubspec.yaml.' >&2
  exit 2
fi
if [ "$(uname -m)" != "x86_64" ]; then
  echo 'The Fedora package currently targets x86_64 hosts.' >&2
  exit 2
fi
if [ "$skip_flutter_build" != "1" ] && \
  ! command -v "$flutter_bin" >/dev/null 2>&1; then
  echo 'Flutter is required to build the Linux release bundle.' >&2
  exit 2
fi
if ! command -v rpmbuild >/dev/null 2>&1; then
  echo 'rpmbuild is required. On Fedora, run: sudo dnf install rpm-build' >&2
  exit 2
fi

rm -rf "$topdir"
mkdir -p "$source_dir/bundle" "$topdir/BUILD" "$topdir/BUILDROOT" \
  "$topdir/RPMS" "$topdir/SRPMS"

bundle="$app_dir/build/linux/x64/release/bundle"
if [ "$skip_flutter_build" = "1" ]; then
  if [ ! -x "$bundle/echo_codex_app" ]; then
    echo 'SKIP_FLUTTER_BUILD=1 requires an existing Linux release bundle.' >&2
    exit 2
  fi
else
  (
    cd "$app_dir"
    "$flutter_bin" build linux --release
  )
fi

cp -a "$bundle/." "$source_dir/bundle/"
cp "$repo_root/packaging/flatpak/com.dmgworkshop.echo_codex_app.desktop" \
  "$source_dir/com.dmgworkshop.echo_codex_app.desktop"
cp "$repo_root/packaging/flatpak/com.dmgworkshop.echo_codex_app.metainfo.xml" \
  "$source_dir/com.dmgworkshop.echo_codex_app.metainfo.xml"
cp "$app_dir/icons/android-chrome-512x512.png" \
  "$source_dir/com.dmgworkshop.echo_codex_app.png"
cp "$repo_root/LICENSE" "$source_dir/LICENSE"
tar -C "$topdir/SOURCES" -czf "$source_archive" \
  "${package}-${version}"

rpmbuild -bb "$repo_root/packaging/fedora/echo-codex.spec" \
  --define "_topdir $topdir" \
  --define "app_version $version" \
  --define "app_release $release"

set -- "$topdir/RPMS/x86_64/${package}-${version}-${release}"*.x86_64.rpm
if [ ! -f "$1" ]; then
  echo 'rpmbuild completed without producing the expected x86_64 RPM.' >&2
  exit 1
fi

cp "$1" "$out_dir/"
printf 'Built %s/%s\n' "$out_dir" "$(basename -- "$1")"

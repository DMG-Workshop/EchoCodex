%{!?app_version:%global app_version 0.6.0}
%{!?app_release:%global app_release 1}

Name:           echo-codex
Version:        %{app_version}
Release:        %{app_release}%{?dist}
Summary:        Private recordings turned into structured notes

License:        MIT
URL:            https://echocodex.xyz
Source0:        %{name}-%{version}.tar.gz

BuildArch:      x86_64
BuildRequires:  patchelf
Requires:       alsa-lib
Requires:       gtk3
Requires:       libglvnd-egl
Requires:       libglvnd-glx
Requires:       /usr/bin/ffmpeg

%description
Echo Codex records speech and turns it into structured notes, tasks,
timelines, and calendar exports using AI providers selected by the user.

%prep
%autosetup

%build

%install
install -dm755 %{buildroot}/opt/echo-codex
cp -a bundle/. %{buildroot}/opt/echo-codex/
find %{buildroot}/opt/echo-codex/lib -maxdepth 1 -type f -name '*.so' \
  -exec patchelf --set-rpath '$ORIGIN' {} +
install -dm755 %{buildroot}%{_bindir}
ln -s /opt/echo-codex/echo_codex_app \
  %{buildroot}%{_bindir}/echo-codex
install -Dm644 com.dmgworkshop.echo_codex_app.desktop \
  %{buildroot}%{_datadir}/applications/com.dmgworkshop.echo_codex_app.desktop
sed -i 's/^Exec=echo-codex$/Exec=\/usr\/bin\/echo-codex/' \
  %{buildroot}%{_datadir}/applications/com.dmgworkshop.echo_codex_app.desktop
install -Dm644 com.dmgworkshop.echo_codex_app.metainfo.xml \
  %{buildroot}%{_datadir}/metainfo/com.dmgworkshop.echo_codex_app.metainfo.xml
install -Dm644 com.dmgworkshop.echo_codex_app.png \
  %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/com.dmgworkshop.echo_codex_app.png

%files
%license LICENSE
/opt/echo-codex
%{_bindir}/echo-codex
%{_datadir}/applications/com.dmgworkshop.echo_codex_app.desktop
%{_datadir}/metainfo/com.dmgworkshop.echo_codex_app.metainfo.xml
%{_datadir}/icons/hicolor/512x512/apps/com.dmgworkshop.echo_codex_app.png

%changelog
* Sat Sep 12 2026 DMG Workshop <hello@echocodex.xyz> - 0.6.0-1
- Add the Fedora RPM package.

# Echo Codex AppImage

Build from the repository root:

```bash
packaging/appimage/build-appimage.sh
```

The script builds the Linux release bundle, creates an AppDir, and invokes
`appimagetool`. Install `appimagetool` first if it is not available:

https://github.com/AppImage/appimagetool/releases

The output is written to `dist/EchoCodex-x86_64.AppImage`.

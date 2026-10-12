#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_version="2.4.2366"
case "$(uname -m)" in
  arm64) task_arch=arm64; task_sha=3b269855928070253a4d9f7c4a57d9ff99d0272102410233c459b02a732e87e7 ;;
  x86_64) task_arch=x64; task_sha=18768b2e3b7fb25bf3eff9e4b4b14b6235b2dfea320701ab172ea7f902eeb97e ;;
  *) echo "Unsupported architecture" >&2; exit 1 ;;
esac
task_cache="$task_root/.support"
task_archive="$task_cache/Suwayomi-Server-v$task_version-macOS-$task_arch.tar.gz"
task_runtime="$task_cache/Suwayomi-Server-v$task_version-macOS-$task_arch"
mkdir -p "$task_cache" "$task_root/dist"
if [[ ! -f "$task_archive" ]] || [[ "$(shasum -a 256 "$task_archive" | cut -d ' ' -f 1)" != "$task_sha" ]]; then
  curl -fL -C - --retry 5 --retry-delay 2 --retry-all-errors -o "$task_archive" "https://github.com/Suwayomi/Suwayomi-Server/releases/download/v$task_version/$(basename "$task_archive")"
fi
if [[ "$(shasum -a 256 "$task_archive" | cut -d ' ' -f 1)" != "$task_sha" ]]; then
  echo "Runtime checksum mismatch. Remove the cached archive and retry." >&2
  exit 1
fi
tar -xzf "$task_archive" -C "$task_cache"
swift build --package-path "$task_root/macos" -c release
task_binary_dir="$(swift build --package-path "$task_root/macos" -c release --show-bin-path)"
task_app="$task_root/dist/Mihon Mac.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources/Runtime" "$task_app/Contents/Resources/Licenses"
cp "$task_binary_dir/MihonMac" "$task_app/Contents/MacOS/MihonMac"
ditto "$task_runtime/jre" "$task_app/Contents/Resources/Runtime/jre"
cp "$task_runtime/bin/Suwayomi-Server.jar" "$task_app/Contents/Resources/Runtime/Suwayomi-Server.jar"
python3 "$task_root/macos/scripts/build-bootstrap.py" "$task_app/Contents/Resources/Runtime/MihonEngine.class"
cp "$task_root/LICENSE" "$task_app/Contents/Resources/Licenses/Mihon-Apache-2.0.txt"
cp "$task_root/macos/THIRD_PARTY_NOTICES.md" "$task_app/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"
task_license="$task_cache/Suwayomi-MPL-2.0.txt"
task_license_sha=3f3d9e0024b1921b067d6f7f88deb4a60cbe7a78e76c64e3f1d7fc3b779b9d04
if [[ ! -f "$task_license" ]] || [[ "$(shasum -a 256 "$task_license" | cut -d ' ' -f 1)" != "$task_license_sha" ]]; then
  curl -fsSL --connect-timeout 20 --max-time 60 --retry 3 "https://raw.githubusercontent.com/Suwayomi/Suwayomi-Server/40bc5da57820324ed0ae724cbbc020cc4673b594/LICENSE" -o "$task_license"
fi
if [[ "$(shasum -a 256 "$task_license" | cut -d ' ' -f 1)" != "$task_license_sha" ]]; then
  echo "License checksum mismatch." >&2
  exit 1
fi
cp "$task_license" "$task_app/Contents/Resources/Licenses/Suwayomi-MPL-2.0.txt"
cat > "$task_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MihonMac</string>
<key>CFBundleIdentifier</key><string>io.github.aaangeelo.mihon-mac</string>
<key>CFBundleName</key><string>Mihon Mac</string>
<key>CFBundleDisplayName</key><string>Mihon Mac</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.books</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
swift "$task_root/macos/scripts/make-icon.swift" "$task_app/Contents/Resources"
codesign --force --deep --sign - "$task_app"
codesign --verify --deep --strict "$task_app"
task_stage="$(mktemp -d "$task_cache/dmg-stage.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT
ditto "$task_app" "$task_stage/Mihon Mac.app"
ln -s /Applications "$task_stage/Applications"
hdiutil create -volname "Mihon Mac" -srcfolder "$task_stage" -format UDZO -ov "$task_root/dist/MihonMac-0.1.0-$task_arch.dmg"
echo "Built: $task_app"
echo "Installer: $task_root/dist/MihonMac-0.1.0-$task_arch.dmg"

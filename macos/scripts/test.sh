#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$task_root/.support"
swiftc "$task_root/macos/Sources/MihonMac/API.swift" "$task_root/macos/Sources/MihonMac/Models.swift" "$task_root/macos/Sources/MihonMac/LocalComicImport.swift" "$task_root/macos/checks/APIChecks.swift" -o "$task_root/.support/API-checks"
"$task_root/.support/API-checks"
python3 "$task_root/macos/scripts/smoke-test.py" "$task_root/dist/Mihon Mac.app/Contents/Resources/Runtime"

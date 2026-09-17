#!/bin/bash
# Equivalent native execution of actual client/authentication sources and XCTest doubles.
# No Apple service, Keychain, production URL or model request is executed by these tests.
set -euo pipefail
set +x
umask 077
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
private_build="$repo_root/build/coach-runtime-client"
mkdir -p "$private_build/Sources" "$private_build/Tests"
export CLANG_MODULE_CACHE_PATH="$private_build/module-cache"
python3 - "$repo_root" "$private_build" <<'PY'
from pathlib import Path
import sys,os
root=Path(sys.argv[1]);package=Path(sys.argv[2]);app=root/'ios/RepToday/RepToday'
sources=[]
for directory in ['Models','Services/Engine','Services/Consistency']:
 sources+=list((app/directory).glob('*.swift'))
sources+=[app/p for p in ['Services/Protocols/ServiceProtocols.swift','Services/Progress/ProgressAnalytics.swift',
 'Services/Coach/CoachAnalyticsInsight.swift','Services/Coach/CoachContextBundle.swift',
 'Services/Coach/CoachProxyClient.swift','Services/Coach/CoachRuntimeAuthentication.swift',
 'Services/Coach/CoachSyntheticFixtures.swift','ViewModels/CoachSyntheticQAViewModel.swift','Utilities/AppState.swift']]
tests=[root/'ios/RepToday/RepTodayTests'/p for p in ['CoachProxyClientTests.swift','CoachProxyClientConfiguredTests.swift','CoachRuntimeAuthenticationTests.swift','CoachSyntheticQAViewModelTests.swift','CoachContextBundleTests.swift']]
for directory,files in [('Sources',sources),('Tests',tests)]:
 for source in files:
  link=package/directory/source.name
  if link.is_symlink(): link.unlink()
  elif link.exists(): raise SystemExit('stopped: unexpected native test source entry')
  link.symlink_to(source)
(package/'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package=Package(name:"RepTodayCoachRuntime",platforms:[.macOS(.v14)],targets:[
 .target(name:"RepToday",path:"Sources"),
 .testTarget(name:"RepTodayTests",dependencies:["RepToday"],path:"Tests")])
''')
PY
xcrun swift test --package-path "$private_build" --cache-path "$private_build/cache" \
    --scratch-path "$private_build/scratch" -Xswiftc -module-cache-path -Xswiftc "$private_build/module-cache"

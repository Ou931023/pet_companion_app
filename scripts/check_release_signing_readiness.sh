#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'OK: %s\n' "$1"
}

require_file() {
  [[ -f "$1" ]] || fail "Missing required file: $1"
  pass "Found $1"
}

require_file ".gitignore"
require_file "android/app/build.gradle.kts"
require_file "ios/Runner.xcodeproj/project.pbxproj"
require_file "docs/RELEASE_SIGNING.md"
require_file "docs/STORE_SUBMISSION_RUNBOOK.md"

git check-ignore -q android/key.properties ||
  fail "android/key.properties must be ignored by git"
pass "android/key.properties is gitignored"

for pattern in "*.jks" "*.keystore" "*.p12" "*.p8" "*.cer" "*.mobileprovision"; do
  if git ls-files -- "$pattern" "**/$pattern" | grep -q .; then
    fail "Tracked signing secret pattern found: $pattern"
  fi
done
pass "No tracked signing key or certificate files"

if git ls-files -- "android/key.properties" | grep -q .; then
  fail "android/key.properties is tracked; remove it from git and rotate secrets if needed"
fi
pass "android/key.properties is not tracked"

if [[ -f android/key.properties ]]; then
  pass "android/key.properties exists locally; contents were not read"
else
  printf 'WARN: android/key.properties is not present locally; Android release build will fail-fast until owner provides it.\n'
fi

grep -q 'rootProject.file("key.properties")' android/app/build.gradle.kts ||
  fail "Android release signing must read android/key.properties"
grep -q 'Missing Android release signing config' android/app/build.gradle.kts ||
  fail "Android release signing must fail-fast when required values are missing"
grep -q 'signingConfigs.getByName("release")' android/app/build.gradle.kts ||
  fail "Android release build type must use release signing config"
if grep -q 'signingConfig = signingConfigs.getByName("debug")' android/app/build.gradle.kts; then
  fail "Android release build must not use debug signing"
fi
pass "Android release signing wiring is production-safe"

grep -q 'PRODUCT_BUNDLE_IDENTIFIER = tw.edu.ncyu.im.aicompanion' ios/Runner.xcodeproj/project.pbxproj ||
  fail "iOS Bundle ID must be tw.edu.ncyu.im.aicompanion"
grep -q 'CODE_SIGN_STYLE = Automatic' ios/Runner.xcodeproj/project.pbxproj ||
  fail "iOS project should keep explicit signing style for Xcode archive"
grep -q 'DEVELOPMENT_TEAM' ios/Runner.xcodeproj/project.pbxproj ||
  fail "iOS project should have a Development Team configured"
pass "iOS signing metadata is present; App Store distribution still requires Xcode/App Store Connect validation"

grep -q 'flutter build appbundle --release' docs/STORE_SUBMISSION_RUNBOOK.md ||
  fail "Store runbook must include Android release build command"
grep -q 'flutter build ipa --release' docs/STORE_SUBMISSION_RUNBOOK.md ||
  fail "Store runbook must include iOS release build command"
grep -q 'aicompanion.support@gmail.com' docs/STORE_SUBMISSION_RUNBOOK.md ||
  fail "Store runbook must include official support email"
pass "Store runbook contains release build commands"

printf 'Release signing readiness checks completed.\n'

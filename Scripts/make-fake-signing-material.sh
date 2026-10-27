#!/usr/bin/env bash
#
# make-fake-signing-material.sh —— 生成一份「假的」证书与描述文件，
# 专门用来在没有 Apple 账号时自测 sign-ipa.sh 的机械流程
# （解描述文件 → 提取 entitlements → 导入钥匙串 → codesign → 校验）。
#
# 产出的东西只在本机自测用，签名不具备任何真实权限。
#
set -euo pipefail

OUT="${1:-build/portal}"
mkdir -p "$OUT" build

TEAM_ID="${TEAM_ID:-97792VH57A}"
APP_BUNDLE="${APP_BUNDLE:-com.god.fitstate}"
WIDGET_BUNDLE="${WIDGET_BUNDLE:-com.god.fitstate.widget}"
GROUP="${GROUP:-group.97792VH57A.com.god.fitstate}"
P12_PW="fitstate"

# --- 一把自签证书，p12 / 描述文件 / 指纹三处共用 ---
openssl req -x509 -newkey rsa:2048 -keyout build/sign-key.pem -out build/sign-cert.pem \
  -days 3650 -nodes -subj "/CN=FitState Self Test" >/dev/null 2>&1

openssl pkcs12 -export -inkey build/sign-key.pem -in build/sign-cert.pem \
  -out "$OUT/portal.p12" -passout "pass:$P12_PW" -name "FitState Self Test" >/dev/null 2>&1
cp build/sign-cert.pem "$OUT/portal.cer"
echo "FAKE_P12 $OUT/portal.p12"
echo "FAKE_CER $OUT/portal.cer"

CERT_DER_B64=$(openssl x509 -in build/sign-cert.pem -outform DER | base64 | tr -d '\n')

# --- 假描述文件：结构和真的一模一样，含 healthkit 与 app groups ---
make_profile() {  # $1=输出文件  $2=bundle id
  local out="$1" bundle="$2"
  local now exp uuid
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  exp=$(date -u -v+7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)
  uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')

  cat > build/fake-profile.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AppIDName</key><string>FitState Self Test</string>
  <key>ApplicationIdentifierPrefix</key><array><string>${TEAM_ID}</string></array>
  <key>CreationDate</key><date>${now}</date>
  <key>Platform</key><array><string>iOS</string></array>
  <key>DeveloperCertificates</key><array><data>${CERT_DER_B64}</data></array>
  <key>Entitlements</key>
  <dict>
    <key>application-identifier</key><string>${TEAM_ID}.${bundle}</string>
    <key>com.apple.developer.team-identifier</key><array><string>${TEAM_ID}</string></array>
    <key>get-task-allow</key><true/>
    <key>keychain-access-groups</key><array><string>${TEAM_ID}.${bundle}</string></array>
    <key>com.apple.developer.healthkit</key><true/>
    <key>com.apple.developer.healthkit.access</key><array/>
    <key>com.apple.security.application-groups</key><array><string>${GROUP}</string></array>
  </dict>
  <key>ExpirationDate</key><date>${exp}</date>
  <key>Name</key><string>FitState Self Test</string>
  <key>ProvisionedDevices</key><array><string>00008140-00166C2636D2801C</string></array>
  <key>ProvisionsAllDevices</key><false/>
  <key>TeamIdentifier</key><array><string>${TEAM_ID}</string></array>
  <key>TeamName</key><string>FitState Self Test</string>
  <key>TimeToLive</key><integer>7</integer>
  <key>UUID</key><string>${uuid}</string>
  <key>Version</key><integer>1</integer>
</dict>
</plist>
PLIST

  # 描述文件本身也要有 CMS 签名
  openssl smime -sign -in build/fake-profile.plist -outform DER -nodetach -binary \
    -signer build/sign-cert.pem -inkey build/sign-key.pem -out "$out" >/dev/null 2>&1
  echo "FAKE_PROFILE $out"
}

make_profile "$OUT/com.god.fitstate.mobileprovision" "$APP_BUNDLE"
make_profile "$OUT/com.god.fitstate.widget.mobileprovision" "$WIDGET_BUNDLE"

cat > "$OUT/manifest.json" <<JSON
{
  "team_id": "${TEAM_ID}",
  "app_group": "${GROUP}",
  "healthkit_enabled": true,
  "p12": "portal.p12",
  "cer": "portal.cer",
  "targets": [
    {
      "bundle_id": "${APP_BUNDLE}",
      "profile": "com.god.fitstate.mobileprovision",
      "entitlements": {},
      "provisioned_devices": ["00008140-00166C2636D2801C"]
    },
    {
      "bundle_id": "${WIDGET_BUNDLE}",
      "profile": "com.god.fitstate.widget.mobileprovision",
      "entitlements": {},
      "provisioned_devices": ["00008140-00166C2636D2801C"]
    }
  ]
}
JSON

echo "FAKE_MANIFEST $OUT/manifest.json"

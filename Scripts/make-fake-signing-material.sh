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

# --- 自签证书 + 私钥，打包成 p12 ---
openssl req -x509 -newkey rsa:2048 -keyout build/fake-key.pem -out build/fake-cert.pem \
  -days 3650 -nodes -subj "/CN=FitState Self Test" >/dev/null 2>&1
openssl pkcs12 -export -inkey build/fake-key.pem -in build/fake-cert.pem \
  -out "$OUT/portal.p12" -passout "pass:$P12_PW" -name "FitState Self Test" >/dev/null 2>&1
rm -f build/fake-key.pem build/fake-cert.pem
echo "FAKE_P12 $OUT/portal.p12"

# --- 假描述文件：结构和真的长得一模一样，含 healthkit 与 app groups ---
make_profile() {  # $1=输出文件  $2=bundle id
  local out="$1" bundle="$2"
  local now exp uuid cert_b64
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  exp=$(date -u -v+7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)
  uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
  cert_b64=$(openssl req -x509 -newkey rsa:2048 -keyout build/tmp-key.pem -out build/tmp-cert.pem \
    -days 3650 -nodes -subj "/CN=FitState Profile" >/dev/null 2>&1; \
    openssl x509 -in build/tmp-cert.pem -outform DER | base64 | tr -d '\n')
  rm -f build/tmp-key.pem build/tmp-cert.pem

  cat > build/fake-profile.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AppIDName</key><string>FitState Self Test</string>
  <key>ApplicationIdentifierPrefix</key><array><string>${TEAM_ID}</string></array>
  <key>CreationDate</key><date>${now}</date>
  <key>Platform</key><array><string>iOS</string></array>
  <key>DeveloperCertificates</key><array><data>${cert_b64}</data></array>
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

  openssl smime -sign -in build/fake-profile.plist -outform DER -nodetach -binary \
    -signer build/fake-sign.pem -inkey build/fake-sign-key.pem -out "$out" >/dev/null 2>&1
  echo "FAKE_PROFILE $out"
}

# 描述文件本身也要有签名（Apple 的就是 CMS 签名），这里用刚才那把自签证书
openssl req -x509 -newkey rsa:2048 -keyout build/fake-sign-key.pem -out build/fake-sign.pem \
  -days 3650 -nodes -subj "/CN=FitState Self Test Signer" >/dev/null 2>&1

make_profile "$OUT/com.god.fitstate.mobileprovision" "$APP_BUNDLE"
make_profile "$OUT/com.god.fitstate.widget.mobileprovision" "$WIDGET_BUNDLE"

cat > "$OUT/manifest.json" <<JSON
{
  "team_id": "${TEAM_ID}",
  "app_group": "${GROUP}",
  "healthkit_enabled": true,
  "p12": "portal.p12",
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

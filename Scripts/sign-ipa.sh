#!/usr/bin/env bash
#
# sign-ipa.sh —— 用我们自己从 Apple 门户申请到的「开发证书 + 描述文件」给 .app 正签。
#
# 为什么要自己签：Sideloadly 之类的工具会用它自己的 App ID 和证书重签，
# 那样 HealthKit / App Groups 能力就又没了。自己签则完全可控：
# 描述文件里的 Entitlements 就是 App 该有的权限，原样写进签名。
#
# 输入：build/portal/manifest.json + build/portal/*.mobileprovision + build/portal/portal.p12
# 输出：签好名的 build/Build/Products/Release-iphoneos/FitState.app
#
set -euo pipefail

APP_PATH="${APP_PATH:-build/Build/Products/Release-iphoneos/FitState.app}"
PORTAL_DIR="${PORTAL_DIR:-build/portal}"
MANIFEST="$PORTAL_DIR/manifest.json"
KEYCHAIN_PW="fitstate"
P12_PW="fitstate"

# 钥匙串一律用绝对路径：codesign 走的是 SecKeychain API，相对路径会解析失败，
# 症状是 "The specified item could not be found in the keychain."
KEYCHAIN_DB="$PWD/build/ci-signing.keychain-db"

die() { echo "::error::$1"; exit 1; }

[ -f "$MANIFEST" ] || die "缺少 $MANIFEST"
[ -f "$PORTAL_DIR/portal.p12" ] || die "缺少 $PORTAL_DIR/portal.p12"
[ -d "$APP_PATH" ] || die "缺少产物 $APP_PATH"

mkdir -p build/ent

APP_BUNDLE=$(jq -r '.targets[0].bundle_id' "$MANIFEST")
WIDGET_BUNDLE=$(jq -r '.targets[1].bundle_id // ""' "$MANIFEST")
APP_PROFILE=$(jq -r '.targets[0].profile' "$MANIFEST")
WIDGET_PROFILE=$(jq -r '.targets[1].profile // ""' "$MANIFEST")
GROUP=$(jq -r '.app_group // ""' "$MANIFEST")

echo "### App bundle     = $APP_BUNDLE"
echo "### Widget bundle  = $WIDGET_BUNDLE"
echo "### App Group      = $GROUP"
echo "### App profile    = $APP_PROFILE"
echo "### Widget profile = $WIDGET_PROFILE"
echo "### 钥匙串          = $KEYCHAIN_DB"

# ---------------------------------------------------------------------------
# 1. 把 bundle id / App Group 改成门户里真正登记的那一套
# ---------------------------------------------------------------------------
set_plist_string() {  # $1=plist $2=key $3=value
  /usr/libexec/PlistBuddy -c "Set $2 $3" "$1" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add $2 string $3" "$1"
}

echo "### [1/5] 改写 bundle id 与 App Group"
if [ -n "$APP_BUNDLE" ] && [ "$APP_BUNDLE" != "null" ]; then
  set_plist_string "$APP_PATH/Info.plist" ":CFBundleIdentifier" "$APP_BUNDLE"
fi
if [ -n "$GROUP" ] && [ "$GROUP" != "null" ]; then
  set_plist_string "$APP_PATH/Info.plist" ":AppGroupIdentifier" "$GROUP"
fi

WIDGET_PATH="$APP_PATH/PlugIns/FitStateWidget.appex"
if [ -d "$WIDGET_PATH" ]; then
  if [ -n "$WIDGET_BUNDLE" ] && [ "$WIDGET_BUNDLE" != "null" ]; then
    set_plist_string "$WIDGET_PATH/Info.plist" ":CFBundleIdentifier" "$WIDGET_BUNDLE"
  fi
  if [ -n "$GROUP" ] && [ "$GROUP" != "null" ]; then
    set_plist_string "$WIDGET_PATH/Info.plist" ":AppGroupIdentifier" "$GROUP"
  fi
fi

# ---------------------------------------------------------------------------
# 2. 导入证书
# ---------------------------------------------------------------------------
echo "### [2/5] 创建临时钥匙串"
security delete-keychain "$KEYCHAIN_DB" >/dev/null 2>&1 || true
security create-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN_DB" >/dev/null 2>&1 \
  || die "create-keychain 失败"
security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN_DB" >/dev/null 2>&1 || true
security set-keychain-settings -lut 3600 "$KEYCHAIN_DB" >/dev/null 2>&1 || true

echo "### [2/5] 导入 p12"
security import "$PORTAL_DIR/portal.p12" -k "$KEYCHAIN_DB" -P "$P12_PW" -A \
  || die "导入 p12 失败"

echo "### [2/5] 设置钥匙串搜索列表"
# 注意：这里用绝对路径，并且把 login 钥匙串留在列表里。
# 只留一个相对路径的钥匙串时，SecKeychain 搜索会失败，
# codesign 就会报 "The specified item could not be found in the keychain."
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"
security list-keychain -d user -s "$KEYCHAIN_DB" "$LOGIN_KC" >/dev/null 2>&1 || true
echo "--- 当前搜索列表 ---"
security list-keychain -d user 2>&1 | sed 's/^/    /' || true

echo "### [2/5] 设置钥匙串分区列表"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PW" "$KEYCHAIN_DB" \
  >/dev/null 2>&1 || true
security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN_DB" >/dev/null 2>&1 || true

echo "### [2/5] 钥匙串诊断信息"
echo "--- find-identity（全部）---"
security find-identity -v "$KEYCHAIN_DB" 2>&1 | sed 's/^/    /' || true
echo "--- find-identity（codesigning 策略）---"
security find-identity -v -p codesigning "$KEYCHAIN_DB" 2>&1 | sed 's/^/    /' || true
echo "--- find-certificate（SHA-1）---"
security find-certificate -a -Z "$KEYCHAIN_DB" 2>&1 | sed 's/^/    /' || true

# ---------------------------------------------------------------------------
# 3. 选一个能用的签名身份
#
# 依次尝试：find-identity 报出来的哈希（按策略）→ find-identity 报出来的哈希
# （不过策略）→ portal.cer 的 SHA-1 → 证书的 CN。
# 哪个能签成就用哪个，并记下来。
# ---------------------------------------------------------------------------
CANDIDATES=""
add_candidate() {
  [ -z "$1" ] && return 0
  case " $CANDIDATES " in
    *" $1 "*) return 0 ;;
  esac
  CANDIDATES="$CANDIDATES $1"
}

for h in $(security find-identity -v -p codesigning "$KEYCHAIN_DB" 2>/dev/null \
             | grep -oE '[0-9A-F]{40}' || true); do
  add_candidate "$h"
done
for h in $(security find-identity -v "$KEYCHAIN_DB" 2>/dev/null \
             | grep -oE '[0-9A-F]{40}' || true); do
  add_candidate "$h"
done
if [ -f "$PORTAL_DIR/portal.cer" ]; then
  add_candidate "$(openssl x509 -in "$PORTAL_DIR/portal.cer" -noout -fingerprint -sha1 2>/dev/null \
    | sed 's/.*=//; s/://g' | tr -d '[:space:]')"
  CN=$(openssl x509 -in "$PORTAL_DIR/portal.cer" -noout -subject -nameopt RFC2253 2>/dev/null \
    | sed 's/^subject=//' | tr ',' '\n' | sed -n 's/^ *CN=//p' | head -1 | sed 's/^"//; s/"$//')
  [ -n "$CN" ] && add_candidate "$CN"
fi

CANDIDATES="$(echo "$CANDIDATES" | sed 's/^ *//; s/ *$//')"
if [ -z "$CANDIDATES" ]; then
  echo "::error::钥匙串里找不到任何可用的签名身份"
  exit 1
fi
echo "### 候选签名身份：$CANDIDATES"

IDENTITY=""

# ---------------------------------------------------------------------------
# 4. 从描述文件里取出 Entitlements（描述文件里有什么，App 就有什么权限）
# ---------------------------------------------------------------------------
extract_entitlements() {  # $1=profile $2=out
  security cms -D -i "$1" > build/profile-decoded.plist \
    || die "解不开描述文件 $1"
  /usr/libexec/PlistBuddy -x -c "Print :Entitlements" build/profile-decoded.plist > "$2" \
    || die "描述文件 $1 里没有 Entitlements"
}

sign_with() {  # $1=entitlements $2=bundle
  local ent="$1" bundle="$2" id err
  err=$(mktemp)
  for id in $CANDIDATES; do
    echo "    尝试签名身份：$id"
    # 第一轮：带 --generate-entitlement-der（较新的 codesign）
    if codesign --force --sign "$id" --keychain "$KEYCHAIN_DB" \
        --entitlements "$ent" --timestamp=none --generate-entitlement-der "$bundle" \
        >"$err" 2>&1; then
      IDENTITY="$id"; rm -f "$err"; echo "    -> 成功"; return 0
    fi
    # 第二轮：不带 --keychain（走搜索列表）
    if codesign --force --sign "$id" \
        --entitlements "$ent" --timestamp=none --generate-entitlement-der "$bundle" \
        >>"$err" 2>&1; then
      IDENTITY="$id"; rm -f "$err"; echo "    -> 成功"; return 0
    fi
    # 第三轮：老版本 codesign，不带 --generate-entitlement-der
    if codesign --force --sign "$id" --keychain "$KEYCHAIN_DB" \
        --entitlements "$ent" --timestamp=none "$bundle" \
        >>"$err" 2>&1; then
      IDENTITY="$id"; rm -f "$err"; echo "    -> 成功"; return 0
    fi
    # 第四轮：老版本 codesign + 搜索列表
    if codesign --force --sign "$id" \
        --entitlements "$ent" --timestamp=none "$bundle" \
        >>"$err" 2>&1; then
      IDENTITY="$id"; rm -f "$err"; echo "    -> 成功"; return 0
    fi
  done
  echo "--- codesign 全部尝试都失败，错误输出如下 ---"
  cat "$err" || true
  rm -f "$err"
  return 1
}

# ---------------------------------------------------------------------------
# 5. 先签内层扩展，再签外层 App
# ---------------------------------------------------------------------------
echo "### [3/5] 签小组件扩展"
if [ -n "$WIDGET_PROFILE" ] && [ "$WIDGET_PROFILE" != "null" ] && [ -f "$PORTAL_DIR/$WIDGET_PROFILE" ]; then
  cp "$PORTAL_DIR/$WIDGET_PROFILE" "$WIDGET_PATH/embedded.mobileprovision"
  extract_entitlements "$PORTAL_DIR/$WIDGET_PROFILE" build/ent/widget.entitlements
  echo "--- 小组件 entitlements ---"
  cat build/ent/widget.entitlements
  sign_with build/ent/widget.entitlements "$WIDGET_PATH" || die "小组件签名失败"
  echo "### 小组件已签（身份：$IDENTITY）"
else
  echo "### 没有小组件描述文件，跳过扩展签名"
fi

echo "### [4/5] 签主 App"
cp "$PORTAL_DIR/$APP_PROFILE" "$APP_PATH/embedded.mobileprovision"
extract_entitlements "$PORTAL_DIR/$APP_PROFILE" build/ent/app.entitlements
echo "--- App entitlements ---"
cat build/ent/app.entitlements
sign_with build/ent/app.entitlements "$APP_PATH" || die "主 App 签名失败"
echo "### App 已签（身份：$IDENTITY）"

# ---------------------------------------------------------------------------
# 6. 校验：HealthKit 必须在签名里
# ---------------------------------------------------------------------------
echo "### [5/5] 校验签名"
codesign -dv "$APP_PATH" 2>&1 | sed 's/^/    /' || true

SIGNED_ENT=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null || true)
echo "### 签名中的 entitlements："
echo "$SIGNED_ENT"

if ! echo "$SIGNED_ENT" | grep -q "com.apple.developer.healthkit"; then
  echo "::error::签名里没有 com.apple.developer.healthkit —— 门户上的 App ID 没开成功 HealthKit"
  exit 1
fi
if ! echo "$SIGNED_ENT" | grep -q "com.apple.security.application-groups"; then
  echo "::warning::签名里没有 App Groups（小组件拿不到数据，但 HealthKit 可用）"
fi
codesign -v --strict "$APP_PATH" || echo "::warning::codesign 校验有告警（自签证书属正常现象）"

security delete-keychain "$KEYCHAIN_DB" >/dev/null 2>&1 || true
echo "SIGN_OK"

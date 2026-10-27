#!/usr/bin/env ruby
# frozen_string_literal: true

#
# apple-portal.rb —— 用 Apple 开发者门户接口，为「免费个人团队」的 App ID
# 开启 HealthKit / App Groups 能力，并生成真正带这些能力的开发证书与描述文件。
#
# 关键点：能力（capability）是挂在 **App ID** 上的，不是挂在签名工具上的。
# 只要门户里的 App ID 勾上了 HealthKit，之后任何工具为这个 App ID 申请的
# 描述文件都会带上 com.apple.developer.healthkit，App 签名里也就有了这项权限。
# 所以免费账号也能做到——不需要 Apple Developer Program。
#
# 用法（GitHub Actions 里）：
#   APPLE_ID=... APP_SPECIFIC_PASSWORD=... ruby Scripts/apple-portal.rb
#
# 环境变量：
#   APPLE_ID                 Apple ID 邮箱
#   APP_SPECIFIC_PASSWORD    Apple 专用密码（appleid.apple.com 生成，免二次验证）
#   TARGET_APP_BUNDLE_ID     主 App 的 bundle id（默认 com.god.fitstate）
#   TARGET_WIDGET_BUNDLE_ID  小组件扩展的 bundle id（默认 com.god.fitstate.widget）
#   APP_GROUP_ID             要注册的 App Group（默认 group.<TeamID>.com.god.fitstate）
#   DEVICE_UDID              设备 UDID
#   TEAM_ID                  已知的 Team ID（可选，用于构造候选 identifier）
#   OUT_DIR                  产物目录（默认 build/portal）
#   DO_PROFILE               1 = 同时创建证书与描述文件（默认 1）
#
# 产物：
#   <OUT_DIR>/portal.p12            开发证书（含私钥，PKCS#12）
#   <OUT_DIR>/<bundleid>.mobileprovision   每个 bundle id 一份描述文件
#   <OUT_DIR>/manifest.json         清单：bundle id → 描述文件 / entitlements
#

require 'json'
require 'openssl'
require 'base64'
require 'fileutils'

APPLE_ID  = ENV.fetch('APPLE_ID')
PASSWORD  = ENV.fetch('APP_SPECIFIC_PASSWORD')
OUT_DIR   = ENV.fetch('OUT_DIR', 'build/portal')
TEAM_ID   = ENV['TEAM_ID'].to_s
DEVICE_UDID = ENV.fetch('DEVICE_UDID', '00008140-00166C2636D2801C')
APP_BUNDLE    = ENV.fetch('TARGET_APP_BUNDLE_ID', 'com.god.fitstate')
WIDGET_BUNDLE = ENV.fetch('TARGET_WIDGET_BUNDLE_ID', 'com.god.fitstate.widget')
DO_PROFILE   = ENV.fetch('DO_PROFILE', '1') == '1'

FileUtils.mkdir_p(OUT_DIR)

def log(msg)
  puts "[portal] #{msg}"
  $stdout.flush
end

def fail_hard(msg)
  log "FATAL #{msg}"
  exit 1
end

require 'spaceship'

# --------------------------------------------------------------------------
# 登录
# --------------------------------------------------------------------------
client = Spaceship::PortalClient.login(APPLE_ID, PASSWORD)
team = begin
  client.team_information || {}
rescue StandardError
  {}
end
log "LOGIN_OK team=#{client.team_id} name=#{team['name']} type=#{team['type']}"
log "FREE_TEAM=#{team['type'].to_s.downcase.include?('free') ? 'YES' : 'NO'}"

TEAM_ID = client.team_id if TEAM_ID.empty?

# --------------------------------------------------------------------------
# 列出已有 App ID
# --------------------------------------------------------------------------
apps = Spaceship::Portal::App.all(mac: false)
log "APPID_COUNT #{apps.count}"
apps.each do |a|
  log "APPID id=#{a.app_id} identifier=#{a.bundle_id} name=#{a.name} prefix=#{a.prefix} services=#{a.enable_services.inspect}"
end

# --------------------------------------------------------------------------
# 找出（或创建）我们要用的两个 App ID
#
# 免费个人团队的 identifier 有好几种写法，先按后缀匹配已存在的，
# 匹配不到再按几种候选形式去建。
# --------------------------------------------------------------------------
def candidate_identifiers(base, team_id)
  list = []
  list << base
  list << "#{team_id}.#{base}" unless team_id.empty?
  list << "#{base}.#{team_id}" unless team_id.empty?
  list
end

def find_app(apps, base, team_id)
  cands = candidate_identifiers(base, team_id)
  apps.each do |a|
    ident = a.bundle_id.to_s
    return a if cands.include?(ident)
  end
  # 退一步：只要 identifier 里包含我们的基名就算
  apps.find { |a| a.bundle_id.to_s.include?(base) }
end

def ensure_app(apps, base, team_id, display_name)
  existing = find_app(apps, base, team_id)
  if existing
    log "APPID_FOUND #{base} -> #{existing.bundle_id} (id=#{existing.app_id})"
    return existing
  end

  candidate_identifiers(base, team_id).each do |ident|
    begin
      created = Spaceship::Portal::App.create!(bundle_id: ident, name: display_name, mac: false)
      log "APPID_CREATED #{base} -> #{created.bundle_id} (id=#{created.app_id})"
      apps << created
      return created
    rescue StandardError => e
      log "APPID_CREATE_FAIL #{ident} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    end
  end
  log "APPID_MISSING #{base}"
  nil
end

app    = ensure_app(apps, APP_BUNDLE,    TEAM_ID, 'FitState')
widget = ensure_app(apps, WIDGET_BUNDLE, TEAM_ID, 'FitState Widget')
fail_hard("找不到主 App 的 App ID（#{APP_BUNDLE}）") if app.nil?

# --------------------------------------------------------------------------
# 用户组（App Groups）
# --------------------------------------------------------------------------
group_id = ENV['APP_GROUP_ID'].to_s
group_id = "group.#{TEAM_ID}.#{APP_BUNDLE}" if group_id.empty?

group = begin
  Spaceship::Portal::AppGroup.find(group_id)
rescue StandardError
  nil
end
if group.nil?
  group = begin
    Spaceship::Portal::AppGroup.create!(group_id: group_id, name: 'FitState Group')
    log "APP_GROUP_CREATED #{group.group_id}"
  rescue StandardError => e
    log "APP_GROUP_CREATE_FAIL #{group_id} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    nil
  end
else
  log "APP_GROUP_EXISTS #{group.group_id}"
end

# --------------------------------------------------------------------------
# 开启能力：HealthKit（主 App）+ App Groups（两个都要）
# --------------------------------------------------------------------------
def enable_service(app, service, label)
  app.update_service(service)
  log "SERVICE_OK #{label} #{app.bundle_id}"
  true
rescue StandardError => e
  log "SERVICE_FAIL #{label} #{app.bundle_id} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
  false
end

health_ok = enable_service(app, Spaceship::Portal::AppService::HealthKit, 'HealthKit')
enable_service(widget, Spaceship::Portal::AppService::AppGroup, 'AppGroup') if widget

if group
  [app, widget].compact.each do |a|
    begin
      a.associate_groups([group])
      log "GROUP_ASSIGNED #{a.bundle_id} <- #{group.group_id}"
    rescue StandardError => e
      log "GROUP_ASSIGN_FAIL #{a.bundle_id} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    end
  end
end

# 回读一遍，确认能力真的挂上了
[app, widget].compact.each do |a|
  begin
    d = a.details
    log "DETAIL #{a.bundle_id} services=#{d.enable_services.inspect} groups=#{d.associated_groups.map { |g| g.group_id }.inspect}"
  rescue StandardError => e
    log "DETAIL_FAIL #{a.bundle_id} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
  end
end

# --------------------------------------------------------------------------
# 设备
# --------------------------------------------------------------------------
device = begin
  Spaceship::Portal::Device.find_by_udid(DEVICE_UDID)
rescue StandardError
  nil
end
if device.nil?
  device = begin
    Spaceship::Portal::Device.create!(name: 'God iPhone', udid: DEVICE_UDID)
    log "DEVICE_CREATED #{device.udid} id=#{device.id}"
  rescue StandardError => e
    log "DEVICE_CREATE_FAIL #{DEVICE_UDID} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    nil
  end
else
  log "DEVICE_EXISTS #{device.udid} id=#{device.id}"
end

# --------------------------------------------------------------------------
# 证书 + 描述文件
# --------------------------------------------------------------------------
manifest = {
  'team_id' => TEAM_ID,
  'app_group' => group&.group_id,
  'healthkit_enabled' => health_ok,
  'targets' => []
}

if DO_PROFILE
  # 证书：免费团队一般发 "Apple Development"（83Q87W3TGH），退路是老式 Development（5QPB9NHCEI）
  csr, key = Spaceship::Portal::Certificate.create_certificate_signing_request
  cert = nil
  [Spaceship::Portal::Certificate::AppleDevelopment, Spaceship::Portal::Certificate::Development].each do |klass|
    begin
      cert = klass.create!(csr: csr, bundle_id: app.bundle_id)
      log "CERT_CREATED #{klass} id=#{cert.id} name=#{cert.name}"
      break
    rescue StandardError => e
      log "CERT_FAIL #{klass} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    end
  end

  if cert.nil?
    log 'CERT_MISSING —— 描述文件无法创建'
  else
    # 下载证书内容（DER），和私钥一起打包成 p12
    begin
      pem = client.download_certificate(cert.id, cert.type_display_id, mac: false)
      x509 = OpenSSL::X509::Certificate.new(pem)
      p12 = OpenSSL::PKCS12.new('fitstate', 'FitState Development', key, x509)
      p12_path = File.join(OUT_DIR, 'portal.p12')
      File.binwrite(p12_path, p12.serialize)
      log "P12_WRITTEN #{p12_path} #{File.size(p12_path)} bytes"
      manifest['p12'] = 'portal.p12'
    rescue StandardError => e
      log "P12_FAIL #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    end

    # 每个 bundle id 一份描述文件
    [app, widget].compact.each do |a|
      begin
        profile = Spaceship::Portal::ProvisioningProfile.create!(
          name: "FitState #{a.bundle_id} Dev",
          bundle_id: a.bundle_id,
          certificate: cert,
          devices: device ? [device] : []
        )
        data = profile.download
        safe = a.bundle_id.gsub(/[^A-Za-z0-9._-]/, '_')
        path = File.join(OUT_DIR, "#{safe}.mobileprovision")
        File.binwrite(path, data)
        log "PROFILE_WRITTEN #{path} #{File.size(path)} bytes"

        # 从描述文件里读出真实的 entitlements 和设备列表
        plist = data.to_s
        ent = {}
        dev = []
        if (m = plist.match(/<key>Entitlements<\/key>\s*<dict>(.*?)<\/dict>/m))
          body = m[1]
          body.scan(/<key>([^<]+)<\/key>\s*(?:<string>([^<]*)<\/string>|<array>(.*?)<\/array>|<true\/>|<false\/>)/m) do |k, sv, av|
            if av
              ent[k] = av.scan(/<string>([^<]*)<\/string>/m).flatten
            elsif sv
              ent[k] = sv
            else
              ent[k] = true
            end
          end
        end
        if (m = plist.match(/<key>ProvisionedDevices<\/key>\s*<array>(.*?)<\/array>/m))
          dev = m[1].scan(/<string>([^<]*)<\/string>/m).flatten
        end
        manifest['targets'] << {
          'bundle_id' => a.bundle_id,
          'profile' => File.basename(path),
          'entitlements' => ent,
          'provisioned_devices' => dev
        }
        log "PROFILE_ENTITLEMENTS #{a.bundle_id} #{ent.inspect}"
      rescue StandardError => e
        log "PROFILE_FAIL #{a.bundle_id} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
      end
    end
  end
else
  [app, widget].compact.each do |a|
    manifest['targets'] << { 'bundle_id' => a.bundle_id, 'profile' => nil, 'entitlements' => {} }
  end
end

File.write(File.join(OUT_DIR, 'manifest.json'), JSON.pretty_generate(manifest))
log "MANIFEST_WRITTEN #{File.join(OUT_DIR, 'manifest.json')}"
log 'PORTAL_DONE'

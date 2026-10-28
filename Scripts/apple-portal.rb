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
# 为什么全部用原始接口（不直接用 spaceship 的高层方法）：
#   免费个人团队在门户里有一批「列表」接口会返回
#   "Access Unavailable — only for developers enrolled in a developer program"，
#   而 spaceship 的 App.create! / ProvisioningProfile.create! 内部都要先列一次，
#   一失败整条链路就断了。所以这里全部走 services-account 的原始 action，
#   并且每个「写」操作都不依赖任何「读」操作。
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
#   <OUT_DIR>/portal.p12                 开发证书（含私钥，PKCS#12）
#   <OUT_DIR>/portal.cer                 证书本体（签名脚本靠它的 SHA-1 指纹定位身份）
#   <OUT_DIR>/<bundleid>.mobileprovision 每个 bundle id 一份描述文件
#   <OUT_DIR>/manifest.json              清单：bundle id → 描述文件 / entitlements
#

require 'json'
require 'openssl'
require 'base64'
require 'fileutils'
require 'tempfile'

APPLE_ID  = ENV.fetch('APPLE_ID')
PASSWORD  = ENV.fetch('APP_SPECIFIC_PASSWORD')
OUT_DIR   = ENV.fetch('OUT_DIR', 'build/portal')
TEAM_ID_ENV = ENV['TEAM_ID'].to_s
DEVICE_UDID = ENV.fetch('DEVICE_UDID', '00008140-00166C2636D2801C')
APP_BUNDLE = ENV.fetch('TARGET_APP_BUNDLE_ID', 'com.god.fitstate')
WIDGET_BUNDLE = ENV.fetch('TARGET_WIDGET_BUNDLE_ID', 'com.god.fitstate.widget')
DO_PROFILE = ENV.fetch('DO_PROFILE', '1') == '1'
GROUP_ID_ENV = ENV['APP_GROUP_ID'].to_s

# 门户里代表这两项能力的 featureType
HEALTHKIT_FEATURE = 'HK421J6T7P'
APPGROUP_FEATURE  = 'APG3427HIY'

# 证书类型：优先用现代的 Apple Development，退回老式 Development
CERT_TYPE_APPLE_DEV = '83Q87W3TGH'
CERT_TYPE_DEV       = '5QPB9NHCEI'

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
#
# spaceship 有两条登录路径：
#   1. SIRP（默认，2023 年 Apple 改的）——密码先做 PBKDF2 再走挑战应答
#   2. legacy pre-SIRP（FASTLANE_USE_LEGACY_PRE_SIRP_AUTH=1）——直接 POST 明文密码
# App 专用密码在 legacy 路径上是被接受的，而 SIRP 路径对某些账号会莫名其妙 401。
# 所以两条都试，先 legacy 后 SIRP。
# --------------------------------------------------------------------------
def login_with_strategy(name)
  if name == 'legacy'
    ENV['FASTLANE_USE_LEGACY_PRE_SIRP_AUTH'] = '1'
  else
    ENV.delete('FASTLANE_USE_LEGACY_PRE_SIRP_AUTH')
  end
  Spaceship::PortalClient.login(APPLE_ID, PASSWORD)
end

# --------------------------------------------------------------------------
# 登录探针用的补丁
#
# 关键是要拿到 Apple 回应的 body —— 401 时 spaceship 会把 body 吞掉，
# 只抛一个 "Unauthorized Access"，看不出到底是密码错、hashcash 缺失还是被限流。
# --------------------------------------------------------------------------
module Spaceship
  class Client
    attr_accessor :probe_last_response

    alias_method :orig_handle_error, :handle_error
    def handle_error(response)
      self.probe_last_response = response
      body = response.respond_to?(:body) ? response.body.to_s : ''
      if body.include?('serviceErrors') || body.include?('message')
        puts "[portal] RAW_ERROR status=#{response.status} body=#{body[0, 700]}"
      end
      orig_handle_error(response)
    end

    alias_method :orig_request, :request
    def request(method, url_or_path = nil, params = nil, headers = {}, auto_paginate = false, &block)
      resp = orig_request(method, url_or_path, params, headers, auto_paginate, &block)
      u = url_or_path.to_s
      if u.include?('signin') && resp.respond_to?(:body)
        puts "[portal] RAW #{method.to_s.upcase} #{u} -> #{resp.status} #{resp.body.to_s[0, 500]}"
      end
      resp
    end

    alias_method :orig_fetch_hashcash, :fetch_hashcash
    def fetch_hashcash
      hc = orig_fetch_hashcash
      puts "[portal] PROBE_HASHCASH #{hc.nil? ? 'NIL（Apple 没给 hashcash 头）' : 'OK'}"
      hc
    end
  end
end

def raw_login_probe
  begin
    probe = Spaceship::PortalClient.new
    log "PROBE_WIDGET_KEY #{probe.itc_service_key.inspect}"
  rescue StandardError => e
    log "PROBE_WIDGET_KEY_FAIL #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
  end

  probe = nil
  begin
    probe = Spaceship::PortalClient.new
    resp = probe.do_sirp(APPLE_ID, PASSWORD, nil)
    log "PROBE_SIRP status=#{resp.status} body=#{resp.body.to_s[0, 800]}"
  rescue StandardError => e
    r = probe&.probe_last_response
    if r
      log "PROBE_SIRP status=#{r.status} body=#{r.body.to_s[0, 800]}"
    else
      log "PROBE_SIRP_FAIL #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    end
  end

  probe = nil
  begin
    probe = Spaceship::PortalClient.new
    ENV['FASTLANE_USE_LEGACY_PRE_SIRP_AUTH'] = '1'
    resp = probe.perform_login_method(APPLE_ID, PASSWORD, nil)
    log "PROBE_LEGACY status=#{resp.status} body=#{resp.body.to_s[0, 800]}"
  rescue StandardError => e
    r = probe&.probe_last_response
    if r
      log "PROBE_LEGACY status=#{r.status} body=#{r.body.to_s[0, 800]}"
    else
      log "PROBE_LEGACY_FAIL #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    end
  ensure
    ENV.delete('FASTLANE_USE_LEGACY_PRE_SIRP_AUTH')
  end
end

ENV['SPACESHIP_SKIP_2FA_UPGRADE'] = '1'

client = nil

# --- 会话模式 -----------------------------------------------------------
# GitHub Actions 的共享 runner IP 调 idmsa.apple.com 的 POST 偶尔会被 Apple 挡回 503，
# 所以备用方案是：在自己机器上登录一次拿到 myacinfo 会话 cookie，
# 塞进 APPLE_SESSION 环境变量，CI 直接复用这个会话，不再碰 idmsa 登录。
#
# additional_headers 会被合并进每一个请求头；我们的 cookie jar 是空的，
# 不会覆盖这个显式 Cookie 头。
session = ENV['APPLE_SESSION'].to_s.strip
if !session.empty?
  begin
    client = Spaceship::PortalClient.new
    client.additional_headers = { 'Cookie' => session }
    log "SESSION_MODE 复用外部会话 cookie（长度 #{session.length}）"
  rescue StandardError => e
    log "SESSION_MODE_FAIL #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    client = nil
  end
end

if client.nil?
  ['legacy', 'sirp'].each do |strategy|
    begin
      client = login_with_strategy(strategy)
      log "LOGIN_OK strategy=#{strategy}"
      break
    rescue StandardError => e
      log "LOGIN_FAIL strategy=#{strategy} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    end
  end
end

if client.nil?
  raw_login_probe
  fail_hard('门户登录失败（两种策略都不行）')
end

# --------------------------------------------------------------------------
# 门户原始接口封装
#
# 关键：CSRF token 来自任意一次响应的头。spaceship 的 ensure_csrf 在列表接口
# 失败前会先把 csrf_tokens 清空，导致后续原始请求也带上不了 token。
# 所以这里自己保存一份登录后的 token，必要时恢复。
# --------------------------------------------------------------------------
class Portal
  def initialize(client)
    @client = client
    @csrf_backup = read_csrf
    log "CSRF_INIT #{@csrf_backup.inspect}"
  end

  def read_csrf
    if @client.respond_to?(:csrf_tokens)
      @client.csrf_tokens
    else
      @client.send(:csrf_tokens)
    end
  rescue StandardError
    nil
  end

  def write_csrf(value)
    if @client.respond_to?(:csrf_tokens=)
      @client.csrf_tokens = value
    else
      @client.send(:csrf_tokens=, value)
    end
  rescue StandardError
    nil
  end

  def restore_csrf!
    current = read_csrf
    return if current.is_a?(Array) && current.compact.size == 2

    write_csrf(@csrf_backup) if @csrf_backup
    log "CSRF_RESTORED #{read_csrf.inspect}"
  end

  def team_id
    @client.team_id
  end

  def raw(method, path, params)
    restore_csrf!
    @client.send(:request, method, path, params)
  end

  def post(path, params)
    handle(raw(:post, path, params), path)
  end

  def get(path, params)
    handle(raw(:get, path, params), path)
  end

  def handle(resp, path)
    body = resp.body.to_s

    # 免费个人账号最常见的两种拒绝，明确抛出来，日志一眼能看懂
    if body.include?('Access Unavailable') || body.include?('enrolled in a developer program')
      raise "ACCESS_UNAVAILABLE #{path} :: #{body[0, 400]}"
    end

    unless resp.success?
      raise "HTTP #{resp.status} #{path} :: #{body[0, 400]}"
    end

    data = begin
      JSON.parse(body)
    rescue StandardError
      body
    end

    if data.is_a?(Hash)
      if data.key?('resultCode') && data['resultCode'].to_s != '0'
        raise "RESULT_CODE #{data['resultCode']} #{path} :: #{data.inspect[0, 400]}"
      end
      msgs = data['messages'] || data['validationMessages']
      log "PORTAL_MESSAGES #{path} :: #{msgs.inspect[0, 300]}" if msgs.is_a?(Array) && !msgs.empty?
    end
    data
  end
end

portal = Portal.new(client)

# --------------------------------------------------------------------------
# 团队（Team）
# --------------------------------------------------------------------------
TEAM_ID = begin
  tid = portal.team_id
  tid = tid.to_s.strip
  tid.empty? ? nil : tid
rescue StandardError => e
  log "TEAM_ID_VIA_PORTAL_FAIL #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
  nil
end

if TEAM_ID.nil? || TEAM_ID.empty?
  TEAM_ID = TEAM_ID_ENV
  log "TEAM_ID_FROM_ENV #{TEAM_ID}"
else
  log "TEAM_ID_FROM_PORTAL #{TEAM_ID}"
end

if TEAM_ID.nil? || TEAM_ID.empty?
  # 最后的退路：从 olympus 会话里反查
  begin
    data = client.user_details_data
    tid = data.dig('provider', 'providerId') || data.dig('provider', 'publicProviderId')
    TEAM_ID = tid.to_s unless tid.to_s.empty?
    log "TEAM_ID_VIA_OLYMPUS #{TEAM_ID}"
  rescue StandardError => e
    log "TEAM_ID_VIA_OLYMPUS_FAIL #{e.class}"
  end
end

fail_hard('拿不到 Team ID') if TEAM_ID.nil? || TEAM_ID.empty?

begin
  team = client.team_information || {}
  log "TEAM_INFO name=#{team['name']} type=#{team['type']}"
  log "FREE_TEAM=#{team['type'].to_s.downcase.include?('free') ? 'YES' : 'NO'}"
rescue StandardError => e
  log "TEAM_INFO_FAIL #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
end

# --------------------------------------------------------------------------
# App ID
# --------------------------------------------------------------------------
def candidate_identifiers(base, team_id)
  list = [base]
  list << "#{team_id}.#{base}" unless team_id.to_s.empty?
  list << "#{base}.#{team_id}" unless team_id.to_s.empty?
  list.uniq
end

# 列表接口在免费账号上可能被拒；拿不到就当空列表，后面靠创建 + 回读。
def list_app_ids(portal, team_id)
  data = portal.post('account/ios/identifiers/listAppIds.action', {
                      teamId: team_id, pageNumber: 1, pageSize: 100, sort: 'name=asc'
                    })
  list = data.is_a?(Hash) ? (data['appIds'] || []) : []
  log "APPID_LIST_COUNT #{list.count}"
  list.each do |a|
    log "APPID id=#{a['appIdId']} identifier=#{a['identifier']} name=#{a['name']}"
  end
  list
rescue StandardError => e
  log "APPID_LIST_FAIL #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
  []
end

def create_app_id(portal, team_id, identifier, name)
  data = portal.post('account/ios/identifiers/addAppId.action', {
                      name: name, teamId: team_id, type: 'explicit', identifier: identifier
                    })
  app = data.is_a?(Hash) ? (data['appId'] || data) : {}
  log "APPID_CREATED identifier=#{app['identifier']} id=#{app['appIdId']}"
  app
rescue StandardError => e
  log "APPID_CREATE_FAIL #{identifier} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
  nil
end

def get_app_detail(portal, team_id, app_id)
  data = portal.post('account/ios/identifiers/getAppIdDetail.action', {
                      teamId: team_id, appIdId: app_id
                    })
  data.is_a?(Hash) ? (data['appId'] || data) : {}
rescue StandardError => e
  log "APPID_DETAIL_FAIL #{app_id} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
  {}
end

apps = list_app_ids(portal, TEAM_ID)

def find_app(apps, base, team_id, must_include: nil, must_exclude: nil)
  cands = candidate_identifiers(base, team_id)
  apps.each do |a|
    ident = a['identifier'].to_s
    return a if cands.any? { |c| c.casecmp(ident).zero? }
  end
  apps.each do |a|
    ident = a['identifier'].to_s
    next unless ident.include?(base)
    next if must_exclude && ident.include?(must_exclude)
    next if must_include && !ident.include?(must_include)
    return a
  end
  nil
end

def ensure_app(portal, apps, team_id, base, display_name, must_include: nil, must_exclude: nil)
  existing = find_app(apps, base, team_id, must_include: must_include, must_exclude: must_exclude)
  if existing
    log "APPID_FOUND #{base} -> #{existing['identifier']} (id=#{existing['appIdId']})"
    return existing
  end

  candidate_identifiers(base, team_id).each do |ident|
    created = create_app_id(portal, team_id, ident, display_name)
    next if created.nil? || created['appIdId'].to_s.empty?

    apps << created
    return created
  end

  log "APPID_MISSING #{base}"
  nil
end

app    = ensure_app(portal, apps, TEAM_ID, APP_BUNDLE,    'FitState',        must_exclude: 'widget')
widget = ensure_app(portal, apps, TEAM_ID, WIDGET_BUNDLE, 'FitState Widget', must_include: 'widget')
fail_hard("建不出主 App 的 App ID（#{APP_BUNDLE}）") if app.nil?

# --------------------------------------------------------------------------
# 开启能力：HealthKit（主 App）+ App Groups（两个都要）
# --------------------------------------------------------------------------
def enable_service(portal, team_id, app, feature_type, label)
  portal.post('account/ios/identifiers/updateService.action', {
                teamId: team_id,
                displayId: app['appIdId'],
                featureType: feature_type,
                featureValue: 'on'
              })
  log "SERVICE_OK #{label} #{app['identifier']}"
  true
rescue StandardError => e
  log "SERVICE_FAIL #{label} #{app['identifier']} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
  false
end

health_ok = enable_service(portal, TEAM_ID, app, HEALTHKIT_FEATURE, 'HealthKit')
enable_service(portal, TEAM_ID, widget, APPGROUP_FEATURE, 'AppGroup') if widget

# --------------------------------------------------------------------------
# 用户组（App Groups）
# --------------------------------------------------------------------------
group_id = GROUP_ID_ENV
if group_id.to_s.empty?
  group_id = "group.#{TEAM_ID}.#{APP_BUNDLE}"
else
  # 免费个人团队的 App Group 标识符必须带 Team ID 前缀，
  # 也就是 group.<TeamID>.xxx —— 不带前缀门户会直接拒收。
  # 这里统一纠正成标准形式，别名（group.com.god.fitstate）也能吃。
  suffix = group_id.to_s.sub(/\Agroup\./, '')
  suffix = suffix.sub(/\A#{Regexp.escape(TEAM_ID)}\./, '')
  expected = "group.#{TEAM_ID}.#{suffix}"
  if expected != group_id
    log "APP_GROUP_RENAME #{group_id} -> #{expected}"
    group_id = expected
  end
end

group_app_id = nil
begin
  data = portal.post('account/ios/identifiers/addApplicationGroup.action', {
                      name: 'FitState Group', identifier: group_id, teamId: TEAM_ID
                    })
  grp = data.is_a?(Hash) ? (data['applicationGroup'] || {}) : {}
  group_app_id = grp['applicationGroup']
  log "APP_GROUP_ADD identifier=#{grp['identifier']} id=#{group_app_id}"
rescue StandardError => e
  log "APP_GROUP_ADD_FAIL #{group_id} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
end

# 组早就建过的话，add 会返回「已存在」而不是对象，再列一次兜底。
if group_app_id.nil?
  begin
    data = portal.post('account/ios/identifiers/listApplicationGroups.action', {
                        teamId: TEAM_ID, pageNumber: 1, pageSize: 100, sort: 'name=asc'
                      })
    list = data.is_a?(Hash) ? (data['applicationGroupList'] || []) : []
    hit = list.find { |g| g['identifier'].to_s == group_id }
    group_app_id = hit['applicationGroup'] if hit
    log "APP_GROUP_LIST hit=#{!hit.nil?} id=#{group_app_id} count=#{list.count}"
  rescue StandardError => e2
    log "APP_GROUP_LIST_FAIL #{e2.class}: #{e2.message.to_s.lines.first.to_s.strip}"
  end
end

if group_app_id
  [app, widget].compact.each do |a|
    begin
      portal.post('account/ios/identifiers/assignApplicationGroupToAppId.action', {
                    teamId: TEAM_ID,
                    appIdId: a['appIdId'],
                    displayId: a['appIdId'],
                    applicationGroups: [group_id]
                  })
      log "GROUP_ASSIGNED #{a['identifier']} <- #{group_id}"
    rescue StandardError => e
      log "GROUP_ASSIGN_FAIL #{a['identifier']} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    end
  end
end

# 回读一遍，确认能力真的挂上了
[app, widget].compact.each do |a|
  d = get_app_detail(portal, TEAM_ID, a['appIdId'])
  features = d['features'].is_a?(Hash) ? d['features'].keys : []
  log "DETAIL #{a['identifier']} features=#{features.inspect} groups=#{d['associatedApplicationGroups'].inspect}"
end

# --------------------------------------------------------------------------
# 设备
# --------------------------------------------------------------------------
device_id = nil
begin
  data = portal.post('account/ios/device/addDevices.action', {
                      teamId: TEAM_ID,
                      deviceClasses: 'iphone',
                      deviceNumbers: DEVICE_UDID,
                      deviceNames: 'God iPhone',
                      register: 'single'
                    })
  devs = data.is_a?(Hash) ? (data['devices'] || []) : []
  device_id = devs.first['deviceId'] if devs.first
  log "DEVICE_ADD ok id=#{device_id}"
rescue StandardError => e
  log "DEVICE_ADD_FAIL #{DEVICE_UDID} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
end

# 设备可能早就注册过（Sideloadly 之类的工具会顺手注册），addDevices 会返回
# 「已存在」的提示而不是 devices 数组，所以再列一次兜底。
if device_id.nil?
  begin
    data = portal.post('account/ios/device/listDevices.action', {
                        teamId: TEAM_ID, pageNumber: 1, pageSize: 100,
                        sort: 'name=asc', includeRemovedDevices: false
                      })
    devs = data.is_a?(Hash) ? (data['devices'] || []) : []
    hit = devs.find { |d| d['deviceNumber'].to_s == DEVICE_UDID }
    device_id = hit['deviceId'] if hit
    log "DEVICE_LIST hit=#{!hit.nil?} id=#{device_id} count=#{devs.count}"
  rescue StandardError => e2
    log "DEVICE_LIST_FAIL #{e2.class}: #{e2.message.to_s.lines.first.to_s.strip}"
  end
end

# --------------------------------------------------------------------------
# 证书 + 描述文件
# --------------------------------------------------------------------------
manifest = {
  'team_id' => TEAM_ID,
  'app_group' => group_id,
  'healthkit_enabled' => health_ok,
  'targets' => []
}

def parse_profile_plist(xml)
  Tempfile.create(['fitstate-profile', '.plist']) do |f|
    f.binmode
    f.write(xml)
    f.flush
    out = `plutil -convert json -o - "#{f.path}" 2>/dev/null`
    return JSON.parse(out) if $?.success? && !out.to_s.strip.empty?
  end
  {}
rescue StandardError => e
  log "PLIST_PARSE_FAIL #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
  {}
end

if DO_PROFILE
  # --- CSR ---
  key = OpenSSL::PKey::RSA.new(2048)
  csr = OpenSSL::X509::Request.new
  csr.version = 0
  csr.subject = OpenSSL::X509::Name.new([
                                        ['CN', 'FitState Development'],
                                        ['emailAddress', APPLE_ID]
                                      ])
  csr.public_key = key.public_key
  csr.sign(key, OpenSSL::Digest::SHA256.new)
  csr_content = Base64.strict_encode64(csr.to_der)

  # --- 申请证书 ---
  cert_request = nil
  cert_type = nil
  [CERT_TYPE_APPLE_DEV, CERT_TYPE_DEV].each do |type|
    begin
      data = portal.post('account/ios/certificate/submitCertificateRequest.action', {
                          teamId: TEAM_ID,
                          type: type,
                          csrContent: csr_content,
                          appIdId: app['appIdId'],
                          specialIdentifierDisplayId: app['appIdId']
                        })
      req = data.is_a?(Hash) ? (data['certRequest'] || data) : {}
      if req['certificateId'].to_s.empty?
        raise "响应里没有 certificateId :: #{data.inspect[0, 300]}"
      end
      cert_request = req
      cert_type = req['certificateTypeDisplayId'] || type
      log "CERT_OK type=#{type} id=#{req['certificateId']} name=#{req['name']}"
      break
    rescue StandardError => e
      log "CERT_FAIL type=#{type} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    end
  end

  if cert_request.nil?
    fail_hard('证书申请失败 —— 免费团队可能不给发证书')
  end

  # --- 下载证书 + 打包 p12 ---
  begin
    resp = portal.raw(:get, 'account/ios/certificate/downloadCertificateContent.action',
                      teamId: TEAM_ID, certificateId: cert_request['certificateId'], type: cert_type)
    der = resp.body
    raise "下载到的证书是空的" if der.to_s.empty?

    File.binwrite(File.join(OUT_DIR, 'portal.cer'), der)
    x509 = OpenSSL::X509::Certificate.new(der)
    log "CERT_DOWNLOADED subject=#{x509.subject} fingerprint=#{x509.fingerprint('sha1')}"

    p12 = OpenSSL::PKCS12.new('fitstate', 'FitState Development', key, x509)
    p12_path = File.join(OUT_DIR, 'portal.p12')
    File.binwrite(p12_path, p12.serialize)
    File.chmod(0o600, p12_path)
    log "P12_WRITTEN #{p12_path} #{File.size(p12_path)} bytes"
    manifest['p12'] = 'portal.p12'
    manifest['cer'] = 'portal.cer'
  rescue StandardError => e
    log "P12_FAIL #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
    fail_hard('证书下载失败')
  end

  # --- 每个 bundle id 一份描述文件 ---
  [app, widget].compact.each do |a|
    bundle = a['identifier']
    profile_xml = nil
    profile_ent = {}

    # 模板候选：默认（按 App ID 已开能力自动生成）→ 显式指定
    templates = [nil, "iOS Team Provisioning Profile:#{bundle}", "iOS Team Provisioning Profile:#{bundle}:HealthKit"]

    templates.each do |template|
      begin
        params = {
          teamId: TEAM_ID,
          provisioningProfileName: "FitState #{bundle} Dev",
          appIdId: a['appIdId'],
          distributionType: 'development',
          certificateIds: cert_request['certificateId'],
          deviceIds: device_id ? [device_id] : []
        }
        params[:template] = template if template

        data = portal.post('account/ios/profile/createProvisioningProfile.action', params)
        prof = data.is_a?(Hash) ? (data['provisioningProfile'] || data) : {}
        pid = prof['provisioningProfileId']
        raise "响应里没有 provisioningProfileId :: #{data.inspect[0, 300]}" if pid.to_s.empty?

        resp = portal.raw(:get, 'account/ios/profile/downloadProfileContent',
                          teamId: TEAM_ID, provisioningProfileId: pid)
        xml = resp.body.to_s
        raise "下载到的描述文件是空的" if xml.strip.empty?

        parsed = parse_profile_plist(xml)
        ent = parsed['Entitlements'] || {}

        log "PROFILE template=#{template.inspect} bundle=#{bundle} entitlements=#{ent.keys.inspect}"

        if ent.key?('com.apple.developer.healthkit')
          profile_xml = xml
          profile_ent = ent
          break
        end

        log "PROFILE_NO_HEALTHKIT template=#{template.inspect}"
        profile_xml ||= xml
        profile_ent = ent
      rescue StandardError => e
        log "PROFILE_FAIL #{bundle} template=#{template.inspect} #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
      end
    end

    if profile_xml.nil?
      log "PROFILE_MISSING #{bundle}"
      manifest['targets'] << {
        'bundle_id' => bundle, 'profile' => nil, 'entitlements' => {}, 'provisioned_devices' => []
      }
      next
    end

    safe = bundle.gsub(/[^A-Za-z0-9._-]/, '_')
    path = File.join(OUT_DIR, "#{safe}.mobileprovision")
    File.binwrite(path, profile_xml)

    parsed = parse_profile_plist(profile_xml)
    ent = parsed['Entitlements'] || profile_ent
    dev = parsed['ProvisionedDevices'] || []

    log "PROFILE_WRITTEN #{path} #{File.size(path)} bytes"
    log "PROFILE_ENTITLEMENTS #{bundle} #{ent.inspect}"
    log "PROFILE_DEVICES #{dev.inspect}"

    manifest['targets'] << {
      'bundle_id' => bundle,
      'profile' => File.basename(path),
      'entitlements' => ent,
      'provisioned_devices' => dev,
      'expires_at' => parsed['ExpirationDate'].to_s
    }
  end
else
  [app, widget].compact.each do |a|
    manifest['targets'] << { 'bundle_id' => a['identifier'], 'profile' => nil, 'entitlements' => {} }
  end
end

# App Group 以描述文件里真正授权的那一个为准。
# 我们申请时写的是 group.<TeamID>.com.god.fitstate，但门户可能给出别的形式，
# 描述文件里授权的才是 App 运行时能打开的那个。
granted_groups = manifest['targets'].flat_map do |t|
  ent = t['entitlements'].is_a?(Hash) ? t['entitlements'] : {}
  Array(ent['com.apple.security.application-groups'])
end
if granted_groups.any? { |g| !g.to_s.empty? }
  manifest['app_group'] = granted_groups.find { |g| !g.to_s.empty? }
  log "APP_GROUP_GRANTED #{manifest['app_group']}"
else
  log "APP_GROUP_NOT_GRANTED（描述文件里没有 App Groups 权限）"
end

File.write(File.join(OUT_DIR, 'manifest.json'), JSON.pretty_generate(manifest))
log "MANIFEST_WRITTEN #{File.join(OUT_DIR, 'manifest.json')}"

# --- 最后一道闸门：描述文件里必须真的有 HealthKit ---
has_hk = manifest['targets'].any? do |t|
  t['entitlements'].is_a?(Hash) && t['entitlements'].key?('com.apple.developer.healthkit')
end
log "HEALTHKIT_IN_PROFILES=#{has_hk ? 'YES' : 'NO'}"
log 'PORTAL_DONE'

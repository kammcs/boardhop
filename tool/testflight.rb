#!/usr/bin/env ruby
# TestFlight state and tester invitations for BoardHop through the App
# Store Connect API (spaceship from the installed fastlane gem).
#
#   tool/testflight.rb status            builds, groups and testers with states
#   tool/testflight.rb invite <email>    send (or resend) the invitation to a tester
#   tool/testflight.rb notify            "build available" notification for the latest build
#
# Authenticates with the App Store Connect API key at the repo root,
# AuthKey_<KEY_ID>.p8 (gitignored; Kelly's Admin key), and the team's
# issuer id. Override with BOARDHOP_ASC_KEY_ID, BOARDHOP_ASC_ISSUER_ID and
# BOARDHOP_ASC_KEY_PATH. Never prints the key.
#
# Why this exists: on 2026-09-11 the internal tester added to the group
# after build 2 had landed stayed NOT_INVITED and App Store Connect offered
# no resend; POST betaTesterInvitations sent the mail at once.
require 'spaceship'

KEY_ID = ENV.fetch('BOARDHOP_ASC_KEY_ID', 'YD5P39439T')
ISSUER_ID = ENV.fetch('BOARDHOP_ASC_ISSUER_ID', '69a6de70-8b43-47e3-e053-5b8c7c11a4d1')
KEY_PATH = ENV.fetch('BOARDHOP_ASC_KEY_PATH', File.expand_path("../AuthKey_#{KEY_ID}.p8", __dir__))
BUNDLE_ID = 'com.kammcs.boardhop'

abort("no API key at #{KEY_PATH}") unless File.exist?(KEY_PATH)
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(key_id: KEY_ID, issuer_id: ISSUER_ID, filepath: KEY_PATH)
client = Spaceship::ConnectAPI.test_flight_request_client
app = Spaceship::ConnectAPI::App.find(BUNDLE_ID) or abort("no app record for #{BUNDLE_ID}")

def builds(app)
  Spaceship::ConnectAPI::Build.all(app_id: app.id, includes: 'buildBetaDetail,preReleaseVersion', sort: '-uploadedDate')
end

def group_testers(client, group_id)
  client.get("v1/betaGroups/#{group_id}/betaTesters").body['data'].map do |t|
    { id: t['id'], email: t['attributes']['email'], state: t['attributes']['state'] }
  end
end

case ARGV[0]
when 'status'
  puts "#{app.name} (#{app.id})"
  builds(app).each do |b|
    d = b.build_beta_detail
    puts "  build #{b.pre_release_version&.version} (#{b.version}) #{b.processing_state}" \
         " internal=#{d&.internal_build_state} external=#{d&.external_build_state}#{b.expired ? ' EXPIRED' : ''}"
  end
  app.get_beta_groups.each do |g|
    puts "  group #{g.name} (#{g.is_internal_group ? 'internal' : 'external'}, auto-distribute=#{g.has_access_to_all_builds}" \
         "#{g.public_link_enabled ? ', public link ' + g.public_link.to_s : ''})"
    group_testers(client, g.id).each { |t| puts "    #{t[:email]} #{t[:state]}" }
  end
when 'invite'
  email = ARGV[1] or abort('usage: tool/testflight.rb invite <email>')
  tester = app.get_beta_groups.flat_map { |g| group_testers(client, g.id) }.find { |t| t[:email] == email }
  abort("#{email} is not in any of the app's groups; add them in App Store Connect first") unless tester
  client.post('v1/betaTesterInvitations', { data: { type: 'betaTesterInvitations', relationships: {
    app: { data: { type: 'apps', id: app.id } },
    betaTester: { data: { type: 'betaTesters', id: tester[:id] } } } } })
  state = app.get_beta_groups.flat_map { |g| group_testers(client, g.id) }.find { |t| t[:email] == email }[:state]
  puts "invitation sent to #{email}; state now #{state}"
when 'notify'
  build = builds(app).first or abort('no builds')
  begin
    client.post('v1/buildBetaNotifications', { data: { type: 'buildBetaNotifications',
      relationships: { build: { data: { type: 'builds', id: build.id } } } } })
    puts "notified testers of #{build.pre_release_version&.version} (#{build.version})"
  rescue => e
    puts "notification not sent: #{e.message[0, 200]}"
  end
else
  abort('usage: tool/testflight.rb status | invite <email> | notify')
end

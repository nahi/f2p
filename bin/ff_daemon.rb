#!/usr/local/bin/ruby

ENV['RAILS_ENV'] ||= 'production'

dir = File.dirname(__FILE__)
libdir = File.expand_path('../lib', dir)
pid_file = File.expand_path('ff_daemon.pid', dir)

$: << libdir

require File.expand_path('../config/environment', dir)
require 'ff_daemon'
require 'webrick'
require 'logger'

if File.exist?(pid_file)
  pid = File.open(pid_file) { |f| f.gets }.to_i
  begin
    Process.kill(:INT, pid)
  rescue SystemCallError
  end
end

Process.daemon unless $DEBUG

File.open(pid_file, 'w') do |f|
  f.puts($$)
end

front = FriendFeed::APIV2Daemon.new(RAILS_DEFAULT_LOGGER)
front.client.http_proxy = F2P::Config.http_proxy
front.client.oauth_consumer_key = F2P::Config.friendfeed_api_oauth_consumer_key
front.client.oauth_consumer_secret = F2P::Config.friendfeed_api_oauth_consumer_secret
front.client.oauth_site = F2P::Config.friendfeed_api_oauth_site
front.client.oauth_scheme = F2P::Config.friendfeed_api_oauth_scheme
front.client.oauth_signature_method = F2P::Config.friendfeed_api_oauth_signature_method
front.client.json_parse_size_limit = F2P::Config.json_parse_size_limit
DRb.start_service(F2P::Config.friendfeed_api_daemon_drb_uri, front)

trap(:INT) do
  DRb.stop_service
  exit!
end

if $DEBUG
  gets
else
  DRb.thread.join
end

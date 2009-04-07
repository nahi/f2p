fork do
  require 'ff_daemon'
  require 'webrick'
  pid_file = File.expand_path('ff_daemon.pid', File.dirname(__FILE__))
  if File.exist?(pid_file)
    pid = File.open(pid_file) { |f| f.gets }.to_i
    begin
      Process.kill('SIGKILL', pid)
    rescue SystemCallError
    end
  end
  File.open(pid_file, 'w') do |f|
    f.puts($$)
  end
  front = FriendFeed::APIDaemon.new
  front.client.logger = RAILS_DEFAULT_LOGGER
  front.client.apikey = F2P::Config.friendfeed_api_key
  front.client.http_proxy = F2P::Config.http_proxy
  DRb.start_service(F2P::Config.friendfeed_api_daemon_drb_uri, front)
  DRb.thread.join
end

require 'ff'
require 'drb/drb'


module FriendFeed
  module ClientProxy
    def define_proxy_method(msg_id)
      define_method(msg_id) do |*arg|
        ClientProxy.proxy(@client, msg_id, *arg)
      end
    end

    # do retry 1 time
    def proxy(client, *sig)
      begin
        client.send(*sig)
      rescue SystemCallError => e
        client.send(*sig)
      end
    end
    module_function :proxy
  end

  module ClientCachedProxy
    include ClientProxy

    # first argument(name) is used as a key for purge cache.
    def define_cached_proxy_method(msg_id)
      define_method(msg_id) do |*arg|
        basekey = arg[0]
        cachekey = [msg_id, *arg]
        (@cache[basekey] ||= {})[cachekey] ||=
          ClientProxy.proxy(@client, msg_id, *arg)
      end
    end
  end

  class APIClientProxy
    extend ClientProxy

    define_proxy_method :validate
    define_proxy_method :get_entry
    define_proxy_method :get_entries
    define_proxy_method :get_home_entries
    define_proxy_method :get_list_entries
    define_proxy_method :get_user_entries
    define_proxy_method :get_friends_entries
    define_proxy_method :get_room_entries
    define_proxy_method :get_comments
    define_proxy_method :get_likes
    define_proxy_method :get_discussion
    define_proxy_method :get_url_entries
    define_proxy_method :search_entries
    #define_proxy_method :post
    define_proxy_method :delete
    define_proxy_method :post_comment
    define_proxy_method :edit_comment
    define_proxy_method :delete_comment
    define_proxy_method :like
    define_proxy_method :unlike

    define_proxy_method :get_user_picture_url
    define_proxy_method :get_room_picture_url
    define_proxy_method :get_profile
    define_proxy_method :get_profiles
    define_proxy_method :get_room_profile

    define_proxy_method :purge_cache

    def initialize
      @client = DRb::DRbObject.new(nil, F2P::Config.friendfeed_api_daemon_drb_uri)
    end

    # need custom wrapping for dispatching IO.
    def post(name, remote_key, title, link = nil, comment = nil, images = nil, files = nil, room = nil)
      if files
        files = files.map { |file, file_link|
          file = file.read if file.respond_to?(:read)
          [file, file_link]
        }
      end
      @client.post(name, remote_key, title, link, comment, images, files, room)
    end
  end

  class APIDaemon
    extend ClientCachedProxy

    attr_reader :client

    define_proxy_method :validate
    define_proxy_method :get_entry
    define_proxy_method :get_entries
    define_proxy_method :get_home_entries
    define_proxy_method :get_list_entries
    define_proxy_method :get_user_entries
    define_proxy_method :get_friends_entries
    define_proxy_method :get_room_entries
    define_proxy_method :get_comments
    define_proxy_method :get_likes
    define_proxy_method :get_discussion
    define_proxy_method :get_url_entries
    define_proxy_method :search_entries
    define_proxy_method :post
    define_proxy_method :delete
    define_proxy_method :post_comment
    define_proxy_method :edit_comment
    define_proxy_method :delete_comment
    define_proxy_method :like
    define_proxy_method :unlike

    define_cached_proxy_method :get_user_picture_url
    define_cached_proxy_method :get_room_picture_url
    #define_cached_proxy_method :get_profile
    #define_cached_proxy_method :get_profiles
    define_cached_proxy_method :get_room_profile

    def initialize(logger = nil)
      @client = FriendFeed::APIClient.new(logger)
      @cache = {}
    end

    def purge_cache(key)
      @cache.delete(key)
      nil
    end

    def get_profile(name, remote_key, user = nil)
      user ||= name
      basekey = name
      cache = ((@cache ||= {})[basekey] ||= {})[:get_profile] ||= {}
      cache[user] ||= ClientProxy.proxy(@client, :get_profile, name, remote_key, user)
    end

    def get_profiles(name, remote_key, users)
      basekey = name
      cache = ((@cache ||= {})[basekey] ||= {})[:get_profile] ||= {}
      unless users.all? { |e| cache[e] }
        profiles = ClientProxy.proxy(@client, :get_profiles, name, remote_key, users)
        profiles.each do |profile|
          cache[profile['nickname']] = profile
        end
      end
      users.map { |e| cache[e] }
    end
  end
end


if $0 == __FILE__
  require 'webrick'

  env = File.expand_path('../config/environment', File.dirname(__FILE__))
  require env
  unless $DEBUG
    puts $$
    WEBrick::Daemon.start
    File.umask 007
    STDERR.reopen(open('stderr', 'a'))
  end

  front = FriendFeed::APIDaemon.new
  front.client.logger = RAILS_DEFAULT_LOGGER
  front.client.apikey = F2P::Config.friendfeed_api_key
  front.client.http_proxy = F2P::Config.http_proxy
  DRb.start_service(F2P::Config.friendfeed_api_daemon_drb_uri, front)

  if $DEBUG
    p "Started."
    gets
  else
    STDIN.reopen('/dev/null')
    STDOUT.reopen('/dev/null', 'w')
    STDERR.reopen('/dev/null', 'w')
    DRb.thread.join
  end
end

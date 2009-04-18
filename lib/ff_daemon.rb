require 'ff'
require 'drb/drb'
require 'monitor'


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
    define_proxy_method :get_inbox_entries
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

    class Channel
      attr_reader :client
      attr_accessor :timeout
      attr_accessor :cache_size
      attr_accessor :lifetime

      def initialize(name, remote_key, logger)
        @name = name
        @logger = logger
        @client = FriendFeed::ChannelClient.new(name, remote_key, logger)
        @timeout = 60
        @cache_size = 512
        @lifetime = 600
        @inbox = []
        @inbox.extend(MonitorMixin)
        @stopping = false
        @thread = nil
        @logger.info("channel initialized for #{@name}")
      end

      def start
        @stopping = false
        @logger.info("channel started for #{@name}")
        
        @client.initialize_token
        @inbox.synchronize do
          @inbox.replace(@client.get_home_entries(:start => 0, :num => @cache_size))
        end
        @last_access = Time.now
        @thread = Thread.new {
          begin
            while !@stopping
              @logger.debug("channel start long polling for #{@name}")
              @client.timeout = @timeout
              updated = @client.updated_home_entries()
              update_inbox(updated['entries']) if updated
              if Time.now > @last_access + @lifetime
                @logger.info("channel for #{@name} stopping by time limit...")
                @stopping = true
                @thread = nil
              end
            end
          rescue Exception => e
            @logger.warn(e)
          end
          @logger.info("channel for #{@name} stopped")
        }
        @stopping = false
      end

      def stop
        @logger.info("channel for #{@name} stopping by request...")
        @stopping = true
        # TODO: uglish
        @thread.kill rescue nil
        @thread = nil
      end

      def inbox(start, num)
        start() if @thread.nil? or !@thread.alive?
        @inbox.synchronize do
          entries = @inbox[start, num]
          if entries and entries.size == num
            @last_access = Time.now
            entries
          else
            @client.get_home_entries(:start => start, :num => num)
          end
        end
      end

    private

      def update_inbox(entries)
        return if entries.empty?
        ids = entries.collect { |e| e['id'] }
        @inbox.synchronize do
          @inbox.delete_if { |i| ids.include?(i['id']) }
          @inbox[0, 0] = entries
          @inbox.replace(@inbox[0, @cache_size])
        end
        @logger.info("channel updated for #{@name}")
      end
    end

    attr_reader :client
    attr_accessor :use_channel
    attr_accessor :channel_timeout
    attr_accessor :channel_cache_size
    attr_accessor :channel_lifetime

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
      @logger = @client.logger
      @use_channel = false
      @channel_timeout = 60
      @channel_cache_size = 512
      @channel = {}
      @cache = {}
    end

    def purge_cache(key)
      @cache.delete(key)
      if @channel.key?(key)
        @channel[key].stop
        @channel.delete(key)
      end
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
      if users.any? { |e| cache[e].nil? }
        profiles = ClientProxy.proxy(@client, :get_profiles, name, remote_key, users)
        profiles.each do |profile|
          cache[profile['nickname']] = profile
        end
      end
      users.map { |e| cache[e] }
    end

    def get_inbox_entries(*arg)
      if @use_channel
        realtime_inbox_entries(*arg)
      else
        plain_get_inbox_entries(*arg)
      end
    end

    def plain_get_inbox_entries(name, remote_key, start, num)
      get_home_entries(name, remote_key, :start => start, :num => num)
    end

    def realtime_inbox_entries(name, remote_key, start, num)
      unless @channel.key?(name)
        @channel[name] = Channel.new(name, remote_key, @logger)
        @channel[name].timeout = @channel_timeout
        @channel[name].cache_size = @channel_cache_size
        @channel[name].lifetime = @channel_lifetime
        @channel[name].start
      end
      @channel[name].inbox(start || 0, num || @channel_cache_size)
    end
  end
end


if $0 == __FILE__
  require 'logger'
  name = ARGV.shift or raise
  remote_key = ARGV.shift or raise
  daemon = FriendFeed::APIDaemon.new#(Logger.new(STDERR))
  daemon.channel_timeout = 1
  p daemon.get_inbox_entries(name, remote_key, 0, 10).size
  sleep 10
  p daemon.get_inbox_entries(name, remote_key, 200, 10).size
end

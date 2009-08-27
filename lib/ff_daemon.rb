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

  class APIV2ClientProxy
    extend ClientProxy

    define_proxy_method :validate
    define_proxy_method :oauth_validate
    define_proxy_method :feed
    define_proxy_method :search
    define_proxy_method :feedlist
    define_proxy_method :feedinfo
    define_proxy_method :profile
    define_proxy_method :entries
    define_proxy_method :entry
    define_proxy_method :url
    #define_proxy_method :post_entry
    #define_proxy_method :edit_entry

    define_proxy_method :delete_entry
    define_proxy_method :undelete_entry
    define_proxy_method :post_comment
    define_proxy_method :edit_comment
    define_proxy_method :delete_comment
    define_proxy_method :undelete_comment
    define_proxy_method :like
    define_proxy_method :delete_like
    define_proxy_method :subscribe
    define_proxy_method :unsubscribe
    define_proxy_method :hide_entry
    define_proxy_method :unhide_entry
    define_proxy_method :create_short_url

    define_proxy_method :get_user_picture_url
    define_proxy_method :get_room_picture_url

    define_proxy_method :get_cached_entries
    define_proxy_method :set_cached_entries

    def initialize
      @client = DRb::DRbObject.new(nil, F2P::Config.friendfeed_api_daemon_drb_uri)
    end

    # need custom wrapping for dispatching IO.
    def post_entry(to, body, opt = {})
      @client.post_entry(to, body, wrap_opt_file(opt))
    end

    def edit_entry(eid, opt = {})
      @client.edit_entry(eid, wrap_opt_file(opt))
    end

    def wrap_opt_file(opt)
      if opt[:file]
        opt = opt.dup
        opt[:file] = opt[:file].map { |file|
          filename = file.original_filename if file.respond_to?(:original_filename)
          content_type = file.content_type if file.respond_to?(:content_type)
          file = file.read if file.respond_to?(:read)
          [file, content_type, filename]
        }
      end
      opt
    end
  end

  class APIV2Daemon
    extend ClientCachedProxy

    attr_reader :client

    define_proxy_method :validate
    define_proxy_method :oauth_validate
    define_proxy_method :feed
    define_proxy_method :search
    define_proxy_method :feedlist
    define_proxy_method :feedinfo
    define_proxy_method :profile
    define_proxy_method :entries
    define_proxy_method :entry
    define_proxy_method :url
    define_proxy_method :post_entry
    define_proxy_method :edit_entry

    define_proxy_method :delete_entry
    define_proxy_method :undelete_entry
    define_proxy_method :post_comment
    define_proxy_method :edit_comment
    define_proxy_method :delete_comment
    define_proxy_method :undelete_comment
    define_proxy_method :like
    define_proxy_method :delete_like
    define_proxy_method :subscribe
    define_proxy_method :unsubscribe
    define_proxy_method :hide_entry
    define_proxy_method :unhide_entry
    define_proxy_method :create_short_url

    define_proxy_method :get_user_picture_url
    define_proxy_method :get_room_picture_url

    def initialize(logger = nil)
      @client = FriendFeed::APIV2Client.new(logger)
      @logger = @client.logger
      @cache = {}
    end

    def set_cached_entries(name, entries)
      basekey = name
      cache = ((@cache ||= {})[basekey] ||= {})
      cache[:last_entries] = entries
      nil
    end

    def get_cached_entries(name)
      basekey = name
      cache = ((@cache ||= {})[basekey] ||= {})
      cache[:last_entries]
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

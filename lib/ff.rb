require 'httpclient'
require 'uri'
require 'json'
require 'monitor'
require 'stringio'
require 'zlib'


module FriendFeed
  class NullLogger
    def <<(*arg)
    end

    def method_missing(msg_id, *a, &b)
    end
  end

  class BaseClient
    attr_accessor :logger
    attr_accessor :apikey
    attr_accessor :http_proxy

    class LShiftLogger
      def initialize(logger)
        @logger = logger
      end

      def <<(*arg)
        @logger.info(*arg)
      end

      def method_missing(msg_id, *a, &b)
        @logger.send(msg_id, *a, &b)
      end
    end

    class UserClient
      def initialize(name, remote_key, logger, http_proxy)
        @client = HTTPClient.new(http_proxy)
        @name = name
        @remote_key = remote_key
        #@client.debug_dev = LShiftLogger.new(logger)
        @client.extend(MonitorMixin)
        reset_auth
      end

      def client(remote_key)
        @client.synchronize do
          if remote_key != @remote_key
            @remote_key = remote_key
            reset_auth
          end
          @client
        end
      end

      def inspect
        sprintf("#<%s:0x%x>", self.class.name, object_id)
      end

    private

      def reset_auth
        @client.set_auth(nil, @name, @remote_key)
      end
    end

    def initialize(logger = nil, apikey = nil)
      @logger = logger || NullLogger.new
      @apikey = apikey
      @http_proxy = nil
      @clients = {}
    end

  private

    def uri(part)
      begin
        URI.parse(File.join(url_base, part))
      rescue URI::InvalidURIError
      end
    end

    def create_client(name, remote_key)
      UserClient.new(name, remote_key, @logger, @http_proxy)
    end

    def client_sync(uri, name, remote_key)
      user_client = @clients[name] ||= create_client(name, remote_key)
      client = user_client.client(remote_key)
      logger.info("#{user_client.inspect} is accessing to #{uri.to_s} for #{name}")
      httpclient_protect do
        client.www_auth.basic_auth.challenge(uri, true)
        yield(client)
      end
    end

    def httpclient_protect(&block)
      result = nil
      start = Time.now
      begin
        result = yield
      rescue HTTPClient::BadResponseError => e
        logger.error(e)
      rescue HTTPClient::TimeoutError => e
        logger.error(e)
      end
      logger.info("elapsed: #{((Time.now - start) * 1000).to_i}ms")
      result
    end

    def get_request(client, uri, query = {})
      ext = { 'Accept-Encoding' => 'gzip' }
      query = query.merge(:apikey => @apikey) if @apikey
      res = client.get(uri, query, ext)
      if res.status != 200
        logger.warn("got status #{res.status}: #{res.inspect}")
      end
      enc = res.header['content-encoding']
      if enc and enc[0] and enc[0].downcase == 'gzip'
        c = Zlib::GzipReader.wrap(StringIO.new(res.content)) { |gz| gz.read }
        res.body.init_response(c)
      end
      res
    end

    def post_request(client, uri, query = {})
      query = query.merge(:apikey => @apikey) if @apikey
      client.post(uri, query)
    end

    def get_feed(uri, name, remote_key, query = {})
      logger.info("getting entries with query: " + query.inspect)
      res = client_sync(uri, name, remote_key) { |client|
        get_request(client, uri, query)
      }
      if res.status == 200
        obj = JSON.parse(res.content)
        logger.debug { JSON.pretty_generate(obj) }
        obj['entries']
      end
    end
  end

  class ChannelClient < BaseClient
    URL_BASE = 'http://chan.friendfeed.com/api/'

    attr_reader :name
    attr_reader :remote_key
    attr_accessor :timeout

    def initialize(name, remote_key, logger = nil)
      super(logger)
      @name = name
      @remote_key = remote_key
      @timeout = 60
    end

    def initialize_token
      @token = get_token()
    end

    def get_home_entries(opt = {})
      uri = URI.parse('https://friendfeed.com/api/feed/home')
      get_feed(uri, @name, @remote_key, opt)
    end

    def updated_home_entries(opt = {})
      initialize_token unless @token
      uri = uri("updates/home")
      query = opt.merge(:token => @token, :timeout => @timeout, :format => 'json')
      res = client_sync(uri, @name, @remote_key) { |client|
        client.receive_timeout = @timeout * 1.1
        get_request(client, uri, query)
      }
      if res.status == 200 and !res.content.strip.empty?
        begin
          obj = JSON.parse(res.content)
          logger.debug { JSON.pretty_generate(obj) }
          @token = obj['update']['token']
          obj
        rescue Exception => e
          logger.warn("JSON parsing failed: #{res.inspect}")
          logger.warn(e)
          nil
        end
      end
    end

  private

    def get_token
      uri = uri("updates")
      query = { :format => 'json', :timeout => 0 }
      res = client_sync(uri, @name, @remote_key) { |client|
        get_request(client, uri, query)
      }
      if res.status == 200
        JSON.parse(res.content)['update']['token']
      end
    end

    def url_base
      URL_BASE
    end
  end

  class APIClient < BaseClient
    URL_BASE = 'https://friendfeed.com/api/'

    def validate(name, remote_key)
      uri = uri('validate')
      res = client_sync(uri, name, remote_key) { |client|
        get_request(client, uri)
      }
      res.status == 200
    end

    # size: small, medium, or large.
    def get_user_picture_url(name, size = 'small')
      "http://friendfeed.com/#{name}/picture?size=#{size}"
    end

    # size: small, medium, or large.
    def get_room_picture_url(name, size = 'small')
      "http://friendfeed.com/rooms/#{name}/picture?size=#{size}"
    end

    def get_profile(name, remote_key, user)
      uri = uri("user/#{user}/profile")
      return nil unless uri
      res = client_sync(uri, name, remote_key) { |client|
        get_request(client, uri)
      }
      if res.status == 200
        JSON.parse(res.content)
      end
    end

    def get_profiles(name, remote_key, users)
      uri = uri("profiles")
      query = { 'nickname' => users.join(',') }
      return nil unless uri
      res = client_sync(uri, name, remote_key) { |client|
        get_request(client, uri, query)
      }
      if res.status == 200
        JSON.parse(res.content)['profiles']
      end
    end

    def get_room_profile(name, remote_key, room)
      uri = uri("room/#{room}/profile")
      return nil unless uri
      res = client_sync(uri, name, remote_key) { |client|
        res = get_request(client, uri)
      }
      if res.status == 200
        JSON.parse(res.content)
      end
    end

    def get_entry(name, remote_key, eid, opt = {})
      uri = uri("feed/entry/#{eid}")
      return nil unless uri
      get_feed(uri, name, remote_key, opt)
    end

    def get_entries(name, remote_key, eids, opt = {})
      uri = uri("feed/entry")
      opt = opt.merge(:entry_id => eids.join(','))
      get_feed(uri, name, remote_key, opt)
    end

    def get_home_entries(name, remote_key, opt = {})
      uri = uri("feed/home")
      get_feed(uri, name, remote_key, opt)
    end

    def get_list_entries(name, remote_key, list, opt = {})
      uri = uri("feed/list/#{list}")
      return nil unless uri
      get_feed(uri, name, remote_key, opt)
    end

    def get_user_entries(name, remote_key, user, opt = {})
      uri = uri("feed/user/#{user}")
      return nil unless uri
      get_feed(uri, name, remote_key, opt)
    end

    def get_friends_entries(name, remote_key, user, opt = {})
      uri = uri("feed/user/#{user}/friends")
      return nil unless uri
      get_feed(uri, name, remote_key, opt)
    end

    def get_room_entries(name, remote_key, room = nil, opt = {})
      if room.nil?
        uri = uri("feed/rooms")
      else
        uri = uri("feed/room/#{room}")
      end
      return nil unless uri
      get_feed(uri, name, remote_key, opt)
    end

    def get_comments(name, remote_key, user, opt = {})
      uri = uri("feed/user/#{user}/comments")
      return nil unless uri
      get_feed(uri, name, remote_key, opt)
    end

    def get_likes(name, remote_key, user, opt = {})
      uri = uri("feed/user/#{user}/likes")
      return nil unless uri
      get_feed(uri, name, remote_key, opt)
    end

    def get_discussion(name, remote_key, user, opt = {})
      uri = uri("feed/user/#{user}/discussion")
      return nil unless uri
      get_feed(uri, name, remote_key, opt)
    end

    def get_url_entries(name, remote_key, url, opt = {})
      uri = uri("feed/url")
      query = opt.merge(:url => url)
      get_feed(uri, name, remote_key, opt)
    end

    def search_entries(name, remote_key, query, opt = {})
      uri = uri("feed/search")
      opt = opt.merge(:q => query)
      get_feed(uri, name, remote_key, opt)
    end

    def post(name, remote_key, title, link = nil, comment = nil, images = nil, files = nil, room = nil)
      uri = uri("share")
      query = { 'title' => title }
      query['link'] = link if link
      query['comment'] = comment if comment
      if images
        images.each_with_index do |image, idx|
          image_url, image_link = image
          query["image#{idx}_url"] = image_url
          query["image#{idx}_link"] = image_link
        end
      end
      if files
        files.each_with_index do |file, idx|
          file, file_link = file
          file = StringIO.new(file.to_s) unless file.respond_to?(:read)
          query["file#{idx}"] = file
          query["file#{idx}_link"] = file_link
        end
      end
      query['room'] = room if room
      client_sync(uri, name, remote_key) do |client|
        res = post_request(client, uri, query)
        JSON.parse(res.content)['entries']
      end
    end

    def delete(name, remote_key, entry, undelete = false)
      uri = uri("entry/delete")
      query = { 'entry' => entry }
      query['undelete'] = 1 if undelete
      client_sync(uri, name, remote_key) do |client|
        post_request(client, uri, query)
      end
    end

    def post_comment(name, remote_key, entry, body)
      uri = uri("comment")
      query = {
        'entry' => entry,
        'body' => body
      }
      client_sync(uri, name, remote_key) do |client|
        res = post_request(client, uri, query)
        JSON.parse(res.content)
      end
    end

    def edit_comment(name, remote_key, entry, comment, body)
      uri = uri("comment")
      query = {
        'entry' => entry,
        'comment' => comment,
        'body' => body
      }
      client_sync(uri, name, remote_key) do |client|
        res = post_request(client, uri, query)
        JSON.parse(res.content)
      end
    end

    def delete_comment(name, remote_key, entry, comment, undelete = false)
      uri = uri("comment/delete")
      query = {
        'entry' => entry,
        'comment' => comment
      }
      query['undelete'] = 1 if undelete
      client_sync(uri, name, remote_key) do |client|
        post_request(client, uri, query)
      end
    end

    def like(name, remote_key, entry)
      uri = uri("like")
      query = {'entry' => entry}
      client_sync(uri, name, remote_key) do |client|
        post_request(client, uri, query)
      end
    end

    def unlike(name, remote_key, entry)
      uri = uri("like/delete")
      query = {'entry' => entry}
      client_sync(uri, name, remote_key) do |client|
        post_request(client, uri, query)
      end
    end

  private

    def url_base
      URL_BASE
    end
  end
end


if $0 == __FILE__
  name = ARGV.shift or raise
  remote_key = ARGV.shift or raise
  require 'logger'
  logger = Logger.new('ff.log')
  client = FriendFeed::APIClient.new(logger)
  print JSON.pretty_generate(client.get_home_entries(name, remote_key))
#  client = FriendFeed::ChannelClient.new(name, remote_key, logger)
#  while true
#    print JSON.pretty_generate(client.updated_home_entries(:timeout => 10))
#  end
end

require 'httpclient'
require 'uri'
require 'json'
require 'monitor'
require 'stringio'
require 'zlib'


module FriendFeed
  module JSONFilter
    class << self
      def parse(str)
        safe = filter_utf8(str)
        JSON.parse(safe)
      end

      def pretty_generate(obj)
        JSON.pretty_generate(obj)
      end

    private

      # these definition source code is from soap4r.
      us_ascii = '[\x9\xa\xd\x20-\x7F]'     # XML 1.0 restricted.
      # 0xxxxxxx
      # 110yyyyy 10xxxxxx
      twobytes_utf8 = '(?:[\xC0-\xDF][\x80-\xBF])'
      # 1110zzzz 10yyyyyy 10xxxxxx
      threebytes_utf8 = '(?:[\xE0-\xEF][\x80-\xBF][\x80-\xBF])'
      # 11110uuu 10uuuzzz 10yyyyyy 10xxxxxx
      fourbytes_utf8 = '(?:[\xF0-\xF7][\x80-\xBF][\x80-\xBF][\x80-\xBF])'
      CHAR_UTF_8 =
        "(?:#{us_ascii}|#{twobytes_utf8}|#{threebytes_utf8}|#{fourbytes_utf8})"

      def filter_utf8(str)
        str.scan(/(#{CHAR_UTF_8})|(.)/n).collect { |u, x|
          if u
            u
          else
            sprintf("\\x%02X", x[0])
          end
        }.join
      end
    end
  end

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
    attr_accessor :httpclient_max_keepalive

    attr_accessor :name
    attr_accessor :remote_key

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
      attr_accessor :httpclient_max_keepalive

      def initialize(name, remote_key, logger, http_proxy)
        @client = HTTPClient.new(http_proxy)
        @name = name
        @remote_key = remote_key
        #@client.debug_dev = LShiftLogger.new(logger)
        @logger = logger
        @client.extend(MonitorMixin)
        @last_accessed = Time.now
        reset_auth
      end

      def idle?
        if @httpclient_max_keepalive
          elapsed = Time.now - @last_accessed
          if elapsed > @httpclient_max_keepalive
            @client.reset_all rescue nil
            true
          end
        end
      end

      def client(remote_key)
        @client.synchronize do
          if remote_key != @remote_key
            @remote_key = remote_key
            reset_auth
          end
          @last_accessed = Time.now
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
      @httpclient_max_keepalive = 5 * 60
      @clients = {}
      @name = nil
      @remote_key = nil
      @mutex = Monitor.new
    end

    # size: small, medium, or large.
    def get_user_picture_url(name, size = 'small')
      "http://friendfeed.com/#{name}/picture?size=#{size}"
    end

    # size: small, medium, or large.
    def get_room_picture_url(name, size = 'small')
      "http://friendfeed.com/rooms/#{name}/picture?size=#{size}"
    end

  private

    def uri(part)
      begin
        URI.parse(File.join(url_base, part))
      rescue URI::InvalidURIError
      end
    end

    def create_client(name, remote_key)
      client = UserClient.new(name, remote_key, @logger, @http_proxy)
      client.httpclient_max_keepalive = @httpclient_max_keepalive
      client
    end

    def client_sync(uri, name, remote_key)
      @mutex.synchronize do
        clients = {}
        @clients.each do |key, value|
          if value.idle?
            @logger.info("removed idle HTTPClient for #{key}")
          else
            clients[key] = value
          end
        end
        @clients = clients
      end
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
        obj = JSONFilter.parse(res.content)
        logger.debug { JSONFilter.pretty_generate(obj) }
        obj['entries']
      end
    end

    SEARCH_KEY = ['from', 'room', 'friends', 'service', 'intitle', 'incomment', 'comment', 'comments', 'like', 'likes']
    def search_opt_filter(query, opt)
      ary = []
      opt.each do |k, v|
        if SEARCH_KEY.include?(k.to_s)
          opt.delete(k)
          ary << k.to_s + ':' + v.to_s if v
        end
      end
      ary.unshift(query) if query and !query.empty?
      ary.join(' ')
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
          obj = JSONFilter.parse(res.content)
          logger.debug { JSONFilter.pretty_generate(obj) }
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
        JSONFilter.parse(res.content)['update']['token']
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

    def get_profile(name, remote_key, user, opt = {})
      uri = uri("user/#{user}/profile")
      return nil unless uri
      res = client_sync(uri, name, remote_key) { |client|
        get_request(client, uri, opt)
      }
      if res.status == 200
        JSONFilter.parse(res.content)
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
        JSONFilter.parse(res.content)['profiles']
      end
    end

    def get_room_profile(name, remote_key, room, opt = {})
      uri = uri("room/#{room}/profile")
      return nil unless uri
      res = client_sync(uri, name, remote_key) { |client|
        res = get_request(client, uri, opt)
      }
      if res.status == 200
        JSONFilter.parse(res.content)
      end
    end

    def get_list_profile(name, remote_key, list, opt = {})
      uri = uri("list/#{list}/profile")
      return nil unless uri
      res = client_sync(uri, name, remote_key) { |client|
        res = get_request(client, uri, opt)
      }
      if res.status == 200
        JSONFilter.parse(res.content)
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
      get_feed(uri, name, remote_key, query)
    end

    def search_entries(name, remote_key, query, opt = {})
      uri = uri("feed/search")
      opt[:q] = search_opt_filter(query, opt)
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
          file, file_link, content_type = file
          unless file.respond_to?(:read)
            file = StringIO.new(file.to_s)
            class << file
              attr_accessor :mime_type
            end
            file.mime_type = content_type
          end
          query["file#{idx}"] = file
          query["file#{idx}_link"] = file_link
        end
      end
      query['room'] = room if room
      client_sync(uri, name, remote_key) do |client|
        res = post_request(client, uri, query)
        JSONFilter.parse(res.content)['entries']
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
        JSONFilter.parse(res.content)
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
        JSONFilter.parse(res.content)
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

    def hide(name, remote_key, entry, unhide = false)
      uri = uri("entry/hide")
      query = {'entry' => entry}
      query['unhide'] = 1 if unhide
      client_sync(uri, name, remote_key) do |client|
        post_request(client, uri, query)
      end
    end

  private

    def url_base
      URL_BASE
    end
  end

  class APIV2Client < BaseClient
    URL_BASE = 'http://friendfeed-api.com/v2/'

    # Reading data from FriendFeed
    def get_feed(fid, opt = {})
      uri = uri("feed/#{fid}")
      return nil unless uri
      query = opt.dup
      name, remote_key = get_credential!(query)
      get_and_parse(uri, name, remote_key, query)
    end

    def search(q, opt = {})
      uri = uri("search")
      return nil unless uri
      query = opt.dup
      name, remote_key = get_credential!(query)
      query[:q] = search_opt_filter(q, query)
      get_and_parse(uri, name, remote_key, query)
    end

    def feedlist(opt = {})
      uri = uri("feedlist")
      return nil unless uri
      query = opt.dup
      name, remote_key = get_credential!(query)
      get_and_parse(uri, name, remote_key, query)
    end

    def feedinfo(fid, opt = {})
      uri = uri("feedinfo/#{fid}")
      return nil unless uri
      query = opt.dup
      name, remote_key = get_credential!(query)
      get_and_parse(uri, name, remote_key, query)
    end
    alias profile feedinfo

    def get_entries(*args)
      if args.last.is_a?(Hash)
        query = args.pop.dup
      else
        query = {}
      end
      uri = uri("entry")
      return nil unless uri
      name, remote_key = get_credential!(query)
      query[:id] = args.join(',')
      get_and_parse(uri, name, remote_key, query)
    end

    def get_entry(eid, opt = {})
      uri = uri("entry/#{eid}")
      return nil unless uri
      query = opt.dup
      name, remote_key = get_credential!(query)
      get_and_parse(uri, name, remote_key, query)
    end

    def post(to, body, opt = {})
      uri = uri("entry")
      return nil unless uri
      query = opt.dup
      name, remote_key = get_credential!(query)
      query[:to] = [*to].join(',')
      query[:body] = body
      set_if(query, opt, :link)
      set_if(query, opt, :comment)
      set_if(query, opt, :image_url)
      if opt[:file]
        query[:file] = opt[:file].map { |file|
          file, content_type = file
          unless file.respond_to?(:read)
            file = StringIO.new(file.to_s)
            class << file
              attr_accessor :mime_type
            end
            file.mime_type = content_type
          end
          file
        }
      end
      client_sync(uri, name, remote_key) do |client|
        res = post_request(client, uri, query)
        parse_response(res)
      end
    end

  private

    def get_credential!(query = nil)
      if query.nil?
        return [@name, @remote_key]
      end
      name = query.delete(:name) || @name
      remote_key = query.delete(:remote_key) || @remote_key
      [name, remote_key]
    end

    def set_if(new, old, key)
      new[key] = old[key] if old.key?(key)
    end

    def url_base
      URL_BASE
    end

    def get_and_parse(uri, name, remote_key, opt = {})
      res = client_sync(uri, name, remote_key) { |client|
        get_request(client, uri, opt)
      }
      parse_response(res)
    end

    def parse_response(res)
      if res.status == 200
        JSONFilter.parse(res.content)
      end
    end
  end
end

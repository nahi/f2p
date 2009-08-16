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

    attr_accessor :oauth_consumer_key
    attr_accessor :oauth_consumer_secret
    attr_accessor :oauth_site
    attr_accessor :oauth_scheme
    attr_accessor :oauth_signature_method

    attr_accessor :json_parse_size_limit

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
      attr_accessor :oauth_site
      attr_accessor :oauth_config

      def initialize(name, logger, http_proxy)
        @client = HTTPClient.new(http_proxy)
        @name = name
        @cred = nil
        @oauth_site = nil
        @oauth_config = ::HTTPClient::OAuth::Config.new
        #@client.debug_dev = LShiftLogger.new(logger)
        @logger = logger
        @client.extend(MonitorMixin)
        @last_accessed = Time.now
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

      def client(uri, cred = nil)
        @client.synchronize do
          if cred != @cred
            @cred = cred
            reset_auth
          end
          @client.www_auth.basic_auth.challenge(uri)
          @client.www_auth.oauth.challenge(uri)
          @last_accessed = Time.now
          @client
        end
      end

      def inspect
        sprintf("#<%s:0x%x>", self.class.name, object_id)
      end

    private

      def reset_auth
        if @cred.is_a?(Hash)
          # OAuth Hash
          @oauth_config.token = @cred[:access_token]
          @oauth_config.secret = @cred[:access_token_secret]
          @client.www_auth.oauth.set_config(@oauth_site, @oauth_config)
        else
          # remote key
          @client.set_auth(nil, @name, @cred)
        end
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
      @oauth_consumer_key = nil
      @oauth_consumer_secret = nil
      @oauth_site = nil
      @oauth_scheme = nil
      @oauth_signature_method = nil
      @json_parse_size_limit = nil
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

    def create_client(name)
      client = UserClient.new(name, @logger, @http_proxy)
      client.httpclient_max_keepalive = @httpclient_max_keepalive
      client.oauth_site = @oauth_site
      client.oauth_config.consumer_key = @oauth_consumer_key
      client.oauth_config.consumer_secret = @oauth_consumer_secret
      client.oauth_config.signature_method = @oauth_signature_method
      client
    end

    def client_sync(uri, name, cred = nil)
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
      user_client = @clients[name] ||= create_client(name)
      client = user_client.client(uri, cred)
      logger.info("#{user_client.inspect} is accessing to #{uri.to_s} for #{name}")
      httpclient_protect do
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

    def post_request(client, uri, query = {}, ext = {})
      if @apikey
        if query.is_a?(Hash)
          query = query.merge(:apikey => @apikey)
        else
          query << [:apikey, @apikey]
        end
      end
      client.post(uri, query, ext)
    end

    def request(client, method, uri, query = nil, body = nil, ext = {})
      if @apikey
        if query.is_a?(Hash)
          query = query.merge(:apikey => @apikey)
        else
          query << [:apikey, @apikey]
        end
      end
      client.request(method, uri, query, body, ext)
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
    URL_BASE = 'https://friendfeed-api.com/v2/'

    def initialize(*arg)
      super
    end

    # wrapper method for V1 compatibility
    def validate(name, remote_key)
      uri = uri("validate")
      return false unless uri
      res = client_sync(uri, name, remote_key) { |client|
        get_request(client, uri)
      }
      res.status == 200
    end

    # validate OAuth credential
    def oauth_validate(opt)
      uri = uri("validate")
      uri.scheme = 'http'
      uri = URI.parse(uri.to_s)
      return false unless uri
      cred = get_credential(opt)
      return false unless cred.first == :oauth
      name, oauth = cred[1]
      res = client_sync(uri, name, oauth) { |client|
        get_request(client, uri)
      }
      res.status == 200
    end

    # Reading data from FriendFeed
    def feed(fid, opt = {})
      uri = uri("feed/#{fid}")
      return nil unless uri
      query = opt.dup
      cred = get_credential!(query)
      get_and_parse(uri, cred, query)
    end

    def search(q, opt = {})
      uri = uri("search")
      return nil unless uri
      query = opt.dup
      cred = get_credential!(query)
      query[:q] = search_opt_filter(q, query)
      get_and_parse(uri, cred, query)
    end

    def feedlist(opt = {})
      uri = uri("feedlist")
      return nil unless uri
      query = opt.dup
      cred = get_credential!(query)
      get_and_parse(uri, cred, query)
    end

    def feedinfo(fid, opt = {})
      uri = uri("feedinfo/#{fid}")
      return nil unless uri
      query = opt.dup
      cred = get_credential!(query)
      get_and_parse(uri, cred, query)
    end
    alias profile feedinfo

    def entries(*args)
      if args.last.is_a?(Hash)
        query = args.pop.dup
      else
        query = {}
      end
      uri = uri("entry")
      return nil unless uri
      cred = get_credential!(query)
      query[:id] = args.join(',')
      get_and_parse(uri, cred, query)
    end

    def entry(eid, opt = {})
      uri = uri("entry/#{eid}")
      return nil unless uri
      query = opt.dup
      cred = get_credential!(query)
      get_and_parse(uri, cred, query)
    end

    def url(opt = {})
      uri = uri("url")
      return nil unless uri
      query = opt.dup
      cred = get_credential!(query)
      get_and_parse(uri, cred, query)
    end

    # Publishing to FriendFeed
    def post_entry(to, body, opt = {})
      uri = uri("entry")
      return nil unless uri
      to = [*to] # idiom for to_a
      to << 'me' if to.empty?
      cred = get_credential(opt)
      query = {}
      query[:to] = to.join(',')
      query[:body] = body
      set_if(query, opt, :link)
      set_if(query, opt, :comment)
      set_if(query, opt, :image_url)
      set_if(query, opt, :audio_url)
      set_if(query, opt, :short)
      set_if(query, opt, :geo)
      ext = {}
      query = query.to_a
      if opt[:file]
        opt[:file].each do |filedef|
          file, content_type, filename = filedef
          unless file.respond_to?(:read)
            file = StringIO.new(file.to_s)
            class << file
              attr_accessor :mime_type
              attr_accessor :path
            end
            file.mime_type = content_type
            file.path = filename
          end
          file
          query << [:file, file]
        end
        boundary = Digest::SHA1.hexdigest(Time.now.to_s)
        ext['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      end
      post_and_parse(uri, cred, query, ext)
    end

    def edit_entry(eid, opt)
      uri = uri("entry")
      return nil unless uri
      cred = get_credential(opt)
      query = {}
      query[:id] = eid
      if opt[:to]
        query[:to] = opt[:to].join(',')
      end
      set_if(query, opt, :body)
      set_if(query, opt, :link)
      set_if(query, opt, :comment)
      set_if(query, opt, :image_url)
      set_if(query, opt, :audio_url)
      set_if(query, opt, :short)
      set_if(query, opt, :geo)
      ext = {}
      query = query.to_a
      if opt[:file]
        opt[:file].each do |filedef|
          file, content_type, filename = filedef
          unless file.respond_to?(:read)
            file = StringIO.new(file.to_s)
            class << file
              attr_accessor :mime_type
              attr_accessor :path
            end
            file.mime_type = content_type
            file.path = filename
          end
          file
          query << [:file, file]
        end
        boundary = Digest::SHA1.hexdigest(Time.now.to_s)
        ext = { 'Content-Type' => "multipart/form-data; boundary=#{boundary}" }
      end
      post_and_parse(uri, cred, query, ext)
    end

    def delete_entry(eid, opt = {})
      uri = uri("entry/delete")
      return nil unless uri
      cred = get_credential(opt)
      query = {}
      query[:id] = eid
      post_and_parse(uri, cred, query)
    end

    def undelete_entry(eid, opt = {})
      uri = uri("entry/delete")
      return nil unless uri
      cred = get_credential(opt)
      query = {}
      query[:id] = eid
      query[:undelete] = 1
      post_and_parse(uri, cred, query)
    end

    def post_comment(eid, body, opt = {})
      uri = uri("comment")
      return nil unless uri
      cred = get_credential(opt)
      query = {}
      query[:entry] = eid
      query[:body] = body
      post_and_parse(uri, cred, query)
    end

    def edit_comment(cid, body, opt = {})
      uri = uri("comment")
      return nil unless uri
      cred = get_credential(opt)
      query = {}
      query[:id] = cid
      query[:body] = body
      post_and_parse(uri, cred, query)
    end

    def delete_comment(cid, opt = {})
      uri = uri("comment/delete")
      return nil unless uri
      cred = get_credential(opt)
      query = {}
      query[:id] = cid
      post_and_parse(uri, cred, query)
    end

    def undelete_comment(cid, opt = {})
      uri = uri("comment/delete")
      return nil unless uri
      cred = get_credential(opt)
      query = {}
      query[:id] = cid
      query[:undelete] = 1
      post_and_parse(uri, cred, query)
    end

    def like(eid, opt = {})
      uri = uri("like")
      return nil unless uri
      perform_entry_action(uri, eid, opt)
    end

    def delete_like(eid, opt = {})
      uri = uri("like/delete")
      return nil unless uri
      perform_entry_action(uri, eid, opt)
    end

    def subscribe(fid, opt = {})
      uri = uri("subscribe")
      return nil unless uri
      cred = get_credential(opt)
      query = {}
      query[:feed] = fid
      query[:list] = opt[:list] if opt.key?(:list)
      post_and_parse(uri, cred, query)
    end

    def unsubscribe(fid, opt = {})
      uri = uri("unsubscribe")
      return nil unless uri
      cred = get_credential(opt)
      query = {}
      query[:feed] = fid
      query[:list] = opt[:list] if opt.key?(:list)
      post_and_parse(uri, cred, query)
    end

    def hide_entry(eid, opt = {})
      uri = uri("hide")
      return nil unless uri
      perform_entry_action(uri, eid, opt)
    end

    def unhide_entry(eid, opt = {})
      uri = uri("hide")
      return nil unless uri
      cred = get_credential(opt)
      query = {}
      query[:entry] = eid
      query[:unhide] = 1
      post_and_parse(uri, cred, query)
    end

    def create_short_url(eid, opt = {})
      uri = uri("short")
      return nil unless uri
      perform_entry_action(uri, eid, opt)
    end

  private

    def perform_entry_action(uri, eid, opt)
      cred = get_credential(opt)
      query = {}
      query[:entry] = eid
      post_and_parse(uri, cred, query)
    end

    def get_credential(query = {})
      get_credential!(query.dup)
    end

    def get_credential!(query = nil)
      if query.key?(:oauth_token) and query.key?(:oauth_token_secret)
        name = query.delete(:name) || @name
        oauth_token = query.delete(:oauth_token)
        oauth_token_secret = query.delete(:oauth_token_secret)
        [:oauth, [name, {:access_token => oauth_token, :access_token_secret => oauth_token_secret}]]
      else
        if query.nil?
          name = @name
          remote_key = @remote_key
        else
          name = query.delete(:name) || @name
          remote_key = query.delete(:remote_key) || @remote_key
        end
        [:basicauth, [name, remote_key]]
      end
    end

    def set_if(new, old, key)
      new[key] = old[key] if old.key?(key) and old[key]
    end

    def url_base
      URL_BASE
    end

    def get_and_parse(uri, cred, query = {})
      case cred.first
      when :basicauth
        name, remote_key = cred[1]
        query = add_appid_for_basicauth(query)
        res = client_sync(uri, name, remote_key) { |client|
          get_request(client, uri, query)
        }
        parse_response(res)
      when :oauth
        uri.scheme = 'http'
        uri = URI.parse(uri.to_s)
        name, oauth = cred[1]
        res = client_sync(uri, name, oauth) { |client|
          get_request(client, uri, query)
        }
        parse_response(res)
      else
        raise "unsupported scheme: #{cred.first}"
      end
    end

    def post_and_parse(uri, cred, query = {}, ext = {})
      case cred.first
      when :basicauth
        name, remote_key = cred[1]
        query = add_appid_for_basicauth(query)
        res = client_sync(uri, name, remote_key) { |client|
          post_request(client, uri, query, ext)
        }
        parse_response(res)
      when :oauth
        # OAuth + multipart/form-data seems to be fairly complex issue.
        # No clear definition in OAuth Core 1.0 spec. Let's do it in this way;
        #   1. When Content-Type is multipart/form-data (for stream upload)
        #   2. Use HTTP message-body only for uploading streams.  What must
        #      be a stream is application specific.
        #      For example, FriendFeed API V2 defines multipart parameter
        #      which hash 'Content-Disposition' with 'filename' is a stream.
        #   3. Other (non stream) parameters must be in HTTP Request-URI as
        #      an encoded query part of URI (RFC3986). Bear in mind that
        #      it's not embedded in body so Content-Type is not
        #      'application/x-www-urlencoded'.
        #   4. For OAuth signature calculation, treat parameters stated #3
        #      as if it's from a HTTP request body in
        #      'application/x-www-urleocoded' content-type. This means that
        #      stream parameters are not signed.
        uri.scheme = 'http'
        uri = URI.parse(uri.to_s)
        name, oauth = cred[1]
        file = query.find_all { |k, v| k == :file }
        unless file.empty?
          query = query.find_all { |k, v| k != :file }
          res = client_sync(uri, name, oauth) { |client|
            request(client, :post, uri, query, file)
          }
        else
          res = client_sync(uri, name, oauth) { |client|
            post_request(client, uri, query, ext)
          }
        end
        parse_response(res)
      else
        raise "unsupported scheme: #{cred.first}"
      end
    end

    def add_appid_for_basicauth(query)
      if @oauth_consumer_key
        if query.is_a?(Hash)
          query.merge(:appid => @oauth_consumer_key)
        else
          query + [[:appid, @oauth_consumer_key]]
        end
      else
        query
      end
    end

    def parse_response(res)
      if res.status == 200
        if @json_parse_size_limit and res.content.size > @json_parse_size_limit
          logger.warn("too big JSON stream: #{res.content.size}")
          nil
        else
          JSONFilter.parse(res.content)
        end
      end
    end

    def create_access_token(auth, opt = {})
      access_token = auth[:access_token]
      access_token_secret = auth[:access_token_secret]
      OAuth::AccessToken.new(create_oauth_consumer(opt), access_token, access_token_secret)
    end

    def create_oauth_consumer(opt = {})
      opt = {
        :site              => @oauth_site,
        :scheme            => @oauth_scheme,
        :signature_method  => @oauth_signature_method,
        :proxy             => @http_proxy || ENV['http_proxy']
      }.merge(opt)
      OAuth::Consumer.new(@oauth_consumer_key, @oauth_consumer_secret, opt)
    end
  end
end

if __FILE__ == $0
  require 'test/unit'
  require 'logger'

  class APIV2ClientTest < Test::Unit::TestCase
    def setup
      cred = JSON.parse(File.read(File.expand_path("~/.fftest_credential")))
      @test_user = cred['name']
      @test_key = cred['remote_key']
      logger = Logger.new('ff.log')
      @v1 = FriendFeed::APIClient.new
      @tc = FriendFeed::APIV2Client.new(logger)
      @tc.name = @test_user
      @tc.remote_key = @test_key
    end

    def test_validate
      assert(@tc.validate(@test_user, @test_key))
      assert(!@tc.validate(@test_user, 'dummy'))
    end

    def test_post_entry
      to = ['me']
      body = 'test body'
      e1 = @tc.post_entry(to, body)
      e2 = @tc.entry(e1['id'])
      assert_equal(e1['id'], e2['id'])
      posted = JSON.pretty_generate(e2)
      #
      @tc.edit_entry(e1['id'], :body => 'test body 2')
      e2 = @tc.entry(e1['id'])
      edited = JSON.pretty_generate(e2)
      assert_match(/test body 2/, edited)
      @tc.edit_entry(e1['id'], :body => 'test body')
      e2 = @tc.entry(e1['id'])
      edited = JSON.pretty_generate(e2)
      assert_equal(posted, edited)
      #
      @tc.delete_entry(e1['id'])
      assert_nil(@tc.entry(e1['id']))
      @tc.undelete_entry(e1['id'])
      assert_not_nil(@tc.entry(e1['id']))
      @tc.delete_entry(e1['id'])
    end

    def test_post_geo_entry
      to = ['me']
      body = 'test body'
      e1 = @tc.post_entry(to, body, :geo => "35.69169,139.770883")
      e2 = @tc.entry(e1['id'])
      geo = { "lat" => 35.69169, "long" => 139.770883 }
      assert_equal(geo, e2['geo'])
      #
      @tc.delete_entry(e1['id'])
    end

    def test_post_comment
      to = ['me']
      body = 'test body'
      e1 = @tc.post_entry(to, body)
      assert_nil(e1['comments'])
      #
      c1 = @tc.post_comment(e1['id'], 'test comment')
      assert(c1)
      e2 = @tc.entry(e1['id'])
      c2 = e2['comments'].find { |c| c['id'] == c1['id'] }
      assert(c2)
      assert_equal('test comment', c2['body'])
      #
      @tc.edit_comment(c1['id'], 'test comment 2')
      e2 = @tc.entry(e1['id'])
      c2 = e2['comments'].find { |c| c['id'] == c1['id'] }
      assert(c2)
      assert_equal('test comment 2', c2['body'])
      #
      @tc.delete_comment(c1['id'])
      e2 = @tc.entry(e1['id'])
      assert_nil(e2['comments'])
      @tc.undelete_comment(c1['id'])
      e2 = @tc.entry(e1['id'])
      assert(e2['comments'])
      #
      @tc.delete_entry(e1['id'])
    end

    def test_like
      to = ['me']
      body = 'test body'
      e1 = @tc.post_entry(to, body)
      # cannot like self entry
      assert_nil(@tc.like(e1['id']))
      @tc.delete_entry(e1['id'])
    end

    def test_home_feed
      opt = {:num => 30}
      v2_opt = opt.merge(:fof => 1, :hidden => 1)
      actual = @tc.feed('home', v2_opt)['entries']
      expected = @v1.get_home_entries(@test_user, @test_key, opt)
      assert_equal(expected.size, actual.size)
      e_ids = expected.map { |e| conv_to_new_eid(e['id']) }
      a_ids = actual.map { |e| e['id'] }
      e_ids.each_with_index do |e, idx|
        assert_equal(e, a_ids[idx])
      end
    end

    def test_my_feed
      opt = {:num => 30}
      actual = @tc.feed(@test_user, opt)['entries']
      expected = @v1.get_user_entries(@test_user, @test_key, @test_user, opt)
      assert_equal(expected.size, actual.size)
      actual.each_with_index do |a, idx|
        e = expected[idx]
        assert_equal(conv_to_new_eid(e['id']), a['id'])
      end
    end

    def test_search
      actual = @tc.search('f2p', :service => 'internal', :num => 10)['entries']
      assert_equal(10, actual.size)
    end

    def test_feedlist
      feedlist = @tc.feedlist
      assert_equal(4, feedlist['main'].size)
      assert_equal(3, feedlist['lists'].size)
      assert_equal(2, feedlist['groups'].size)
      assert_equal(2, feedlist['searches'].size)
      assert_equal(3, feedlist['sections'].size)
    end

    def test_feedinfo
      feedinfo = @tc.feedinfo('list/personal')
      assert_equal('パーソナル', feedinfo['name'])
      assert_equal(3, feedinfo['feeds'].size)
      #
      profile = @tc.profile('nahi') # same thing
      assert_equal('Hiroshi Nakamura', profile['name'])
      assert(!profile['subscriptions'].empty?)
      assert(!profile['subscribers'].empty?)
      assert(!profile['services'].empty?)
      #
      profile = @tc.profile('f2ptest-room') # same thing
      assert_equal('f2ptest_room', profile['name'])
      assert(!profile['subscribers'].empty?)
      assert(!profile['admins'].empty?)
      assert(profile['services'].empty?)
    end

    def test_entries
      expected = @tc.feed('home')['entries']
      ids = expected.map { |e| e['id'] }
      actual = @tc.entries(ids)['entries']
      # NB: order of retrieved entries does not match with request ids.
      assert((actual.map { |e| e['id'] } - ids).empty?)
    end

  private

    def conv_to_new_eid(id)
      'e/' + id.gsub(/-/, '')
    end
  end
end

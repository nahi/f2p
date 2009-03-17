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
      def initialize(name, remote_key, logger)
        @client = HTTPClient.new
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

    private

      def reset_auth
        @client.set_auth(nil, @name, @remote_key)
      end
    end

    def initialize(logger = nil)
      @logger = logger || NullLogger.new
      @clients = {}
    end

  private

    def create_client(name, remote_key)
      UserClient.new(name, remote_key, @logger)
    end

    def client_sync(uri, name, remote_key)
      user_client = @clients[name] ||= create_client(name, remote_key)
      client = user_client.client(remote_key)
      logger.info("#{self.class} is accessing to #{uri.to_s} with client #{client.object_id} for #{name}")
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
      logger.info("elapsed: #{Time.now - start} [sec]")
      result
    end
  end

  class ChannelClient < BaseClient
    URL_BASE = 'http://chan.friendfeed.com/api/'

    def get_token
      uri = uri("updates")
      query = { :format => 'json', :timeout => 0 }
      JSON.parse(client.get(uri, query).content)['update']['token']
    end

    def get_home_entries(name, remote_key, token, opt = {})
      uri = uri("updates/home")
      query = opt.merge(:token => token, :format => 'json')
      client_sync(uri, name, remote_key) do |client|
        JSON.parse(client.get(uri, query).content)
      end
    end

  private

    def uri(part)
      uri = URI.parse(File.join(URL_BASE, part))
    end
  end

  class APIClient < BaseClient
    URL_BASE = 'https://friendfeed.com/api/'

    def validate(name, remote_key)
      uri = uri('validate')
      client_sync(uri, name, remote_key) do |client|
        client.get(uri).status == 200
      end
    end

    # size: small, medium, or large.
    def get_user_picture_url(name, size = 'small')
      "http://friendfeed.com/#{name}/picture?size=#{size}"
    end

    # size: small, medium, or large.
    def get_room_picture_url(name, size = 'small')
      "http://friendfeed.com/rooms/#{name}/picture?size=#{size}"
    end

    def get_profile(name, remote_key, user = nil)
      uri = uri("user/#{user || name}/profile")
      client_sync(uri, name, remote_key) do |client|
        JSON.parse(client.get(uri).content)
      end
    end

    def get_room_profile(name, remote_key, room)
      uri = uri("room/#{room}/profile")
      client_sync(uri, name, remote_key) do |client|
        JSON.parse(client.get(uri).content)
      end
    end

    def get_entry(name, remote_key, eid, opt = {})
      uri = uri("feed/entry/#{eid}")
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri, opt)
      end
    end

    def get_entries(name, remote_key, eids, opt = {})
      uri = uri("feed/entry")
      opt = opt.merge(:entry_id => eids.join(','))
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri, opt)
      end
    end

    def get_home_entries(name, remote_key, opt = {})
      uri = uri("feed/home")
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri, opt)
      end
    end

    def get_list_entries(name, remote_key, list, opt = {})
      uri = uri("feed/list/#{list}")
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri, opt)
      end
    end

    def get_user_entries(name, remote_key, user, opt = {})
      uri = uri("feed/user/#{user}")
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri, opt)
      end
    end

    def get_friends_entries(name, remote_key, user, opt = {})
      uri = uri("feed/user/#{user}/friends")
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri, opt)
      end
    end

    def get_room_entries(name, remote_key, room = nil, opt = {})
      if room.nil?
        uri = uri("feed/rooms")
      else
        uri = uri("feed/room/#{room}")
      end
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri, opt)
      end
    end

    def get_comments(name, remote_key, opt = {})
      uri = uri("feed/user/#{name}/comments")
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri, opt)
      end
    end

    def get_likes(name, remote_key, user, opt = {})
      uri = uri("feed/user/#{user}/likes")
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri, opt)
      end
    end

    def get_url_entries(name, remote_key, url, opt = {})
      uri = uri("feed/url")
      query = opt.merge(:url => url)
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri, query)
      end
    end

    def search_entries(name, remote_key, query, opt = {})
      uri = uri("feed/search")
      opt = opt.merge(:q => query)
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri, opt)
      end
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
          query["file#{idx}"] = file
          query["file#{idx}_link"] = file_link
        end
      end
      query['room'] = room if room
      client_sync(uri, name, remote_key) do |client|
        res = client.post(uri, query)
        JSON.parse(res.content)['entries']
      end
    end

    def delete(name, remote_key, entry, undelete = false)
      uri = uri("entry/delete")
      query = { 'entry' => entry }
      query['undelete'] = 1 if undelete
      client_sync(uri, name, remote_key) do |client|
        client.post(uri, query)
      end
    end

    def post_comment(name, remote_key, entry, body)
      uri = uri("comment")
      query = {
        'entry' => entry,
        'body' => body
      }
      client_sync(uri, name, remote_key) do |client|
        res = client.post(uri, query)
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
        client.post(uri, query)
      end
    end

    def like(name, remote_key, entry)
      uri = uri("like")
      query = {'entry' => entry}
      client_sync(uri, name, remote_key) do |client|
        client.post(uri, query)
      end
    end

    def unlike(name, remote_key, entry)
      uri = uri("like/delete")
      query = {'entry' => entry}
      client_sync(uri, name, remote_key) do |client|
        client.post(uri, query)
      end
    end

  private

    def uri(part)
      uri = URI.parse(File.join(URL_BASE, part))
    end

    def get_feed(client, uri, query = {})
      logger.info("getting entries with query: " + query.inspect)
      ext = { 'Accept-Encoding' => 'gzip' }
      res = client.get(uri, query, ext)
      enc = res.header['content-encoding']
      if enc and enc[0] and enc[0].downcase == 'gzip'
        content = Zlib::GzipReader.wrap(StringIO.new(res.content)) { |gz| gz.read }
      else
        content = res.content
      end
      JSON.parse(content)['entries']
    end
  end
end


if $0 == __FILE__
  name = ARGV.shift or raise
  remote_key = ARGV.shift or raise
  client = FriendFeed::APIClient.new
  require 'pp'
  pp client.get_home_entries(name, remote_key)
end

require 'httpclient'
require 'uri'
require 'json'
require 'monitor'
require 'stringio'
require 'zlib'


module FriendFeed
  class APIClient
    URL_BASE = 'https://friendfeed.com/api/'

    attr_reader :client
    attr_accessor :logger

    class NullLogger
      def method_missing(msg_id, *a, &b)
      end
    end

    def initialize(logger = nil)
      @logger = logger || NullLogger.new
      @client = HTTPClient.new
      @client.extend(MonitorMixin)
    end

    def validate(name, remote_key)
      uri = uri('validate')
      client_sync(uri, name, remote_key) do |client|
        client.get(uri).status == 200
      end
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
        client.post(uri, query)
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
        client.post(uri, query)
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

    def client_sync(uri, name, remote_key)
      logger.info("APIClient is accessing to #{uri.to_s}")
      @client.synchronize do
        httpclient_protect do
          @client.set_auth(nil, name, remote_key)
          @client.www_auth.basic_auth.challenge(uri, true)
          result = yield(@client)
          @client.set_auth(nil, nil, nil)
          result
        end
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
      logger.info("APIClient elapsed: #{Time.now - start} [sec]")
      result
    end

    def get_feed(client, uri, query = {})
      ext = { 'Accept-Encoding' => 'gzip' }
      res = client.get(uri, query, ext)
      enc = res.header['content-encoding']
      if enc and enc[0] and enc[0].downcase == 'gzip'
        begin
          gz = Zlib::GzipReader.new(StringIO.new(res.content))
          content = gz.read
        ensure
          gz.close
        end
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

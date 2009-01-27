require 'httpclient'
require 'uri'
require 'json'
require 'monitor'


module FriendFeed
  class APIClient
    URL_BASE = 'http://friendfeed.com/api/'

    def initialize
      @client = HTTPClient.new
      @client.extend(MonitorMixin)
    end

    def validate(name, remote_key)
      uri = uri('validate')
      client_sync(uri, name, remote_key) do |client|
        client.get(uri).status == 200
      end
    end

    def get_profile(name, remote_key)
      uri = uri("user/#{name}/profile")
      client_sync(uri, name, remote_key) do |client|
        JSON.parse(client.get(uri).content)
      end
    end

    def get_entry(name, remote_key, eid)
      uri = uri("feed/entry/#{eid}")
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri)
      end
    end

    def get_home_entries(name, remote_key, opt = {})
      uri = uri("feed/home")
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

    def get_comments(name, remote_key)
      uri = uri("feed/user/#{name}/comments")
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri)
      end
    end

    def get_likes(name, remote_key)
      uri = uri("feed/user/#{name}/likes")
      client_sync(uri, name, remote_key) do |client|
        get_feed(client, uri)
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

  private

    def uri(part)
      uri = URI.parse(File.join(URL_BASE, part))
    end

    def client_sync(uri, name, remote_key)
      @client.synchronize do
        @client.www_auth.basic_auth.challenge(uri, true)
        @client.set_auth(nil, name, remote_key)
        result = yield(@client)
        @client.set_auth(nil, nil, nil)
        result
      end
    end

    def get_feed(client, uri, query = {})
      JSON.parse(client.get(uri, query).content)['entries']
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

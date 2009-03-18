require 'hash_utils'


class Room < Hash
  include HashUtils

  class << self
    def ff_id(arg)
      auth = arg[:auth]
      room = arg[:room]
      ff_profile(auth, room)['id']
    end

    def ff_name(arg)
      auth = arg[:auth]
      room = arg[:room]
      ff_profile(auth, room)['name']
    end

    def ff_url(arg)
      auth = arg[:auth]
      room = arg[:room]
      ff_profile(auth, room)['url']
    end

    def status(arg)
      auth = arg[:auth]
      room = arg[:room]
      ff_profile(auth, room)['status']
    end

    def description(arg)
      auth = arg[:auth]
      room = arg[:room]
      ff_profile(auth, room)['description']
    end

    def picture_url(arg)
      room = arg[:room]
      size = arg[:size] || 'small'
      ff_picture_url(room, size)
    end

    def members(arg)
      auth = arg[:auth]
      room = arg[:room]
      sort_by_name(ff_profile(auth, room)['members'] || [])
    end

  private

    def ff_picture_url(room, size = 'small')
      ff_client.get_room_picture_url(room, size)
    end

    def ff_profile(auth, room)
      ff_client.get_room_profile(auth.name, auth.remote_key, room) || {}
    end

    def sort_by_name(lists)
      lists.sort_by { |e| e['name'] }
    end

    def ff_client
      ApplicationController.ff_client
    end
  end

  def id
    v('id')
  end

  def nickname
    v('nickname')
  end

  def name
    v('name')
  end
end

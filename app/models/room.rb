require 'hash_utils'


class Room < Hash
  include HashUtils

  class << self
    def members(arg)
      auth = arg[:auth]
      room = arg[:room]
      sort_by_name(ff_profile(auth, room)['members'] || [])
    end

  private

    def ff_profile(auth, room)
      ff_client.get_room_profile(auth.name, auth.remote_key, room)
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

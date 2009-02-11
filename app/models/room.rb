require 'hash_utils'


class Room < Hash
  include HashUtils

  class << self
    def members(arg)
      name = arg[:name]
      remote_key = arg[:remote_key]
      room = arg[:room]
      sort_by_name(ff_profile(name, remote_key, room)['members'] || [])
    end

  private

    def ff_profile(name, remote_key, room)
      ff_client.get_room_profile(name, remote_key, room)
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

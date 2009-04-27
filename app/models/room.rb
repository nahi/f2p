require 'hash_utils'


class Room
  include HashUtils

  class << self
    def ff_picture_url(room, size = 'small')
      ff_client.get_room_picture_url(room, size)
    end

    def ff_profile(auth, room)
      convert_profile(ff_client.get_room_profile(auth.name, auth.remote_key, room) || {})
    end

    def ff_status_map(auth, rooms)
      ff_client.get_room_status(auth.name, auth.remote_key, rooms)
    end

  private

    def convert_profile(profile)
      profile = profile.dup
      if list = profile['members']
        profile['members'] = sort_by_name(list.map { |e| EntryUser[e] })
      end
      profile
    end

    def sort_by_name(lists)
      lists.sort_by { |e| e.name }
    end

    def ff_client
      ApplicationController.ff_client
    end
  end

  attr_accessor :id
  attr_accessor :name
  attr_accessor :nickname

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'name', 'nickname')
  end
end

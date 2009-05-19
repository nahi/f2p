require 'hash_utils'


class List
  include HashUtils

  class << self
    def ff_profile(auth, list)
      convert_profile(ff_client.get_list_profile(auth.name, auth.remote_key, list) || {})
    end

  private

    def convert_profile(profile)
      profile = profile.dup
      if rooms = profile['rooms']
        profile['rooms'] = sort_by_name(rooms.map { |e| Room[e] })
      end
      if users = profile['users']
        profile['users'] = sort_by_name(users.map { |e| EntryUser[e] })
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
  attr_accessor :url

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'name', 'nickname', 'url')
  end
end

require 'hash_utils'


class EntryUser
  include HashUtils

  attr_accessor :id
  attr_accessor :name
  attr_accessor :nickname
  attr_accessor :profile_url

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'name', 'nickname')
    @profile_url = hash['profileUrl']
  end
end

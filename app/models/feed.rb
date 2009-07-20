require 'hash_utils'


class Feed
  include HashUtils

  attr_accessor :id
  attr_accessor :name
  attr_accessor :type
  attr_accessor :entries

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'name', 'type')
  end
end

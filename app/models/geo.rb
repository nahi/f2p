require 'hash_utils'


class Geo
  include HashUtils

  attr_accessor :lat
  attr_accessor :long

  def initialize(hash)
    initialize_with_hash(hash, 'lat', 'long')
  end
end

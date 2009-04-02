require 'hash_utils'


class Via
  include HashUtils

  attr_accessor :name
  attr_accessor :url

  def initialize(hash)
    initialize_with_hash(hash, 'name', 'url')
  end
end

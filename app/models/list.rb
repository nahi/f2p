require 'hash_utils'


class List
  include HashUtils

  attr_accessor :id
  attr_accessor :name
  attr_accessor :nickname
  attr_accessor :url

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'name', 'nickname', 'url')
  end
end

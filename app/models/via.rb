require 'hash_utils'


class Via
  include HashUtils

  attr_accessor :name
  attr_accessor :url

  def initialize(hash)
    initialize_with_hash(hash, 'name', 'url')
  end

  def twitter?
    self.name == 'Twitter'
  end

  def brightkite?
    self.name == 'brightkite.com'
  end
end

require 'hash_utils'


class Via
  include HashUtils

  attr_accessor :name
  attr_accessor :url

  attr_accessor :service_id

  def initialize(hash = nil)
    initialize_with_hash(hash, 'name', 'url') if hash
    @service_id = nil
  end

  def twitter?
    self.name == 'Twitter'
  end

  def brightkite?
    self.name == 'brightkite.com'
  end
end

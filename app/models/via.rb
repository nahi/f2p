require 'hash_utils'


class Via
  include HashUtils

  attr_accessor :name
  attr_accessor :url

  attr_accessor :service_id
  attr_accessor :service_icon_url

  def initialize(hash)
    initialize_with_hash(hash, 'name', 'url')
    @service_id = @service_icon_url = nil
  end

  def twitter?
    self.name == 'Twitter'
  end

  def brightkite?
    self.name == 'brightkite.com'
  end
end

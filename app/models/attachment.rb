require 'hash_utils'


class Attachment
  include HashUtils

  attr_accessor :url
  attr_accessor :type
  attr_accessor :name
  attr_accessor :size
  attr_accessor :icon

  def initialize(hash)
    initialize_with_hash(hash, 'url', 'type', 'name', 'size', 'icon')
  end
end

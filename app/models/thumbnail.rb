require 'hash_utils'


class Thumbnail
  include HashUtils

  attr_accessor :url
  attr_accessor :width
  attr_accessor :height
  attr_accessor :link
  attr_accessor :player

  def initialize(hash)
    initialize_with_hash(hash, 'url', 'width', 'height', 'link', 'player')
  end
end

require 'hash_utils'


class Media
  include HashUtils
  EMPTY = [].freeze

  class Content
    include HashUtils

    attr_accessor :url
    attr_accessor :type
    attr_accessor :width
    attr_accessor :height

    def initialize(hash)
      initialize_with_hash(hash, 'url', 'type', 'width', 'height')
    end
  end

  attr_accessor :title
  attr_accessor :player
  attr_accessor :link
  attr_accessor :thumbnails
  attr_accessor :contents
  attr_accessor :enclosures

  def initialize(hash)
    initialize_with_hash(hash, 'title', 'player', 'link')
    @thumbnails = (hash['thumbnails'] || EMPTY).map { |e| Content[e] }
    @contents = (hash['content'] || EMPTY).map { |e| Content[e] }
    @enclosures = hash['enclosures'] || EMPTY
  end
end

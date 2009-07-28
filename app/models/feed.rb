require 'hash_utils'


class Feed
  include HashUtils
  EMPTY = [].freeze

  attr_accessor :id
  attr_accessor :name
  attr_accessor :type
  attr_accessor :entries

  attr_accessor :feed_opt

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'name', 'type')
    @entries = (hash['entries'] || EMPTY).map { |e| Entry[e] }
    @feed_opt = nil
  end
end

require 'hash_utils'


class Like
  include HashUtils

  attr_accessor :date
  attr_accessor :from

  def initialize(hash)
    initialize_with_hash(hash, 'date')
    @from = From[hash['from']]
  end

  def from_id
    from.id
  end
end

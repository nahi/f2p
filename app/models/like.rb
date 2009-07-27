require 'hash_utils'


class Like
  include HashUtils

  attr_accessor :date
  attr_accessor :from
  attr_accessor :placeholder
  attr_accessor :num

  def initialize(hash)
    initialize_with_hash(hash, 'date', 'placeholder', 'num')
    @from = From[hash['from']]
  end

  def from_id
    from ? from.id : nil
  end
end

require 'hash_utils'


class Like
  include HashUtils

  attr_accessor :date
  attr_accessor :from
  attr_accessor :placeholder
  attr_accessor :num

  attr_accessor :entry

  def initialize(hash = nil)
    if hash
      initialize_with_hash(hash, 'date', 'placeholder', 'num')
      @from = From[hash['from']]
    end
    @entry = nil
  end

  def from_id
    from ? from.id : nil
  end

  def emphasize?
    entry and entry.view_unread and entry.checked_at < date_at
  end

  def date_at
    @date_at ||= (date ? Time.parse(date) : Time.now)
  end
end

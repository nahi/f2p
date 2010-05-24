require 'hash_utils'


class Comment
  include HashUtils
  EMPTY = [].freeze

  attr_accessor :id
  attr_accessor :date
  attr_accessor :body
  attr_accessor :from
  attr_accessor :via
  attr_accessor :commands
  attr_accessor :clipped
  attr_accessor :placeholder
  attr_accessor :num

  attr_accessor :index
  attr_accessor :entry
  attr_accessor :view_links

  def initialize(hash = nil)
    initialize_with_hash(hash, 'id', 'date', 'commands', 'clipped', 'placeholder', 'num') if hash
    @body = hash && hash['rawBody']
    @commands ||= EMPTY
    @from = hash && From[hash['from']]
    @via = hash && Via[hash['via']]
    @index = nil
    @entry = nil
    @view_links = nil
    @date ||= ''
  end

  def from_id
    from ? from.id : nil
  end

  def by_user(id)
    self.from_id == id
  end

  def last?
    self.entry.comments.last == self
  end

  def posted_with_entry?
    self.entry.from_id == self.from_id and (entry.date_at - self.date_at).abs < 30.seconds
  end

  def emphasize?
    entry.view_unread and entry.checked_at < date_at
  end

  def date_at
    @date_at ||= (date ? Time.parse(date) : Time.now)
  end
end

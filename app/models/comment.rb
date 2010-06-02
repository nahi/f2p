require 'hash_utils'


class Comment
  include HashUtils
  EMPTY = [].freeze

  def self.from_buzz(hash)
    c = Comment.new
    c.id = hash['id']
    c.date = hash['published']
    c.body = hash['content']
    c.from = Entry.buzz_from(hash['actor']) if hash['actor']
    c.service_source = 'buzz'
    c
  end

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
  attr_accessor :service_source
  attr_writer :checked_at

  def initialize(hash = nil)
    initialize_with_hash(hash, 'id', 'date', 'commands', 'clipped', 'placeholder', 'num') if hash
    @body = hash && hash['rawBody']
    @commands ||= EMPTY
    @from = hash && From[hash['from']]
    @via = hash && Via[hash['via']]
    @index = nil
    @entry = nil
    @view_links = nil
    @service_source = nil
    @checked_at = nil
    @date ||= ''
  end

  def from_id
    from ? from.id : nil
  end

  def by_user(id)
    self.from_id == id
  end

  def last?
    self.entry and self.entry.comments.last == self
  end

  def posted_with_entry?
    if self.entry
      self.entry.from_id == self.from_id and (entry.date_at - self.date_at).abs < 30.seconds
    end
  end

  def checked_at
    @checked_at || (entry ? entry.checked_at : Entry::TIME_ZERO)
  end

  def unread?
    checked_at < date_at
  end

  def date_at
    @date_at ||= (date ? Time.parse(date) : Time.now)
  end

  def buzz?
    @service_source == 'buzz' or (entry and entry.buzz?)
  end
end

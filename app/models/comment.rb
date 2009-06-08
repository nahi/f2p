require 'hash_utils'


class Comment
  include HashUtils

  attr_accessor :id
  attr_accessor :body
  attr_accessor :date
  attr_accessor :user
  attr_accessor :via

  attr_accessor :index
  attr_accessor :entry
  attr_accessor :view_links

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'body', 'date')
    @user = EntryUser[hash['user']]
    @via = Via[hash['via']]
    @index = nil
    @entry = nil
    @view_links = nil
  end

  def user_id
    user.id
  end

  def nickname
    user.nickname
  end

  def by_user(nickname)
    self.nickname == nickname
  end

  def last?
    self.entry.comments.last == self
  end

  def posted_with_entry?
    self.entry.nickname == self.nickname and (entry.published_at - self.date_at).abs < 30.seconds
  end

  def view_unread
    e = self.entry
    e.view_unread and (e.checked_at.nil? or e.checked_at < self.date_at)
  end

protected

  def date_at
    @date_at ||= (date ? Time.parse(date) : Time.now)
  end
end

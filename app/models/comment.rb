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
end

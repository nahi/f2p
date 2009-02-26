require 'hash_utils'


class Comment < Hash
  include HashUtils

  attr_accessor :entry

  def id
    v('id')
  end

  def body
    v('body')
  end

  def user_id
    v('user', 'id')
  end

  def by_self?
    if entry
      user_id == entry.user_id
    end
  end
end

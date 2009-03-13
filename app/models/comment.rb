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

  def nickname
    v('user', 'nickname')
  end

  def by_user(nickname)
    v('user', 'nickname') == nickname
  end
end

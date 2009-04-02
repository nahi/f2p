require 'hash_utils'


class Like
  include HashUtils

  attr_accessor :user
  attr_accessor :date

  def initialize(hash)
    initialize_with_hash(hash, 'date')
    @user = EntryUser[hash['user']]
  end

  def nickname
    user.nickname
  end
end

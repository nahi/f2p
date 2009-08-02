require 'hash_utils'


class From
  include HashUtils
  EMPTY = [].freeze

  attr_accessor :id
  attr_accessor :name
  attr_accessor :type
  attr_accessor :private
  attr_accessor :commands

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'name', 'type', 'commands')
    @commands ||= EMPTY
    @private = hash['private'] == true
  end

  def user?
    type == 'user'
  end

  def me?
    commands and !commands.include?('post')
  end

  def friend?
    commands and !commands.include?('subscribe')
  end

  def group?
    type == 'group'
  end
end

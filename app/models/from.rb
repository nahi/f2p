require 'hash_utils'


class From
  include HashUtils

  attr_accessor :id
  attr_accessor :name
  attr_accessor :type
  attr_accessor :private
  attr_accessor :commands

  attr_accessor :service_source
  attr_accessor :profile_url
  attr_accessor :profile_image_url

  def initialize(hash = nil)
    initialize_with_hash(hash, 'id', 'name', 'type', 'commands') if hash
    @private = hash && hash['private'] == true
    @commands ||= Array::EMPTY
    @profile_url = nil
    @profile_image_url = nil
  end

  def user?
    type == 'user'
  end

  def me?
    user? and commands and commands.include?('post')
  end

  def friend?
    user? and commands and !commands.include?('subscribe')
  end

  def group?
    type == 'group'
  end
end

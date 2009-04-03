require 'hash_utils'


class Service
  include HashUtils

  attr_accessor :id
  attr_accessor :name
  attr_accessor :icon_url
  attr_accessor :profile_url
  attr_accessor :entry_type

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'name')
    @icon_url = hash['iconUrl']
    @profile_url = hash['profileUrl']
    @entry_type = hash['entryType']
  end

  ['internal', 'twitter', 'tumblr', 'brightkite'].each do |name|
    define_method(name + '?') do
      self.id == name
    end
  end

  def service_group?
    ['blog', 'feed'].include?(self.id)
  end
end

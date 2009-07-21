require 'hash_utils'


class Feedinfo
  include HashUtils
  EMPTY = [].freeze

  attr_accessor :id
  attr_accessor :name
  attr_accessor :type
  attr_accessor :description
  attr_accessor :sup_id
  attr_accessor :subscriptions
  attr_accessor :subscribers
  attr_accessor :feeds
  attr_accessor :services
  attr_accessor :commands

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'name', 'type', 'description', 'commands', 'sup_id')
    @subscriptions = sort_by_name((hash['subscriptions'] || EMPTY).map { |e| From[e] })
    @subscribers = sort_by_name((hash['subscribers'] || EMPTY).map { |e| From[e] })
    @feeds = sort_by_name((hash['feeds'] || EMPTY).map { |e| From[e] })
    @services = sort_by_name((hash['services'] || EMPTY).map { |e| From[e] })
  end

  def sort_by_name(lists)
    lists.sort_by { |e| e.name }
  end
end

require 'hash_utils'


class Feedinfo
  include HashUtils

  def self.opt_exclude(*arg)
    {
      :include => [:id, :name, :type, :private, :description, :sup_id, :subscriptions, :subscribers, :feeds, :services, :commands].reject { |e| arg.include?(e) }.join(',')
    }
  end

  attr_accessor :id
  attr_accessor :name
  attr_accessor :type
  attr_accessor :private
  attr_accessor :description
  attr_accessor :sup_id
  attr_accessor :subscriptions
  attr_accessor :subscribers
  attr_accessor :feeds
  attr_accessor :services
  attr_accessor :commands

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'name', 'type', 'private', 'description', 'commands', 'sup_id')
    @subscriptions = sort_by_name((hash['subscriptions'] || Array::EMPTY).map { |e| From[e] })
    @subscribers = sort_by_name((hash['subscribers'] || Array::EMPTY).map { |e| From[e] })
    @feeds = sort_by_name((hash['feeds'] || Array::EMPTY).map { |e| From[e] })
    @services = sort_by_name((hash['services'] || Array::EMPTY).map { |e| From[e] })
    @commands ||= []
  end

  def sort_by_name(lists)
    lists.sort_by { |e| e.name.downcase }
  end
end

require 'encrypt'
require 'service'


class User < ActiveRecord::Base
  extend Encrypt

  TEXT_MAXLEN = 255
  validates_length_of :name, :in => 1..TEXT_MAXLEN
  validates_length_of :remote_key, :in => 1..TEXT_MAXLEN

  encrypt F2P::Config.encryption_key, :remote_key, :algorithm => F2P::Config.cipher_algorithm, :block_size => F2P::Config.cipher_block_size

  class << self
    def validate(name, remote_key)
      if name and remote_key
        if ff_client.validate(name, remote_key)
          ActiveRecord::Base.transaction do
            if user = User.find_by_name(name)
              user.remote_key = remote_key
            else
              user = User.new
              user.name = name
              user.remote_key = remote_key
            end
            user.save!
            user
          end
        end
      end
    end

    def ff_picture_url(user, size = 'small')
      # uglish but for reducing DRb overhead...
      # ff_client.get_user_picture_url(user, size)
      "http://friendfeed.com/#{user}/picture?size=#{size}"
    end

    def ff_feedlist(auth)
      convert_feedlist(ff_client.feedlist(:name => auth.name, :remote_key => auth.remote_key) || {})
    end

    def ff_feedinfo(auth, feedid)
      Feedinfo[ff_client.feedinfo(feedid, :name => auth.name, :remote_key => auth.remote_key) || {}]
    end

    def ff_subscribe(auth, feed, list = nil)
      opt = { :name => auth.name, :remote_key => auth.remote_key }
      opt[:list] = list if list
      ff_client.subscribe(feed, opt)
    end

    def ff_unsubscribe(auth, feed, list = nil)
      opt = { :name => auth.name, :remote_key => auth.remote_key }
      opt[:list] = list if list
      ff_client.unsubscribe(feed, opt)
    end

  private

    def convert_feedlist(feedlist)
      feedlist = feedlist.dup
      if list = feedlist['groups']
        feedlist['groups'] = sort_by_name(list.map { |e| From[e] })
      end
      if list = feedlist['searches']
        feedlist['searches'] = sort_by_name(list.map { |e| From[e] })
      end
      if list = feedlist['lists']
        feedlist['lists'] = sort_by_name(list.map { |e| From[e] })
      end
      feedlist
    end

    def sort_by_name(lists)
      lists.sort_by { |e| e.name }
    end

    def ff_client
      ApplicationController.ff_client
    end
  end
end

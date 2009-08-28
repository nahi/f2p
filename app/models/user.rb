require 'encrypt'


class User < ActiveRecord::Base
  extend Encrypt

  TEXT_MAXLEN = 255
  validates_length_of :name, :in => 1..TEXT_MAXLEN

  encrypt F2P::Config.encryption_key, :remote_key, :algorithm => F2P::Config.cipher_algorithm, :block_size => F2P::Config.cipher_block_size

  class << self
    def validate(name, remote_key)
      if name and remote_key
        if ff_client.validate(name, remote_key)
          ActiveRecord::Base.transaction do
            if user = User.find_by_name(name)
              if user.oauth? and ff_client.oauth_validate(user.new_cred)
                # reusable OAuth access token found. just use it.
              else
                # store remote_key in DB.
                user.store_remote_key(remote_key)
              end
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

    def oauth_validate(token, secret)
      ActiveRecord::Base.transaction do
        name = name_from_token(token, secret)
        return unless name
        unless user = User.find_by_name(name)
          user = User.new
          user.name = name
        end
        user.store_access_token(token, secret)
        user.save!
        user
      end
    end
  
    def ff_url(name)
      "http://friendfeed.com/#{name}"
    end
  
    def ff_picture_url(user, size = 'small')
      # uglish but for reducing DRb overhead...
      # ff_client.get_user_picture_url(user, size)
      "http://friendfeed.com/#{user}/picture?size=#{size}"
    end

    def ff_feedlist(auth)
      convert_feedlist(ff_client.feedlist(auth.new_cred) || {})
    end

    def ff_feedinfo(auth, feedid, opt = {})
      Feedinfo[ff_client.feedinfo(feedid, opt.merge(auth.new_cred)) || {}]
    end

    def ff_subscribe(auth, feed, list = nil)
      opt = auth.new_cred
      opt[:list] = list if list
      ff_client.subscribe(feed, opt)
    end

    def ff_unsubscribe(auth, feed, list = nil)
      opt = auth.new_cred
      opt[:list] = list if list
      ff_client.unsubscribe(feed, opt)
    end

  private

    def name_from_token(token, secret)
      cred = {
        :oauth_token => token,
        :oauth_token_secret => secret
      }
      if id = ff_client.feedinfo('me', cred.merge(:include => :id))
        id['id']
      end
    end

    def convert_feedlist(feedlist)
      feedlist = feedlist.dup
      list = feedlist['groups'] || []
      feedlist['groups'] = sort_by_name(list.map { |e| From[e] })
      list = feedlist['searches'] || []
      feedlist['searches'] = sort_by_name(list.map { |e| From[e] })
      list = feedlist['lists'] || []
      feedlist['lists'] = sort_by_name(list.map { |e| From[e] })
      feedlist['commands'] ||= []
      feedlist
    end

    def sort_by_name(lists)
      lists.sort_by { |e| e.name }
    end

    def ff_client
      ApplicationController.ff_client
    end
  end

  def oauth?
    !!self.oauth_access_token
  end

  def new_cred
    if oauth?
      {
        :name => self.name,
        :oauth_token => self.oauth_access_token,
        :oauth_token_secret => self.oauth_access_token_secret
      }
    else
      {
        :name => self.name,
        :remote_key => self.remote_key
      }
    end
  end

  def store_remote_key(remote_key)
    self.remote_key = remote_key
    self.oauth_access_token = nil
    self.oauth_access_token_secret = nil
    self.oauth_access_token_generated = nil
  end

  def store_access_token(token, secret)
    self.oauth_access_token = token
    self.oauth_access_token_secret = secret
    self.oauth_access_token_generated = Time.now
    self.remote_key = '' # TODO: nil not allowed!
  end
end

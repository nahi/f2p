require 'encrypt'


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
          if user = User.find_by_name(name)
            user.remote_key = remote_key
          else
            user = User.new
            user.name = name
            user.remote_key = remote_key
          end
          if user.save
            user
          end
        end
      end
    end

    def ff_id(arg)
      auth = arg[:auth]
      user = arg[:user]
      ff_profile(auth, user)['id']
    end

    def ff_name(arg)
      auth = arg[:auth]
      user = arg[:user]
      ff_profile(auth, user)['name']
    end

    def ff_url(arg)
      auth = arg[:auth]
      user = arg[:user]
      ff_profile(auth, user)['profileUrl']
    end

    def status(arg)
      auth = arg[:auth]
      user = arg[:user]
      ff_profile(auth, user)['status']
    end

    def picture_url(arg)
      user = arg[:user]
      size = arg[:size] || 'small'
      ff_picture_url(user, size)
    end

    def services(arg)
      auth = arg[:auth]
      user = arg[:user]
      sort_by_name(ff_profile(auth, user)['services'] || [])
    end

    def lists(arg)
      auth = arg[:auth]
      user = arg[:user] || auth.name
      sort_by_name(ff_profile(auth, user)['lists'] || [])
    end

    def rooms(arg)
      auth = arg[:auth]
      user = arg[:user] || auth.name
      sort_by_name(ff_profile(auth, user)['rooms'] || [])
    end

    def subscriptions(arg)
      auth = arg[:auth]
      user = arg[:user] || auth.name
      sort_by_name(ff_profile(auth, user)['subscriptions'] || [])
    end

  private

    def ff_picture_url(user, size = 'small')
      ff_client.get_user_picture_url(user, size)
    end

    def ff_profile(auth, user)
      ff_client.get_profile(auth.name, auth.remote_key, user) || {}
    end

    def sort_by_name(lists)
      lists.sort_by { |e| e['name'] }
    end

    def ff_client
      ApplicationController.ff_client
    end
  end
end

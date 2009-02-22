require 'encrypt'


class User < ActiveRecord::Base
  extend Encrypt

  has_one :profile

  TEXT_MAXLEN = 255
  validates_length_of :name, :in => 1..TEXT_MAXLEN
  validates_length_of :remote_key, :in => 1..TEXT_MAXLEN

  encrypt F2P::Config.encryption_key, :remote_key, :algorithm => F2P::Config.cipher_algorithm, :block_size => F2P::Config.cipher_block_size

  class << self
    def validate(name, remote_key)
      if name and remote_key
        ff_client.validate(name, remote_key)
      end
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

    def ff_profile(auth, user)
      ff_client.get_profile(auth.name, auth.remote_key, user)
    end

    def sort_by_name(lists)
      lists.sort_by { |e| e['name'] }
    end

    def ff_client
      ApplicationController.ff_client
    end
  end
end

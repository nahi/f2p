require 'encrypt'


class User < ActiveRecord::Base
  extend Encrypt

  TEXT_MAXLEN = 255
  validates_length_of :name, :in => 1..TEXT_MAXLEN
  validates_length_of :remote_key, :in => 1..TEXT_MAXLEN

  encrypt FFP::Config.encryption_key, :remote_key, :algorithm => FFP::Config.cipher_algorithm, :block_size => FFP::Config.cipher_block_size

  class << self
    def services(arg)
      name = arg[:name]
      remote_key = arg[:remote_key]
      user = arg[:user]
      profile(name, remote_key, user)['services'] || []
    end

    def rooms(arg)
      name = arg[:name]
      remote_key = arg[:remote_key]
      user = arg[:user] || name
      profile(name, remote_key, user)['rooms'] || []
    end

  private

    def profile(name, remote_key, user)
      ff_client.get_profile(name, remote_key, user)
    end

    def ff_client
      ApplicationController.ff_client
    end
  end
end

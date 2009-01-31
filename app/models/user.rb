require 'encrypt'


class User < ActiveRecord::Base
  extend Encrypt

  TEXT_MAXLEN = 255
  validates_length_of :name, :in => 1..TEXT_MAXLEN
  validates_length_of :remote_key, :in => 1..TEXT_MAXLEN

  encrypt FFP::Config.encryption_key, :remote_key, :algorithm => FFP::Config.cipher_algorithm, :block_size => FFP::Config.cipher_block_size

  def services
    profile['services']
  end

  def rooms
    profile['rooms']
  end

private

  def profile
    @profile ||= ff_client.get_profile(name, remote_key)
  end

  def ff_client
    ApplicationController.ff_client
  end
end

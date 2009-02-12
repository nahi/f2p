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
      name = arg[:name]
      remote_key = arg[:remote_key]
      user = arg[:user]
      sort_by_name(ff_profile(name, remote_key, user)['services'] || [])
    end

    def lists(arg)
      name = arg[:name]
      remote_key = arg[:remote_key]
      user = arg[:user] || name
      sort_by_name(ff_profile(name, remote_key, user)['lists'] || [])
    end

    def rooms(arg)
      name = arg[:name]
      remote_key = arg[:remote_key]
      user = arg[:user] || name
      sort_by_name(ff_profile(name, remote_key, user)['rooms'] || [])
    end

    def subscriptions(arg)
      name = arg[:name]
      remote_key = arg[:remote_key]
      user = arg[:user] || name
      sort_by_name(ff_profile(name, remote_key, user)['subscriptions'] || [])
    end

  private

    def ff_profile(name, remote_key, user)
      ff_client.get_profile(name, remote_key, user)
    end

    def sort_by_name(lists)
      lists.sort_by { |e| e['name'] }
    end

    def ff_client
      ApplicationController.ff_client
    end
  end

  def initialize
    super
    self.profile = Profile.new
    self.profile.font_size = F2P::Config.font_size
    self.profile.entries_in_page = F2P::Config.entries_in_page
    self.profile.entries_in_thread = F2P::Config.entries_in_thread
    self.profile.text_folding_size = F2P::Config.text_folding_size
  end
end

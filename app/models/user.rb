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

    def ff_profile(auth, user)
      convert_profile(ff_client.get_profile(auth.name, auth.remote_key, user) || {})
    end

    def ff_status_map(auth, users)
      ff_client.get_user_status(auth.name, auth.remote_key, users)
    end

  private

    def convert_profile(profile)
      profile = profile.dup
      if list = profile['services']
        profile['services'] = sort_by_name(list.map { |e| Service[e] })
      end
      if list = profile['lists']
        profile['lists'] = sort_by_name(list.map { |e| List[e] })
      end
      if list = profile['rooms']
        profile['rooms'] = sort_by_name(list.map { |e| Room[e] })
      end
      if list = profile['subscriptions']
        profile['subscriptions'] = sort_by_name(list.map { |e| EntryUser[e] })
      end
      profile
    end

    def sort_by_name(lists)
      lists.sort_by { |e| e.name }
    end

    def ff_client
      ApplicationController.ff_client
    end
  end
end

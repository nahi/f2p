require 'rubytter'


class Tweet

  class << self
    def home(token, args = {})
      client(token).home_timeline(args)
    end

  private

    def client(token)
      OAuthRubytter.new(
        :token => token.token,
        :secret => token.secret,
        :consumer => {
          :key => F2P::Config.twitter_api_oauth_consumer_key,
          :secret => F2P::Config.twitter_api_oauth_consumer_secret
        }
      )
    end
  end
end

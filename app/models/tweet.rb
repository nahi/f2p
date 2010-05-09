require 'rubytter'


class Tweet

  class << self
    def home_timeline(token, args = {})
      res = with_perf('[perf] start home_timeline fetch') {
        protect([]) {
          client(token).home_timeline(args)
        }
      }
      su = token.service_user
      res.map { |e| wrap(su, e) }
    end

    def user_timeline(token, user, args = {})
      res = with_perf('[perf] start user_timeline fetch') {
        protect([]) {
          client(token).user_timeline(user, args)
        }
      }
      su = token.service_user
      res.map { |e| wrap(su, e) }
    end

    def mentions(token, args = {})
      res = with_perf('[perf] start mentions fetch') {
        protect([]) {
          client(token).mentions(args)
        }
      }
      su = token.service_user
      res.map { |e| wrap(su, e) }
    end

    def direct_messages(token, args = {})
      res = with_perf('[perf] start direct_messages fetch') {
        protect([]) {
          client(token).direct_messages(args)
        }
      }
      su = token.service_user
      res.map { |e| wrap(su, e) }
    end

    def favorites(token, args = {})
      res = with_perf('[perf] start favorites fetch') {
        protect([]) {
          client(token).favorites(token.service_user, args)
        }
      }
      su = token.service_user
      res.map { |e| wrap(su, e) }
    end

    def show(token, id, args = {})
      res = with_perf('[perf] start tweet fetch') {
        protect(nil) {
          client(token).show(id, args)
        }
      }
      wrap(token.service_user, res)
    end

    # raises exception
    def update_status(token, status, args = {})
      res = with_perf('[perf] start tweet post') {
        client(token).update_status(args.merge(:status => status))
      }
      wrap(token.service_user, res)
    end

    # raises exception
    def retweet(token, id, args = {})
      res = with_perf('[perf] start retweet post') {
        client(token).retweet(id, args)
      }
      wrap(token.service_user, res)
    end

    def favorite(token, id, args = {})
      res = with_perf('[perf] start favorite post') {
        client(token).favorite(id, args)
      }
      wrap(token.service_user, res)
    end

    def remove_favorite(token, id, args = {})
      res = with_perf('[perf] start removing favorite post') {
        client(token).remove_favorite(id, args)
      }
      wrap(token.service_user, res)
    end

  private

    def logger
      ActiveRecord::Base.logger
    end

    def protect(default = nil)
      begin
        yield
      rescue
        default
      end
    end

    def with_perf(msg)
      logger.info(msg)
      begin
        start = Time.now
        yield
      rescue
        logger.warn($!)
        raise
      ensure
        logger.info("elapsed: #{((Time.now - start) * 1000).to_i}ms")
      end
    end

    def wrap(service_user, hash)
      return nil unless hash
      hash['service_source'] = 'twitter'
      hash['service_user'] = service_user
      hash
    end

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

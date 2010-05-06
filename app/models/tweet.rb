require 'rubytter'


class Tweet

  class << self
    def home_timeline(token, args = {})
      res = with_perf('[perf] start home_timeline fetch') {
        client(token).home_timeline(args)
      }
      su = token.service_user
      res.map { |e| wrap(su, e) }
    end

    def user_timeline(token, user, args = {})
      res = with_perf('[perf] start user_timeline fetch') {
        client(token).user_timeline(user, args)
      }
      su = token.service_user
      res.map { |e| wrap(su, e) }
    end

    def mentions(token, args = {})
      res = with_perf('[perf] start mentions fetch') {
        client(token).mentions(args)
      }
      su = token.service_user
      res.map { |e| wrap(su, e) }
    end

    def direct_messages(token, args = {})
      res = with_perf('[perf] start direct_messages fetch') {
        client(token).direct_messages(args)
      }
      su = token.service_user
      res.map { |e| wrap(su, e) }
    end

    def show(token, id)
      res = with_perf('[perf] start tweet fetch') {
        client(token).show(id)
      }
      wrap(token.service_user, res)
    end

    def update_status(token, status, opt = {})
      params = {}
      params[:status] = status
      if opt[:in_reply_to_status_id]
        params[:in_reply_to_status_id] = opt[:in_reply_to_status_id]
      end
      res = with_perf('[perf] start tweet post') {
        client(token).update_status(params)
      }
      wrap(token.service_user, res)
    end

  private

    def logger
      ActiveRecord::Base.logger
    end

    def with_perf(msg)
      logger.info(msg)
      begin
        start = Time.now
        res = yield
      ensure
        logger.info("elapsed: #{((Time.now - start) * 1000).to_i}ms")
      end
      res
    end

    def wrap(service_user, hash)
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

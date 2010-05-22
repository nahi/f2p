class Buzz
  BUZZ_API_BASE = 'https://www.googleapis.com/buzz/v1/'

  class << self
    def profile(token, who = '@me', args = {})
      res = with_perf('[perf] start profile fetch') {
        protect {
          client(token).get_content(BUZZ_API_BASE + "people/#{who}/@self", args.merge(:alt => :json))
        }
      }
      JSON.parse(res) if res
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

    def client(token)
      client = HTTPClient.new(F2P::Config.http_proxy || ENV['http_proxy'])
      site = F2P::Config.buzz_api_oauth_site
      config = HTTPClient::OAuth::Config.new
      config.consumer_key = F2P::Config.buzz_api_oauth_consumer_key
      config.consumer_secret = F2P::Config.buzz_api_oauth_consumer_secret
      config.token = token.token
      config.secret = token.secret
      config.signature_method = F2P::Config.buzz_api_oauth_signature_method
      config.http_method = F2P::Config.buzz_api_oauth_http_method
      client.www_auth.oauth.set_config(site, config)
      client.www_auth.oauth.challenge(site)
      client
    end
  end
end

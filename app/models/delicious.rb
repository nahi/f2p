require 'xsd/mapping'


class Delicious
  DELICIOUS_API_BASE = 'http://api.del.icio.us/v2'

  class << self
    include API

    def recent(token, args = {})
      get_posts(token, post_path('recent'), args)
    end

    def all(token, args = {})
      get_posts(token, post_path('all'), args)
    end

  private

    def token_protect(token)
      begin
        res = yield(token)
        if res.status == 401
          params = YAML.load(token.params)
          handle = params[:oauth_session_handle]
          res = create_delicious_oauth_consumer(handle).get_access_token(F2P::Config.delicious_api_oauth_access_token_url, token.token, token.secret)
          if res.status == 200
            new_token = res.oauth_params["oauth_token"]
            new_secret = res.oauth_params["oauth_token_secret"]
            # OAuth Session 1.0: http://oauth.googlecode.com/svn/spec/ext/session/1.0/drafts/1/spec.html
            oauth_session_handle = res.oauth_params["oauth_session_handle"]
            oauth_expires_in = res.oauth_params["oauth_expires_in"]
            oauth_authorization_expires_in = res.oauth_params["oauth_authorization_expires_in"]
            # proprietary extension
            xoauth_yahoo_guid = res.oauth_params["xoauth_yahoo_guid"]
            token.token = new_token
            token.secret = new_secret
            param = {
              :oauth_session_handle => oauth_session_handle,
              :oauth_expires_in => oauth_expires_in,
              :oauth_authorization_expires_in => oauth_authorization_expires_in
            }
            token.params = YAML.dump(param)
            token.save!
            yield(token)
          end
        end
      end
    end

    def post_path(name)
      path(DELICIOUS_API_BASE, "posts/#{name}")
    end

    def get_posts(token, path, opt)
      res = token_protect(token) { |t|
        with_perf("[perf] start #{path} fetch") {
          protect {
            res = client(t).get(path, opt)
          }
        }
      }
      parse_posts(token, res) if res
    end

    def parse_posts(token, res)
      if res
        if parsed = protect { XSD::Mapping.xml2obj(res.content) }
          su = token.service_user
          if data = parsed.post
            parsed.post = data.map { |e| wrap(su, e) }
            parsed
          end
        else
          logger.warn("Unknown structure: " + res.content)
          nil
        end
      end
    end

    def wrap(service_user, hash)
      return nil unless hash
      hash['service_source'] = 'delicious'
      hash['service_user'] = service_user
      hash
    end

    def client(token)
      client = HTTPClient.new(F2P::Config.http_proxy || ENV['http_proxy'])
      site = DELICIOUS_API_BASE
      config = HTTPClient::OAuth::Config.new
      config.consumer_key = F2P::Config.delicious_api_oauth_consumer_key
      config.consumer_secret = F2P::Config.delicious_api_oauth_consumer_secret
      config.token = token.token
      config.secret = token.secret
      config.signature_method = F2P::Config.delicious_api_oauth_signature_method
      config.http_method = F2P::Config.delicious_api_oauth_http_method
      client.www_auth.oauth.set_config(site, config)
      client.www_auth.oauth.challenge(site)
      client.protocol_retry_count = 1 # for 401 response.
      client.debug_dev = STDERR
      client
    end

    # TODO: merge with LoginController
    def create_delicious_oauth_consumer(handle)
      client = OAuthClient.new
      client.oauth_config.consumer_key = F2P::Config.delicious_api_oauth_consumer_key
      client.oauth_config.consumer_secret = F2P::Config.delicious_api_oauth_consumer_secret
      client.oauth_config.signature_method = F2P::Config.delicious_api_oauth_signature_method
      client.oauth_config.http_method = F2P::Config.delicious_api_oauth_http_method
      client.oauth_config.session_handle = handle
      client
    end
  end
end

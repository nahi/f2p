require 'xsd/mapping'


class Tumblr
  class << self
    include API

    def profile(token, args = {})
      profile = Profile.new
      res = with_perf('[perf] start profile fetch') {
        protect {
          client(token).get('http://www.tumblr.com/api/authenticate')
        }
      }
      if res
        if parsed = protect { XSD::Mapping.xml2obj(res.content) }
          tumblelogs = parsed['tumblelog'].to_a
          tumblelog = tumblelogs.find { |t|
            t.xmlattr_is_primary == 'yes' if t.respond_to?(:xmlattr_is_primary)
          }
          profile.id = tumblelog.xmlattr_name
          profile.name = profile.display_name = profile.id
          profile.profile_url = tumblelog.xmlattr_url
          profile.profile_image_url = tumblelog.xmlattr_avatar_url
          profile.location = nil
          profile.description = nil
          profile.private = tumblelog.xmlattr_type != 'public'
          profile.followings_count = nil
          profile.followers_count = nil
          profile.entries_count = nil
        end
      end
      profile
    end

    def dashboard(token, args = {})
      get_posts(token, 'http://www.tumblr.com/api/dashboard/json', args.merge(:likes => 1))
    end

    def show(token, id, args = {})
      user, id = id.split('/')
      res = get_posts(token, "http://#{user}.tumblr.com/api/read/json", args.merge(:id => id, :likes => 1))
      if res && res['posts']
        res['posts'].first
      end
    end

    def read(token, user, args = {})
      get_posts(token, "http://#{user}.tumblr.com/api/read/json", args)
    end

    def search(token, user, query, args = {})
      get_posts(token, "http://#{user}.tumblr.com/api/read/json", args.merge(:search => query))
    end

    def like(token, id, reblog_key)
      user, id = id.split('/')
      post(token, "http://www.tumblr.com/api/like", {'post-id' => id, 'reblog-key' => reblog_key})
    end

    def unlike(token, id, reblog_key)
      user, id = id.split('/')
      post(token, "http://www.tumblr.com/api/unlike", {'post-id' => id, 'reblog-key' => reblog_key})
    end

  private

    def post(token, path, opt)
      with_perf("[perf] start posting to #{path}") {
        protect {
          client(token).post(path, opt)
        }
      }
    end

    def get_posts(token, path, opt)
      res = with_perf("[perf] start #{path} fetch") {
        protect([]) {
          client(token).get(path, opt)
        }
      }
      parse_posts(token, res) if res
    end

    def parse_posts(token, res)
      if res
        # need to convert JS -> JSON
        if parsed = protect { JSON.parse(js_to_json(res.content)) }
          su = token.service_user
          if data = parsed['posts']
            parsed['posts'] = data.map { |e|
              e['tumblelog'] ||= parsed['tumblelog']
              wrap(su, e)
            }
            parsed['profile'] = parse_profile(parsed['tumblelog'])
            parsed
          end
        else
          logger.warn("Unknown structure: " + res.content)
          nil
        end
      end
    end

    def parse_profile(hash)
      profile = Profile.new
      if tumblelog = hash && hash['tumblelog']
        profile.id = tumblelog['name']
        profile.name = profile.display_name = profile.id
        profile.profile_url = tumblelog['url']
        profile.profile_image_url = nil
        profile.location = nil
        profile.description = nil
        profile.private = false
        profile.followings_count = nil
        profile.followers_count = nil
        profile.entries_count = nil
      end
      profile
    end

    # "var tumblr_api_read = {...};" -> "{...}"
    def js_to_json(str)
      str.sub(/\A[^{]*/, '').sub(/;\s*\z/, '')
    end

    def wrap(service_user, hash)
      return nil unless hash
      hash['service_source'] = 'tumblr'
      hash['service_user'] = service_user
      hash
    end

    def client(token)
      client = HTTPClient.new(F2P::Config.http_proxy || ENV['http_proxy'])
      config = HTTPClient::OAuth::Config.new
      config.consumer_key = F2P::Config.tumblr_api_oauth_consumer_key
      config.consumer_secret = F2P::Config.tumblr_api_oauth_consumer_secret
      config.token = token.token
      config.secret = token.secret
      config.signature_method = F2P::Config.tumblr_api_oauth_signature_method
      config.http_method = F2P::Config.tumblr_api_oauth_http_method
      client.www_auth.oauth.set_config(nil, config)
      client.www_auth.oauth.challenge(nil)
      client.debug_dev = STDERR if $DEBUG
      client
    end
  end
end

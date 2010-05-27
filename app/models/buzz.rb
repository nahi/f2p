class Buzz
  BUZZ_API_BASE = 'https://www.googleapis.com/buzz/v1'

  class << self
    def profile(token, who = '@me', args = {})
      res = with_perf('[perf] start profile fetch') {
        protect {
          client(token).get(profile_path(who), args.merge(:alt => :json))
        }
      }
      JSON.parse(res.content) if res
    end

    def activities(token, feed = '@me/@consumption', args = {})
      res = with_perf('[perf] start activities fetch') {
        protect {
          client(token).get(activity_path(feed), args.merge(:alt => :json))
        }
      }
      if res
        parsed = JSON.parse(res.content)
        data = parsed['data']
        su = token.service_user
        data['items'] = data['items'].map { |e| wrap(su, e) }
        data
      end
    end

    def show_all(token, feed)
      task1 = Task.run { show(token, feed) }
      task2 = Task.run { comments(token, feed) }
      task3 = Task.run { liked(token, feed) }
      buzz = task1.result
      buzz['object']['comments'] = task2.result['items']
      buzz['object']['liked'] = task3.result['entry']
      buzz
    end

    def show(token, feed, args = {})
      get_element(token, activity_path(feed), args)
    end

    def comments(token, feed, args = {})
      get_element(token, comments_path(feed), args)
    end

    def liked(token, feed, args = {})
      get_element(token, liked_path(feed), args)
    end

    def create_note(token, content, args = {})
      data = {:data => {:object => {:type => :note, :content => content}}}
      res = with_perf("[perf] start creating a note") {
        post(token, activity_path('@me/@self'), args, data)
      }
      parse_element(token, res) if res
    end

    def delete_activity(token, feed)
      with_perf("[perf] start deleting an activity") {
        delete(token, activity_path(feed))
      }
    end

    def like(token, feed)
      with_perf("[perf] start liking an activity") {
        put(token, like_path(feed))
      }
    end

    def unlike(token, feed)
      with_perf("[perf] start unliking an activity") {
        delete(token, like_path(feed))
      }
    end

    def mute(token, feed)
      with_perf("[perf] start muting an activity") {
        put(token, mute_path(feed))
      }
    end

    def unmute(token, feed)
      with_perf("[perf] start unmuting an activity") {
        delete(token, mute_path(feed))
      }
    end

    def create_comment(token, feed, content, args = {})
      data = {:data => {:content => content}}
      res = with_perf("[perf] start creating a comment") {
        post(token, comments_path(feed), args, data)
      }
      parse_element(token, res) if res
    end

    def delete_comment(token, feed)
      with_perf("[perf] start deleting a comment") {
        delete(token, activity_path(feed))
      }
    end

  private

    def post(token, path, args, data)
      protect {
        json = data.to_json
        client(token).request(:post, path, args.merge(:alt => :json), json, 'Content-Type' => 'application/json')
      }
    end

    def put(token, path)
      protect {
        client(token).put(path)
      }
    end

    def delete(token, path)
      protect {
        client(token).delete(path)
      }
    end

    def profile_path(user)
      path(BUZZ_API_BASE, "people/#{user}/@self")
    end

    def activity_path(feed)
      path(BUZZ_API_BASE, "activities/#{feed}")
    end

    def comments_path(feed)
      activity_path(feed + '/@comments')
    end

    def liked_path(feed)
      activity_path(feed + '/@liked')
    end

    def like_path(feed)
      activity_path(path('@me/@liked', feed.split('/').last))
    end

    def mute_path(feed)
      activity_path(path('@me/@muted', feed.split('/').last))
    end

    def path(*args)
      args.compact.join('/')
    end

    def get_element(token, path, opt)
      res = with_perf("[perf] start #{path} fetch") {
        protect {
          client(token).get(path, opt.merge(:alt => :json))
        }
      }
      parse_element(token, res) if res
    end

    def parse_element(token, res)
      if res
        parsed = JSON.parse(res.content)
        data = parsed['data']
        su = token.service_user
        wrap(su, data)
      end
    end

    def logger
      ActiveRecord::Base.logger
    end

    def protect(default = nil)
      begin
        yield
      rescue
        logger.error($!)
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
      hash['service_source'] = 'buzz'
      hash['service_user'] = service_user
      hash
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

class Graph
  GRAPH_API_BASE = 'https://graph.facebook.com'

  class << self
    include API

    def profile(token, who = 'me')
      profile = Profile.new
      if res = get(token, id_path(who), :fields => 'id,name,link,picture,location')
        profile.id = res['id']
        profile.name = profile.display_name = res['name']
        profile.profile_url = res['link']
        profile.profile_image_url = res['picture']
        if res['location']
          profile.location = res['location']['name']
        end
        profile.description = nil
        profile.private = false # ???
        profile.followings_count = nil
        profile.followers_count = nil
        profile.entries_count = nil
      end
      profile
    end

    def connections(token, feed = 'home', args = {})
      res = get(token, id_path(feed), args)
      get_elements(token, res)
    end

    def show_all(token, id)
      task1 = Task.run { show(token, id) }
      task2 = Task.run { comments(token, id) }
      task3 = Task.run { likes(token, id) }
      if graph = task1.result
        graph['comments'] = task2.result
        graph['likes'] = task3.result
      end
      graph
    end

    def show(token, id, args = {})
      if res = get(token, id_path(id), args)
        su = token.service_user
        wrap(su, res)
      end
    end

    def comments(token, id, args = {})
      res = get(token, comments_path(id), args.merge(:limit => F2P::Config.max_friend_list_num))
      get_elements(token, res)
    end

    def likes(token, id, args = {})
      res = get(token, likes_path(id), args.merge(:limit => F2P::Config.max_friend_list_num))
      get_elements(token, res)
    end

    def create_message(token, message, to = 'me')
      if res = post(token, feed_id(to), :message => message)
        su = token.service_user
        wrap(su, res)
      end
    end

    def like(token, id)
      post(token, likes_path(id))
    end

    def unlike(token, id)
      delete(token, likes_path(id))
    end

    def create_comment(token, id, content)
      post(token, comments_path(id), :message => content)
    end

    def delete_comment(token, id)
      delete(token, id)
    end

  private

    def feed_id(id)
      path(GRAPH_API_BASE, id, 'feed')
    end

    def comments_path(id)
      path(GRAPH_API_BASE, id, 'comments')
    end

    def likes_path(id)
      path(GRAPH_API_BASE, id, 'likes')
    end

    def id_path(id)
      path(GRAPH_API_BASE, id)
    end

    def get(token, path, query)
      res = with_perf("perf] start getting #{path} fetch") {
        protect {
          client.get(path, query.merge(:access_token => token.secret))
        }
      }
      parse(token, res)
    end

    def post(token, path, body = '')
      res = with_perf("[perf] start posting to #{path}") {
        protect {
          client.request(:post, path, {:access_token => token.secret }, body)
        }
      }
      parse(token, res)
    end

    def delete(token, path)
      with_perf("[perf] start deleting #{path}") {
        protect {
          client.request(:delete, path, {:access_token => token.secret }, '')
        }
      }
    end

    def parse(token, res)
      if res
        if parsed = protect { JSON.parse(res.content) }
          if parsed['error']
            raise parsed['error'].inspect
          end
          parsed['service_user'] = token.service_user
          parsed
        end
      end
    end

    def get_elements(token, res)
      if res and res['data']
        su = token.service_user
        res['data'] = res['data'].map { |e| wrap(su, e) }
        res
      else
        {}
      end
    end

    def wrap(service_user, hash)
      return nil unless hash
      hash['service_source'] = 'graph'
      hash['service_user'] = service_user
      hash
    end

    def client
      drv = HTTPClient.new(F2P::Config.http_proxy || ENV['http_proxy'])
      drv.debug_dev = STDERR if $DEBUG
      drv
    end
  end
end

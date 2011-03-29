require 'rubytter'
require 'cgi'
require 'api'


class Tweet

  class << self
    include API

    def home_timeline(token, args = {})
      res = with_perf('[perf] start home_timeline fetch') {
        protect([]) {
          client(token).home_timeline(args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    def user_timeline(token, user, args = {})
      res = with_perf('[perf] start user_timeline fetch') {
        protect([]) {
          client(token).user_timeline(user, args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    def mentions(token, args = {})
      res = with_perf('[perf] start mentions fetch') {
        protect([]) {
          client(token).mentions(args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    def list_statuses(token, user, list, args = {})
      res = with_perf('[perf] start list statuses fetch') {
        protect([]) {
          client(token).list_statuses(user, list, args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    def sent_direct_messages(token, args = {})
      res = with_perf('[perf] start direct_messages/sent fetch') {
        protect([]) {
          client(token).sent_direct_messages(args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    def direct_messages(token, args = {})
      res = with_perf('[perf] start direct_messages fetch') {
        protect([]) {
          client(token).direct_messages(args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    def favorites(token, args = {})
      res = with_perf('[perf] start favorites fetch') {
        protect([]) {
          client(token).favorites(token.service_user, args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    def retweeted_by_me(token, args = {})
      res = with_perf('[perf] start retweeted_by_me fetch') {
        protect([]) {
          client(token).retweeted_by_me(args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    def retweeted_to_me(token, args = {})
      res = with_perf('[perf] start retweeted_to_me fetch') {
        protect([]) {
          client(token).retweeted_to_me(args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    def retweets_of_me(token, args = {})
      res = with_perf('[perf] start retweets_of_me fetch') {
        protect([]) {
          client(token).retweets_of_me(args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    def search(token, query, args = {})
      res = with_perf('[perf] start favorites fetch') {
        protect([]) {
          client(token).search(query, args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap_search(su, e) }
      }
    end

    def show(token, id, args = {})
      res = with_perf('[perf] start tweet fetch') {
        protect(nil) {
          client(token).show(id, args)
        }
      }
      with_header_ext(res) {
        wrap(token.service_user, res)
      }
    end

    def retweets(token, id, args = {})
      res = with_perf('[perf] start retweets fetch') {
        protect([]) {
          client(token).retweets(id, args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    # raises exception
    def update_status(token, status, args = {})
      res = with_perf('[perf] start tweet post') {
        client(token).update_status(args.merge(:status => status))
      }
      with_header_ext(res) {
        wrap(token.service_user, res)
      }
    end

    def send_direct_message(token, user, text, args = {})
      res = with_perf('[perf] start DM post') {
        client(token).send_direct_message(args.merge(:user => user, :text => text))
      }
      with_header_ext(res) {
        wrap(token.service_user, res)
      }
    end

    # raises exception
    def retweet(token, id, args = {})
      res = with_perf('[perf] start retweet post') {
        client(token).retweet(id, args)
      }
      with_header_ext(res) {
        wrap(token.service_user, res)
      }
    end

    def remove_status(token, id, args = {})
      with_perf('[perf] start deleting tweet') {
        client(token).remove_status(id, args)
      }
    end

    def favorite(token, id, args = {})
      res = with_perf('[perf] start favorite post') {
        client(token).favorite(id, args)
      }
      with_header_ext(res) {
        wrap(token.service_user, res)
      }
    end

    def remove_favorite(token, id, args = {})
      res = with_perf('[perf] start removing favorite post') {
        client(token).remove_favorite(id, args)
      }
      with_header_ext(res) {
        wrap(token.service_user, res)
      }
    end

    def saved_searches(token, args = {})
      res = with_perf('[perf] start fetching saved searches') {
        protect([]) {
          client(token).saved_searches(args)
        }
      }
      with_header_ext(res) {
        su = token.service_user
        res.map { |e| wrap(su, e) }
      }
    end

    def lists(token, user, args = {})
      res = with_perf('[perf] start fetching lists') {
        protect([]) {
          client(token).lists(user, args)
        }
      }
      if res.is_a?(Hash) and lists = res[:lists]
        with_header_ext(res) {
          su = token.service_user
          lists.map { |e| wrap(su, e) }
        }
      end
    end

    def friends(token, user, args = {})
      res = with_perf('[perf] start fetching friends') {
        protect([]) {
          client(token).friends(user, args)
        }
      }
      if res.is_a?(Hash) and users = res[:users]
        with_header_ext(res) {
          su = token.service_user
          res[:users] = users.map { |e| wrap(su, e) }
        }
      end
      res
    end

    def followers(token, user, args = {})
      res = with_perf('[perf] start fetching followers') {
        protect([]) {
          client(token).followers(user, args)
        }
      }
      if res.is_a?(Hash) and users = res[:users]
        with_header_ext(res) {
          su = token.service_user
          res[:users] = users.map { |e| wrap(su, e) }
        }
      end
      res
    end

    def profile(token, user, args = {})
      profile = Profile.new
      res = with_perf('[perf] start fetching profile') {
        protect(nil) {
          client(token).user(user, args)
        }
      }
      if res
        profile.id = res[:id].to_s
        profile.name = res[:screen_name]
        profile.display_name = res[:name]
        profile.profile_url = "http://twitter.com/#{res[:screen_name]}"
        profile.profile_image_url = res[:profile_image_url]
        profile.location = res[:location] unless res[:location].blank?
        profile.description = CGI.escapeHTML(res[:description]) unless res[:description].blank?
        profile.private = res[:protected]
        profile.followings_count = res[:friends_count]
        profile.followers_count = res[:followers_count]
        profile.entries_count = res[:statuses_count]
      end
      with_header_ext(res) {
        profile
      }
    end

  private

    def with_header_ext(res)
      obj = yield(res)
      obj.extend(Rubytter::ResponseHeaderExtension)
      if res.respond_to?(:headers)
        obj.headers = res.headers
        obj.headers.each do |k, v|
          msg = k.downcase.sub(/\Ax-/, '').tr('-', '_') + '='
          obj.send(msg, v) if obj.respond_to?(msg)
        end
      end
      obj
    end

    def wrap(service_user, hash)
      return nil unless hash
      hash['service_source'] = 'twitter'
      hash['service_user'] = service_user
      hash
    end

    # handles 'Warning' in Twitter Search API.
    def wrap_search(service_user, hash)
      return nil unless hash
      if user = hash[:user]
        user[:id] = user[:screen_name]
      end
      wrap(service_user, hash)
    end

    def client(token)
      client = OAuthRubytter.new(
        {
          :token => token.token,
          :secret => token.secret,
          :consumer => {
            :key => F2P::Config.twitter_api_oauth_consumer_key,
            :secret => F2P::Config.twitter_api_oauth_consumer_secret
          }
        },
        {
          :wiredump => '/tmp/rubytter.log'
        }
      )
      client.connection.client.transparent_gzip_decompression = true
      client
    end
  end
end


# TODO: JRuby's Zlib does not support wbits. I'll fix JRuby.
require 'httpclient/session'
class HTTPClient
  class Session
    def get_body(&block)
      begin
        read_header if @state == :META
        return nil if @state != :DATA
        if @gzipped and @transparent_gzip_decompression
          buf = ''
          original_block = block
          block = Proc.new { |str|
            buf << str
          }
        end
        if @chunked
          read_body_chunked(&block)
        elsif @content_length
          read_body_length(&block)
        else
          read_body_rest(&block)
        end
        if original_block and buf
          begin
            gz = Zlib::GzipReader.new(StringIO.new(buf))
            original_block.call(gz.read)
          ensure
            gz.close
          end
        end
      rescue
        close
        raise
      end
      if eof?
        if @next_connection
          @state = :WAIT
        else
          close
        end
      end
      nil
    end
  end
end


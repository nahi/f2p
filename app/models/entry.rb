require 'hash_utils'
require 'attachment'
require 'comment'
require 'from'
require 'geo'
require 'like'
require 'thumbnail'
require 'via'
require 'cgi'


class Entry
  include HashUtils

  class << self
    def [](hash)
      if hash
        case hash['service_source']
        when 'twitter'
          from_tweet(hash)
        when 'buzz'
          from_buzz(hash)
        when 'graph'
          from_graph(hash)
        when 'delicious'
          from_delicious(hash)
        when 'tumblr'
          from_tumblr(hash)
        else
          new(hash)
        end
      end
    end

    def from_tweet(hash)
      if hash[:retweeted_status]
        base = hash
        hash = hash[:retweeted_status]
        hash['service_source'] = base['service_source']
        hash['service_user'] = base['service_user']
      end
      e = new()
      e.service_source = hash['service_source']
      e.service_user = hash['service_user']
      user = hash[:user] || hash[:sender]
      e.id = from_service_id('twitter', hash[:id].to_s)
      e.date = hash[:created_at]
      e.body = hash[:text]
      e.from = tweet_from(user)
      e.to = []
      e.to << tweet_from(hash[:recipient]) if hash[:recipient]
      e.via = Via.new
      /<a href="([^"]+)" [^>]*>([^<]+)<\/a>/ =~ hash[:source]
      e.via.name = $2 || 'Twitter'
      e.via.url = $1 || 'http://twitter.com/'
      if hash[:geo] and hash[:geo][:coordinates]
        lat, long = hash[:geo][:coordinates]
        e.geo = Geo['lat' => lat, 'long' => long]
      end
      e.twitter_username = e.from.name
      if hash[:in_reply_to_status_id]
        e.twitter_reply_to_status_id = Entry.from_service_id('twitter', hash[:in_reply_to_status_id].to_s)
        e.twitter_reply_to = hash[:in_reply_to_screen_name]
      end
      if base
        e.twitter_retweeted_by_status_id = Entry.from_service_id('twitter', base[:id].to_s)
        e.twitter_retweeted_by = base[:user][:screen_name]
        # just use retweeted date.
        e.date = base[:created_at]
      end
      e.url = twitter_url(e.from.name, e.id)
      e.commands = []
      e.commands << 'comment'
      if e.from.id == e.service_user
        e.commands << 'delete'
      end
      e.likes = []
      if hash[:favorited]
        like = Like.new
        like.date = e.date
        like.from = From.new
        like.from.name = 'You'
        like.entry = e
        e.likes << like
      else
        e.commands << 'like'
      end
      e.commands << 'retweet' if e.from.id != e.service_user
      e.thumbnails = []
      e.files = []
      e.comments = []
      if rts = hash[:retweets]
        e.twitter_retweets = rts.map { |s|
          tweet_from(s[:user])
        }
      end
      e
    end

    def from_buzz(hash)
      e = new()
      e.service_source = hash['service_source']
      e.service_user = hash['service_user']
      user_id = hash['actor']['id']
      e.id = from_service_id('buzz', [user_id, '@self', hash['id']].join('/'))
      e.date = hash['updated']
      body, raw_body, link, thumbnails, files = parse_buzz_object(hash)
      e.body = body || ''
      e.raw_body = raw_body
      e.link = link
      e.thumbnails = thumbnails || Array::EMPTY
      # Tumblr feed treats a link as an attachment.
      if files and files.size == 1 and files.first.type == 'article' and e.link.nil?
        e.link = files.first.url
      end
      e.files = files || Array::EMPTY
      e.view_links = scan_link_from_html_content(e.body)
      e.link ||= e.view_links.shift
      e.url = extract_buzz_link_href(hash['links'])
      e.from = buzz_from(hash['actor'])
      if re = hash['reshare']
        e.buzz_reshared_by = buzz_from(re['sharedBy']['author'])
        e.buzz_reshared_of = buzz_from(re['original']['author'])
        link = extract_buzz_link_href(re['original']['links'], 'via')
        if %r|/(tag:[^/?]+)| =~ link
          e.buzz_reshared_id = from_service_id('buzz', [user_id, '@self', $1].join('/'))
        end
      end
      if hash['source']
        e.via = Via.new
        e.via.name = normalize_content_in_buzz(hash['source']['title'])
        e.via.url = scan_link_from_html_content(hash['source']['title']).first
        if e.via.name == 'Twitter'
          e.body = e.raw_body = normalize_tweet_content_in_buzz(e.body)
          e.twitter_username = (hash['crosspostSource'] || '').match(%r{twitter.com/([^/]+)})[1]
          if /@([a-zA-Z0-9_]+)/ =~ hash['title']
            e.twitter_reply_to = $1
          end
        end
      end
      if hash['geocode']
        lat, long = hash['geocode'].split
        e.geo = Geo['lat' => lat, 'long' => long]
      end
      e.commands = hash['verbs'] || []
      if e.from.id == e.service_user
        e.commands << 'delete'
      end
      # TODO: AFAIK, we cannot know whether comment is disabled of not.
      e.commands << 'comment'
      already_liked = false
      if hash['object'] and liked = hash['object']['liked']
        e.likes = liked.map { |like|
          l = Like.new
          l.date = e.date
          l.from = buzz_from(like)
          l.entry = e
          already_liked = true if l.from.id == e.service_user
          l
        }
      else
        e.likes = []
      end
      e.commands << 'like' if !already_liked
      if hash['links'] and liked = hash['links']['liked']
        liked = liked.first
        if liked['count'] != e.likes.size
          l = Like.new
          l.placeholder = true 
          l.num = liked['count'] - e.likes.size
          l.entry = e
          e.likes.unshift(l)
        end
      end
      if hash['object']
        e.comments = buzz_comments(hash['object']['comments'])
        e.comments.each do |c|
          c.entry = e
        end
      else
        e.comments = Array::EMPTY
      end
      if hash['links'] and replies = hash['links']['replies']
        replies = replies.first
        if replies['count'] != e.comments.size
          c = Comment.new
          c.placeholder = true
          c.num = replies['count'] - e.comments.size
          c.entry = e
          e.comments.unshift(c)
        end
      end
      if categories = hash['categories']
        categories.each do |c|
          if c['term'] == 'mute' and c['label'] == 'Muted'
            e.hidden = true
          end
        end
      end
      e.to = []
      e
    end

    def from_graph(hash)
      e = new()
      e.service_source = hash['service_source']
      e.service_user = hash['service_user']
      e.id = from_service_id('graph', hash['id'])
      e.date = hash['updated_time']
      e.from = graph_from(hash['from'])
      e.to = []
      if hash['to']
        hash['to']['data'].each do |u|
          e.to << graph_from(u)
        end
      end
      e.thumbnails = []
      e.files = []
      # TODO: location
      case hash['type']
      when 'album'
        e.body = hash['description'] + "(#{hash['count']} photo(s))"
        e.link = hash['link']
      when 'event'
        e.body = [hash['name'], hash['description'], hash['owner']['name']]
      when 'group'
        e.body = [hash['name'], hash['description'], hash['owner']['name']]
        e.link = hash['link']
      when 'link'
        e.body = [hash['name'], hash['description'], hash['message']].compact
        if hash['link'] != 'http://www.facebook.com/'
          e.link = hash['link']
        end
      when 'note'
        e.body = [hash['subject'], normalize_content_in_buzz(hash['message'])]
      when 'page'
        # TODO
        e.body = hash['name']
      when 'photo'
        e.body = [hash['name'], hash['message']]
        e.link = hash['link'] if hash['source']
      when 'video'
        e.body = normalize_content_in_buzz(hash['description'])
      else
        e.body = hash['message']
      end
      if hash['picture']
        t = Thumbnail.new
        t.link = hash['source'] || hash['link']
        t.url = hash['picture']
        t.title = hash['message'] || hash['description'] || hash['caption'] || e.body
        t.height = hash['height']
        t.width = hash['width']
        e.thumbnails << t
      end
      if e.body.is_a?(Array)
        e.body = e.body.compact.join(' - ')
      end
      e.raw_body = e.body
      if hash['attribution']
        e.via = Via.new
        e.via.name = normalize_content_in_buzz(hash['attribution'])
        # TODO: report
        e.via.url = scan_link_from_html_content(hash['attribution']).first
        e.via.url.sub!(/graph.facebook.com/, 'www.facebook.com') if e.via.url
      end
      e.commands = []
      if hash['actions']
        hash['actions'].each do |a|
          case a['name']
          when /@([a-zA-Z0-9_]+) on Twitter\z/
            e.twitter_username = $1
            if /@([a-zA-Z0-9_]+)/ =~ e.body
              e.twitter_reply_to = $1
            end
          when 'Comment'
            e.commands << 'comment'
            e.url = a['link']
          when 'Like'
            e.url = a['link']
          end
        end
      end
      if hash['comments']
        e.comments = graph_comments(hash['comments']['data'])
        e.comments.each do |c|
          c.entry = e
        end
      else
        e.comments = []
      end
      e.likes = []
      already_liked = false
      if likes = hash['likes']
        if likes.is_a?(Hash)
          likes['data'].each do |like|
            l = Like.new
            l.date = e.date
            l.from = graph_from(like)
            l.entry = e
            e.likes << l
            already_liked = true if l.from.id == e.service_user
          end
        else
          like = Like.new
          like.placeholder = true
          like.num = hash['likes']
          e.likes << like
        end
      end
      e.commands << 'like' unless already_liked
      e
    end

    def from_delicious(hash)
      e = new()
      e.service_source = hash['service_source']
      e.service_user = hash['service_user']
      e.id = from_service_id('delicious', hash['hash'])
      e.date = hash['time']
      e.body = e.raw_body = (hash['description'] || '') + delicious_tag(hash['tag'])
      e.link = hash['href']
      e.from = delicious_from(hash)
      e.to = Array::EMPTY
      e.thumbnails = Array::EMPTY
      e.files = Array::EMPTY
      e.commands = Array::EMPTY
      e.comments = Array::EMPTY
      e.likes = Array::EMPTY
      e
    end

    def from_tumblr(hash)
      e = new()
      e.service_source = hash['service_source']
      e.service_user = hash['service_user']
      e.from = tumblr_from(hash['tumblelog'])
      e.id = from_service_id('tumblr', [e.from.id, hash['id'].to_s].join('/'))
      e.date = Time.at(hash['unix-timestamp']).xmlschema
      e.url = hash['url']
      case hash['type']
      when 'regular'
        e.raw_body = hash['regular-title']
        c = Comment.new
        c.id = e.id
        c.date = e.date
        c.body = normalize_content_in_tumblr(hash['regular-body'])
        c.from = e.from
        c.service_source = 'tumblr'
        c.entry = e
        e.comments = [c]
        e.view_links = scan_link_from_html_content(hash['regular-body'])
        e.link = e.view_links.shift
      when 'photo'
        e.raw_body = normalize_content_in_tumblr(hash['photo-caption'])
        e.view_links = scan_link_from_html_content(hash['photo-caption'])
        e.link = e.view_links.shift
        t = Thumbnail.new
        t.link = hash['photo-link-url']
        t.url = hash['photo-url-100']
        t.title = hash['reblogged-from-title'] || normalize_content_in_tumblr(e.raw_body)
        e.thumbnails = [t]
      when 'quote'
        # remove single new-line for AA alignment.
        quoted = hash['quote-text'].gsub(/\n(?!\n)/, '')
        e.raw_body = '"' + normalize_content_in_tumblr(quoted) + '"'
        f = Attachment.new
        f.type = 'article'
        f.name = normalize_content_in_tumblr(hash['quote-source'])
        e.view_links = scan_link_from_html_content(hash['quote-source'])
        f.url = e.view_links.shift
        e.files = [f]
      when 'link'
        e.raw_body = normalize_content_in_tumblr(hash['link-text'])
        e.link = hash['link-url']
        unless hash['link-description'].blank?
          c = Comment.new
          c.id = e.id
          c.date = e.date
          c.body = normalize_content_in_tumblr(hash['link-description'])
          c.from = e.from
          c.service_source = 'tumblr'
          c.entry = e
          e.comments = [c]
        end
      when 'conversation'
        e.raw_body = hash['conversation-title'] + "\n"
        hash['conversation'].each do |c|
          e.raw_body += [c['name'], c['phrase']].join(': ') + "\n"
        end
      when 'video'
        e.raw_body = normalize_content_in_tumblr(hash['video-caption'])
        e.view_links = scan_link_from_html_content(hash['video-caption'])
        e.link = e.view_links.shift || hash['video-source']
      when 'audio'
        e.raw_body = normalize_content_in_tumblr(hash['audio-caption'])
        e.view_links = scan_link_from_html_content(hash['audio-caption'])
        e.link = e.view_links.shift || hash['audio-source']
      when 'answer'
        e.raw_body = normalize_content_in_tumblr([hash['question'], hash['answer']].join(' - '))
      end
      e.body = normalize_content_in_tumblr(e.raw_body)
      e.likes = []
      e.commands = []
      if hash['liked']
        like = Like.new
        like.date = e.date
        like.from = From.new
        like.from.name = 'You'
        like.entry = e
        e.likes << like
      else
        e.commands << 'like'
      end
      e.tumblr_reblog_key = hash['reblog-key']
      e.to = Array::EMPTY
      e.thumbnails ||= Array::EMPTY
      e.files ||= Array::EMPTY
      e.comments ||= Array::EMPTY
      e
    end

    def normalize_content_in_buzz(body)
      if body
        CGI.unescapeHTML(body.gsub(/<br\s*\/?>/i, "\n").gsub(/<[^>]+>/, ''))
      end
    end

    def normalize_tweet_content_in_buzz(body)
      normalize_content_in_buzz(body).sub(/[^:]+: /, '')
    end

    def normalize_content_in_tumblr(body)
      if body
        # &#160; = 0xa0 : No-Break Space
        normalize_content_in_buzz(body.gsub(/&#160;/, ' '))
      end
    end

    HTML_URI_REGEXP = /href=(?:'([^']+)'|"([^"]+)")/i
    URI_REGEXP = URI.regexp(['http', 'https'])
    def scan_link_from_html_content(base)
      links = []
      str = base
      # find href='...' first
      while str.match(HTML_URI_REGEXP)
        m = $~
        links << (m[1] || m[2])
        str = m.post_match
      end
      return links unless links.empty?
      # then, pick up links by scanning
      str = base
      while str.match(URI_REGEXP)
        m = $~
        links << m[0]
        str = m.post_match
      end
      links
    end

    def tweet_from(hash)
      f = From.new
      f.id = hash[:id].to_s
      f.name = hash[:screen_name]
      f.type = 'user'
      f.private = hash[:protected]
      f.profile_url = "http://twitter.com/#{f.name}"
      f.profile_image_url = hash[:profile_image_url]
      f.service_source = 'twitter'
      f
    end

    def buzz_comments(comments)
      return [] unless comments
      comments.map { |comment|
        Comment.from_buzz(comment)
      }
    end

    def buzz_from(hash)
      return nil unless hash
      f = From.new
      f.id = hash['id']
      f.name = hash['name'] || hash['displayName']
      f.type = 'user'
      f.profile_url = hash['profileUrl']
      f.service_source = 'buzz'
      # ad hoc conversion. We cannot these from activities stream.
      f.private = false
      f.commands = []
      profile_image_url = hash['thumbnailUrl']
      if profile_image_url.blank?
        f.profile_image_url = 'http://mail.google.com/mail/images/blue_ghost.jpg'
      else
        f.profile_image_url = profile_image_url
      end
      f
    end

    def graph_comments(comments)
      return [] unless comments
      comments.map { |comment|
        Comment.from_graph(comment)
      }
    end

    def graph_from(hash)
      return nil unless hash
      f = From.new
      f.id = hash['id']
      f.name = hash['name']
      f.type = 'user'
      f.service_source = 'graph'
      f.private = false
      f.commands = ['subscribe']
      f.profile_url = "http://www.facebook.com/#{f.id}"
      f.profile_image_url = "http://graph.facebook.com/#{f.id}/picture"
      f
    end

    def delicious_from(hash)
      return nil unless hash
      f = From.new
      f.id = hash['service_user']
      f.name = 'You'
      f.type = 'user'
      f.service_source = 'delicious'
      f.private = false
      f.commands = Array::EMPTY
      f
    end

    def tumblr_from(hash)
      return nil unless hash
      f = From.new
      f.id = f.name = hash['name']
      f.type = 'user'
      f.service_source = 'tumblr'
      f.private = false
      f.commands = ['subscribe']
      f.profile_url = hash['url']
      f.profile_image_url = hash['avatar_url_48']
      f
    end

    def create(opt)
      auth = opt[:auth]
      to = opt[:to]
      body = opt[:body]
      token = opt[:token]
      case opt[:service_source]
      when 'twitter'
        params = {}
        if opt[:in_reply_to_status_id]
          params[:in_reply_to_status_id] = opt[:in_reply_to_status_id]
        end
        if opt[:to].empty?
          entry = Tweet.update_status(token, body, params)
        else # DM
          entry = Tweet.send_direct_message(token, opt[:to].first, body, params)
        end
        Entry.from_tweet(entry) if entry
      when 'buzz'
        if entry = Buzz.create_note(token, body)
          Entry.from_buzz(entry)
        end
      when 'graph'
        if entry = Graph.create_message(token, body)
          Entry.from_graph(entry)
        end
      else # FriendFeed
        if entry = ff_client.post_entry(to, body, opt.merge(auth.new_cred))
          Entry[entry]
        end
      end
    end

    def update(opt)
      auth = opt[:auth]
      eid = opt[:eid]
      if entry = ff_client.edit_entry(eid, opt.merge(auth.new_cred))
        Entry[entry]
      end
    end

    def delete(opt)
      id = opt[:eid]
      token = opt[:token]
      sid = Entry.if_service_id(id)
      case opt[:service_source]
      when 'twitter'
        Tweet.remove_status(token, sid)
      when 'buzz'
        Buzz.delete_activity(opt[:token], sid)
      else # FriendFeed
        auth = opt[:auth]
        undelete = !!opt[:undelete]
        if undelete
          ff_client.undelete_entry(id, auth.new_cred)
        else
          ff_client.delete_entry(id, auth.new_cred)
        end
      end
    end

    def add_comment(opt)
      auth = opt[:auth]
      id = opt[:eid]
      body = opt[:body]
      sid = Entry.if_service_id(id)
      token = opt[:token]
      case opt[:service_source]
      when 'twitter'
        params = {}
        params[:in_reply_to_status_id] = opt[:in_reply_to_status_id]
        if entry = Tweet.update_status(token, body, params)
          Entry.from_tweet(entry)
        end
      when 'buzz'
        if comment = Buzz.create_comment(token, sid, body)
          Comment.from_buzz(comment)
        end
      when 'graph'
        if comment = Graph.create_comment(token, sid, body)
          Comment.from_graph(comment)
        end
      else # FriendFeed
        if comment = ff_client.post_comment(id, body, auth.new_cred)
          Comment[comment]
        end
      end
    end

    def edit_comment(opt)
      auth = opt[:auth]
      comment = opt[:comment]
      body = opt[:body]
      if comment = ff_client.edit_comment(comment, body, auth.new_cred)
        Comment[comment]
      end
    end

    def delete_comment(opt)
      auth = opt[:auth]
      comment = opt[:comment]
      undelete = !!opt[:undelete]
      if undelete
        ff_client.undelete_comment(comment, auth.new_cred)
      else
        ff_client.delete_comment(comment, auth.new_cred)
      end
    end

    def add_like(opt)
      auth = opt[:auth]
      id = opt[:eid]
      sid = Entry.if_service_id(id)
      case opt[:service_source]
      when 'twitter'
        hash = Tweet.favorite(opt[:token], sid)
        hash[:favorited] = true
        entry = Entry.from_tweet(hash)
        if pin = Pin.find_by_user_id_and_eid(auth.id, entry.id)
          pin.entry = hash
          pin.save!
        end
        entry
      when 'buzz'
        Buzz.like(opt[:token], sid)
        hash = Buzz.show(opt[:token], sid)
        entry = Entry.from_buzz(hash)
        # TODO: since Buzz.show does not returns likes detail...
        entry.commands.delete('like')
        if pin = Pin.find_by_user_id_and_eid(auth.id, entry.id)
          pin.entry = hash
          pin.save!
        end
        entry
      when 'graph'
        Graph.like(opt[:token], sid)
        hash = Graph.show(opt[:token], sid)
        entry = Entry.from_graph(hash)
        if pin = Pin.find_by_user_id_and_eid(auth.id, entry.id)
          pin.entry = hash
          pin.save!
        end
        entry
      when 'tumblr'
        Tumblr.like(opt[:token], sid, opt[:tumblr_reblog_key])
        hash = Tumblr.show(opt[:token], sid)
        entry = Entry.from_tumblr(hash)
        if pin = Pin.find_by_user_id_and_eid(auth.id, entry.id)
          pin.entry = hash
          pin.save!
        end
        entry
      else
        hash = ff_client.like(id, auth.new_cred)
        Entry[hash]
      end
    end

    def delete_like(opt)
      auth = opt[:auth]
      id = opt[:eid]
      sid = Entry.if_service_id(id)
      case opt[:service_source]
      when 'twitter'
        hash = Tweet.remove_favorite(opt[:token], sid)
        hash[:favorited] = false
        entry = Entry.from_tweet(hash)
        if pin = Pin.find_by_user_id_and_eid(auth.id, entry.id)
          pin.entry = hash
          pin.save!
        end
        entry
      when 'buzz'
        Buzz.unlike(opt[:token], sid)
        hash = Buzz.show(opt[:token], sid)
        entry = Entry.from_buzz(hash)
        if pin = Pin.find_by_user_id_and_eid(auth.id, entry.id)
          pin.entry = hash
          pin.save!
        end
        entry
      when 'graph'
        Graph.unlike(opt[:token], sid)
        hash = Graph.show(opt[:token], sid)
        entry = Entry.from_graph(hash)
        if pin = Pin.find_by_user_id_and_eid(auth.id, entry.id)
          pin.entry = hash
          pin.save!
        end
        entry
      when 'tumblr'
        Tumblr.unlike(opt[:token], sid, opt[:tumblr_reblog_key])
        hash = Tumblr.show(opt[:token], sid)
        p hash
        entry = Entry.from_tumblr(hash)
        p entry
        if pin = Pin.find_by_user_id_and_eid(auth.id, entry.id)
          pin.entry = hash
          pin.save!
        end
        entry
      else
        hash = ff_client.delete_like(id, auth.new_cred)
        Entry[hash]
      end
    end

    def hide(opt)
      auth = opt[:auth]
      id = opt[:eid]
      if opt[:service_source] == 'buzz'
        Buzz.mute(opt[:token], Entry.if_service_id(id))
      else
        ff_client.hide_entry(id, auth.new_cred)
      end
    end

    def create_short_url(opt)
      auth = opt[:auth]
      id = opt[:eid]
      if entry = ff_client.create_short_url(id, auth.new_cred)
        Entry[entry]
      end
    end

    def add_pin(opt)
      auth = opt[:auth]
      id = opt[:eid]
      source = opt[:source]
      ActiveRecord::Base.transaction do
        # ignore different source for the same id.
        unless Pin.find_by_user_id_and_eid(auth.id, id)
          pin = Pin.new
          pin.source = source
          pin.user = auth
          pin.eid = id
          pin.entry = opt[:entry]
          pin.save!
        end
      end
    end

    def delete_pin(opt)
      auth = opt[:auth]
      id = opt[:eid]
      if pin = Pin.find_by_user_id_and_eid(auth.id, id)
        raise unless pin.destroy
      end
    end

    def if_service_id(id, &block)
      if m = id.match(/\A._/)
        post = m.post_match
        if block_given?
          yield post
        else
          post
        end
      end
    end

    def from_service_id(service_source, id)
      return id if service_source.nil?
      case service_source
      when 'twitter'
        't_' + id
      when 'buzz'
        'b_' + id
      when 'graph'
        'g_' + id
      when 'delicious'
        'd_' + id
      when 'tumblr'
        'm_' + id
      end
    end

    def twitter_url(screen_name, status_id)
      "http://twitter.com/#{screen_name}/status/#{Entry.if_service_id(status_id)}"
    end

  private

    def logger
      ActiveRecord::Base.logger
    end

    def ff_client
      ApplicationController.ff_client
    end

    def parse_buzz_object(hash)
      body = raw_body = hash['title']
      link = thumbnails = files = nil
      if obj = hash['object']
        case obj['type']
        when 'note'
          if obj['content']
            body = obj['content']
            raw_body = normalize_content_in_buzz(body)
          end
        end
        l = extract_buzz_link_href(obj['links'])
        # imported link from FriendFeed does not have a link to the original site.
        if /www.google.com\/buzz/ !~ l or (hash['source'] and hash['source']['title'] == 'FriendFeed')
          link = l
        end
        thumbnails, files = parse_buzz_attachment(obj)
      end
      if source = hash['crosspostSource']
        if /^http:/ =~ source
          if link.nil?
            link = source
          else
            f = Attachment.new
            f.type = 'article'
            f.name = source
            f.url = source
            files << f
          end
        end
      end
      return body, raw_body, link, thumbnails, files
    end

    def parse_buzz_attachment(obj)
      thumbnails = []
      files = []
      if attachments = obj['attachments']
        attachments.each do |e|
          t = f = nil
          case e['type']
          when 'photo'
            t = Thumbnail.new
            if links = e['links']
              t = Thumbnail.new
              t.link = extract_buzz_link_href(e['links'])
              preview = links['preview']
              preview = preview.first if preview
              t.url = preview['href'] if preview
            end
            t.title = e['title']
          when 'article'
            ref = extract_buzz_link(e['links'])
            f = Attachment.new
            f.type = ref['type']
            f.url = ref['href']
            f.name = e['content'] || f.url
          end
          if t.nil? and f.nil? and link = extract_buzz_link(e['links'])
            if /^image/ =~ link['type']
              t = Thumbnail.new
              t.url = link['href']
              t.title = e['title']
            end
          end
          thumbnails << t if t
          files << f if f
        end
      end
      return thumbnails, files
    end

    def extract_buzz_link_href(links, type = 'alternate')
      if link = extract_buzz_link(links, type)
        link['href']
      end
    end

    def extract_buzz_link(links, type = 'alternate')
      if links
        alt = links[type]
        alt.first if alt
      end
    end

    def delicious_tag(tag)
      (tag || '').split.map { |e| ' #' + e }.join
    end
  end

  attr_accessor :service_source
  attr_accessor :service_user

  attr_accessor :id
  attr_accessor :body
  attr_accessor :raw_body
  attr_accessor :url
  attr_accessor :link
  attr_accessor :date
  attr_accessor :from
  attr_accessor :to
  attr_accessor :thumbnails
  attr_accessor :files
  attr_accessor :comments
  attr_accessor :likes
  attr_accessor :via
  attr_accessor :geo
  attr_accessor :fof
  attr_accessor :fof_type
  attr_accessor :checked_at
  attr_accessor :commands
  attr_accessor :short_id
  attr_accessor :short_url
  attr_accessor :hidden

  attr_accessor :twitter_username
  attr_accessor :twitter_reply_to
  attr_accessor :twitter_reply_to_status_id
  attr_accessor :twitter_retweeted_by
  attr_accessor :twitter_retweeted_by_status_id
  attr_accessor :twitter_retweets
  attr_accessor :buzz_reshared_by
  attr_accessor :buzz_reshared_of
  attr_accessor :buzz_reshared_id
  attr_accessor :tumblr_reblog_key

  attr_accessor :orphan
  attr_accessor :view_pinned
  attr_accessor :view_nextid
  attr_accessor :view_links
  attr_accessor :view_medias
  attr_accessor :view_map

  def initialize(hash = nil)
    initialize_with_hash(hash, 'id', 'url', 'date', 'commands', 'service_source', 'service_user') if hash
    @commands ||= Array::EMPTY
    @twitter_username = nil
    @twitter_reply_to = nil
    @twitter_reply_to_status_id = nil
    @twitter_retweeted_by = nil
    @twitter_retweeted_by_status_id = nil
    @twitter_retweets = nil
    @buzz_reshared_by = nil
    @buzz_reshared_of = nil
    @buzz_reshared_id = nil
    @tumblr_reblog_key = nil
    @view_pinned = nil
    @view_nextid = nil
    @view_links = nil
    @view_medias = []
    @view_map = false
    @raw_body = @body = nil
    @checked_at = Time::ZERO
    @modified = nil
    @hidden = false
    if hash
      @orphan = hash['__f2p_orphan']
      @raw_body = @body = hash['rawBody']
      @link = hash['rawLink']
      if %r(\Ahttp://friendfeed.com/e/) =~ @link
        @link = nil
      end
      @short_id = hash['shortId']
      @short_url = hash['shortUrl']
      @from = From[hash['from']]
      @to = (hash['to'] || Array::EMPTY).map { |e| From[e] }
      @thumbnails = wrap_thumbnails(hash['thumbnails'] || Array::EMPTY)
      @files = (hash['files'] || Array::EMPTY).map { |e| Attachment[e] }
      @comments = wrap_comments(hash['comments'] || Array::EMPTY)
      @likes = wrap_likes(hash['likes'] || Array::EMPTY)
      @via = Via[hash['via']]
      @geo = Geo[hash['geo']] || extract_geo_from_google_staticmap_url(@thumbnails)
      if hash['fof']
        @fof = From[hash['fof']['from']]
        @fof_type = hash['fof']['type']
      else
        @fof = nil
      end
      @hidden = hash['hidden'] || false
      if self.via and self.via.twitter?
        @twitter_username = (self.via.url || '').match(%r{twitter.com/([^/]+)})[1]
        if /@([a-zA-Z0-9_]+)/ =~ self.body
          @twitter_reply_to = $1
        end
      end
    end
  end

  def to_ids
    to.map { |e| e.id }
  end

  def similar?(rhs, opt)
    result = false
    if self.from_id == rhs.from_id
      result ||= same_origin?(rhs)
    end
    if !self.private and !rhs.private
      result ||= same_link?(rhs) || similar_body?(rhs)
    end
    # Twitter thread construction.
    if self.via and rhs.via and self.via.twitter? and rhs.via.twitter?
      opt[:twitter_buddy] ||= self.twitter_reply_to
      if opt[:twitter_buddy]
        # from me, and @ to the buddy
        result ||= (self.twitter_username == rhs.twitter_username and reply_to?(rhs, opt[:twitter_buddy]))
        # from buddy, and @ to me
        result ||= (rhs.twitter_username == opt[:twitter_buddy] and reply_to?(rhs, self.twitter_username))
      elsif self.twitter_reply_to == rhs.twitter_username || self.twitter_username == rhs.twitter_reply_to
        result ||= true
        opt[:twitter_buddy] = rhs.twitter_username
      end
    end
    result
  end

  def reply_to?(rhs, target)
    rhs.twitter_reply_to.nil? or rhs.twitter_reply_to == target
  end

  def service_id
    if via
      via.service_id
    end
  end

  def identity(opt = {})
    @identity ||= [self.from_id, self.to_ids]
    if !opt[:merge_service]
      if self.service_id
        return @identity + [self.service_id]
      end
    end
    @identity
  end

  def date_at
    @date_at ||= (date ? Time.parse(date) : Time.now)
  end

  def modified_at
    @modified_at ||= Time.parse(modified)
  end

  def unread?
    checked_at < date_at
  end

  def modified
    return @modified if @modified
    @modified = self.date
    # check date of each like only if it's mine.
    if self.from and self.from.me?
      if m = likes.map { |e| e.date || '' }.max
        @modified = [@modified, m].max
      end
    end
    # check date of each comment if it's from friend (not fof) or I like it.
    if !self.fof or likes.any? { |e| e.from and e.from.me? }
      if m = comments.map { |e| e.date || '' }.max
        @modified = [@modified, m].max
      end
    end
    @modified || Time.now.xmlschema
  end

  def hidden?
    @hidden
  end

  def from_id
    from.id
  end

  def comments_size
    if placeholder = comments.find { |e| e.placeholder }
      comments.size + placeholder.num - 1
    else
      comments.size
    end
  end
  
  def likes_size
    if placeholder = likes.find { |e| e.placeholder }
      likes.size + placeholder.num - 1
    else
      likes.size
    end
  end

  def self_comment_only?
    comments_size == 1 and self.from_id == self.comments.first.from_id
  end

  def origin_id
    if !orphan
      from_id
    end
  end

  def private
    orphan || from.private || to.any? { |e| e.private }
  end

  def twitter_id
    Entry.if_service_id(self.id) { |tid|
      tid
    }
  end

  def ff?
    service_source.nil?
  end

  def tweet?
    service_source == 'twitter'
  end

  def buzz?
    service_source == 'buzz'
  end

  def graph?
    service_source == 'graph'
  end

  def delicious?
    service_source == 'delicious'
  end

  def tumblr?
    service_source == 'tumblr'
  end

  def twitter_in_reply_to_url
    if twitter_reply_to_status_id
      Entry.twitter_url(twitter_reply_to, twitter_reply_to_status_id)
    end
  end

  def twitter_retweeted_by_url
    if twitter_retweeted_by
      Entry.twitter_url(twitter_retweeted_by, twitter_retweeted_by_status_id)
    end
  end

  # return true if it's dummy entry, person entry of followings for example.
  def dummy?
    @date.nil?
  end

  def id_for_max
    twitter_retweeted_by_status_id || id
  end

private

  def wrap_likes(likes)
    likes.map { |e|
      l = Like[e]
      l.entry = self
      l
    }
  end

  def wrap_comments(comments)
    index = 0
    comments.map { |e|
      c = Comment[e]
      index += 1
      c.index = index
      c.entry = self
      c
    }
  end

  # set Thumbnail#url to nil when it's not a link to an image.
  def wrap_thumbnails(thumbnails)
    thumbnails.map { |e|
      t = Thumbnail[e]
      # FriendFeed API sets html URL for #url for Buzz.  Need to handle by myself.
      if %r(^http://www.pheedo.jp/) =~ t.url ||
          %r(^http://picasaweb.google.com/) =~ t.url ||
          %r(\.html) =~ t.url
        t.link = t.url
        t.url = nil
      end
      t
    }
  end

  def extract_geo_from_google_staticmap_url(tbs)
    tbs.each do |tb|
      if /maps.google.com\/maps\?q=([0-9\.]+),([0-9\.]+)\b/ =~ tb.link
        self.view_map = true
        return Geo['lat' => $1, 'long' => $2]
      end
    end
    nil
  end

  def same_origin?(rhs)
    (self.date_at - rhs.date_at).abs < 5.seconds
  end

  def similar_body?(rhs)
    t1 = self.body
    t2 = rhs.body
    t1 == t2 or part_of(t1, t2) or part_of(t2, t1)
  end

  def same_link?(rhs)
    self.url and rhs.url and self.url == rhs.url
  end

  def part_of(base, part)
    base and part and base.index(part) and part.length > base.length / 2
  end
end

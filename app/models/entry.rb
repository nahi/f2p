require 'hash_utils'
require 'attachment'
require 'comment'
require 'from'
require 'geo'
require 'like'
require 'thumbnail'
require 'via'


class Entry
  include HashUtils
  EMPTY = [].freeze
  TIME_ZERO = Time.at(0).freeze

  class << self
    def [](hash)
      if hash
        case hash['service_source']
        when 'twitter'
          from_tweet(hash)
        when 'buzz'
          from_buzz(hash)
        else
          new(hash)
        end
      end
    end

    def from_tweet(hash)
      e = new(hash)
      user = hash[:user] || hash[:sender]
      e.id = from_service_id('twitter', hash[:id].to_s)
      e.date = hash[:created_at]
      e.body = hash[:text]
      e.from = From.new
      e.from.id = user[:id].to_s
      e.from.name = user[:screen_name]
      e.from.type = 'user'
      e.from.private = user[:protected]
      e.from.profile_url = "http://twitter.com/#{e.from.name}"
      e.from.service_source = e.service_source
      e.via = Via.new
      /<a href="([^"]+)" [^>]*>([^<]+)<\/a>/ =~ hash[:source]
      e.via.name = $2 || 'Twitter'
      e.via.url = $1 || 'http://twitter.com/'
      if hash[:geo] and hash[:geo][:coordinates]
        lat, long = hash[:geo][:coordinates]
        e.geo = Geo['lat' => lat, 'long' => long]
      end
      e.profile_image_url = user[:profile_image_url]
      e.twitter_username = e.from.id
      if hash[:in_reply_to_status_id]
        e.twitter_reply_to_status_id = hash[:in_reply_to_status_id].to_s
        e.twitter_reply_to = hash[:in_reply_to_screen_name]
      end
      if hash[:retweeted_status]
        e.twitter_retweet_of_status_id = hash[:retweeted_status][:id].to_s
        e.twitter_retweet_of = hash[:retweeted_status][:user][:screen_name]
      end
      e.url = twitter_url(e.from.name, hash[:id])
      e.commands = []
      e.likes = []
      if hash[:favorited]
        like = Like.new
        like.date = e.date
        like.from = From.new
        like.from.name = 'You'
        e.likes << like
      else
        e.commands << 'like'
      end
      e
    end

    def from_buzz(hash)
      e = new(hash)
      user_id = hash['actor']['id']
      e.id = from_service_id('buzz', [user_id, '@self', hash['id']].join('/'))
      e.date = hash['updated']
      body, link, thumbnails, files = parse_buzz_object(hash)
      e.body = body
      if /www.google.com\/buzz/ =~ link
        e.url = link
      else
        e.link = link
      end
      e.thumbnails = thumbnails
      e.files = files
      e.from = buzz_from(hash['actor'])
      e.via = Via.new
      e.via.name = hash['source'] && hash['source']['title']
      e.via.name ||= ''
      if e.via.name == 'Twitter'
        e.twitter_username = (hash['crosspostSource'] || '').match(%r{twitter.com/([^/]+)})[1]
        if /@([a-zA-Z0-9_]+)/ =~ hash['title']
          e.twitter_reply_to = ''
        end
      end
      if hash['geocode']
        lat, long = hash['geocode'].split
        e.geo = Geo['lat' => lat, 'long' => long]
      end
      profile_image_url = hash['actor']['thumbnailUrl']
      if profile_image_url.empty?
        profile_image_url = 'http://mail.google.com/mail/images/blue_ghost.jpg'
      end
      e.profile_image_url = profile_image_url
      e.commands = hash['verbs']
      if e.from.id == e.service_user
        e.commands << 'delete'
      end
      # TODO: AFAIK, we cannot know whether comment is disabled of not.
      e.commands << 'comment'
      already_liked = false
      if liked = hash['object']['liked']
        e.likes = liked.map { |like|
          l = Like.new
          l.date = e.date
          l.from = buzz_from(like)
          already_liked = true if l.from.id == e.service_user
          l
        }
      else
        e.likes = []
      end
      e.commands << 'like' unless already_liked
      if liked = hash['links']['liked']
        liked = liked.first
        if liked['count'] != e.likes.size
          l = Like.new
          l.from = From.new
          l.placeholder = true 
          l.num = liked['count'] - e.likes.size
          e.likes.unshift(l)
        end
      end
      e.comments = buzz_comments(hash['object']['comments'])
      e.comments.each do |c|
        c.entry = e
      end
      if replies = hash['links']['replies']
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
      e
    end

    def buzz_comments(comments)
      return [] unless comments
      comments.map { |comment|
        Comment.from_buzz(comment)
      }
    end

    def buzz_from(hash)
      f = From.new
      f.id = hash['id']
      f.name = hash['name'] || hash['displayName']
      f.type = 'user'
      f.private = false # ???
      f.profile_url = hash['profileUrl']
      f.service_source = 'buzz'
      f
    end

    def create(opt)
      auth = opt[:auth]
      to = opt[:to]
      body = opt[:body]
      case opt[:service_source]
      when 'twitter'
        params = {}
        if opt[:in_reply_to_status_id]
          params[:in_reply_to_status_id] = opt[:in_reply_to_status_id]
        end
        if entry = Tweet.update_status(opt[:token], body, params)
          Entry.from_tweet(entry)
        end
      when 'buzz'
        if entry = Buzz.create_note(opt[:token], body)
          Entry.from_buzz(entry)
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
      case opt[:service_source]
      when 'buzz'
        Buzz.delete_activity(opt[:token], Entry.if_service_id(id))
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
      case opt[:service_source]
      when 'buzz'
        token = opt[:token]
        if comment = Buzz.create_comment(token, Entry.if_service_id(id), body)
          Comment.from_buzz(comment)
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
      case opt[:service_source]
      when 'twitter'
        hash = Tweet.favorite(opt[:token], Entry.if_service_id(id))
        hash[:favorited] = true
        entry = Entry.from_tweet(hash)
        if pin = Pin.find_by_user_id_and_eid(auth.id, entry.id)
          pin.entry = hash
          pin.save!
        end
        entry
      when 'buzz'
        Buzz.like(opt[:token], Entry.if_service_id(id))
        hash = Buzz.show(opt[:token], Entry.if_service_id(id))
        entry = Entry.from_buzz(hash)
        # TODO: since Buzz.show does not returns likes detail...
        entry.commands.delete('like')
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
      case opt[:service_source]
      when 'twitter'
        hash = Tweet.remove_favorite(opt[:token], Entry.if_service_id(id))
        hash[:favorited] = false
        entry = Entry.from_tweet(hash)
        if pin = Pin.find_by_user_id_and_eid(auth.id, entry.id)
          pin.entry = hash
          pin.save!
        end
        entry
      when 'buzz'
        Buzz.unlike(opt[:token], Entry.if_service_id(id))
        hash = Buzz.show(opt[:token], Entry.if_service_id(id))
        entry = Entry.from_buzz(hash)
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
      end
    end

    def twitter_url(screen_name, status_id)
      "http://twitter.com/#{screen_name}/status/#{status_id}"
    end

  private

    def logger
      ActiveRecord::Base.logger
    end

    def ff_client
      ApplicationController.ff_client
    end

    def parse_buzz_object(hash)
      body = hash['title']
      link = thumbnails = files = nil
      if obj = hash['object']
        case obj['type']
        when 'note'
          body = obj['content']
        end
        link = extract_buzz_link_href(obj['links'])
        thumbnails, files = parse_buzz_attachment(obj)
      end
      if link = hash['crosspostSource']
        if /^http:/ =~ link
          f = Attachment.new
          f.type = 'article'
          f.name = link
          f.url = link
          files << f
        end
      end
      return body, link, thumbnails, files
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
            f = Attachment.new
            f.type = 'article'
            f.name = e['content']
            f.url = extract_buzz_link_href(e['links'])
          end
          if t.nil? and link = extract_buzz_link(e['links'])
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

    def extract_buzz_link_href(links)
      if link = extract_buzz_link(links)
        link['href']
      end
    end

    def extract_buzz_link(links)
      if links
        alt = links['alternate']
        alt.first if alt
      end
    end
  end

  attr_accessor :service_source
  attr_accessor :service_user

  attr_accessor :id
  attr_accessor :body
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

  attr_accessor :profile_image_url
  attr_accessor :twitter_username
  attr_accessor :twitter_reply_to
  attr_accessor :twitter_reply_to_status_id
  attr_accessor :twitter_retweet_of
  attr_accessor :twitter_retweet_of_status_id

  attr_accessor :orphan
  attr_accessor :view_pinned
  attr_accessor :view_unread
  attr_accessor :view_nextid
  attr_accessor :view_links
  attr_accessor :view_medias
  attr_accessor :view_map

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'url', 'date', 'commands', 'service_source', 'service_user')
    @commands ||= EMPTY
    @profile_image_url = nil
    @twitter_username = nil
    @twitter_reply_to = nil
    @twitter_reply_to_status_id = nil
    @twitter_retweet_of = nil
    @twitter_retweet_of_status_id = nil
    @orphan = hash['__f2p_orphan']
    @view_pinned = nil
    @view_unread = nil
    @view_nextid = nil
    @view_links = nil
    @view_medias = []
    @view_map = false
    @body = hash['rawBody']
    @link = hash['rawLink']
    if %r(\Ahttp://friendfeed.com/e/) =~ @link
      @link = nil
    end
    @short_id = hash['shortId']
    @short_url = hash['shortUrl']
    @from = From[hash['from']]
    @to = (hash['to'] || EMPTY).map { |e| From[e] }
    @thumbnails = wrap_thumbnails(hash['thumbnails'] || EMPTY)
    @files = (hash['files'] || EMPTY).map { |e| Attachment[e] }
    @comments = wrap_comments(hash['comments'] || EMPTY)
    @likes = wrap_likes(hash['likes'] || EMPTY)
    @via = Via[hash['via']]
    @geo = Geo[hash['geo']] || extract_geo_from_google_staticmap_url(@thumbnails)
    if hash['fof']
      @fof = From[hash['fof']['from']]
      @fof_type = hash['fof']['type']
    else
      @fof = nil
    end
    @checked_at = TIME_ZERO
    @hidden = hash['hidden'] || false
    if self.via and self.via.twitter?
      @twitter_username = (self.via.url || '').match(%r{twitter.com/([^/]+)})[1]
      if /@([a-zA-Z0-9_]+)/ =~ self.body
        @twitter_reply_to = $1
      end
    end
    @modified = nil
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

  def emphasize?
    view_unread and checked_at < date_at
  end

  def pick?
    (self.from.me?) or
      likes.any? { |e| e.from.me? } or
      comments.any? { |e| e.from.me? }
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

  def twitter_in_reply_to_url
    if twitter_reply_to_status_id
      Entry.twitter_url(twitter_reply_to, twitter_reply_to_status_id)
    end
  end

  def twitter_retweet_of_url
    if twitter_retweet_of
      Entry.twitter_url(twitter_retweet_of, twitter_retweet_of_status_id)
    end
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

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
        if hash['service_source'] == 'twitter' and hash['service_user']
          from_tweet(hash)
        else
          new(hash)
        end
      end
    end

    def from_tweet(hash)
      e = new(hash)
      user = hash[:user] || hash[:sender]
      e.id = from_twitter_id(hash[:id].to_s)
      e.date = hash[:created_at]
      e.body = hash[:text]
      e.from = From.new
      e.from.id = user[:id].to_s
      e.from.name = user[:screen_name]
      e.from.type = 'user'
      e.from.private = user[:protected]
      e.from.profile_url = "http://twitter.com/#{e.from.name}"
      e.via = Via.new
      /<a href="([^"]+)" [^>]*>([^<]+)<\/a>/ =~ hash[:source]
      e.via.name = $2 || 'Twitter'
      e.via.url = $1 || 'http://twitter.com/'
      if e.geo
        e.geo.lat, e.geo.long = hash[:geo][:coordinates]
      end
      e.profile_image_url = user[:profile_image_url]
      e.twitter_username = e.from.id
      e.twitter_reply_to_status_id = hash[:in_reply_to_status_id]
      e.twitter_reply_to = hash[:in_reply_to_screen_name]
      e.url = "http://twitter.com/#{e.from.name}/status/#{hash[:id].to_s}"
      e
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
          Entry[entry]
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
      auth = opt[:auth]
      id = opt[:eid]
      undelete = !!opt[:undelete]
      if undelete
        ff_client.undelete_entry(id, auth.new_cred)
      else
        ff_client.delete_entry(id, auth.new_cred)
      end
    end

    def add_comment(opt)
      auth = opt[:auth]
      id = opt[:eid]
      body = opt[:body]
      if comment = ff_client.post_comment(id, body, auth.new_cred)
        Comment[comment]
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
      ff_client.like(id, auth.new_cred)
    end

    def delete_like(opt)
      auth = opt[:auth]
      id = opt[:eid]
      ff_client.delete_like(id, auth.new_cred)
    end

    def hide(opt)
      auth = opt[:auth]
      id = opt[:eid]
      ff_client.hide_entry(id, auth.new_cred)
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

    def if_twitter_id(id, &block)
      if m = id.match(/\At_/)
        post = m.post_match
        if block_given?
          yield post
        else
          post
        end
      end
    end

    def from_twitter_id(id)
      't_' + id
    end

  private

    def logger
      ActiveRecord::Base.logger
    end

    def ff_client
      ApplicationController.ff_client
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

  attr_accessor :profile_image_url
  attr_accessor :twitter_username
  attr_accessor :twitter_reply_to
  attr_accessor :twitter_reply_to_status_id
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
    Entry.if_twitter_id(self.id) { |tid|
      tid
    }
  end

  def tweet?
    service_source == 'twitter'
  end

  def twitter_in_reply_to_url
    if twitter_reply_to_status_id
      "http://twitter.com/#{from.name}/status/#{twitter_reply_to_status_id}"
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

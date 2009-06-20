require 'hash_utils'


class Entry
  include HashUtils
  EMPTY = [].freeze

  class << self
    def create(opt)
      auth = opt[:auth]
      body = opt[:body]
      link = opt[:link]
      comment = opt[:comment]
      images = opt[:images]
      files = opt[:files]
      room = opt[:room]
      entry = ff_client.post(auth.name, auth.remote_key, body, link, comment, images, files, room)
      if entry
        entry.first['id']
      end
    end

    def delete(opt)
      auth = opt[:auth]
      id = opt[:id]
      undelete = !!opt[:undelete]
      ff_client.delete(auth.name, auth.remote_key, id, undelete)
    end

    def add_comment(opt)
      auth = opt[:auth]
      id = opt[:id]
      body = opt[:body]
      comment = ff_client.post_comment(auth.name, auth.remote_key, id, body)
      if comment
        comment['id']
      end
    end

    def edit_comment(opt)
      auth = opt[:auth]
      id = opt[:id]
      comment = opt[:comment]
      body = opt[:body]
      comment = ff_client.edit_comment(auth.name, auth.remote_key, id, comment, body)
      if comment
        comment['id']
      end
    end

    def delete_comment(opt)
      auth = opt[:auth]
      id = opt[:id]
      comment = opt[:comment]
      undelete = !!opt[:undelete]
      ff_client.delete_comment(auth.name, auth.remote_key, id, comment, undelete)
    end

    def add_like(opt)
      auth = opt[:auth]
      id = opt[:id]
      ff_client.like(auth.name, auth.remote_key, id)
    end

    def delete_like(opt)
      auth = opt[:auth]
      id = opt[:id]
      ff_client.unlike(auth.name, auth.remote_key, id)
    end

    def hide(opt)
      auth = opt[:auth]
      id = opt[:id]
      ff_client.hide(auth.name, auth.remote_key, id)
    end

    def add_pin(opt)
      auth = opt[:auth]
      id = opt[:id]
      ActiveRecord::Base.transaction do
        unless Pin.find_by_user_id_and_eid(auth.id, id)
          pin = Pin.new
          pin.user = auth
          pin.eid = id
          pin.save!
        end
      end
    end

    def delete_pin(opt)
      auth = opt[:auth]
      id = opt[:id]
      if pin = Pin.find_by_user_id_and_eid(auth.id, id)
        raise unless pin.destroy
      end
    end

  private

    def ff_client
      ApplicationController.ff_client
    end
  end

  attr_accessor :id
  attr_accessor :title
  attr_accessor :link
  attr_accessor :updated
  attr_accessor :published
  attr_accessor :anonymous
  attr_accessor :service
  attr_accessor :user
  attr_accessor :medias
  attr_accessor :comments
  attr_accessor :likes
  attr_accessor :via
  attr_accessor :room
  attr_accessor :geo
  attr_accessor :friend_of
  attr_accessor :checked_at

  attr_accessor :twitter_username
  attr_accessor :twitter_reply_to
  attr_accessor :orphan
  attr_accessor :view_pinned
  attr_accessor :view_unread
  attr_accessor :view_nextid
  attr_accessor :view_links
  attr_accessor :view_medias
  attr_accessor :view_map

  def initialize(hash)
    initialize_with_hash(hash, 'id', 'title', 'link', 'updated', 'published', 'anonymous')
    @twitter_username = nil
    @twitter_reply_to = nil
    @orphan = hash['__f2p_orphan']
    @view_pinned = nil
    @view_unread = nil
    @view_nextid = nil
    @view_links = nil
    @view_medias = []
    @view_map = false
    @service = Service[hash['service']]
    @user = EntryUser[hash['user']]
    @medias = (hash['media'] || EMPTY).map { |e| Media[e] }
    @comments = wrap_comment(hash['comments'] || EMPTY)
    @likes = (hash['likes'] || EMPTY).map { |e| Like[e] }
    @via = Via[hash['via']]
    @room = Room[hash['room']]
    @geo = Geo[hash['geo']] || extract_geo_from_google_staticmap_url(@medias)
    @friend_of = EntryUser[hash['friendof']]
    @checked_at = nil
    @hidden = hash['hidden'] || false
    if self.service and self.service.twitter?
      @twitter_username = (self.service.profile_url || '').sub(/\A.*\//, '')
      if /@([a-zA-Z0-9_]+)/ =~ self.title
        @twitter_reply_to = $1
      end
    end
    @modified = nil
  end

  def similar?(rhs)
    result = false
    if self.user_id == rhs.user_id
      result ||= same_origin?(rhs)
    end
    result ||= same_link?(rhs) || similar_title?(rhs)
    if self.service and rhs.service and self.service.twitter? and rhs.service.twitter?
      result ||= self.twitter_reply_to == rhs.twitter_username || self.twitter_username == rhs.twitter_reply_to
    end
    result
  end

  def same_feed?(rhs)
    rhs and user_id == rhs.user_id and service_identity == rhs.service_identity
  end

  def service_identity
    return nil unless service
    sid = service.service_group? ? service.profile_url : service.id
    rid = room ? room.nickname : nil
    [sid, rid]
  end

  def published_at
    @published_at ||= (published ? Time.parse(published) : Time.now)
  end

  def modified_at
    @modified_at ||= Time.parse(modified)
  end

  def modified
    return @modified if @modified
    @modified = self.updated || self.published
    unless comments.empty?
      @modified = [@modified, comments.last.date].max
    end
    @modified || Time.now.xmlschema
  end

  def hidden?
    @hidden
  end

  def user_id
    user ? user.id : nil
  end

  def nickname
    user ? user.nickname : nil
  end

  def self_comment_only?
    cs = comments
    cs.size == 1 and self.user_id == cs.first.user_id
  end

  def origin_nickname
    if !orphan
      if anonymous
        if room
          room.nickname
        end
      else
        nickname
      end
    end
  end

private

  def wrap_comment(comments)
    index = 0
    comments.map { |e|
      c = Comment[e]
      index += 1
      c.index = index
      c.entry = self
      c
    }
  end

  def extract_geo_from_google_staticmap_url(medias)
    medias.each do |m|
      m.contents.each do |c|
        if /maps.google.com\/staticmap\b.*\bmarkers=([0-9\.]+),([0-9\.]+)\b/ =~ c.url
          self.view_map = true
          return Geo['lat' => $1, 'long' => $2]
        end
      end
    end
    nil
  end

  def same_origin?(rhs)
    (self.published_at - rhs.published_at).abs < 30.seconds
  end

  def similar_title?(rhs)
    t1 = self.title
    t2 = rhs.title
    t1 == t2 or part_of(t1, t2) or part_of(t2, t1)
  end

  def same_link?(rhs)
    self.link and rhs.link and self.link == rhs.link
  end

  def part_of(base, part)
    base and part and base.index(part) and part.length > base.length / 2
  end
end

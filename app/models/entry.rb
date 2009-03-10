require 'hash_utils'


class Entry < Hash
  extend HashUtils
  include HashUtils

  class << self
    def create(opt)
      auth = opt[:auth]
      body = opt[:body]
      link = opt[:link]
      comment = opt[:comment]
      images = opt[:images]
      files = opt[:files]
      room = opt[:room]
      entries = ff_client.post(auth.name, auth.remote_key, body, link, comment, images, files, room)
      if entries
        v(entries.first, 'id')
      end
    end

    def delete(opt)
      auth = opt[:auth]
      id = opt[:id]
      undelete = opt[:undelete]
      ff_client.delete(auth.name, auth.remote_key, id, undelete)
    end

    def add_comment(opt)
      auth = opt[:auth]
      id = opt[:id]
      body = opt[:body]
      comment = ff_client.post_comment(auth.name, auth.remote_key, id, body)
      v(comment, 'id')
    end

    def delete_comment(opt)
      auth = opt[:auth]
      id = opt[:id]
      comment = opt[:comment]
      undelete = opt[:undelete]
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

    def add_pin(opt)
      auth = opt[:auth]
      id = opt[:id]
      unless Pin.find_by_user_id_and_eid(auth.id, id)
        pin = Pin.new
        pin.user = auth
        pin.eid = id
        raise unless pin.save
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

  def pinned?
    !!v(EntryThread::MODEL_PIN_TAG)
  end

  def similar?(rhs)
    result = false
    if self.user_id == rhs.user_id
      result ||= same_origin?(rhs)
    end
    result ||= same_link?(rhs) || similar_title?(rhs)
  end

  def service_identity
    [service_id, room]
  end

  def modified
    updated = v('updated')
    unless comments.empty?
      updated = [updated, comments.last['date']].max
    end
    unless likes.empty?
      updated = [updated, likes.last['date']].max
    end
    updated
  end

  def id
    v('id')
  end

  def title
    v('title')
  end

  def link
    v('link')
  end

  def medias
    v('media') || []
  end

  def published_at
    @published_at ||= Time.parse(v('published'))
  end

  def service_id
    v('service', 'id')
  end

  def user_id
    v('user', 'id')
  end

  # can be nil for imaginary friend
  def nickname
    v('user', 'nickname')
  end

  def room
    v('room')
  end

  def comments
    v('comments') || []
  end

  def likes
    v('likes') || []
  end

  def hidden?
    v('hidden') || false
  end

  def self_comment_only?
    cs = comments
    cs.size == 1 and self.user_id == cs.first.user_id
  end

private

  def same_origin?(rhs)
    (self.published_at - rhs.published_at).abs < 10.seconds
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
    base.index(part) and part.length > base.length / 2
  end
end

class Entry < Hash

  class << self
    def create(opt)
      name = opt[:name]
      remote_key = opt[:remote_key]
      body = opt[:body]
      link = opt[:link]
      comment = opt[:comment]
      images = opt[:images]
      files = opt[:files]
      room = opt[:room]
      ff_client.post(name, remote_key, body, link, comment, images, files, room)
    end

    def delete(opt)
      name = opt[:name]
      remote_key = opt[:remote_key]
      id = opt[:id]
      undelete = opt[:undelete]
      ff_client.delete(name, remote_key, id, undelete)
    end

    def add_comment(opt)
      name = opt[:name]
      remote_key = opt[:remote_key]
      id = opt[:id]
      body = opt[:body]
      ff_client.post_comment(name, remote_key, id, body)
    end

    def delete_comment(opt)
      name = opt[:name]
      remote_key = opt[:remote_key]
      id = opt[:id]
      comment = opt[:comment]
      undelete = opt[:undelete]
      ff_client.delete_comment(name, remote_key, id, comment, undelete)
    end

    def add_like(opt)
      name = opt[:name]
      remote_key = opt[:remote_key]
      id = opt[:id]
      ff_client.like(name, remote_key, id)
    end

    def delete_like(opt)
      name = opt[:name]
      remote_key = opt[:remote_key]
      id = opt[:id]
      ff_client.unlike(name, remote_key, id)
    end

  private

    def ff_client
      ApplicationController.ff_client
    end

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

  def thread_date
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

private

  def v(*keywords)
    keywords.inject(self) { |r, k|
      r[k] if r
    }
  end

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

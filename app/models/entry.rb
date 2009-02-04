class Entry < Hash
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

class Entry < Hash
  class << self
    def find(arg = {})
      opt = arg.dup
      name = extract(opt, :name)
      remote_key = extract(opt, :remote_key)
      user = extract(opt, :user)
      room = extract(opt, :room)
      likes = extract(opt, :likes)
      id = extract(opt, :id)
      if id
        entries = ff_client.get_entry(name, remote_key, id)
      elsif user
        entries = ff_client.get_user_entries(name, remote_key, user, opt)
      elsif room
        room = nil if room == '*'
        entries = ff_client.get_room_entries(name, remote_key, room, opt)
      elsif likes
        entries = ff_client.get_likes(name, remote_key, opt)
      else
        entries = ff_client.get_home_entries(name, remote_key, opt)
      end
      sort_by_service(wrap(entries || []))
    end

  private

    def extract(hash, key)
      value = hash[key]
      hash.delete(key)
      value
    end

    def ff_client
      ApplicationController.ff_client
    end

    def wrap(entries)
      entries.map { |entry|
        Entry[entry]
      }
    end

    def sort_by_service(entries)
      result = []
      buf = entries.dup
      while !buf.empty?
        result << (entry = buf.shift)
        group = []
        kinds = similar_entries(buf, entry)
        group += kinds
        buf -= kinds
        kinds = []
        buf.each do |e|
          if entry.identity == e.identity and !kinds.include?(e)
            kinds << e
            similar_entries(buf, e).each do |e2|
              kinds << e2 unless kinds.include?(e2)
            end
          end
        end
        group += kinds
        buf -= kinds
        group.each do |e|
          e.grouped = true
        end
        result += group
      end
      result
    end

    def similar_entries(collection, entry)
      collection.find_all { |e| entry.similar?(e) }
    end
  end

  def similar?(rhs)
    if self.identity == rhs.identity
      similar_title?(rhs)
    elsif self.user_id == rhs.user_id
      same_origin?(rhs)
    else
      same_link?(rhs) or similar_title?(rhs)
    end
  end

  def identity
    @identity ||= [v('user', 'nickname'), v('service', 'id'), v('room')]
  end

  def title
    v('title')
  end

  def link
    v('link')
  end

  def user_id
    v('user', 'id')
  end

  def medias
    v('media') || []
  end

  def published_at
    @published_at ||= Time.parse(v('published'))
  end

  def grouped
    @grouped
  end

  def grouped=(grouped)
    @grouped = true
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

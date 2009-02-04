class Entry < Hash
  SERVICE_GROUPING_THRESHOLD = 1.5.hour

  class << self
    def find(arg = {})
      opt = arg.dup
      name = extract(opt, :name)
      remote_key = extract(opt, :remote_key)
      if opt[:query]
        entries = search_entries(name, remote_key, opt)
      elsif opt[:id]
        entries = get_entry(name, remote_key, opt)
      elsif opt[:user]
        entries = get_user_entries(name, remote_key, opt)
      elsif opt[:room]
        entries = get_room_entries(name, remote_key, opt)
      elsif opt[:likes]
        entries = get_likes(name, remote_key, opt)
      else
        entries = get_home_entries(name, remote_key, opt)
      end
      sort_by_service(wrap(entries || []), opt)
    end

  private

    def search_entries(name, remote_key, opt)
      query = extract(opt, :query)
      ff_client.search_entries(name, remote_key, query, opt)
    end

    def get_home_entries(name, remote_key, opt)
      opt.delete(:user)
      opt.delete(:room)
      opt.delete(:likes)
      ff_client.get_home_entries(name, remote_key, opt)
    end

    def get_user_entries(name, remote_key, opt)
      user = extract(opt, :user)
      opt.delete(:room)
      opt.delete(:likes)
      ff_client.get_user_entries(name, remote_key, user, opt)
    end

    def get_room_entries(name, remote_key, opt)
      opt.delete(:user)
      room = extract(opt, :room)
      opt.delete(:likes)
      room = nil if room == '*'
      ff_client.get_room_entries(name, remote_key, room, opt)
    end

    def get_likes(name, remote_key, opt)
      opt.delete(:user)
      opt.delete(:room)
      opt.delete(:likes)
      ff_client.get_likes(name, remote_key, opt)
    end

    def get_entry(name, remote_key, opt)
      id = extract(opt, :id)
      ff_client.get_entry(name, remote_key, id)
    end

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

    def sort_by_service(entries, opt = {})
      result = []
      buf = entries.dup
      while !buf.empty?
        group = [entry = buf.shift]
        kinds = similar_entries(buf, entry)
        group += kinds
        buf -= kinds
        kinds = []
        pre = entry
        entry_tag = tag(entry, opt)
        buf.each do |e|
          if entry_tag == tag(e, opt) and ((e.published_at - pre.published_at).abs < SERVICE_GROUPING_THRESHOLD) and !kinds.include?(e)
            kinds << (pre = e)
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
        group.first.grouped = false
        result += group
      end
      result
    end

    def tag(entry, opt)
      t = [entry.user_id]
      t << entry.service_id unless opt[:merge_service]
      t
    end

    def similar_entries(collection, entry)
      collection.find_all { |e| entry.similar?(e) }
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

  def grouped
    @grouped
  end

  def grouped=(grouped)
    @grouped = grouped
  end

  def service_id
    v('service', 'id')
  end

  def user_id
    v('user', 'id')
  end

  def room
    v('room')
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

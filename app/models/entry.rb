class Entry < Hash
  class << self
    def find(arg = {})
      name = arg[:name]
      remote_key = arg[:remote_key]
      user = arg[:user]
      room = arg[:room]
      likes = arg[:likes]
      id = arg[:id]
      opt = arg.dup
      opt.delete(:name)
      opt.delete(:remote_key)
      opt.delete(:user)
      opt.delete(:room)
      opt.delete(:likes)
      opt.delete(:id)
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
        kinds = []
        buf.each do |e|
          kinds << e if entry.similar?(e)
        end
        group += kinds
        buf -= kinds
        kinds.clear
        buf.each do |e|
          if entry.identity == e.identity
            kinds << e
            buf.each do |e2|
              kinds << e2 if e.similar?(e2) and !kinds.include?(e2)
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
  end

  def similar?(rhs)
    self.user_id == rhs.user_id and
      ((self.published_at - rhs.published_at).abs < 2.seconds or
        (similar_title?(rhs) and self.medias.empty? and rhs.medias.empty?))
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
    Time.parse(v('published'))
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

  def similar_title?(rhs)
    t1 = self.title
    t2 = rhs.title
    t1 == t2 or part_of(t1, t2) or part_of(t2, t1)
  end

  def part_of(base, part)
    base.index(part) and part.length > base.length / 2
  end
end

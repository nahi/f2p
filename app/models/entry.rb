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
      sort_by_service(wrap(entries))
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
        kinds = buf.find_all { |e| entry.identity == e.identity }
        result += kinds
        buf -= kinds
      end
      result
    end
  end

  def identity
    @identity ||= [v('user', 'nickname'), v('service', 'id'), v('room')]
  end

private

  def v(*keywords)
    keywords.inject(self) { |r, k|
      r[k] if r
    }
  end
end

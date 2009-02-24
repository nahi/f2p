class EntryThread
  class << self
    def find(opt = {})
      auth = opt[:auth]
      return nil unless auth
      if opt[:query]
        entries = search_entries(auth, opt)
      elsif opt[:id]
        entries = get_entry(auth, opt)
      elsif opt[:like] == 'likes'
        entries = get_likes(auth, opt)
      elsif opt[:like] == 'liked'
        entries = get_liked(auth, opt)
      elsif opt[:user]
        entries = get_user_entries(auth, opt)
      elsif opt[:list]
        entries = get_list_entries(auth, opt)
      elsif opt[:room]
        entries = get_room_entries(auth, opt)
      elsif opt[:friends]
        entries = get_friends_entries(auth, opt)
      elsif opt[:link]
        entries = get_link_entries(auth, opt)
      else
        entries = get_home_entries(auth, opt)
      end
      wrapped = wrap(entries || [])
      if opt[:updated]
        wrapped = filter_checked_entries(auth, wrapped)
      end
      sort_by_service(wrapped, opt)
    end

  private

    def record_last_modified(entries)
      found = LastModified.find_all_by_eid(entries.map { |e| e.id })
      entries.each do |entry|
        if m = found.find { |e| entry.id == e.eid }
          m.date = Time.parse(entry.modified)
          raise unless m.save
        else
          m = LastModified.new
          m.eid = entry.id
          m.date = Time.parse(entry.modified)
          raise unless m.save
        end
      end
    end

    def filter_checked_entries(auth, entries)
      record_last_modified(entries)
      checked = CheckedModified.find_all_by_user_id(auth.id, :include => 'last_modified')
      entries.find_all { |entry|
        if c = checked.find { |e| e.last_modified && e.last_modified.eid == entry.id }
          if c.checked >= c.last_modified.date
            false
          else
            c.checked = c.last_modified.date
            raise unless c.save
            true
          end
        else
          c = CheckedModified.new
          c.user = auth
          c.last_modified = LastModified.find_by_eid(entry.id)
          raise if c.last_modified.nil?
          c.checked = c.last_modified.date
          raise unless c.save
          true
        end
      }
    end

    def search_entries(auth, opt)
      query = opt[:query]
      search = filter_opt(opt)
      search[:from] = opt[:user]
      search[:room] = opt[:room]
      search[:friends] = opt[:friends]
      ff_client.search_entries(auth.name, auth.remote_key, query, search)
    end

    def get_home_entries(auth, opt)
      ff_client.get_home_entries(auth.name, auth.remote_key, filter_opt(opt))
    end

    def get_user_entries(auth, opt)
      user = opt[:user]
      ff_client.get_user_entries(auth.name, auth.remote_key, user, filter_opt(opt))
    end

    def get_list_entries(auth, opt)
      list = opt[:list]
      ff_client.get_list_entries(auth.name, auth.remote_key, list, filter_opt(opt))
    end

    def get_room_entries(auth, opt)
      room = opt[:room]
      room = nil if room == '*'
      ff_client.get_room_entries(auth.name, auth.remote_key, room, filter_opt(opt))
    end

    def get_friends_entries(auth, opt)
      friends = opt[:friends]
      ff_client.get_friends_entries(auth.name, auth.remote_key, friends, filter_opt(opt))
    end

    def get_link_entries(auth, opt)
      link = opt[:link]
      ff_client.get_url_entries(auth.name, auth.remote_key, link, filter_opt(opt))
    end

    def get_likes(auth, opt)
      user = opt[:user]
      ff_client.get_likes(auth.name, auth.remote_key, user, filter_opt(opt))
    end

    def get_liked(auth, opt)
      user = opt[:user]
      search = filter_opt(opt)
      search.delete(:user)
      search[:from] = user
      search[:likes] = 1
      ff_client.search_entries(auth.name, auth.remote_key, '', search)
    end

    def get_entry(auth, opt)
      id = opt[:id]
      ff_client.get_entry(auth.name, auth.remote_key, id)
    end

    def filter_opt(opt)
      {
        :service => opt[:service],
        :start => opt[:start],
        :num => opt[:num]
      }
    end

    def ff_client
      ApplicationController.ff_client
    end

    def wrap(entries)
      entries.map { |hash|
        entry = Entry[hash]
        entry['comments'] = entry['comments'].map { |hash|
          comment = Comment[hash]
          comment.entry = entry
          comment
        }
        entry['room'] = Room[entry['room']] if entry['room']
        entry
      }
    end

    def sort_by_service(entries, opt = {})
      result = []
      buf = entries.find_all { |e| !e.hidden? }.sort_by { |e| e.modified }.reverse
      while !buf.empty?
        entry = buf.shift
        result << (t = EntryThread.new(entry))
        group = [entry]
        kinds = similar_entries(buf, entry)
        group += kinds
        buf -= kinds
        kinds = []
        pre = entry
        entry_tag = tag(entry, opt)
        buf.each do |e|
          if entry_tag == tag(e, opt) and ((e.published_at - pre.published_at).abs < F2P::Config.service_grouping_threashold) and !kinds.include?(e)
            kinds << (pre = e)
            similar_entries(buf, e).each do |e2|
              kinds << e2 unless kinds.include?(e2)
            end
          end
        end
        group += kinds
        buf -= kinds
        t.add(group.shift)
        t.add(*group.reverse)
      end
      result
    end

    def tag(entry, opt)
      t = [entry.user_id, entry.room]
      t << entry.service_id unless opt[:merge_service]
      t
    end

    def similar_entries(collection, entry)
      collection.find_all { |e| entry.similar?(e) }
    end
  end

  # root is included in entries, too.
  attr_reader :root
  attr_reader :entries

  def initialize(root)
    @root = root
    @entries = []
  end

  def related_entries
    entries - [root]
  end

  def add(*entries)
    @entries += entries
  end

  def chunked?
    @entries.size > 1
  end
end

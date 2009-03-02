class EntryThread
  MODEL_LAST_MODIFIED_TAG = '__model_last_modified'
  MODEL_PIN_TAG = '__model_pin'

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
      if opt[:updated] or opt[:id]
        wrapped = filter_pinned_entries(auth, wrapped, opt)
      end
      if opt[:updated]
        wrapped = filter_checked_entries(auth, wrapped)
      end
      sort_by_service(wrapped, opt)
    end

    def update_checked_modified(auth, hash)
      pinned = pinned_map(auth, hash.keys)
      cond = [
        'user_id = ? and last_modifieds.eid in (?)',
        auth.id,
        hash.keys
      ]
      checked = CheckedModified.find(:all, :conditions => cond, :include => 'last_modified')
      hash.each do |eid, checked_modified|
        next unless checked_modified
        next if pinned.key?(eid)
        if c = checked.find { |e| e.last_modified.eid == eid }
          c.checked = Time.parse(checked_modified)
          raise unless c.save
        else
          m = LastModified.find_by_eid(eid)
          if m
            c = CheckedModified.new
            c.user = auth
            c.last_modified = m
            c.checked = Time.parse(checked_modified)
            raise unless c.save
          end
        end
      end
    end

  private

    def record_last_modified(entries)
      found = LastModified.find_all_by_eid(entries.map { |e| e.id })
      entries.collect { |entry|
        if m = found.find { |e| entry.id == e.eid }
          m.date = Time.parse(entry.modified)
          raise unless m.save
          m
        else
          m = LastModified.new
          m.eid = entry.id
          m.date = Time.parse(entry.modified)
          raise unless m.save
          m
        end
      }
    end

    def filter_checked_entries(auth, entries)
      record_last_modified(entries)
      cond = [
        'user_id = ? and last_modifieds.eid in (?)',
        auth.id,
        entries.map { |e| e.id }
      ]
      checked = CheckedModified.find(:all, :conditions => cond, :include => 'last_modified')
      entries.find_all { |entry|
        if c = checked.find { |e| e.last_modified.eid == entry.id }
          entry[MODEL_LAST_MODIFIED_TAG] = entry.modified
          c.checked < c.last_modified.date
        else
          entry[MODEL_LAST_MODIFIED_TAG] = entry.modified
          true
        end
      }
    end

    def filter_pinned_entries(auth, entries, opt)
      target_ids = entries.map { |e| e.id }
      map = pinned_map(auth, target_ids)
      entries.each do |entry|
        entry[MODEL_PIN_TAG] = true if map.key?(entry.id)
      end
      if opt[:start] and opt[:start] != 0
        entries.find_all { |entry|
          !entry[MODEL_PIN_TAG]
        }
      else
        pinned = Pin.find_all_by_user_id(auth.id).map { |e| e.eid }
        rest_ids = pinned - target_ids
        unless rest_ids.empty?
          pinned_entries = wrap(get_entries(auth, :ids => rest_ids) || [])
          pinned_entries.each do |entry|
            entry[MODEL_PIN_TAG] = true
          end
          entries += pinned_entries
        end
        entries
      end
    end

    def pinned_map(auth, eids)
      cond = [
        'user_id = ? and eid in (?)',
        auth.id,
        eids
      ]
      Pin.find(:all, :conditions => cond).inject({}) { |r, e| r[e.eid] = true; r }
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

    def get_entries(auth, opt)
      ids = opt[:ids]
      ff_client.get_entries(auth.name, auth.remote_key, ids)
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

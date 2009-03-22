require 'timeout'


class EntryThread
  class Task
    class << self
      def run(&block)
        new(&block)
      end
      private :new
    end

    def initialize(&block)
      @result = nil
      @thread = Thread.new {
        @result = yield
      }
    end

    def result(timeout = F2P::Config.friendfeed_api_timeout)
      begin
        timeout(timeout) do
          @thread.join
          @result
        end
      rescue Timeout::Error
        @result = nil
      end
    end
  end

  class << self
    def find(opt = {})
      auth = opt[:auth]
      return nil unless auth
      entries = pinned_entries = nil
      if opt[:inbox]
        list_task = Task.run {
          get_home_entries(auth, opt)
        }
        if opt[:start].nil? or opt[:start] == 0
          pinned = Pin.find_all_by_user_id(auth.id).map { |e| e.eid }
          unless pinned.empty?
            pin_task =  Task.run {
              get_entries(auth, :ids => pinned)
            }
            pinned_entries = wrap(pin_task.result || [])
          end
        end
        entries = list_task.result
      elsif opt[:query]
        entries = Task.run { search_entries(auth, opt) }.result
      elsif opt[:id]
        entries = Task.run { get_entry(auth, opt) }.result
      elsif opt[:like] == 'likes'
        entries = Task.run { get_likes(auth, opt) }.result
      elsif opt[:like] == 'liked'
        entries = Task.run { get_liked(auth, opt) }.result
      elsif opt[:comment] == 'comments'
        entries = Task.run { get_comments(auth, opt) }.result
      elsif opt[:comment] == 'commented'
        entries = Task.run { get_commented(auth, opt) }.result
      elsif opt[:user]
        entries = Task.run { get_user_entries(auth, opt) }.result
      elsif opt[:list]
        entries = Task.run { get_list_entries(auth, opt) }.result
      elsif opt[:room]
        entries = Task.run { get_room_entries(auth, opt) }.result
      elsif opt[:friends]
        entries = Task.run { get_friends_entries(auth, opt) }.result
      elsif opt[:link]
        entries = Task.run { get_link_entries(auth, opt) }.result
      else
        entries = Task.run { get_home_entries(auth, opt) }.result
      end
      wrapped = sort_by_modified(wrap(entries || []))
      if opt[:link]
        wrapped = filter_link_entries(auth, wrapped)
      end
      record_last_modified(wrapped)
      check_inbox(auth, wrapped)
      check_pinned(auth, wrapped, opt)
      if opt[:inbox]
        wrapped = filter_pinned_entries(auth, wrapped, pinned_entries, opt)
        wrapped = filter_checked_entries(auth, wrapped)
      end
      sort_by_service(wrapped, opt)
    end

    def update_checked_modified(auth, hash)
      cond = [
        'user_id = ? and last_modifieds.eid in (?)',
        auth.id,
        hash.keys
      ]
      checked = CheckedModified.find(:all, :conditions => cond, :include => 'last_modified')
      hash.each do |eid, checked_modified|
        next unless checked_modified
        if c = checked.find { |e| e.last_modified.eid == eid }
          d = Time.parse(checked_modified)
          if c.checked < d
            c.checked = d
            raise unless c.save
          end
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

    def filter_link_entries(auth, entries)
      entries.partition { |e| e.nickname == auth.name }.flatten
    end

    def record_last_modified(entries)
      found = LastModified.find_all_by_eid(entries.map { |e| e.id })
      entries.each do |entry|
        if m = found.find { |e| entry.id == e.eid }
          d = entry.modified_at
          if m.date != d
            m.date = d
            raise unless m.save
          end
        else
          m = LastModified.new
          m.eid = entry.id
          m.date = entry.modified_at
          raise unless m.save
        end
      end
    end

    def check_inbox(auth, entries)
      cond = [
        'user_id = ? and last_modifieds.eid in (?)',
        auth.id,
        entries.map { |e| e.id }
      ]
      checked = CheckedModified.find(:all, :conditions => cond, :include => 'last_modified')
      oldest = CheckedModified.find(:all, :order => 'checked asc', :limit => 1).first
      entries.each do |entry|
        if c = checked.find { |e| e.last_modified.eid == entry.id }
          entry.view_inbox = c.checked < c.last_modified.date
        else
          entry.view_inbox = oldest ? oldest.checked < entry.modified_at : true
        end
      end
    end

    def check_pinned(auth, entries, opt)
      map = pinned_map(auth, entries.map { |e| e.id })
      entries.each do |entry|
        if map.key?(entry.id)
          entry.view_pinned = true
          entry.view_inbox = true
        end
      end
    end

    def filter_pinned_entries(auth, entries, pinned_entries, opt)
      if opt[:start] and opt[:start] != 0
        entries.find_all { |entry|
          !entry.view_pinned
        }
      elsif pinned_entries
        all = entries.map { |e| e.id }
        rest = pinned_entries.find_all { |e| !all.include?(e.id) }
        rest.each do |entry|
          entry.view_pinned = true
          entry.view_inbox = true
        end
        entries + rest
      else
        entries
      end
    end

    def filter_checked_entries(auth, entries)
      entries.find_all { |entry|
        entry.view_inbox
      }
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

    def get_comments(auth, opt)
      user = opt[:user]
      ff_client.get_comments(auth.name, auth.remote_key, user, filter_opt(opt))
    end

    def get_commented(auth, opt)
      user = opt[:user]
      ff_client.get_discussion(auth.name, auth.remote_key, user, filter_opt(opt))
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

    def sort_by_modified(entries)
      sorted = entries.find_all { |e| !e.hidden? }.sort_by { |e|
        [e.modified, e.id].join('-') # join e.id for stable sort
      }
      sorted.reverse
    end

    def sort_by_service(entries, opt = {})
      result = []
      buf = entries.dup
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
        t.add(*group)
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

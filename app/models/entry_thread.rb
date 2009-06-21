require 'task'


class EntryThread
  class EntryThreads < Array
    attr_accessor :from_modified
    attr_accessor :to_modified
    attr_accessor :pins
  end

  class << self
    EMPTY = [].freeze

    def find(opt = {})
      auth = opt[:auth]
      return nil unless auth
      unless opt.key?(:merge_entry)
        opt[:merge_entry] = true
      end
      opt.delete(:auth)
      logger.info('[perf] start entries fetch')
      original = entries = fetch_entries(auth, opt)
      logger.info('[perf] start internal data handling')
      record_last_modified(entries)
      logger.info('[perf] record_last_modified done')
      pins = check_inbox(auth, entries)
      logger.info('[perf] check_inbox done')
      if opt[:inbox]
        entries = entries.find_all { |entry|
          entry.view_unread or entry.view_pinned or entry.id == opt[:filter_inbox_except]
        }
      elsif opt[:label] == 'pin'
        entries = entries.find_all { |entry|
          entry.view_pinned or entry.id == opt[:updated_id] or entry.id == opt[:filter_inbox_except]
        }
      end
      if opt[:merge_entry]
        entries = sort_by_service(entries, opt)
      else
        entries = entries.map { |e|
          EntryThread.new(e)
        }
      end
      threads = EntryThreads[*entries]
      flatten = threads.map { |t| t.entries }.flatten
      if !flatten.any? { |e| e.view_nextid }
        prev = nil
        flatten.reverse_each do |e|
          e.view_nextid = prev
          prev = e.id
        end
      end
      unless original.empty?
        threads.from_modified = original.last.modified
        threads.to_modified = original.first.modified
      end
      threads.pins = pins
      threads
    end

    def update_checked_modified(auth, hash)
      cond = [
        'user_id = ? and last_modifieds.eid in (?)',
        auth.id,
        hash.keys
      ]
      checked = CheckedModified.find(:all, :conditions => cond, :include => 'last_modified')
      # do update/create without transaction.  we can use transaction and retry
      # invoking this method (whole transaction) but it's too expensive.
      hash.each do |eid, checked_modified|
        next unless checked_modified
        if c = checked.find { |e| e.last_modified.eid == eid }
          d = Time.parse(checked_modified)
          if c.checked < d
            c.checked = d
            begin
              c.save!
            rescue ActiveRecord::ActiveRecordError => e
              logger.warn("update CheckedModified failed for #{eid}")
              logger.warn(e)
            end
          end
        else
          if m = LastModified.find_by_eid(eid)
            c = CheckedModified.new
            c.user = auth
            c.last_modified = m
            c.checked = Time.parse(checked_modified)
            begin
              c.save!
            rescue ActiveRecord::ActiveRecordError => e
              logger.warn("create CheckedModified failed for #{eid}")
              logger.warn(e)
            end
          end
        end
      end
    end

  private

    def logger
      ActiveRecord::Base.logger
    end

    def fetch_entries(auth, opt)
      if opt[:id]
        fetch_single_entry_as_array(auth, opt)
      else
        entries = fetch_list_entries(auth, opt)
        entries = filter_hidden(entries)
        if opt[:inbox]
          entries = sort_by_detection(entries)
        elsif opt[:ids]
          entries = sort_by_ids(entries, opt[:ids])
        else
          entries = sort_by_modified(entries)
        end
        if opt[:link]
          # You comes first
          entries = entries.partition { |e| e.nickname == auth.name }.flatten
        end
        if updated_id = opt[:updated_id]
          entry = wrap(get_entry(auth, :id => updated_id)).first
          if entry
            update_cache_entry(auth, entry)
            if entries.find { |e| e.id == updated_id }
              replace_entry(entries, entry)
            else
              entries.unshift(entry)
            end
          end
        end
        entries
      end
    end

    def fetch_single_entry_as_array(auth, opt)
      @entries_cache ||= {}
      allow_cache = opt[:allow_cache]
      if allow_cache
        if cached = @entries_cache[auth.name]
          entries = cached[1]
          if found = entries.find { |e| e.id == opt[:id] }
            logger.info("[cache] entry cache found for #{opt[:id]}")
            return [found]
          end
        end
      end
      wrap(Task.run { get_entry(auth, opt) }.result)
    end

    def fetch_list_entries(auth, opt)
      cache_entries(auth, opt) {
        if opt[:inbox]
          start = opt[:start]
          num = opt[:num]
          wrap(Task.run { get_inbox_entries(auth, start, num) }.result)
        elsif opt[:ids]
          wrap(Task.run { get_entries(auth, opt) }.result)
        elsif opt[:link]
          if opt[:query]
            start = (opt[:start] || 0) / 2
            num = (opt[:num] || 0) / 2
            opt = opt.merge(:start => start, :num => num)
            search_task = Task.run { search_entries(auth, opt) }
          end
          link_task = Task.run { get_link_entries(auth, opt) }
          merged = wrap(link_task.result)
          if opt[:query]
            merged += wrap(search_task.result)
            merged = merged.inject({}) { |r, e| r[e.id] = e; r }.values
          end
          merged
        elsif opt[:query]
          wrap(Task.run { search_entries(auth, opt) }.result)
        elsif opt[:like] == 'likes'
          wrap(Task.run { get_likes(auth, opt) }.result)
        elsif opt[:like] == 'liked'
          wrap(Task.run { get_liked(auth, opt) }.result)
        elsif opt[:comment] == 'comments'
          wrap(Task.run { get_comments(auth, opt) }.result)
        elsif opt[:comment] == 'discussion'
          wrap(Task.run { get_discussion(auth, opt) }.result)
        elsif opt[:user]
          wrap(Task.run { get_user_entries(auth, opt) }.result)
        elsif opt[:list]
          wrap(Task.run { get_list_entries(auth, opt) }.result)
        elsif opt[:label] == 'pin'
          wrap(Task.run { pinned_entries(auth, opt) }.result)
        elsif opt[:room]
          wrap(Task.run { get_room_entries(auth, opt) }.result)
        elsif opt[:friends]
          wrap(Task.run { get_friends_entries(auth, opt) }.result)
        else
          wrap(Task.run { get_home_entries(auth, opt) }.result)
        end
      }
    end

    def cache_entries(auth, opt, &block)
      @entries_cache ||= {}
      allow_cache = opt[:allow_cache]
      opt = opt.dup
      opt.delete(:allow_cache)
      opt.delete(:updated_id)
      opt.delete(:merge_entry)
      opt.delete(:merge_service)
      opt.delete(:filter_inbox_except)
      if allow_cache and @entries_cache[auth.name]
        cached_opt, entries = @entries_cache[auth.name]
        if opt == cached_opt
          logger.info("[cache] entries cache found for #{opt.inspect}")
          return entries
        end
      end
      entries = yield
      @entries_cache[auth.name] = [opt, entries]
      entries
    end

    def update_cache_entry(auth, entry)
      opt, entries = @entries_cache[auth.name]
      if entries
        replace_entry(entries, entry)
      end
    end

    def record_last_modified(entries)
      found = LastModified.find_all_by_eid(entries.map { |e| e.id })
      found_map = found.inject({}) { |r, e|
        r[e.eid] = e
        r
      }
      # do update/create without transaction.  we can use transaction and retry
      # invoking this method (whole transaction) but it's too expensive.
      entries.each do |entry|
        if m = found_map[entry.id]
          d = entry.modified_at
          if m.date != d
            m.date = d
            begin
              m.save!
            rescue ActiveRecord::ActiveRecordError => e
              logger.warn("update LastModified failed for #{entry.id}")
              logger.warn(e)
            end
          end
        else
          m = LastModified.new
          m.eid = entry.id
          m.date = entry.modified_at
          begin
            m.save!
          rescue ActiveRecord::ActiveRecordError => e
            logger.warn("create LastModified failed for #{entry.id}")
            logger.warn(e)
          end
        end
      end
    end

    def check_inbox(auth, entries)
      eids = entries.map { |e| e.id }
      checked_map = checked_map(auth, eids)
      pinned_map = pinned_map(auth)
      entries.each do |entry|
        entry.view_pinned = pinned_map.key?(entry.id)
        if checked = checked_map[entry.id]
          entry.checked_at = checked
          entry.view_unread = checked < entry.modified_at
        else
          entry.view_unread = true
        end
      end
      pinned_map.keys.size
    end

    def checked_map(auth, eids)
      cond = [
        'user_id = ? and last_modifieds.eid in (?)',
        auth.id,
        eids
      ]
      CheckedModified.find(:all, :conditions => cond, :include => 'last_modified').inject({}) { |r, e|
        #r[e.last_modified.eid] = e.checked < e.last_modified.date
        r[e.last_modified.eid] = e.checked
        r
      }
    end

    def pinned_map(auth)
      Pin.find_all_by_user_id(auth.id).inject({}) { |r, e|
        r[e.eid] = true
        r
      }
    end

    def pinned_entries(auth, opt)
      start = opt[:start]
      num = opt[:num]
      pinned = Pin.find(
        :all,
        :conditions => [ 'user_id = ?', auth.id ],
        :joins => 'INNER JOIN last_modifieds ON pins.eid = last_modifieds.eid',
        :order => 'last_modifieds.date desc'
      )
      pinned_id = pinned.map { |e| e.eid }
      if opt[:service]
        entries = get_entries(auth, :ids => pinned_id).find_all { |e|
          e['service'] && (opt[:service] == e['service']['id'])
        }
        entries[start, num] || []
      elsif opt[:room]
        entries = get_entries(auth, :ids => pinned_id).find_all { |e|
          e['room'] && (opt[:room] == e['room']['nickname'])
        }
        entries[start, num] || []
      elsif pinned_id = pinned_id[start, num]
        entries = get_entries(auth, :ids => pinned_id)
        return nil unless entries
        map = entries.inject({}) { |r, e| r[e['id']] = e; r }
        pinned_id.map { |eid|
          if map.key?(eid)
            map[eid]
          else
            pin = pinned.find { |e| e.eid == eid }
            date = pin ? pin.created_at.xmlschema : nil
            {'id' => eid, 'updated' => date, 'published' => date, '__f2p_orphan' => true}
          end
        }
      end
    end

    def search_entries(auth, opt)
      query = opt[:query]
      search = filter_opt(opt)
      search[:from] = opt[:user]
      search[:room] = opt[:room]
      search[:friends] = opt[:friends]
      search[:likes] = opt[:likes] if opt[:likes]
      search[:comments] = opt[:comments] if opt[:comments]
      ff_client.search_entries(auth.name, auth.remote_key, query, search)
    end

    def get_inbox_entries(auth, start, num)
      ff_client.get_inbox_entries(auth.name, auth.remote_key, start, num)
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

    def get_discussion(auth, opt)
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
      return EMPTY if entries.nil?
      entries.map { |e| Entry[e] }
    end

    def filter_hidden(entries)
      entries.find_all { |e| !e.hidden? }
    end

    def sort_by_detection(entries)
      sorted = []
      entries.each do |e|
        if e.comments.empty? or e.self_comment_only?
          # keep the order
          sorted << e
        else
          # updated by commented or liked
          if loc = find_insert_point(sorted, e)
            sorted[loc, 0] = e
          else
            sorted << e
          end
        end
      end
      sorted
    end

    def find_insert_point(seq, entry)
      if idx = seq.find { |e| e.modified_at < entry.modified_at }
        seq.index(idx)
      end
    end

    def sort_by_ids(entries, ids)
      map = entries.inject({}) { |r, e| r[e.id] = e; r }
      ids.map { |id| map[id] }
    end

    def sort_by_modified(entries)
      entries.sort_by { |e|
        -e.modified_at.to_i
      }
    end

    def sort_by_service(entries, opt = {})
      result = []
      buf = entries.dup
      while !buf.empty?
        entry = buf.shift
        result << (t = EntryThread.new)
        group = [entry]
        kinds = similar_entries(buf, entry)
        group += kinds
        buf -= kinds
        if kinds.empty?
          pre = entry
          entry_tag = tag(entry, opt)
          buf.each do |e|
            if entry_tag == tag(e, opt) and ((e.published_at - pre.published_at).abs < F2P::Config.service_grouping_threashold) and !kinds.include?(e)
              kinds << (pre = e)
              # too agressive?
              #similar_entries(buf, e).each do |e2|
              #  kinds << e2 unless kinds.include?(e2)
              #end
            end
          end
          group += kinds
          buf -= kinds
        end
        sorted = sort_by_published(group)
        t.add(*sorted)
        t.root = sorted.first
      end
      result
    end

    def sort_by_published(entries)
      entries.sort_by { |e|
        -e.published_at.to_i
      }
    end

    def tag(entry, opt)
      t = [entry.user_id, entry.room ? entry.room.id : nil]
      t << entry.service.id unless opt[:merge_service]
      t
    end

    def similar_entries(collection, entry)
      collection.find_all { |e| entry.similar?(e) }
    end

    def first_page_option?(opt)
      opt[:start].nil? or opt[:start] == 0
    end

    def replace_entry(entries, entry)
      entries.each_with_index do |e, idx|
        if e.id == entry.id
          entries[idx] = entry
          entry.view_nextid = e.view_nextid
          return
        end
      end
    end
  end

  # root is included in entries, too.
  attr_accessor :root
  attr_reader :entries

  def initialize(root = nil)
    @root = root
    @entries = []
    @entries << @root if @root
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

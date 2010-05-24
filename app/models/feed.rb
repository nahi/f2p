require 'hash_utils'
require 'entry_thread'
require 'entry'


class Feed
  include HashUtils
  EMPTY = [].freeze

  class << self
    def find(opt = {})
      auth = opt[:auth]
      return nil unless auth
      unless opt.key?(:merge_entry)
        opt[:merge_entry] = true
      end
      opt[:start] ||= 0
      opt[:num] ||= 100
      opt.delete(:auth)
      logger.info('[perf] start entries fetch')
      feed = fetch_entries(auth, opt)
      if opt[:tweets] or opt[:buzz]
        pins = check_inbox(auth, feed, false)
        logger.info('[perf] check_inbox done')
      else
        logger.info('[perf] start internal data handling')
        update_last_modified(feed)
        logger.info('[perf] update_last_modified done')
        pins = check_inbox(auth, feed)
        logger.info('[perf] check_inbox done')
        add_service_icon(feed.entries)
        logger.info('[perf] add_service_icon done')
      end
      feed.entries = filter_hidden(feed.entries)
      entries = feed.entries
      if opt[:eids]
        entries = sort_by_ids(entries, opt[:eids])
      elsif opt[:link]
        # You comes first
        entries = entries.partition { |e| e.from_id == auth.name }.flatten
      end
      # build entry thread
      if opt[:merge_entry]
        threads = sort_by_service(entries.compact, opt)
      else
        threads = entries.map { |e|
          EntryThread.new(e)
        }
      end
      # update threads for inbox
      if opt[:inbox]
        threads = filter_unread_entries(threads, opt)
      elsif opt[:label] == 'pin'
        threads = filter_pinned_entries(threads, opt)
      end
      threads = EntryThread::EntryThreads[*threads]
      flatten = threads.map { |t| t.entries }.flatten.find_all { |e| !e.tweet? }
      prev = nil
      flatten.reverse_each do |e|
        e.view_nextid = prev
        prev = e.id
      end
      unless feed.entries.empty?
        threads.from_modified = feed.entries.last.modified
        threads.to_modified = feed.entries.first.modified
        threads.max_id = feed.entries.last.id
      end
      threads.pins = pins
      feed.entries = threads
      feed
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
      hash.each do |eid, last_modified|
        next unless last_modified
        modified_at = Time.parse(last_modified)
        if c = checked.find { |e| e.last_modified.eid == eid }
          if c.checked < modified_at
            c.checked = modified_at
            begin
              c.save!
            rescue ActiveRecord::ActiveRecordError => e
              logger.warn("update CheckedModified failed for #{eid}")
              logger.warn(e)
            end
          end
        else
          m = LastModified.find_by_eid(eid)
          unless m
            m = LastModified.new
            m.eid = eid
            m.date = modified_at
            begin
              m.save!
            rescue ActiveRecord::ActiveRecordError => e
              logger.warn("create LastModified failed for #{eid}")
              logger.warn(e)
            end
          end
          c = CheckedModified.new
          c.user = auth
          c.last_modified = m
          c.checked = modified_at
          begin
            c.save!
          rescue ActiveRecord::ActiveRecordError => e
            logger.warn("create CheckedModified failed for #{eid}")
            logger.warn(e)
          end
        end
      end
    end

  private

    def logger
      ActiveRecord::Base.logger
    end

    def fetch_entries(auth, opt)
      if opt[:eid]
        feed = fetch_single_entry_as_array(auth, opt)
        if !opt[:buzz] and entry = feed.entries.first
          update_cache_entry(auth, entry)
        end
        feed
      else
        feed = fetch_list_entries(auth, opt)
        if !opt[:tweets] and !opt[:buzz] and (updated_id = opt[:updated_id])
          entry = wrap(Task.run { get_feed(auth, updated_id, opt) }.result).entries.first
          if entry
            update_cache_entry(auth, entry)
            if feed.entries.find { |e| e.id == updated_id }
              replace_entry(feed, entry)
            else
              feed.entries = [entry] + feed.entries
            end
          end
        end
        feed
      end
    end

    def fetch_single_entry_as_array(auth, opt)
      if opt[:buzz]
        return from_service([opt[:buzz]], opt)
      end
      if opt[:allow_cache]
        if cache = get_cached_entries(auth)
          if found = cache.entries.find { |e| e.id == opt[:eid] && e.id != opt[:updated_id] }
            logger.info("[cache] entry cache found for #{opt[:eid]}")
            return [found]
          end
        end
      end
      wrap(Task.run { get_feed(auth, opt[:eid], opt) }.result)
    end

    def fetch_list_entries(auth, opt)
      if opt[:tweets]
        return from_service(opt[:tweets], opt)
      elsif opt[:buzz]
        return from_service(opt[:buzz], opt)
      end
      cache_entries(auth, opt) {
        if opt[:inbox]
          wrap(Task.run { get_feed(auth, 'home', opt) }.result)
        elsif opt[:eids]
          wrap(Task.run { get_entries(auth, opt) }.result)
        elsif opt[:link]
          if opt[:query]
            start = opt[:start] / 2
            num = opt[:num] / 2
            opt = opt.merge(:start => start, :num => num)
            search_task = Task.run { search_entries(auth, opt) }
          end
          link_task = Task.run { get_link_entries(auth, opt) }
          merged = wrap(link_task.result)
          if opt[:query]
            merged.entries += wrap(search_task.result).entries
            merged.entries = merged.entries.inject({}) { |r, e| r[e.id] = e; r }.values
          end
          merged
        elsif opt[:feed]
          wrap(Task.run { get_feed(auth, opt[:feed], opt) }.result)
        elsif opt[:query] or opt[:service]
          wrap(Task.run { search_entries(auth, opt) }.result)
        elsif opt[:like] == 'liked'
          wrap(Task.run { get_liked(auth, opt) }.result)
        elsif opt[:user]
          wrap(Task.run { get_feed(auth, opt[:user], opt) }.result)
        elsif opt[:list]
          wrap(Task.run { get_feed(auth, opt[:list], opt) }.result)
        elsif opt[:label] == 'pin'
          wrap(Task.run { pinned_entries(auth, opt) }.result)
        elsif opt[:room]
          wrap(Task.run { get_feed(auth, opt[:room], opt) }.result)
        else
          wrap(Task.run { get_feed(auth, 'home', opt) }.result)
        end
      }
    end

    def cache_entries(auth, opt, &block)
      allow_cache = opt[:allow_cache]
      opt = opt.dup
      opt.delete(:allow_cache)
      opt.delete(:updated_id)
      opt.delete(:merge_entry)
      opt.delete(:merge_service)
      opt.delete(:filter_except)
      opt.delete(:tweets)
      opt.delete(:buzz)
      if allow_cache
        if cache = get_cached_entries(auth)
          if opt == cache.feed_opt
            logger.info("[cache] entries cache found for #{opt.inspect}")
            return cache
          end
        end
      end
      cache = yield
      cache.feed_opt = opt
      set_cached_entries(auth, cache)
      cache
    end

    def update_cache_entry(auth, entry)
      if cache = get_cached_entries(auth)
        replace_entry(cache, entry)
        set_cached_entries(auth, cache)
      end
    end

    def get_cached_entries(auth)
      cache = ff_client.get_cached_entries(auth.name)
      cache
    end

    def set_cached_entries(auth, cache)
      ff_client.set_cached_entries(auth.name, cache)
    end

    def update_last_modified(feed)
      found = LastModified.find_all_by_eid(feed.entries.map { |e| e.id })
      found_map = found.inject({}) { |r, e|
        r[e.eid] = e
        r
      }
      # do update/create without transaction.  we can use transaction and retry
      # invoking this method (whole transaction) but it's too expensive.
      feed.entries.each do |entry|
        if m = found_map[entry.id]
          d = entry.modified_at
          if m.date < d
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

    def check_inbox(auth, feed, update_unread = true)
      eids = feed.entries.map { |e| e.id }
      checked_map = checked_map(auth, eids) if update_unread
      pinned_map = pinned_map(auth)
      feed.entries.each do |entry|
        entry.view_pinned = pinned_map.key?(entry.id)
        if update_unread
          if checked = checked_map[entry.id]
            entry.checked_at = checked
            entry.view_unread = checked < entry.modified_at
          else
            entry.view_unread = true
          end
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
        :joins => 'LEFT OUTER JOIN last_modifieds ON pins.eid = last_modifieds.eid',
        :order => 'last_modifieds.date desc',
        :offset => start,
        :limit => num
      )
      entries = pinned.find_all { |e| e.source != 'twitter' }
      unless entries.empty?
        hash = get_entries(auth, opt.merge(:eids => entries.map { |e| e.eid }))
        map = (hash['entries'] || []).inject({}) { |r, e| r[e['id']] = e; r }
      else
        hash = {}
        map = {}
      end
      hash['entries'] = pinned.map { |e|
        if ['twitter', 'buzz'].include?(e.source)
          YAML.load(e.entry)
        elsif map.key?(e.eid)
          map[e.eid]
        else
          pin = pinned.find { |f| f.eid == e.eid }
          date = pin ? pin.created_at.xmlschema : nil
          {'id' => e.eid, 'date' => date, '__f2p_orphan' => true, 'from' => {}}
        end
      }
      hash
    end

    def search_entries(auth, opt)
      query = opt[:query] || ''
      if opt[:user]
        from = "from:#{opt[:user]}"
      elsif opt[:friends]
        from = "friends:#{opt[:friends]}"
      end
      if from and (opt[:with_like] or opt[:with_comment])
        ary = [from]
        user = opt[:user] || opt[:friends]
        ary << "like:#{user}" if opt[:with_like]
        ary << "comment:#{user}" if opt[:with_comment]
        from = '(' + ary.join(' OR ') + ')'
      end
      query += ' ' + from if from
      search = filter_opt(opt)
      search[:room] = opt[:room]
      search[:service] = opt[:service] if opt[:service]
      search[:likes] = opt[:with_likes] if opt[:with_likes]
      search[:comments] = opt[:with_comments] if opt[:with_comments]
      ff_client.search(query, search.merge(auth.new_cred)) || {}
    end

    def get_feed(auth, feedid, opt)
      ff_client.feed(feedid, filter_opt(opt).merge(auth.new_cred)) || {}
    end

    def get_link_entries(auth, opt)
      link = opt[:link]
      query = filter_opt(opt)
      query[:url] = link
      query[:subscribed] = opt[:subscribed]
      query[:from] = opt[:from]
      ff_client.url(query.merge(auth.new_cred)) || {}
    end

    def get_liked(auth, opt)
      user = opt[:user]
      search = filter_opt(opt)
      search.delete(:user)
      search[:from] = user
      search[:likes] = 1
      ff_client.search('', search.merge(auth.new_cred)) || {}
    end

    def get_entries(auth, opt)
      eids = opt[:eids]
      query = filter_opt(opt)
      ff_client.entries(eids, query.merge(auth.new_cred)) || {}
    end

    # pick up only unread entries
    def filter_unread_entries(threads, opt)
      threads.map { |th|
        entries = th.entries.find_all { |e|
          e.view_unread or e.view_pinned or e.id == opt[:filter_except]
        }
        unless entries.empty?
          t = EntryThread.new
          t.add(*entries)
          t.root = entries.first
          t.twitter_thread = th.twitter_thread
          t
        end
      }.compact
    end

    def filter_pinned_entries(threads, opt)
      threads.map { |th|
        entries = th.entries.find_all { |e|
          e.view_pinned or e.id == opt[:updated_id] or e.id == opt[:filter_except]
        }
        unless entries.empty?
          t = EntryThread.new
          t.add(*entries)
          t.root = entries.first
          t.twitter_thread = th.twitter_thread
          t
        end
      }.compact
    end

    def sorted?(opt)
      /\bsummary\b/ =~ opt[:feed]
    end

    def filter_opt(opt)
      new_opt = {
        :raw => 1,
        :fof => opt[:fof] || 1,
        :start => opt[:start] || 0,
        :num => opt[:num] || 100
      }
      new_opt[:maxcomments] = opt[:maxcomments] if opt.key?(:maxcomments)
      new_opt[:maxlikes] = opt[:maxlikes] if opt.key?(:maxlikes)
      new_opt
    end

    def ff_client
      ApplicationController.ff_client
    end

    def wrap(hash)
      Feed[hash || {}]
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
        if tweets = find_twitter_thread(buf, entry)
          group += tweets
          buf -= tweets
          t.twitter_thread = true
        else
          opt = {}
          kinds = similar_entries(buf, entry, opt)
          group += kinds
          buf -= kinds
          if kinds.empty?
            pre = entry
            entry_tag = entry.identity(opt)
            buf.each do |e|
              # skip reply tweet for threading
              next if e.tweet? and e.twitter_reply_to_status_id
              if entry_tag == e.identity(opt) and !kinds.include?(e) and
                  # do not merge if both have a comment.
                  (entry.comments.empty? or e.comments.empty?)
                if e.via and e.via.twitter?
                  threashold = F2P::Config.twitter_grouping_threashold
                else
                  threashold = F2P::Config.service_grouping_threashold
                end
                if (e.date_at - pre.date_at).abs < threashold
                  kinds << (pre = e)
                  # too agressive?
                  #similar_entries(buf, e).each do |e2|
                  #  kinds << e2 unless kinds.include?(e2)
                  #end
                end
              end
            end
            group += kinds
            buf -= kinds
          end
        end
        sorted = sort_by_published(group)
        t.add(*sorted)
        t.root = sorted.first
        if opt[:twitter_buddy] and
            sorted.all? { |e| e.via and e.via.twitter? } and
            sorted.any? { |e| e.twitter_username == opt[:twitter_buddy] }
          t.twitter_thread = true
        end
      end
      result
    end

    def sort_by_published(entries)
      entries.sort_by { |e|
        -e.date_at.to_i
      }
    end

    def find_root_tweet(from, tweets)
      while id = from.twitter_reply_to_status_id
        if found = tweets.find { |e|
            e.tweet? and id == Entry.if_service_id(e.id)
          }
          from = found
        else
          break
        end
      end
      return from
    end

    def find_reply_tweets(root, tweets)
      id = Entry.if_service_id(root.id)
      tweets.find_all { |e|
        e.tweet? and e.twitter_reply_to_status_id == id
      }
    end

    def find_twitter_thread(collection, entry)
      return nil unless entry
      return nil unless entry.tweet?
      # forward search: entry -> root
      root = find_root_tweet(entry, collection)
      return nil if root == entry
      # backward search: root -> replies
      result = rest = [root]
      while true
        added = rest.map { |e|
          find_reply_tweets(e, collection)
        }.flatten
        if added.empty?
          return result.uniq
        else
          result += added
          rest = added
        end
      end
    end

    def similar_entries(collection, entry, opt)
      collection.find_all { |e| entry.similar?(e, opt) }
    end

    def first_page_option?(opt)
      opt[:start].nil? or opt[:start] == 0
    end

    def replace_entry(feed, entry)
      feed.entries.each_with_index do |e, idx|
        if e.id == entry.id
          feed.entries[idx] = entry
          entry.view_nextid = e.view_nextid
          return
        end
      end
    end

    # ugly but needed for V2 API.
    def add_service_icon(entries)
      entries.each do |e|
        if e.via and e.via.name and !e.via.service_id
          if s = Service.find_by_name(e.via.name)
            e.via.service_id = s.service_id
            e.via.service_icon_url = s.icon_url
          end
        end
      end
    end

    def from_service(entries, opt)
      service_user = opt[:service_user]
      feed = Feed.new(nil)
      feed.id = opt[:feedname]
      feed.name = opt[:feedname]
      feed.type = 'special'
      feed.entries = entries.map { |hash|
        e = Entry[hash]
        e.view_unread = true
        e
      }
      feed
    end
  end

  attr_accessor :id
  attr_accessor :name
  attr_accessor :type
  attr_accessor :entries

  attr_accessor :feed_opt

  def initialize(hash = nil)
    if hash
      initialize_with_hash(hash, 'id', 'name', 'type')
      @entries = (hash['entries'] || EMPTY).map { |e| Entry[e] }
    end
    @feed_opt = nil
  end
end

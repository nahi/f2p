class EntryThread
  SERVICE_GROUPING_THRESHOLD = 1.5.hour

  class << self
    def find(opt = {})
      name = opt[:name]
      remote_key = opt[:remote_key]
      if opt[:query]
        entries = search_entries(name, remote_key, opt)
      elsif opt[:id]
        entries = get_entry(name, remote_key, opt)
      elsif opt[:likes]
        entries = get_likes(name, remote_key, opt)
      elsif opt[:user]
        entries = get_user_entries(name, remote_key, opt)
      elsif opt[:list]
        entries = get_list_entries(name, remote_key, opt)
      elsif opt[:room]
        entries = get_room_entries(name, remote_key, opt)
      elsif opt[:friends]
        entries = get_friends_entries(name, remote_key, opt)
      else
        entries = get_home_entries(name, remote_key, opt)
      end
      sort_by_service(wrap(entries || []), opt)
    end

  private

    def search_entries(name, remote_key, opt)
      query = opt[:query]
      search = filter_opt(opt)
      search[:from] = opt[:user]
      search[:room] = opt[:room]
      search[:friends] = opt[:friends]
      ff_client.search_entries(name, remote_key, query, search)
    end

    def get_home_entries(name, remote_key, opt)
      ff_client.get_home_entries(name, remote_key, filter_opt(opt))
    end

    def get_user_entries(name, remote_key, opt)
      user = opt[:user]
      ff_client.get_user_entries(name, remote_key, user, filter_opt(opt))
    end

    def get_list_entries(name, remote_key, opt)
      list = opt[:list]
      ff_client.get_list_entries(name, remote_key, list, filter_opt(opt))
    end

    def get_room_entries(name, remote_key, opt)
      room = opt[:room]
      room = nil if room == '*'
      ff_client.get_room_entries(name, remote_key, room, filter_opt(opt))
    end

    def get_friends_entries(name, remote_key, opt)
      friends = opt[:friends]
      ff_client.get_friends_entries(name, remote_key, friends, filter_opt(opt))
    end

    def get_likes(name, remote_key, opt)
      user = opt[:user]
      ff_client.get_likes(name, remote_key, user, filter_opt(opt))
    end

    def get_entry(name, remote_key, opt)
      id = opt[:id]
      ff_client.get_entry(name, remote_key, id)
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
      entries.map { |entry|
        Entry[entry]
      }
    end

    def sort_by_service(entries, opt = {})
      result = []
      buf = entries.find_all { |e| !e.hidden? }.sort_by { |e| e.thread_date }.reverse
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
        result << (t = EntryThread.new(entry))
        group.reverse.each do |e|
          t.add(e)
        end
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

  def add(entry)
    @entries << entry
  end

  def chunked?
    @entries.size > 1
  end

  def single_entry
    unless chunked?
      @entries.first
    end
  end
end

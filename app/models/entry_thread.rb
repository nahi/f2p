require 'task'
require 'entry'


class EntryThread
  class EntryThreads < Array
    attr_accessor :from_modified
    attr_accessor :to_modified
    attr_accessor :max_id
    attr_accessor :pins
  end

  # root is included in entries, too.
  attr_accessor :root
  attr_accessor :twitter_thread
  attr_reader :entries

  def initialize(root = nil)
    @root = root
    @twitter_thread = false
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

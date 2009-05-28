require 'test_helper'

class EntryThreadTest < ActiveSupport::TestCase
  test 'self.find inbox' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_inbox_entries).with('user1', nil, nil, nil).
      returns(read_entries('entries', 'f2ptest')).times(2)
    ff.stubs(:get_profiles)
    2.times do
      threads = EntryThread.find(:auth => user, :inbox => true, :start => nil)
      assert_equal(
        [1, 2, 1, 1, 1, 4, 2, 6, 3, 1, 3, 1, 1, 1, 1, 1],
        threads.map { |t| t.entries.size }
      )
      assert_equal(
        [
          "06675c5a-ae61-41e7-be94-e3bf2fc3429c",
          "8de1f334-6e5c-42d9-a6ef-32c86ea6edc7",
          "260e9e92-0559-4b2d-8487-f98481f967dc",
          "8c690067-8b1f-41f9-8707-b9bb227a2286"
        ],
        threads[5].entries.map { |e| e.id })
      assert_equal(
        [0, 1, 0, 0, 0, 3, 1, 5, 2, 0, 2, 0, 0, 0, 0, 0],
        threads.map { |t| t.related_entries.size }
      )
      assert_equal(
        [false, true, false, false, false, true, true, true, true, false, true, false, false, false, false, false],
        threads.map { |t| t.chunked? }
      )
    end
  end

  test 'self.find inbox 2nd page' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_inbox_entries).with('user1', nil, 20, nil).
      returns(read_entries('entries', 'f2ptest'))
    ff.stubs(:get_profiles)
    threads = EntryThread.find(:auth => user, :inbox => true, :start => 20)
    assert_equal(
      [1, 2, 1, 1, 1, 4, 2, 6, 3, 1, 3, 1, 1, 1, 1, 1],
      threads.map { |t| t.entries.size }
    )
  end

  test 'self.find inbox with pin' do
    user = User.find_by_name('user1')
    # in f2ptest entries
    pin = Pin.new
    pin.user = user
    pin.eid = 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    pin.save
    pin = Pin.new
    pin.user = user
    pin.eid = '19ec8fb0-3776-4447-a814-cac6b129db6f'
    pin.save
    # not in f2ptest entries
    pin = Pin.new
    pin.user = user
    pin.eid = 'foobar'
    pin.save
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_inbox_entries).with('user1', nil, nil, nil).
      returns(read_entries('entries', 'f2ptest')[2..-1]).times(2)
    ff.stubs(:get_profiles)
    2.times do
      threads = EntryThread.find(:auth => user, :inbox => true, :start => nil)
      assert_equal(
        [1, 1, 1, 1, 4, 2, 6, 3, 1, 3, 1, 1, 1, 1, 1],
        threads.map { |t| t.entries.size }
      )
    end
  end

  test 'self.find inbox cache' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_inbox_entries).with('user1', nil, nil, nil).
      returns(read_entries('entries', 'f2ptest')).times(1) # 1 time only
    ff.stubs(:get_profiles)
    2.times do
      threads = EntryThread.find(:auth => user, :inbox => true, :start => nil, :allow_cache => true)
      assert_equal(
        [1, 2, 1, 1, 1, 4, 2, 6, 3, 1, 3, 1, 1, 1, 1, 1],
        threads.map { |t| t.entries.size }
      )
    end
  end

  test 'self.find home' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_home_entries).with('user1', nil, {:num => nil, :start => nil, :service => nil}).
      returns(read_entries('entries', 'f2ptest'))
    ff.stubs(:get_profiles)
    threads = EntryThread.find(:auth => user, :start => nil)
    assert_equal(
      [1, 2, 1, 1, 1, 4, 2, 6, 3, 1, 3, 1, 1, 1, 1, 1],
      threads.map { |t| t.entries.size }
    )
  end

  test 'self.find home cache' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_inbox_entries).with('user1', nil, nil, nil).
      returns(read_entries('entries', 'f2ptest')).times(2) # no cache used
    ff.expects(:get_home_entries).with('user1', nil, :num => nil, :start => nil, :service => nil).
      returns(read_entries('entries', 'f2ptest')).times(2) # no cache used
    ff.stubs(:get_profiles)
    assert_equal(16, EntryThread.find(:auth => user, :inbox => true, :start => nil, :allow_cache => true).size)
    assert_equal(16, EntryThread.find(:auth => user, :start => nil, :allow_cache => true).size)
    assert_equal(16, EntryThread.find(:auth => user, :inbox => true, :start => nil, :allow_cache => true).size)
    assert_equal(16, EntryThread.find(:auth => user, :start => nil, :allow_cache => true).size)
  end

  test 'self.find query' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:search_entries).with('user1', nil, 'foobar', {:from => nil, :room => nil, :friends => nil, :start => nil, :num => nil, :service => nil}).
      returns(read_entries('entries', 'f2ptest'))
    ff.stubs(:get_profiles)
    threads = EntryThread.find(:auth => user, :query => 'foobar')
    assert_equal(
      [1, 2, 1, 1, 1, 4, 2, 6, 3, 1, 3, 1, 1, 1, 1, 1],
      threads.map { |t| t.entries.size }
    )
  end

  test 'self.find id' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_entry).with('user1', nil, 'foobar').
      returns(read_entries('entries', 'f2ptest'))
    ff.stubs(:get_profiles)
    assert_equal(16, EntryThread.find(:auth => user, :id => 'foobar').size)
  end

  test 'self.find likes' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_likes).with('user1', nil, 'user2', {:start => nil, :num => nil, :service => nil}).
      returns([])
    ff.stubs(:get_profiles)
    EntryThread.find(:auth => user, :user => 'user2', :like => 'likes')
  end

  test 'self.find liked' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:search_entries).with('user1', nil, '', {:from => nil, :start => nil, :num => nil, :likes => 1, :service => nil}).
      returns([])
    ff.stubs(:get_profiles)
    EntryThread.find(:auth => user, :like => 'liked')
  end

  test 'self.find user' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_user_entries).with('user1', nil, 'user2', {:start => nil, :num => nil, :service => nil}).
      returns([])
    ff.stubs(:get_profiles)
    EntryThread.find(:auth => user, :user => 'user2')
  end

  test 'self.find list' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_list_entries).with('user1', nil, 'list1', {:start => nil, :num => nil, :service => nil}).
      returns([])
    ff.stubs(:get_profiles)
    EntryThread.find(:auth => user, :list => 'list1')
  end

  test 'self.find room' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_entries).with('user1', nil, 'room1', {:start => nil, :num => nil, :service => nil}).
      returns([])
    ff.stubs(:get_profiles)
    EntryThread.find(:auth => user, :room => 'room1')
  end

  test 'self.find room chunk' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_entries).with('user1', nil, 'room1', {:start => nil, :num => nil, :service => nil}).
      returns(read_entries('entries', 'room'))
    ff.stubs(:get_profiles)
    threads = EntryThread.find(:auth => user, :room => 'room1')
    assert_equal(
      [3, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1],
      threads.map { |t| t.entries.size }
    )
  end

  test 'self.find friends' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_friends_entries).with('user1', nil, 'user2', {:start => nil, :num => nil, :service => nil}).
      returns([])
    ff.stubs(:get_profiles)
    EntryThread.find(:auth => user, :friends => 'user2')
  end

  test 'self.find link' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_url_entries).with('user1', nil, 'http://www.example.org/', {:start => nil, :num => nil, :service => nil}).
      returns([])
    ff.stubs(:get_profiles)
    EntryThread.find(:auth => user, :link => 'http://www.example.org/')
  end

  test 'update_checked_modified' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    list = read_entries('entries', 'f2ptest')
    #
    ff.expects(:get_inbox_entries).with('user1', nil, nil, nil).
      returns(list)
    ff.stubs(:get_profiles)
    threads = EntryThread.find(:auth => user, :inbox => true, :start => nil)
    hash = {}
    threads.each do |t|
      t.entries.each do |e|
        hash[e.id] = e.modified
      end
    end
    EntryThread.update_checked_modified(user, hash)
    hash[hash.keys[0]] = Time.now.xmlschema
    EntryThread.update_checked_modified(user, hash)
    #
    list[0]['updated'] = Time.now.xmlschema
    ff.expects(:get_inbox_entries).with('user1', nil, nil, nil).
      returns(list)
    ff.stubs(:get_profiles)
    threads = EntryThread.find(:auth => user, :inbox => true, :start => nil)
    assert_equal(1, threads.size)
  end

  test 'self.find timeout' do
    user = User.find_by_name('user1')
    ff = mock('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_inbox_entries).with('user1', nil, nil, nil).raises(Timeout::Error.new)
    ff.stubs(:get_profiles)
    assert(EntryThread.find(:auth => user, :inbox => true, :start => nil).empty?)
  end
end

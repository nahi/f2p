require 'test_helper'

class EntryTest < ActiveSupport::TestCase
  test 'self.create' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:post).with('user1', nil, 'body', 'http://www.example.org/', 'comment', [['images']], [['files']], 'room').
      returns([{'id' => 'eid1'}])
    eid = Entry.create(
      :auth => user,
      :body => 'body',
      :link => 'http://www.example.org/',
      :comment => 'comment',
      :images => [['images']],
      :files => [['files']],
      :room => 'room'
    )
    assert_equal('eid1', eid)
    #
    ff.expects(:post).with('user1', nil, nil, nil, nil, nil, nil, nil).
      returns(nil)
    assert_nil(Entry.create(:auth => user))
  end

  test 'self.delete' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:delete).with('user1', nil, 'eid1', false)
    Entry.delete(:auth => user, :id => 'eid1')
    #
    ff.expects(:delete).with('user1', nil, 'eid1', true)
    Entry.delete(:auth => user, :id => 'eid1', :undelete => true)
  end

  test 'self.add_comment' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:post_comment).with('user1', nil, 'eid1', 'body').
      returns({'id' => 'cid1'})
    comment = Entry.add_comment(:auth => user, :id => 'eid1', :body => 'body')
    assert_equal('cid1', comment)
    #
    ff.expects(:post_comment).with('user1', nil, nil, nil).
      returns(nil)
    assert_nil(Entry.add_comment(:auth => user))
  end

  test 'self.delete_comment' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:delete_comment).with('user1', nil, 'eid1', 'cid1', false)
    Entry.delete_comment(:auth => user, :id => 'eid1', :comment => 'cid1')
    #
    ff.expects(:delete_comment).with('user1', nil, 'eid1', 'cid1', true)
    Entry.delete_comment(:auth => user, :id => 'eid1', :comment => 'cid1', :undelete => true)
  end

  test 'self.add_like' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:like).with('user1', nil, 'eid1')
    Entry.add_like(:auth => user, :id => 'eid1')
  end

  test 'self.delete_like' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:unlike).with('user1', nil, 'eid1')
    Entry.delete_like(:auth => user, :id => 'eid1')
  end

  test 'self.add_pin (new)' do
    user = User.find_by_name('user1')
    #
    assert(Pin.find_by_user_id(user.id).nil?)
    Entry.add_pin(:auth => user, :id => 'eid1')
    assert(Pin.find_by_user_id(user.id))
  end

  test 'self.add_pin (exists)' do
    user = User.find_by_name('user1')
    pin = Pin.new
    pin.user = user
    pin.eid = 'eid1'
    pin.save
    #
    assert(Pin.find_by_user_id(user.id))
    Entry.add_pin(:auth => user, :id => 'eid1')
    assert(Pin.find_by_user_id(user.id))
  end

  test 'self.delete_pin (exists)' do
    user = User.find_by_name('user1')
    pin = Pin.new
    pin.user = user
    pin.eid = 'eid1'
    pin.save
    #
    assert(Pin.find_by_user_id(user.id))
    Entry.delete_pin(:auth => user, :id => 'eid1')
    assert(Pin.find_by_user_id(user.id).nil?)
  end

  test 'self.delete_pin (not exists)' do
    user = User.find_by_name('user1')
    #
    assert(Pin.find_by_user_id(user.id).nil?)
    Entry.delete_pin(:auth => user, :id => 'eid1')
    assert(Pin.find_by_user_id(user.id).nil?)
  end

  test 'similar? same_origin?' do
    entries = read_mapped_entries('entries', 'f2ptest')
    # same user_id, same published_at
    e1 = e2 = entries[0]
    assert(e1.similar?(e2))
    assert(e2.similar?(e1))
    # 9 sec
    e1 = entries[1]
    e2 = e1.dup
    e2.link = 'foo'
    e2.title = 'hello world'
    e2.instance_eval { @published_at = Time.at(e1.published_at + 9) }
    assert(e1.similar?(e2))
    assert(e2.similar?(e1))
    # 10 sec
    e1 = entries[2]
    e2 = e1.dup
    e2.link = 'foo'
    e2.title = 'hello world'
    e2.instance_eval { @published_at = Time.at(e1.published_at + 10) }
    assert(!e1.similar?(e2))
    assert(!e2.similar?(e1))
  end

  test 'similar? same_link?' do
    entries = read_mapped_entries('entries', 'f2ptest')
    e1 = e2 = entries[0]
    e2.user = e1.user.dup
    e2.user.id = 'unknown'
    e2.title = 'unknown'
    assert(e1.similar?(e2))
    assert(e2.similar?(e1))
    # 
    e1 = entries[1]
    e2 = e1.dup
    e2.user = e1.user.dup
    e2.user.id = 'unknown'
    e2.link = e1.link.reverse
    e2.title = 'unknown'
    assert(!e1.similar?(e2))
    assert(!e2.similar?(e1))
  end

  test 'similar? similar_title?' do
    entries = read_mapped_entries('entries', 'f2ptest')
    e1 = e2 = entries[0]
    e2.user = e1.user.dup
    e2.user.id = 'unknown'
    e2.link = e1.link.reverse
    assert(e1.similar?(e2))
    assert(e2.similar?(e1))
    # e2 part_of e1
    e1 = entries[1]
    e2 = e1.dup
    e2.user = e1.user.dup
    e2.user.id = 'unknown'
    e2.link = e1.link.reverse
    e1.title = 'abcdefghijk'
    e2.title = 'defghi'
    assert(e1.similar?(e2))
    assert(e2.similar?(e1))
    # e1 part_of e2
    e1 = entries[1]
    e2 = e1.dup
    e2.user = e1.user.dup
    e2.user.id = 'unknown'
    e2.link = e1.link.reverse
    e1.title = 'defghi'
    e2.title = 'abcdefghijk'
    assert(e1.similar?(e2))
    assert(e2.similar?(e1))
    # not e1 part_of e2
    e1 = entries[1]
    e2 = e1.dup
    e2.user = e1.user.dup
    e2.user.id = 'unknown'
    e2.link = e1.link.reverse
    e1.title = 'defgh' # too short
    e2.title = 'abcdefghijk'
    assert(!e1.similar?(e2))
    assert(!e2.similar?(e1))
  end

  test 'service_identity' do
    entries = read_mapped_entries('entries', 'f2ptest')
    assert_equal(['twitter', nil], entries.first.service_identity)
  end

  test 'modified' do
    entries = read_mapped_entries('entries', 'f2ptest')
    # no comments and likes
    e = entries.find { |i| i.id == "58d3aa1c-519c-4ac2-8181-299de3a83d6d" }
    assert_equal('2009-03-18T03:13:29Z', e.updated)
    assert_equal('2009-03-18T03:13:29Z', e.modified)
    # has comments
    e = entries[1]
    assert_equal('2009-03-18T08:44:34Z', e.updated)
    assert_equal('2009-03-18T08:44:35Z', e.modified) # added 1 sec later!
    # has likes
    e = entries[0]
    assert_equal('2009-03-18T08:41:50Z', e.updated)
    assert_equal('2009-03-18T08:51:08Z', e.modified)
  end

  test 'modified_at' do
    entries = read_mapped_entries('entries', 'f2ptest')
    assert_equal('2009-03-18T08:51:08Z', entries.first.modified_at.xmlschema)
  end

  test 'attrs' do
    entries = read_mapped_entries('entries', 'f2ptest')
    e = entries.first
    assert_equal("df9d34df-23ff-de8e-3675-a82736ef90cc", e.id)
    assert_equal("へー http://online.wsj.com/article/SB123735124997967063.html", e.title)
    assert_equal("http://twitter.com/tkudos/statuses/1347347755", e.link)
    assert_equal('2009-03-18T08:41:50Z', e.published_at.xmlschema)
    assert_equal('twitter', e.service.id)
    assert_equal('9a46f9b0-0775-11dd-9e68-003048343a40', e.user_id)
    assert_equal('tkudo', e.nickname)
    assert_nil(e.room)
    assert(!e.hidden?)
    assert(!e.self_comment_only?)
    assert(entries[1].self_comment_only?)
  end

  test 'media' do
    entries = read_mapped_entries('entries', 'f2ptest')
    e = entries.find { |e| e.id == "260e9e92-0559-4b2d-8487-f98481f967dc" }
    assert_equal(2, e.medias.size)
  end

  test 'twitter_username' do
    entry = read_mapped_entries('entries', 'twitter')[0]
    assert_equal('foo', entry.twitter_username)
    entry = read_mapped_entries('entries', 'f2ptest')[1]
    assert_nil(entry.twitter_username)
  end
end

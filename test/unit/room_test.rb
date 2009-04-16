require 'test_helper'

class RoomTest < ActiveSupport::TestCase
  test 'create' do
    r = Room[
      'id' => 'id',
      'nickname' => 'nickname',
      'name' => 'name'
    ]
    assert_equal('id', r.id)
    assert_equal('nickname', r.nickname)
    assert_equal('name', r.name)
  end

  test 'ff_id' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns('id' => 'id')
    assert_equal('id', Room.ff_profile(user, 'room1')['id'])
  end

  test 'ff_name' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns('name' => 'name')
    assert_equal('name', Room.ff_profile(user, 'room1')['name'])
  end

  test 'ff_url' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns('url' => 'http://www.example.org/')
    assert_equal('http://www.example.org/', Room.ff_profile(user, 'room1')['url'])
  end

  test 'status' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns('status' => 'status')
    assert_equal('status', Room.ff_profile(user, 'room1')['status'])
  end

  test 'description' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns('description' => 'description')
    assert_equal('description', Room.ff_profile(user, 'room1')['description'])
  end

  test 'picture_url' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_picture_url).with('room1', 'small').
      returns('http://www.example.org/')
    assert_equal('http://www.example.org/', Room.ff_picture_url('room1'))
    #
    ff.expects(:get_room_picture_url).with('room1', 'large').
      returns('http://www.example.org/')
    assert_equal('http://www.example.org/', Room.ff_picture_url('room1', 'large'))
  end

  test 'members' do
    user = User.find_by_name('user1')
    ary = [{'name' => 'u1'}, {'name' => 'u2'}]
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns('members' => ary.reverse)
    members = Room.ff_profile(user, 'room1')['members']
    assert_equal('u1', members[0].name)
    assert_equal('u2', members[1].name)
  end
end

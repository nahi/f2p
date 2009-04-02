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
    assert_equal('id', Room.ff_id(:auth => user, :room => 'room1'))
    ff.expects(:get_room_profile).with('user1', nil, nil).
      returns(nil)
    assert_nil(Room.ff_id(:auth => user))
  end

  test 'ff_name' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns('name' => 'name')
    assert_equal('name', Room.ff_name(:auth => user, :room => 'room1'))
  end

  test 'ff_url' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns('url' => 'http://www.example.org/')
    assert_equal('http://www.example.org/', Room.ff_url(:auth => user, :room => 'room1'))
  end

  test 'status' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns('status' => 'status')
    assert_equal('status', Room.status(:auth => user, :room => 'room1'))
  end

  test 'description' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns('description' => 'description')
    assert_equal('description', Room.description(:auth => user, :room => 'room1'))
  end

  test 'picture_url' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_picture_url).with('room1', 'small').
      returns('http://www.example.org/')
    assert_equal('http://www.example.org/', Room.picture_url(:room => 'room1'))
    #
    ff.expects(:get_room_picture_url).with('room1', 'large').
      returns('http://www.example.org/')
    assert_equal('http://www.example.org/', Room.picture_url(:room => 'room1', :size => 'large'))
  end

  test 'members' do
    user = User.find_by_name('user1')
    ary = [{'name' => 'u1'}, {'name' => 'u2'}]
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns('members' => ary.reverse)
    members = Room.members(:auth => user, :room => 'room1')
    assert_equal('u1', members[0].name)
    assert_equal('u2', members[1].name)
  end
end

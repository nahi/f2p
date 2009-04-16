require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'find_all' do
    assert_equal(2, User.find(:all).size)
    5.times do |idx|
      user = User.new
      user.name = idx.to_s
      user.remote_key = idx.to_s
      assert(user.save)
    end
    assert_equal(7, User.find(:all).size)
  end

  test 'create' do
    assert_nothing_raised do
      user = User.new
    end
  end

  test 'save' do
    user = User.new
    user.name = 'test'
    user.remote_key = 'remote key'
    assert(user.save)
    assert(!user.id.nil?)
    assert('test', user.name)
    assert('remote key', user.remote_key)
  end

  test 'find' do
    assert_equal(2, User.find(:all).size)
    user = User.new
    user.name = 'test'
    user.remote_key = 'remote key'
    assert(user.save)
    found = User.find_by_name('test')
    assert_equal(user, found)
    assert_nil(User.find_by_name('no such name'))
    assert_equal(3, User.find(:all).size)
  end

  test 'validate success (new user)' do
    assert_nil(User.find_by_name('newuser'))
    ff = stub('ff_client')
    ff.expects(:validate).with('newuser', 'remote_key').
      returns(true)
    ApplicationController.ff_client = ff
    assert(User.validate('newuser', 'remote_key'))
    user = User.find_by_name('newuser')
    assert_equal('newuser', user.name)
    assert_equal('remote_key', user.remote_key)
  end

  test 'validate success (existing user)' do
    user = User.find_by_name('user1')
    # encrypted password in fixture is resolved to nil
    assert_equal(nil, user.remote_key)
    ff = stub('ff_client')
    ff.expects(:validate).with('user1', 'newkey').
      returns(true)
    ApplicationController.ff_client = ff
    assert(User.validate('user1', 'newkey'))
    user = User.find_by_name('user1')
    assert_equal('newkey', user.remote_key)
  end

  test 'validate failure (nil arg)' do
    assert_nil(User.validate(nil, 'remote_key1'))
    assert_nil(User.validate('user1', nil))
  end

  test 'validate failure' do
    ff = stub('ff_client')
    ff.expects(:validate).with('user1', 'remote_key1').
      returns(false)
    ApplicationController.ff_client = ff
    #
    assert_nil(User.validate('user1', 'remote_key1'))
  end

  test 'ff_id' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_profile).with('user1', nil, 'user1').
      returns('id' => 'id')
    assert_equal('id', User.ff_profile(user, 'user1')['id'])
    #
    ff.expects(:get_profile).with('user1', nil, 'user1').
      returns(nil)
    assert_nil(User.ff_profile(user, 'user1')['id'])
  end

  test 'ff_name' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_profile).with('user1', nil, 'user1').
      returns('name' => 'name')
    assert_equal('name', User.ff_profile(user, 'user1')['name'])
  end

  test 'ff_url' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_profile).with('user1', nil, 'user1').
      returns('profileUrl' => 'http://www.example.org/')
    assert_equal('http://www.example.org/', User.ff_profile(user, 'user1')['profileUrl'])
  end

  test 'status' do
    user = User.find_by_name('user1')
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_profile).with('user1', nil, 'user1').
      returns('status' => 'status')
    assert_equal('status', User.ff_profile(user, 'user1')['status'])
  end

  test 'picture_url' do
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_user_picture_url).with('user1', 'small').
      returns('http://www.example.org/')
    assert_equal('http://www.example.org/', User.ff_picture_url('user1'))
    #
    ff.expects(:get_user_picture_url).with('user1', 'medium').
      returns('http://www.example.org/')
    assert_equal('http://www.example.org/', User.ff_picture_url('user1', 'medium'))
  end

  test 'services' do
    user = User.find_by_name('user1')
    ary = [{'name' => 's1'}, {'name' => 's2'}]
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_profile).with('user1', nil, 'user1').
      returns('services' => ary.reverse)
    services = User.ff_profile(user, 'user1')['services']
    assert_equal('s1', services[0].name)
    assert_equal('s2', services[1].name)
  end

  test 'lists' do
    user = User.find_by_name('user1')
    ary = [{'name' => 'l1'}, {'name' => 'l2'}]
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_profile).with('user1', nil, 'user1').
      returns('lists' => ary.reverse)
    lists = User.ff_profile(user, 'user1')['lists']
    assert_equal('l1', lists[0].name)
    assert_equal('l2', lists[1].name)
  end

  test 'rooms' do
    user = User.find_by_name('user1')
    ary = [{'name' => 'r1'}, {'name' => 'r2'}]
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_profile).with('user1', nil, 'user1').
      returns('rooms' => ary.reverse)
    rooms = User.ff_profile(user, 'user1')['rooms']
    assert_equal('r1', rooms[0].name)
    assert_equal('r2', rooms[1].name)
  end

  test 'subscriptions' do
    user = User.find_by_name('user1')
    ary = [{'name' => 'u1'}, {'name' => 'u2'}]
    ff = stub('ff_client')
    ApplicationController.ff_client = ff
    #
    ff.expects(:get_profile).with('user1', nil, 'user1').
      returns('subscriptions' => ary.reverse)
    subscriptions = User.ff_profile(user, 'user1')['subscriptions']
    assert_equal('u1', subscriptions[0].name)
    assert_equal('u2', subscriptions[1].name)
  end
end

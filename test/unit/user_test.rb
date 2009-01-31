require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'find_all' do
    assert_equal(0, User.find(:all).size)
    5.times do |idx|
      user = User.new
      user.name = idx.to_s
      user.remote_key = idx.to_s
      assert(user.save)
    end
    assert_equal(5, User.find(:all).size)
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
    user = User.new
    user.name = 'test'
    user.remote_key = 'remote key'
    assert(user.save)
    found = User.find_by_name('test')
    assert_equal(user, found)
    assert_nil(User.find_by_name('no such name'))
    assert_equal(1, User.find(:all).size)
  end
end

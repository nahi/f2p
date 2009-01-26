require 'test_helper'

class UserTest < ActiveSupport::TestCase
  fixtures :users

  test 'find_all' do
    assert_equal(2, User.find(:all).size)
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
  end

  test 'find' do
    user = User.new
    user.name = 'test'
    user.remote_key = 'remote key'
    assert(user.save)
    found = User.find_by_name('test')
    assert_equal(user, found)
    assert_nil(User.find_by_name('no such name'))
    assert_equal(3, User.find(:all).size)
  end
end

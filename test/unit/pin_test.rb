require 'test_helper'

class PinTest < ActiveSupport::TestCase
  test 'create' do
    assert_raises(ActiveRecord::StatementInvalid) do
      pin = Pin.new
      pin.save
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      user = User.find_by_name('user1')
      pin = Pin.new
      pin.user = user
      pin.save
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      pin = Pin.new
      pin.eid = 'eid1'
      pin.save
    end
    assert_nothing_raised do
      user = User.find_by_name('user1')
      pin = Pin.new
      pin.user = user
      pin.eid = 'eid1'
      assert(pin.save)
      pin = Pin.find_by_user_id(user.id)
      assert_equal(user, pin.user)
      assert_equal('eid1', pin.eid)
    end
  end

  test 'find' do
    user = User.find_by_name('user1')
    pin = Pin.new
    pin.user = user
    pin.eid = 'eid1'
    assert(pin.save)
    pin = Pin.find_by_user_id_and_eid(user.id, 'eid1')
    assert(pin)
    pin = Pin.find_by_user_id_and_eid('user1', 'eid2')
    assert_nil(pin)
  end
end

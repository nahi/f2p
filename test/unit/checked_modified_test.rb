require 'test_helper'

class CheckedModifiedTest < ActiveSupport::TestCase
  test 'create' do
    assert_raises(ActiveRecord::StatementInvalid) do
      CheckedModified.new.save
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      user = User.find_by_name('user1')
      checked = CheckedModified.new
      checked.user = user
      checked.save
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      mod = LastModified.find_by_eid('eid1')
      checked = CheckedModified.new
      checked.last_modified = mod
      checked.save
    end
    assert_nothing_raised do
      user = User.find_by_name('user1')
      mod = LastModified.find_by_eid('eid1')
      checked = CheckedModified.new
      checked.user = user
      checked.last_modified = mod
      t = checked.checked = Time.now.gmtime
      assert(checked.save)
      checked = CheckedModified.find_by_user_id(user.id)
      assert_equal(user, checked.user)
      assert_equal(mod, checked.last_modified)
      assert_equal(t.xmlschema, checked.checked.xmlschema)
    end
  end

  test 'find' do
    assert_equal(0, CheckedModified.find(:all).size)
    user = User.find_by_name('user1')
    mod = LastModified.find_by_eid('eid1')
    checked = CheckedModified.new
    checked.user = user
    checked.last_modified = mod
    assert(checked.save)
    assert_equal(1, CheckedModified.find(:all).size)
  end

  test 'find cascade' do
    user = User.find_by_name('user1')
    mod = LastModified.find_by_eid('eid1')
    cond = [
      'user_id = ? and last_modifieds.eid in (?)', user.id, ['eid1', 'eid2']
    ]
    all = CheckedModified.find(:all, :conditions => cond, :include => 'last_modified')
    assert_equal(0, all.size)
    checked = CheckedModified.new
    checked.user = user
    checked.last_modified = mod
    assert(checked.save)
    all = CheckedModified.find(:all, :conditions => cond, :include => 'last_modified')
    assert_equal(1, all.size)
    assert_equal('eid1', all.first.last_modified.eid)
    assert_equal('2008-01-01T00:00:00Z', all.first.last_modified.date.xmlschema)
  end
end

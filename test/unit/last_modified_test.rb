require 'test_helper'

class LastModifiedTest < ActiveSupport::TestCase
  test 'create' do
    assert_raises(ActiveRecord::StatementInvalid) do
      LastModified.new.save
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      mod = LastModified.new
      mod.eid = 'eid2'
      mod.save
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      mod = LastModified.new
      mod.date = '2008-02-02T00:00:00'
      mod.save
    end
    assert_nothing_raised do
      mod = LastModified.new
      mod.eid = 'eid2'
      mod.date = '2008-02-02T00:00:00'
      assert(mod.save)
      mod = LastModified.find_by_eid('eid2')
      assert_equal('eid2', mod.eid)
      assert_equal('2008-02-02T00:00:00Z', mod.date.xmlschema)
    end
  end
end

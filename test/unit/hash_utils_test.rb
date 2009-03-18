require 'test_helper'

class HashUtilsTest < ActiveSupport::TestCase
  class Foo < Hash
    include HashUtils
  end

  test 'v' do
    v = Foo.new
    v['a'] = '1'
    v['b'] = {'c' => {'d' => {'e' => 'f'}}}
    assert_equal('1', v.v('a'))
    assert_equal('f', v.v('b', 'c', 'd', 'e'))
    assert_nil(v.v('a', 'b'))
    assert_nil(v.v('a', 'b', 'c'))
    assert_nil(v.v('b', 'c', 'd', 'e', 'g'))
  end

  test 'exceptional key case' do
    v = Foo.new
    v['b'] = {'c' => {'d' => {'e' => 'f'}}}
    # 'f'['f'] == 'f'
    assert_equal('f', v.v('b', 'c', 'd', 'e', 'f'))
  end
end

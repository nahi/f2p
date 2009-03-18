require 'test_helper'

class CommentTest < ActiveSupport::TestCase
  test 'create' do
    c = Comment[
      'id' => 'id',
      'body' => 'body',
      'user' => {'id' => 'user.id', 'nickname' => 'user.nickname'}
    ]
    assert_equal('id', c.id)
    assert_equal('body', c.body)
    assert_equal('user.id', c.user_id)
    assert_equal('user.nickname', c.nickname)
    assert(c.by_user('user.nickname'))
    assert(!c.by_user('XXX'))
  end
end

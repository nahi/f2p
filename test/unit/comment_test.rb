require 'test_helper'

class CommentTest < ActiveSupport::TestCase
  test 'create' do
    c = Comment[
      'id' => 'id',
      'rawBody' => 'body',
      'from' => {'id' => 'user.id', 'name' => 'user.name'}
    ]
    assert_equal('id', c.id)
    assert_equal('body', c.body)
    assert_equal('user.id', c.from_id)
    assert(c.by_user('user.id'))
    assert(!c.by_user('user.name'))
  end
end

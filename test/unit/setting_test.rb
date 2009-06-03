require 'test_helper'

class SettingTest < ActiveSupport::TestCase
  test 'create' do
    s = Setting.new
    assert_equal(F2P::Config.font_size, s.font_size)
    assert_equal(F2P::Config.entries_in_page, s.entries_in_page)
    assert_equal(F2P::Config.entries_in_thread, s.entries_in_thread)
    assert_equal(F2P::Config.text_folding_size, s.text_folding_size)
    assert_equal(F2P::Config.twitter_comment_hack, s.twitter_comment_hack)
    assert_equal(F2P::Config.link_open_new_window, s.link_open_new_window)
    assert_equal(F2P::Config.link_type, s.link_type)
    assert_equal(F2P::Config.list_view_media_rendering, s.list_view_media_rendering)
    assert_equal(F2P::Config.google_maps_zoom, s.google_maps_zoom)
    assert_nil(s.validate)
  end

  test 'validate' do
    s = Setting.new
    s.font_size = 5
    s.entries_in_page = 4
    s.entries_in_thread = -1
    s.text_folding_size = 19
    s.google_maps_zoom = 20
    assert_equal(5, s.validate.size)
  end
end

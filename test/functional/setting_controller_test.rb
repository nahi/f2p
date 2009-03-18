require 'test_helper'

class SettingControllerTest < ActionController::TestCase
  test 'index' do
    login('user1')
    get :index
    assert_response :success
  end

  test 'update success' do
    login('user1')
    s = @request.session[:setting]
    assert_equal(F2P::Config.font_size, s.font_size)
    assert_equal(F2P::Config.entries_in_page, s.entries_in_page)
    assert_equal(F2P::Config.entries_in_thread, s.entries_in_thread)
    assert_equal(F2P::Config.text_folding_size, s.text_folding_size)
    assert_equal(F2P::Config.twitter_comment_hack, s.twitter_comment_hack)
    assert_equal(F2P::Config.list_view_media_rendering, s.list_view_media_rendering)
    assert_equal(F2P::Config.link_open_new_window, s.link_open_new_window)
    assert_equal(F2P::Config.link_type, s.link_type)
    #
    post :update,
      :font_size => '10',
      :entries_in_page => '34',
      :entries_in_thread => '5',
      :text_folding_size => '200',
      :twitter_comment_hack => '',
      :list_view_media_rendering => '',
      :link_open_new_window => '',
      :link_type_gwt => ''
    assert_redirected_to :controller => 'entry'
    s = @request.session[:setting]
    assert_equal(10, s.font_size)
    assert_equal(34, s.entries_in_page)
    assert_equal(5, s.entries_in_thread)
    assert_equal(200, s.text_folding_size)
    assert_equal(false, s.twitter_comment_hack)
    assert_equal(false, s.list_view_media_rendering)
    assert_equal(false, s.link_open_new_window)
    assert_equal(nil, s.link_type)
    #
    post :update,
      :font_size => '11',
      :entries_in_page => '35',
      :entries_in_thread => '6',
      :text_folding_size => '201',
      :twitter_comment_hack => 'checked',
      :list_view_media_rendering => 'checked',
      :link_open_new_window => 'checked',
      :link_type_gwt => 'checked'
    assert_redirected_to :controller => 'entry'
    s = @request.session[:setting]
    assert_equal(11, s.font_size)
    assert_equal(35, s.entries_in_page)
    assert_equal(6, s.entries_in_thread)
    assert_equal(201, s.text_folding_size)
    assert_equal(true, s.twitter_comment_hack)
    assert_equal(true, s.list_view_media_rendering)
    assert_equal(true, s.link_open_new_window)
    assert_equal('gwt', s.link_type)
  end

  test 'update failure' do
    login('user1')
    #
    post :update,
      :font_size => '5',
      :entries_in_page => '4',
      :entries_in_thread => '2',
      :text_folding_size => '19',
      :twitter_comment_hack => '',
      :list_view_media_rendering => '',
      :link_open_new_window => '',
      :link_type_gwt => ''
    assert_response :success
    assert_equal(
      "Settings error: font size must be greater than 6, entries in page must be in 5..100, entries in thread must be in 3..100, text folding size must be in 20..1000",
      flash[:error]
    )
    s = @request.session[:setting]
    assert_equal(F2P::Config.font_size, s.font_size)
    assert_equal(F2P::Config.entries_in_page, s.entries_in_page)
    assert_equal(F2P::Config.entries_in_thread, s.entries_in_thread)
    assert_equal(F2P::Config.text_folding_size, s.text_folding_size)
    assert_equal(F2P::Config.twitter_comment_hack, s.twitter_comment_hack)
    assert_equal(F2P::Config.list_view_media_rendering, s.list_view_media_rendering)
    assert_equal(F2P::Config.link_open_new_window, s.link_open_new_window)
    assert_equal(F2P::Config.link_type, s.link_type)
  end
end

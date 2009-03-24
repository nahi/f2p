require 'test_helper'

class SettingControllerTest < ActionController::TestCase
  test 'index' do
    login('user1')
    get :index
    assert_response :success
  end

  test 'login redirect' do
    get :index
    assert_redirected_to :controller => 'login', :action => 'index'
    assert(!session[:redirect_to_after_authenticate].nil?)
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
    assert_equal(F2P::Config.mobile_gps_type, s.mobile_gps_type)
    assert_equal(F2P::Config.google_maps_geocoding_lang, s.google_maps_geocoding_lang)
    #
    post :update,
      :font_size => '10',
      :entries_in_page => '34',
      :entries_in_thread => '5',
      :text_folding_size => '200',
      :twitter_comment_hack => '',
      :list_view_media_rendering => '',
      :link_open_new_window => '',
      :link_type_gwt => '',
      :mobile_gps_type => '',
      :google_maps_geocoding_lang => ''
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
    assert_equal(nil, s.mobile_gps_type)
    assert_equal(nil, s.google_maps_geocoding_lang)
    #
    post :update,
      :font_size => '11',
      :entries_in_page => '35',
      :entries_in_thread => '6',
      :text_folding_size => '201',
      :twitter_comment_hack => 'checked',
      :list_view_media_rendering => 'checked',
      :link_open_new_window => 'checked',
      :link_type_gwt => 'checked',
      :mobile_gps_type => 'WILLCOM',
      :google_maps_geocoding_lang => 'ja'
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
    assert_equal('WILLCOM', s.mobile_gps_type)
    assert_equal('ja', s.google_maps_geocoding_lang)
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
      :link_type_gwt => '',
      :mobile_gps_type => 'unknown',
      :google_maps_geocoding_lang => 'foobar'
    assert_response :success
    assert_equal(
      "Settings error: font size must be greater than 6, entries in page must be in 5..100, entries in thread must be in 3..100, text folding size must be in 20..1000, gps type shall be one of ezweb, gpsone, DoCoMoFOMA, DoCoMomova, SoftBank3G, WILLCOM",
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
    assert_equal(F2P::Config.mobile_gps_type, s.mobile_gps_type)
    assert_equal(F2P::Config.google_maps_geocoding_lang, s.google_maps_geocoding_lang)
  end
end

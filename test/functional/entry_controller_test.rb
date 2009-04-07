require 'test_helper'

class EntryControllerTest < ActionController::TestCase
  def setup
    super
    @ff = mock('ff_client')
    @ff.stubs(:get_profile).returns(read_profile('profile'))
    ApplicationController.ff_client = @ff
  end

  test 'compress' do
    login('user1')
    @request.env['HTTP_ACCEPT_ENCODING'] = 'gzip'
    get :index
    assert_redirected_to :action => 'inbox'
  end

  test 'compress q' do
    login('user1')
    @request.env['HTTP_ACCEPT_ENCODING'] = 'x-gzip; q=0.1, unknown, unknown; q=0.9, gzip; q=0.2'
    get :index
    assert_redirected_to :action => 'inbox'
  end

  test 'ff_client' do
    ApplicationController.ff_client = nil
    assert(ApplicationController.ff_client)
  end

  test 'http_client' do
    ApplicationController.http_client = nil
    assert(ApplicationController.http_client)
  end

  test 'index' do
    login('user1')
    get :index
    assert_redirected_to :action => 'inbox'
  end

  test 'inbox without login' do
    get :inbox
    assert_redirected_to :controller => 'login', :action => 'index'
  end

  test 'inbox' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :inbox
    assert_response :success
    get :inbox
    assert_response :success
  end

  test 'inbox archive' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest')).times(1)
    get :inbox
    assert_response :success
    post :archive
    assert_redirected_to :action => 'inbox'
  end

  test 'inbox archive by timeout' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest')).times(1)
    post :inbox
    assert_response :success
    #
    session[:last_updated] = Time.at(Time.now - (F2P::Config.updated_expiration + 1))
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest'))
    post :inbox
    assert_response :success
  end

  test 'inbox pagination' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest')).times(1)
    get :inbox, :start => 20, :num => 20
    assert_response :success
  end

  test 'inbox skip' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    @ff.expects(:get_home_entries).
      returns([]).then.returns(read_entries('entries', 'f2ptest')).times(2)
    get :inbox
    assert_response :success
  end

  test 'list home' do
    login('user1')
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list
    assert_response :success
    get :list
    assert_response :success
  end

  test 'list home pagination' do
    login('user1')
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :num => 20, :start => 20
    assert_response :success
    get :list, :num => 20, :start => 20
    assert_response :success
  end

  test 'list query' do
    login('user1')
    @ff.expects(:search_entries).
      with('user1', nil, 'query', {:service => nil, :from => nil, :friends => nil, :num => 20, :start => 0, :room => nil}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :query => 'query'
    assert_response :success
    get :list, :query => 'query'
    assert_response :success
  end

  test 'list likes' do
    login('user1')
    @ff.expects(:get_likes).
      with('user1', nil, 'user1', {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :like => 'likes'
    assert_response :success
    get :list, :like => 'likes'
    assert_response :success
  end

  test 'list likes other' do
    login('user1')
    @ff.expects(:get_user_picture_url).with('user2', 'small').
      returns('http://user2/').times(1)
    @ff.expects(:get_likes).
      with('user1', nil, 'user2', {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :like => 'likes', :user => 'user2'
    assert_response :success
    get :list, :like => 'likes', :user => 'user2'
    assert_response :success
  end

  test 'list liked' do
    login('user1')
    @ff.expects(:search_entries).
      with('user1', nil, '', {:service => nil, :from => 'user1', :num => 20, :start => 0, :likes => 1}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :like => 'liked'
    assert_response :success
    get :list, :like => 'liked'
    assert_response :success
  end

  test 'list liked other' do
    login('user1')
    @ff.expects(:get_user_picture_url).with('user2', 'small').
      returns('http://user2/').times(1)
    @ff.expects(:search_entries).
      with('user1', nil, '', {:service => nil, :from => 'user2', :num => 20, :start => 0, :likes => 1}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :like => 'liked', :user => 'user2'
    assert_response :success
    get :list, :like => 'liked', :user => 'user2'
    assert_response :success
  end

  test 'list comments' do
    login('user1')
    @ff.expects(:get_comments).
      with('user1', nil, 'user1', {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :comment => 'comments'
    assert_response :success
    get :list, :comment => 'comments'
    assert_response :success
  end

  test 'list commented' do
    login('user1')
    @ff.expects(:get_discussion).
      with('user1', nil, 'user1', {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :comment => 'commented'
    assert_response :success
    get :list, :comment => 'commented'
    assert_response :success
  end

  test 'list user' do
    login('user1')
    @ff.expects(:get_user_picture_url).with('user1', 'small').
      returns('http://user1/').times(1)
    @ff.expects(:get_user_entries).
      with('user1', nil, 'user1', {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :user => 'user1'
    assert_response :success
    get :list, :user => 'user1'
    assert_response :success
  end

  test 'list friends' do
    login('user1')
    @ff.expects(:get_user_picture_url).with('user1', 'small').
      returns('http://user1/').times(1)
    @ff.expects(:get_friends_entries).
      with('user1', nil, 'user1', {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :friends => 'user1'
    assert_response :success
    get :list, :friends => 'user1'
    assert_response :success
  end

  test 'list list' do
    login('user1')
    @ff.expects(:get_list_entries).
      with('user1', nil, 'list1', {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :list => 'list1'
    assert_response :success
    get :list, :list => 'list1'
    assert_response :success
  end

  test 'list room any' do
    login('user1')
    @ff.expects(:get_room_entries).
      with('user1', nil, nil, {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :room => '*'
    assert_response :success
    get :list, :room => '*'
    assert_response :success
  end

  test 'list room' do
    login('user1')
    @ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns(read_profile('room_profile')).
      times(4) # for name, url, description, and members.
    @ff.expects(:get_room_picture_url).with('room1', 'small').
      returns('http://room1/').times(1)
    @ff.expects(:get_room_entries).
      with('user1', nil, 'room1', {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :room => 'room1'
    assert_response :success
    get :list, :room => 'room1'
    assert_response :success
  end

  test 'list link' do
    login('user1')
    @ff.expects(:get_url_entries).
      with('user1', nil, 'http://foo/', {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :link => 'http://foo/'
    assert_response :success
    get :list, :link => 'http://foo/'
    assert_response :success
  end

  test 'list link query' do
    login('user1')
    @ff.expects(:get_url_entries).
      with('user1', nil, 'http://foo/', {:service => nil, :num => 10, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    @ff.expects(:search_entries).
      with('user1', nil, 'foo', {:friends => nil, :room => nil, :service => nil, :from => nil, :start => 0, :num => 10}).
      returns(read_entries('entries', 'f2ptest')).times(2)
    get :list, :link => 'http://foo/', :query => 'foo'
    assert_response :success
    get :list, :link => 'http://foo/', :query => 'foo'
    assert_response :success
  end

  test 'show' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    @ff.expects(:get_entry).
      returns(read_entries('entries', 'f2ptest')[0, 1]).times(2)
    get :show, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    assert_response :success
    get :show, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    assert_response :success
  end

  test 'show then like' do
    login('user1')
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest')).times(1)
    get :list
    assert_response :success
    assert_nil(session[:ctx].eid)
    #
    @ff.expects(:get_entry).
      returns(read_entries('entries', 'f2ptest')[0, 1]).times(1)
    get :show, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    assert_response :success
    assert(session[:ctx].eid)
    #
    # redirected to the original single thread view
    #
    @ff.expects(:like).with('user1', nil, 'id')
    get :like, :id => 'id'
    assert_redirected_to :action => 'show'
  end

  test 'edit' do
    login('user1')
    get :edit, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    assert_redirected_to :action => 'inbox'
    #
    @ff.expects(:get_profile).
      returns(read_profile('profile'))
    @ff.expects(:get_entry).
      returns(read_entries('entries', 'f2ptest')[0, 1])
    get :edit, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc', :comment => 'c'
    assert_response :success
  end

  test 'inbox then edit' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile'))
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest'))
    get :inbox
    assert_response :success
    assert(session[:ctx])
    #
    @ff.expects(:get_entry).
      returns(read_entries('entries', 'f2ptest')[0, 1])
    get :edit, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc', :comment => 'c'
    assert_response :success
    assert_equal('df9d34df-23ff-de8e-3675-a82736ef90cc', session[:ctx].eid)
  end

  test 'updated' do
    login('user1')
    get :updated
    assert_redirected_to :action => 'inbox'
  end

  test 'new' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    #
    get :new
    assert_response :success
  end

  test 'new zoom setting' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    assert_equal(13, @setting.google_maps_zoom)
    #
    get :new
    assert_response :success
    assert_equal(13, @setting.google_maps_zoom)
    #
    get :new, :zoom => 1
    assert_response :success
    assert_equal(1, @setting.google_maps_zoom)
  end

  test 'new with gps' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    h = mock('http_client')
    ApplicationController.http_client = h
    mobile = mock('request.mobile')
    position = mock('request.mobile.position')
    @request.stubs(:mobile).returns(mobile)
    mobile.stubs(:supports_cookie?).returns(true)
    mobile.expects(:position).returns(position)
    position.expects(:lat).returns(35.01)
    position.expects(:lon).returns(135.693222222)
    h.expects(:get_content).
      with('http://maps.google.com/maps/geo', {'oe' => 'utf-8', 'll' => '35.01,135.693222222', 'hl' => 'ja', 'output' => 'json', 'key' => ''}).
      returns(read_fixture('google_geocoder_tokyo_sta.json'))
    get :new, :lat => '+35.00.36.00', :lon => '+135.41.35.600'
    assert_response :success
  end

  test 'reshare' do
    login('user1')
    #
    get :reshare
    assert_redirected_to :action => 'inbox'
    #
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    @ff.expects(:get_entry).
      returns(read_entries('entries', 'f2ptest')[0, 1]).times(1)
    #
    get :reshare, :eid => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    assert_response :success
  end

  test 'reshare notfound' do
    login('user1')
    @ff.expects(:get_entry).returns([])
    #
    get :reshare, :eid => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    assert_redirected_to :action => 'list'
  end

  test 'search' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    #
    get :search
    assert_response :success
  end

  test 'add' do
    login('user1')
    post :add
    assert_response :success
  end

  test 'add search ja' do
    login('user1')
    h = mock('http_client')
    ApplicationController.http_client = h
    h.expects(:get_content).
      with('http://www.geocoding.jp/api/', {'v' => 1.1, 'q' => 'address'}).
      returns(read_fixture('geocoding_jp_tokyo_sta.xml'))
    post :add, :commit => 'search', :title => 'address'
    assert_response :success
  end

  test 'add search non ja' do
    login('user1')
    h = mock('http_client')
    ApplicationController.http_client = h
    h.expects(:get_content).
      with('http://maps.google.com/maps/geo', {'oe' => 'utf-8', 'hl' => 'en', 'output' => 'json', 'q' => 'address', 'key' => ''}).
      returns(read_fixture('google_geocoder_tokyo_sta.json'))
    @setting.google_maps_geocoding_lang = 'en'
    post :add, :commit => 'search', :title => 'address'
    assert_response :success
  end

  test 'add search lat long' do
    login('user1')
    post :add, :commit => 'search', :address => 'addredd', :lat => 35.0, :long => 136.0
    assert_response :success
  end

  test 'add post body' do
    login('user1')
    @ff.expects(:post).with('user1', nil, 'hello', nil, nil, nil, nil, nil).
      returns([{'id' => 'foo'}])
    post :add, :commit => 'post', :body => 'hello'
    assert_redirected_to :action => 'list'
  end

  test 'add post body from inbox' do
    login('user1')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest')).times(1)
    get :inbox
    assert_response :success
    assert(!session[:ctx].nil?)
    assert(session[:ctx].inbox)
    #
    @ff.expects(:post).with('user1', nil, 'hello', nil, nil, nil, nil, nil).
      returns([{'id' => 'foo'}])
    post :add, :commit => 'post', :body => 'hello'
    assert_redirected_to :action => 'inbox'
    assert(session[:ctx].inbox)
  end

  test 'add post body from room' do
    login('user1')
    @ff.expects(:get_room_profile).with('user1', nil, 'room1').
      returns(read_profile('room_profile')).
      times(4) # for name, url, description, and members.
    @ff.expects(:get_room_picture_url).with('room1', 'small').
      returns('http://room1/').times(1)
    @ff.expects(:get_room_entries).
      with('user1', nil, 'room1', {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(1)
    get :list, :room => 'room1'
    assert_response :success
    assert(session[:ctx].room)
    #
    @ff.expects(:post).with('user1', nil, 'hello', nil, nil, nil, nil, 'room1').
      returns([{'id' => 'foo'}])
    post :add, :commit => 'post', :body => 'hello', :room => 'room1'
    assert_redirected_to :action => 'list'
    assert(session[:ctx].room)
  end

  test 'add post body from list' do
    login('user1')
    @ff.expects(:get_list_entries).
      with('user1', nil, 'list1', {:service => nil, :num => 20, :start => 0}).
      returns(read_entries('entries', 'f2ptest')).times(1)
    get :list, :list => 'list1'
    assert_response :success
    assert(session[:ctx].list)
    #
    @ff.expects(:post).with('user1', nil, 'hello', nil, nil, nil, nil, nil).
      returns([{'id' => 'foo'}])
    post :add, :commit => 'post', :body => 'hello'
    assert_redirected_to :action => 'list'
    assert(!session[:ctx].list)
  end

  test 'add post link' do
    login('user1')
    h = mock('http_client')
    ApplicationController.http_client = h
    h.expects(:get_content).with('http://foo/').yields(NKF.nkf('-sm0', '<title>日本語</title>'))
    @ff.expects(:post).with('user1', nil, '日本語', 'http://foo/', 'hello', nil, nil, nil).
      returns([{'id' => 'foo'}])
    post :add, :commit => 'post', :body => 'hello', :link => 'http://foo/'
    assert_redirected_to :action => 'list'
  end

  test 'add post link capture failure' do
    login('user1')
    h = mock('http_client')
    ApplicationController.http_client = h
    h.expects(:get_content).with('http://foo/').raises(RuntimeError.new)
    @ff.expects(:post).with('user1', nil, '(unknown)', 'http://foo/', 'hello', nil, nil, nil).
      returns([{'id' => 'foo'}])
    post :add, :commit => 'post', :body => 'hello', :link => 'http://foo/'
    assert_redirected_to :action => 'list'
  end

  test 'add post file' do
    login('user1')
    file = ActionController::TestUploadedFile.new(__FILE__, 'image/png')
    @ff.expects(:post).with('user1', nil, 'hello', nil, nil, nil, [[file]], nil).
      returns([{'id' => 'foo'}])
    post :add, :commit => 'post', :body => 'hello', :file => file
    assert_redirected_to :action => 'list'
    # not an image
    file = ActionController::TestUploadedFile.new(__FILE__, 'text/html')
    post :add, :commit => 'post', :body => 'hello', :file => file
    assert_response :success
  end

  test 'add post location' do
    login('user1')
    file = ActionController::TestUploadedFile.new(__FILE__, 'image/png')
    @ff.expects(:post).
      with('user1', nil,
           'hello ([map] 日本、東京駅)',
           'http://maps.google.com/maps?q=35.681382,139.766084+%28%E6%97%A5%E6%9C%AC%E3%80%81%E6%9D%B1%E4%BA%AC%E9%A7%85%29',
           nil,
           [['http://maps.google.com/staticmap?zoom=14&size=160x80&maptype=mobile&markers=35.681382,139.766084', 'http://maps.google.com/maps?q=35.681382,139.766084+%28%E6%97%A5%E6%9C%AC%E3%80%81%E6%9D%B1%E4%BA%AC%E9%A7%85%29']],
           nil, nil).
      returns([{'id' => 'foo'}])
    post :add,
      :commit => 'post',
      :body => 'hello',
      :lat => '35.681382', :long => '139.766084', :address => '日本、東京駅',
      :zoom => 14
    assert_redirected_to :action => 'list'
  end

  test 'delete' do
    login('user1')
    @ff.expects(:delete).with('user1', nil, 'df9d34df-23ff-de8e-3675-a82736ef90cc', false)
    get :delete, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    assert_redirected_to :action => 'inbox'
    # post not allowed
    post :delete, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    assert_redirected_to :action => 'inbox'
  end

  test 'delete comment' do
    login('user1')
    @ff.expects(:delete_comment).with('user1', nil, 'df9d34df-23ff-de8e-3675-a82736ef90cc', 'foo', false)
    get :delete, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc', :comment => 'foo'
    assert_redirected_to :action => 'inbox'
    # post not allowed
    post :delete, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    assert_redirected_to :action => 'inbox'
  end

  test 'delete redirect back' do
    login('user1')
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest')).times(1)
    get :list, :num => 20, :start => 20
    assert_response :success
    assert_equal(20, session[:ctx].start)
    #
    # redirect back
    #
    @ff.expects(:delete).with('user1', nil, 'df9d34df-23ff-de8e-3675-a82736ef90cc', false)
    get :delete, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    # back to list, not inbox
    assert_redirected_to :action => 'list'
    assert_equal(20, session[:ctx].start)
    #
    # no reset pagination
    #
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest')).times(1)
    get :list
    assert_response :success
    assert_equal(20, session[:ctx].start)
  end

  test 'undelete' do
    login('user1')
    @ff.expects(:delete).with('user1', nil, 'df9d34df-23ff-de8e-3675-a82736ef90cc', true)
    get :undelete, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    assert_redirected_to :action => 'inbox'
    # post not allowed
    post :undelete, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc'
    assert_redirected_to :action => 'inbox'
    @ff.expects(:get_home_entries).
      returns(read_entries('entries', 'f2ptest')).times(1)
    get :list
    assert_response :success
  end

  test 'undelete comment' do
    login('user1')
    @ff.expects(:delete_comment).with('user1', nil, 'df9d34df-23ff-de8e-3675-a82736ef90cc', 'foo', true)
    get :undelete, :id => 'df9d34df-23ff-de8e-3675-a82736ef90cc', :comment => 'foo'
    assert_redirected_to :action => 'inbox'
  end

  test 'add_comment' do
    login('user1')
    @ff.expects(:post_comment).with('user1', nil, 'id', 'body')
    post :add_comment, :id => 'id', :body => 'body'
    assert_redirected_to :action => 'inbox'
  end

  test 'add_comment empty' do
    login('user1')
    post :add_comment, :id => 'id'
    assert_redirected_to :action => 'inbox'
  end

  test 'add_comment edit' do
    login('user1')
    @ff.expects(:post_comment).with('user1', nil, 'id', 'body')
    post :add_comment, :id => 'id', :body => 'body'
    assert_redirected_to :action => 'inbox'
    #
    @ff.expects(:edit_comment).with('user1', nil, 'id', 'comment', 'body').
      returns('id' => 'id')
    post :add_comment, :id => 'id', :comment => 'comment', :body => 'body'
    assert_redirected_to :action => 'inbox'
  end

  test 'like' do
    login('user1')
    @ff.expects(:like).with('user1', nil, 'id')
    get :like, :id => 'id'
    assert_redirected_to :action => 'inbox'
    post :like, :id => 'id'
    assert_redirected_to :action => 'inbox'
  end

  test 'unlike' do
    login('user1')
    @ff.expects(:unlike).with('user1', nil, 'id')
    get :unlike, :id => 'id'
    assert_redirected_to :action => 'inbox'
    post :unlike, :id => 'id'
    assert_redirected_to :action => 'inbox'
  end

  test 'pin' do
    login('user1')
    get :pin, :id => 'id'
    assert_redirected_to :action => 'inbox'
  end

  test 'pin clear checked' do
    login('user1')
    entries = read_entries('entries', 'f2ptest')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    @ff.expects(:get_home_entries).
      returns(entries).times(1)
    get :inbox
    assert_response :success
    assert(session[:checked])
    # commit checked to DB
    post :archive
    assert_redirected_to :action => 'inbox'
    # clear
    get :pin, :id => entries.first['id']
    assert_redirected_to :action => 'inbox'
  end

  test 'unpin' do
    login('user1')
    get :unpin, :id => 'id'
    assert_redirected_to :action => 'inbox'
  end

  test 'unpin commit checked' do
    login('user1')
    entries = read_entries('entries', 'f2ptest')
    @ff.expects(:get_profile).
      returns(read_profile('profile')).times(1)
    @ff.expects(:get_home_entries).
      returns(entries).times(1)
    get :inbox
    assert_response :success
    assert(session[:checked])
    #
    get :unpin, :id => entries.first['id']
    assert_redirected_to :action => 'inbox'
  end
end

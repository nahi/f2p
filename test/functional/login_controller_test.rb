require 'test_helper'

class LoginControllerTest < ActionController::TestCase
  def setup
    super
    @ff = mock('ff_client')
    ApplicationController.ff_client = @ff
    @ff.stubs(:purge_cache)
  end

  test 'index' do
    get :index
    assert_response :success
  end

  test 'index after login' do
    user = User.find_by_name('user1')
    User.expects(:validate).with('user1', 'key1').returns(user)
    post :authenticate, :name => 'user1', :remote_key => 'key1'
    assert_redirected_to :controller => 'entry'
    get :index
    assert_redirected_to :controller => 'entry'
  end

  test 'authenticate success' do
    user = User.find_by_name('user1')
    User.expects(:validate).with('user1', 'key1').returns(user)
    post :authenticate, :name => 'user1', :remote_key => 'key1'
    assert_redirected_to :controller => 'entry'
  end

  test 'authenticate success redirect' do
    user = User.find_by_name('user1')
    User.expects(:validate).with('user1', 'key1').returns(user)
    session[:redirect_to_after_authenticate] = {:controller => 'setting', :action => 'index'}
    post :authenticate, :name => 'user1', :remote_key => 'key1'
    assert_redirected_to :controller => 'setting', :action => 'index'
  end

  test 'authenticate failure' do
    User.expects(:validate).with('user1', 'key1').returns(nil)
    post :authenticate, :name => 'user1', :remote_key => 'key1'
    assert_redirected_to :action => 'index'
  end

  test 'logout' do
    user = User.find_by_name('user1')
    User.expects(:validate).with('user1', 'key1').returns(user)
    post :authenticate, :name => 'user1', :remote_key => 'key1'
    assert_redirected_to :controller => 'entry'
    get :clear
    assert_redirected_to :action => 'index'
  end

  test 'logout without login' do
    get :clear
    assert_redirected_to :action => 'index'
  end
end

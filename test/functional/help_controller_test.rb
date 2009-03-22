require 'test_helper'

class HelpControllerTest < ActionController::TestCase
  test "index without login" do
    get :index
    assert_redirected_to :controller => 'login', :action => 'index'
  end

  test "index" do
    login('user1')
    get :index
    assert_response :success
  end
end

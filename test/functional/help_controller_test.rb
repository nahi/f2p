require 'test_helper'

class HelpControllerTest < ActionController::TestCase
  test "index without login" do
    get :index
    # allowed
    assert_response :success
  end

  test "index" do
    login('user1')
    get :index
    assert_response :success
  end
end

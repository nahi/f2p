class HelpController < ApplicationController
  after_filter :strip_heading_spaces
  after_filter :compress

  def index
    @setting = session[:setting] ||= Setting.new
  end
end

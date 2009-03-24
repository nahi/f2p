class HelpController < ApplicationController
  after_filter :strip_heading_spaces
  after_filter :compress
  trans_sid

  def index
    @setting = Setting.new
  end
end

class SettingController < ApplicationController
  before_filter :login_required
  after_filter :strip_heading_spaces
  after_filter :compress

  def index
    @font_size = param(:font_size) || @auth.profile.font_size
    @entries_in_page = param(:entries_in_page) || @auth.profile.entries_in_page
    @text_folding_size = param(:text_folding_size) || @auth.profile.text_folding_size
  end

  def update
    updated = false
    if param(:font_size)
      @auth.profile.font_size = param(:font_size)
      updated = true
    end
    if param(:entries_in_page)
      @auth.profile.entries_in_page = param(:entries_in_page)
      updated = true
    end
    if param(:text_folding_size)
      @auth.profile.text_folding_size = param(:text_folding_size)
      updated = true
    end
    if updated
      @auth.profile.save
    end
    flash[:message] = 'Settings updated.'
    redirect_to :controller => 'entry', :action => 'list'
  end
end

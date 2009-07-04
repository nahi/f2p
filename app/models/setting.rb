class Setting
  attr_accessor :font_size
  attr_accessor :entries_in_page
  attr_accessor :entries_in_thread
  attr_accessor :text_folding_size
  attr_accessor :link_open_new_window
  attr_accessor :link_type
  attr_accessor :list_view_media_rendering
  attr_accessor :twitter_comment_hack
  attr_accessor :google_maps_geocoding_lang
  attr_accessor :google_maps_zoom
  attr_accessor :list_view_profile_picture
  attr_accessor :disable_status_icon

  def initialize
    super
    @font_size = F2P::Config.font_size
    @entries_in_page = F2P::Config.entries_in_page
    @entries_in_thread = F2P::Config.entries_in_thread
    @text_folding_size = F2P::Config.text_folding_size
    @link_open_new_window = F2P::Config.link_open_new_window
    @link_type = F2P::Config.link_type
    @list_view_media_rendering = F2P::Config.list_view_media_rendering
    @twitter_comment_hack = F2P::Config.twitter_comment_hack
    @google_maps_geocoding_lang = F2P::Config.google_maps_geocoding_lang
    @google_maps_zoom = F2P::Config.google_maps_zoom
    @list_view_profile_picture = F2P::Config.list_view_profile_picture
    @disable_status_icon = F2P::Config.disable_status_icon
  end

  def validate
    errors = []
    if @font_size < 6
      errors << 'font size must be greater than 6'
    end
    unless (5..100) === @entries_in_page
      errors << 'entries in page must be in 5..100'
    end
    unless (0..100) === @entries_in_thread
      errors << 'entries in thread must be in 0..100'
    end
    unless (20..1000) === @text_folding_size
      errors << 'text folding size must be in 20..1000'
    end
    unless (0..19) === @google_maps_zoom
      errors << 'zoom must be in 0..19'
    end
    errors.empty? ? nil : errors
  end
end

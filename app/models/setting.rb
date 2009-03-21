class Setting
  MOBILE_GPS_TYPE = ['ezweb','gpsone','DoCoMoFOMA', 'DoCoMomova','SoftBank3G', 'SoftBankold','WILLCOM']

  attr_accessor :font_size
  attr_accessor :entries_in_page
  attr_accessor :entries_in_thread
  attr_accessor :text_folding_size
  attr_accessor :link_open_new_window
  attr_accessor :link_type
  attr_accessor :list_view_media_rendering
  attr_accessor :twitter_comment_hack
  attr_accessor :mobile_gps_type
  attr_accessor :google_maps_geocoding_lang

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
    @mobile_gps_type = F2P::Config.mobile_gps_type
    @google_maps_geocoding_lang = F2P::Config.google_maps_geocoding_lang
  end

  def validate
    errors = []
    if @font_size < 6
      errors << 'font size must be greater than 6'
    end
    unless (5..100) === @entries_in_page
      errors << 'entries in page must be in 5..100'
    end
    unless (3..100) === @entries_in_thread
      errors << 'entries in thread must be in 3..100'
    end
    unless (20..1000) === @text_folding_size
      errors << 'text folding size must be in 20..1000'
    end
    if @mobile_gps_type
      unless MOBILE_GPS_TYPE.include?(@mobile_gps_type)
        errors << 'gps type shall be one of ' + MOBILE_GPS_TYPE.join(', ')
      end
    end
    errors.empty? ? nil : errors
  end
end

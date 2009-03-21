module SettingHelper
  def viewname
    'session settings'
  end

  def gps_info_select_tag(varname, default)
    candidates = Setting::MOBILE_GPS_TYPE.map { |e| [e, e] }
    candidates.unshift(['None', nil])
    select_tag(varname, options_for_select(candidates, default))
  end
end

require 'geoip'
require 'tzinfo'

class GeoCity
  GEO_CITY_DAT_FILE = File.expand_path('GeoLiteCity.dat', File.dirname(__FILE__))

  def initialize
    if File.exist?(GEO_CITY_DAT_FILE)
      @geoip = GeoIP.new(GEO_CITY_DAT_FILE)
    end
  end

  def ip2tz(ip)
    return nil unless @geoip
    begin
      ary = @geoip.city(ip)
      country = ary[2]
      if country != '--'
        if zones = TZInfo::Country.get(country).zones
          if zones.size > 1
            city = ary[7]
            zone = zones.find { |z| z.name.rindex(city) }
          end
          zone ||= zones.first
        end
        if zone
          zone.name
        end
      end
    rescue
      nil
    end
  end
end

require 'geoip'
require 'tzinfo'

class GeoCity
  # You need to download GeoLiteCity.dat.gz from here:
  # http://www.maxmind.com/app/geolitecity
  #   link: 'Download the latest GeoLite City Binary Format'
  # CAUTION: You need to follow GeoCity Lite license.
  #          Please read the page carefully.
  GEO_CITY_DAT_FILE =
    File.expand_path('GeoLiteCity.dat', File.dirname(__FILE__))

  def initialize
    if File.exist?(GEO_CITY_DAT_FILE)
      @geoip = GeoIP.new(GEO_CITY_DAT_FILE)
    end
  end

  # Convert IPaddr String to TimeZone name.
  # CAUTION: For getting tz name of ActiveResource::TimeZone::ZONES, you need
  # to map the name with ActiveResource::TimeZone::MAPPING.
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

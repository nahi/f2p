require 'xsd/datatypes'


module LoginHelper
  include XSD::XSDDateTimeImpl

  def timezone_select_tag(varname, default)
    candidates = ActiveSupport::TimeZone::ZONES.sort { |a, b|
      a.utc_offset <=> b.utc_offset
    }.map { |z|
      tz = z.utc_offset
      zone = of2tz(tz / 86400.0).sub('Z', '+00:00')
      name = "(#{zone}) " + z.name
      [name, z.name]
    }
    select_tag(varname, options_for_select(candidates, default))
  end
end

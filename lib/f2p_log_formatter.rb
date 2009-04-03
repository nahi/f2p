class F2pLogFormatter
  def call(severity, datetime, progname, msg)
    sv = severity[0, 1] + ','
    dt = datetime.strftime("[%H:%M:%S.") + "%03d] " % (datetime.usec / 1000)
    str = msg2str(msg)
    [sv, dt, str, "\n"].join
  end

private

  def msg2str(msg)
    case msg
    when ::String
      msg.strip
    when ::Exception
      "#{ msg.message } (#{ msg.class })\n" <<
        (msg.backtrace || []).join("\n")
    else
      msg.inspect
    end
  end
end

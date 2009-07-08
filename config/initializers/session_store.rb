# This code is from http://znz.s1.xrea.com/t/?date=20090707#p01 by znz.
# avoid Rails 2.3.2 sessions problem of active record
require "active_record/session_store"
module ActiveRecord #:nodoc:
  class SessionStore #:nodoc:
    private
    def set_session(env, sid, session_data)
      Base.silence do
        record = get_session_model(env, sid) # monky patched
        record.data = session_data
        return false unless record.save

        session_data = record.data
        if session_data && session_data.respond_to?(:each_value)
          session_data.each_value do |obj|
            obj.clear_association_cache if obj.respond_to?(:clear_association_cache)
          end
        end
      end

      return true
    end

    # added for monkey patching for set_session
    def get_session_model(env, sid)
      if env[ENV_SESSION_OPTIONS_KEY][:id].nil?
        env[SESSION_RECORD_KEY] = find_session(sid)
      else
        env[SESSION_RECORD_KEY] ||= find_session(sid)
      end
    end
  end
end

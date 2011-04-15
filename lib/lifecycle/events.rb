gem 'trinidad_jars'
require 'trinidad/jars'
require 'logger'

module Trinidad::Lifecycle::WebApp
  class ShowEventsListener
    include Trinidad::Tomcat::LifecycleListener

    def lifecycle_event(event)
      File.open("/tmp/lifecycle_event.log", "wb") do |file|
        logger = Logger.new(file)
        logger.info "*** INFO: Firing event: #{event.type.to_s} - #{event}"
        logger.info "data: #{event.data}"
        logger.info "source: #{event.source}"
      end
    end
  end
end

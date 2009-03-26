# Settings specified here will take precedence over those in config/environment.rb

# The production environment is meant for finished, "live" apps.
# Code is not reloaded between requests
config.cache_classes = true

# Enable threaded mode
config.threadsafe!

# Use a different logger for distributed setups
# config.logger = SyslogLogger.new
class F2pLogFormatter
  def call(severity, datetime, progname, msg)
    datetime.strftime("#{severity[0, 1]},[%H:%M:%S.") +
      "%06d] #{msg}\n" % datetime.usec
  end
end
config.logger = Logger.new(config.log_path, 'daily')
config.logger.level = Logger::INFO
config.logger.formatter = F2pLogFormatter.new

# Full error reports are disabled and caching is turned on
config.action_controller.consider_all_requests_local = false
config.action_controller.perform_caching             = true

# Use a different cache store in production
# config.cache_store = :mem_cache_store

# Enable serving of images, stylesheets, and javascripts from an asset server
# config.action_controller.asset_host                  = "http://assets.example.com"

# Disable delivery errors, bad email addresses will be ignored
# config.action_mailer.raise_delivery_errors = false

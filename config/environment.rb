# Be sure to restart your server when you modify this file

# Uncomment below to force Rails into production mode when
# you don't control web/app server and can't set it the proper way
# ENV['RAILS_ENV'] ||= 'production'

# Specifies gem version of Rails to use when vendor/rails is not present
RAILS_GEM_VERSION = '2.2.2' unless defined? RAILS_GEM_VERSION

# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')

module F2P
  module Config
    class << self
      attr_accessor :encryption_key
      attr_accessor :cipher_algorithm
      attr_accessor :cipher_block_size
      attr_accessor :google_maps_api_key

      attr_accessor :google_maps_maptype
      attr_accessor :google_maps_zoom
      attr_accessor :google_maps_width
      attr_accessor :google_maps_height

      attr_accessor :font_size
      attr_accessor :entries_in_page
      attr_accessor :text_folding_size
      attr_accessor :entries_in_thread
      attr_accessor :likes_in_page
      attr_accessor :service_grouping_threashold
    end
  end
end

Rails::Initializer.run do |config|
  # Settings in config/environments/* take precedence over those specified here.
  # Application configuration should go into files in config/initializers
  # -- all .rb files in that directory are automatically loaded.
  # See Rails::Configuration for more options.

  # Skip frameworks you're not going to use. To use Rails without a database
  # you must remove the Active Record framework.
  # config.frameworks -= [ :active_record, :active_resource, :action_mailer ]

  # Specify gems that this application depends on. 
  # They can then be installed with "rake gems:install" on new installations.
  # You have to specify the :lib option for libraries, where the Gem name (sqlite3-ruby) differs from the file itself (sqlite3)
  # config.gem "bj"
  # config.gem "hpricot", :version => '0.6', :source => "http://code.whytheluckystiff.net"
  # config.gem "sqlite3-ruby", :lib => "sqlite3"
  # config.gem "aws-s3", :lib => "aws/s3"
  #config.gem 'httpclient'
  config.gem 'json'

  # Only load the plugins named here, in the order given. By default, all plugins 
  # in vendor/plugins are loaded in alphabetical order.
  # :all can be used as a placeholder for all plugins not explicitly named
  # config.plugins = [ :exception_notification, :ssl_requirement, :all ]

  # Add additional load paths for your own custom dirs
  # config.load_paths += %W( #{RAILS_ROOT}/extras )

  # Force all environments to use the same logger level
  # (by default production uses :info, the others :debug)
  # config.log_level = :debug

  # Make Time.zone default to the specified zone, and make Active Record store time values
  # in the database in UTC, and return them converted to the specified local zone.
  # Run "rake -D time" for a list of tasks for finding time zone names. Comment line to use default local time.
  config.time_zone = 'UTC'

  # The internationalization framework can be changed to have another default locale (standard is :en) or more load paths.
  # All files from config/locales/*.rb,yml are added automatically.
  # config.i18n.load_path << Dir[File.join(RAILS_ROOT, 'my', 'locales', '*.{rb,yml}')]
  # config.i18n.default_locale = :de

  # Your secret key for verifying cookie session data integrity.
  # If you change this key, all old sessions will become invalid!
  # Make sure the secret is at least 30 characters and all random, 
  # no regular words or you'll be exposed to dictionary attacks.
  config.action_controller.session = {
    :session_key => '_ff1_session',
    :secret      => 'cb8724bb405f34efcaea391cce2380850d80455f8d01de24a0d385a2452a8772ec7a71d765c85c321d17a1f6705d9cfc642c62c39b9be9594f05b49e8e22e6ae'
  }

  # Use the database for sessions instead of the cookie-based default,
  # which shouldn't be used to store highly confidential information
  # (create the session table with "rake db:sessions:create")
  # config.action_controller.session_store = :active_record_store

  # Use SQL instead of Active Record's schema dumper when creating the test database.
  # This is necessary if your schema can't be completely dumped by the schema dumper,
  # like if you have constraints or database-specific column types
  # config.active_record.schema_format = :sql

  # Activate observers that should always be running
  # Please note that observers generated using script/generate observer need to have an _observer suffix
  # config.active_record.observers = :cacher, :garbage_collector, :forum_observer

  F2P::Config.cipher_algorithm = 'AES-256-CBC'
  F2P::Config.cipher_block_size = 16 # must match with above alg.
  F2P::Config.encryption_key = "]\023\312\203}\271i\244X\002\374O\241\221/\323\277\005\323HN\216\021\253\320W\314S\206m\a\221"
  F2P::Config.google_maps_api_key = ''

  F2P::Config.google_maps_maptype = 'mobile'
  F2P::Config.google_maps_zoom = 13
  F2P::Config.google_maps_width = 160
  F2P::Config.google_maps_height = 80

  F2P::Config.font_size = 9
  F2P::Config.entries_in_page = 20
  F2P::Config.text_folding_size = 140
  F2P::Config.entries_in_thread = 4
  F2P::Config.likes_in_page = 3
  F2P::Config.service_grouping_threashold = 1.5.hour
end

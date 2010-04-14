require 'ff'
require 'fileutils'
require 'time'
require 'httpclient'
require 'logger'
load File.expand_path('export_setting.rb', File.dirname(__FILE__))


class Fetcher
  include ExportSetting

  attr_accessor :logger
  attr_reader :ff_client

  def initialize
    @ff_client = FriendFeed::APIV2Client.new
    @asset_client = HTTPClient.new
    @logger = Logger.new(STDERR)
  end

  def download(url)
    if /i.friendfeed.com\/(.+)$/ =~ url
      name = $1
    elsif /friendfeed-media.com\/(.+)$/ =~ url
      name = $1
    else
      return
    end
    asset_dir = File.join(@json_dir, ASSET_DIR_NAME)
    FileUtils.mkdir_p(asset_dir)
    file = File.join(asset_dir, name)
    return if File.exist?(file)
    5.times do
      begin
        File.open(file, 'wb') do |f|
          @asset_client.get(url) do |str|
            f << str
          end
        end
        @logger.info "downloaded #{url}"
        return
      rescue
        @logger.warn $!
        sleep 2
      end
    end
    @logger.warn "download failed: #{url}"
  end

  def run(feedname, auth, opt = {})
    @feedname = feedname
    @auth = auth
    @start = opt[:start] || 0
    @json_dir = File.join(JSON_DIR, @feedname)
    @logger.info 'start'
    start = @start
    counter = 0
    while true
      @logger.info "fetching #{start}-#{start + FETCH_SIZE} ... "
      newitems = 0
      json = nil
      5.times do
        begin
          opt = @auth.merge(
            :raw => 1,
            :fof => 1,
            :start => start,
            :num => FETCH_SIZE
          )
          json = @ff_client.feed(@feedname, opt)
          break
        rescue
          @logger.warn $!
          sleep 2
        end
      end
      if json
        if entries = json["entries"]
          entries.each do |entry|
            id = entry["id"].sub(/^e\//, '')
            date = Time.parse(entry["date"]).localtime # TODO tz?
            subdir = sprintf("%04d%02d", date.year, date.month)
            file = sprintf("%02d_%02d:%02d:%02d-%s", date.day, date.hour, date.min, date.sec, id[0, 6] + '.json')
            FileUtils.mkdir_p(File.join(@json_dir, subdir))
            path = File.join(@json_dir, subdir, file)
            unless File.exist?(path)
              newitems += 1
            end
            File.open(path, 'wb') do |f|
              f << JSON.pretty_generate(entry)
            end
            if thumbnails = entry["thumbnails"]
              thumbnails.each do |tb|
                if url = tb["url"]
                  download(url)
                end
                if url = tb["link"]
                  download(url)
                end
              end
            end
          end
        end
      end
      @logger.info "found #{newitems} new items"
      if newitems == 0
        @logger.info "no new items"
        counter += 1
        if counter > 2
          @logger.info "finishing..."
          break
        end
      else
        counter = 0
      end
      start += FETCH_SIZE
    end
  end
end

if $0 == __FILE__
  ENV['RAILS_ENV'] ||= 'production'

  load(File.expand_path('../config/environment.rb', File.dirname(__FILE__)))

  name = ARGV.shift or raise
  feedname = ARGV.shift or raise
  start = (ARGV.shift || '0').to_i

  fetcher = Fetcher.new
  client = fetcher.ff_client
  client.oauth_consumer_key = F2P::Config.friendfeed_api_oauth_consumer_key
  client.oauth_consumer_secret = F2P::Config.friendfeed_api_oauth_consumer_secret
  client.oauth_site = F2P::Config.friendfeed_api_oauth_site
  client.oauth_scheme = F2P::Config.friendfeed_api_oauth_scheme
  client.oauth_signature_method = F2P::Config.friendfeed_api_oauth_signature_method

  user = User.find_by_name(name)
  raise "No such user: #{name}" unless user

  oauth_token = user.oauth_access_token
  oauth_token_secret = user.oauth_access_token_secret
  remote_key = user.remote_key

  if oauth_token and oauth_token_secret
    auth = {
      :oauth_token => oauth_token,
      :oauth_token_secret => oauth_token_secret
    }
  elsif remote_key
    auth = {
      :name => name,
      :remote_key => remote_key
    }
  else
    raise "User not authenticated: #{name}"
  end

  fetcher.run(feedname, auth, :start => start)
end

require 'ff'
require 'fileutils'
require 'time'
require 'httpclient'
require 'logger'
load File.expand_path('export_setting.rb', File.dirname(__FILE__))


class Fetcher
  include ExportSetting

  attr_accessor :logger

  def initialize(feedname, auth_hash, opt = {})
    @feedname = feedname
    @auth_hash = auth_hash
    @ff_client = FriendFeed::APIV2Client.new
    @asset_client = HTTPClient.new
    @json_dir = File.join(JSON_DIR, @feedname)
    @logger = Logger.new(STDERR)
    @start = opt[:start] || 0
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

  def run
    @logger.info 'start'
    start = @start
    counter = 0
    while true
      @logger.info "fetching #{start}-#{start + FETCH_SIZE} ... "
      newitems = 0
      json = nil
      5.times do
        begin
          opt = @auth_hash.merge(
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
  feedname = ARGV.shift or raise
  name = ARGV.shift or raise
  remote_key = ARGV.shift or raise
  start = (ARGV.shift || '0').to_i
  Fetcher.new(feedname, {:name => name, :remote_key => remote_key}, :start => start).run
end

require 'ff'
require 'fileutils'
require 'time'
require 'httpclient'

name = ARGV.shift or raise
remote_key = ARGV.shift or raise
client = FriendFeed::APIV2Client.new
$asset_client = HTTPClient.new

DIR = './items'
FileUtils.mkdir_p(DIR)
ASSET_DIR = File.join(DIR, 'asset')
FileUtils.mkdir_p(ASSET_DIR)

def download(url)
  if /i.friendfeed.com\/(.+)$/ =~ url
    name = $1
  elsif /friendfeed-media.com\/(.+)$/ =~ url
    name = $1
  else
    return
  end
  file = File.join(ASSET_DIR, name)
  File.open(file, 'wb') do |f|
    $asset_client.get(url) do |str|
      f << str
    end
  end
  print "downloaded #{url}"
end

puts 'start'
start = 0
while true
  print "fetching #{start}-#{start + 100} ... "
  newitems = 0
  json = client.feed(name, :name => name, :remote_key => remote_key, :raw => 1, :fof => 1, :start => start, :num => 100)
  if json
    if entries = json["entries"]
      entries.each do |entry|
        id = entry["id"].sub(/^e\//, '')
        date = Time.parse(entry["date"])
        subdir = sprintf("%04d%02d", date.year, date.month)
        file = sprintf("%02d_%02d:%02d:%02d-%s", date.day, date.hour, date.min, date.sec, id[0, 6] + '.json')
        FileUtils.mkdir_p(File.join(DIR, subdir))
        path = File.join(DIR, subdir, file)
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
  puts "found #{newitems} new items"
  if newitems == 0
    puts "no new items"
    break
  end
  start += 100
end

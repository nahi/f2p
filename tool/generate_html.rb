require 'fileutils'
require 'erb'
require 'json'
require 'time'
require 'google_maps'
require 'haml'

JSON_DIR = './items'
HTML_DIR = './html'
GOOGLE_MAPS_API_KEY = 'ABQIAAAAyJ3h_wiYLDPpdO_ANIzdMBSjznBtxftpWAhkZA1dGfh4MDNCNBQQ0kiCAFHBsdd9AgMU0-oblibXjg'

title = ARGV.shift or raise

FileUtils.mkdir_p(HTML_DIR)

template = DATA.read
$generator = GoogleMaps::URLGenerator.new(GOOGLE_MAPS_API_KEY)

def link_to(url)
  if /i.friendfeed.com\/(.+)$/ =~ url
    name = $1
  elsif /friendfeed-media.com\/(.+)$/ =~ url
    name = $1
  else
    return url
  end
  "asset/#{name}"
end

def map_url(lat, long)
  $generator.staticmap_url('mobile', lat, long, :zoom => 12, :width => 175, :height => 120)
end

def maplink_url(lat, long, body)
  $generator.link_url(lat, long, body)
end

YEAR_THRESHOLD = 60 * 60 * 24 * (365 - 2)
DATE_THRESHOLD = 60 * 60 * (24 - 8)

def date(time, base = 0)
  elapsed = time - base
  format = nil
  if elapsed.to_i > YEAR_THRESHOLD
    format = "(%y/%m/%d)"
  elsif elapsed.to_i > DATE_THRESHOLD
    format = "(%m/%d)"
  else
    format = "(%H:%M)"
  end
  time.strftime(format)
end

Dir.open(JSON_DIR).each do |json_dir|
  next unless /\d{6}/ =~ json_dir
  entries = {}
  Dir.open(File.join(JSON_DIR, json_dir)).each do |file|
    next unless /.json\z/ =~ file
    path = File.join(JSON_DIR, json_dir, file)
    begin
      entry = JSON.parse(File.read(path))
      entry["date"] = Time.parse(entry["date"]).localtime # TODO tz?
      # TODO: temporarily excludes Buzz for NaHi
      if /\ABuzz by / !~ entry["body"]
        (entries[entry["date"].day] ||= []) << entry
      end
      (entry["comments"] ||= []).each do |c|
        c["date"] = Time.parse(c["date"]).localtime # TODO tz?
      end
    rescue
      puts "parse error: #{path}"
      nil
    end
  end
  html_dir = File.join(HTML_DIR, json_dir)
  haml = Haml::Engine.new(template)
  subject = json_dir.unpack("a4a2").join("-")
  locals = {
    :title => "#{title} (#{subject})",
    :entries => entries
  }
  File.open(File.join(HTML_DIR, json_dir + '.html'), 'wb') do |f|
    f << haml.render(Object.new, locals)
  end
end

__END__
!!! XHTML 1.0 Transitional
%html{:xmlns => "http://www.w3.org/1999/xhtml"}
%head
  %meta{'http-equiv' => 'Content-Type', :content => 'text/html; charset=UTF-8'}
  %title= title
  %link{:rel => 'stylesheet', :href => 'theme.css', :type => 'text/css'}
%body
  %h1
    %a{:name => 'top'}= title
  %p.index
    %a{:href => './'} ^
    - entries.keys.sort.each do |day|
      %a{:href => day}= day
  %hr
  - entries.keys.sort.each do |day|
    %div.day
      %h2.date
        %a{:name => day}
          = entries[day][0]["date"].strftime("%Y-%m-%d")
        %a{:href => '#top'} ^
      - entries[day].sort_by { |a| a["date"] }.each do |entry|
        %div.entry
          %p
            = entry["body"]
            - if thumbnails = entry["thumbnails"]
              %br
              - thumbnails.each do |tb|
                - src = tb["url"] || 175
                - height = tb["height"] || 175
                - width = tb["width"] || 525
                - if link = tb["link"]
                  %a{:href => link_to(link)}
                    %img.media(height=height width=width){:src => link_to(src)}
                - else
                  %img.media(height=height width=width){:src => link_to(src)}
            - if geo = entry["geo"]
              - lat = geo["lat"]
              - long = geo["long"]
              - unless thumbnails
                %br
              %a{:href => maplink_url(lat, long, entry["body"])}
                %img.media(height=120 width=175){:src => map_url(lat, long)}
            %span.from
              - if from = entry["from"]
                from
                = from["name"]
              - if via = entry["via"]
                via
                %a{:href => via["url"]}= via["name"]
              = (base = entry["date"]).strftime("(%H:%M:%S)")
          - unless entry["comments"].empty?
            %div.comments
              %ul
                - entry["comments"].each do |comment|
                  %li
                    = comment["body"]
                    by
                    = comment["from"]["name"]
                    = date(comment["date"], base)
  %p= title

require 'fileutils'
require 'json'
require 'time'
require 'google_maps'
require 'haml'
require 'logger'
load File.expand_path('export_setting.rb', File.dirname(__FILE__))


class HtmlGenerator
  include ExportSetting

  attr_accessor :logger

  TEMPLATE = <<__EOS__
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
      %a{:href => '#' + day}= day
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
                - src = tb["url"]
                - height, width = tb["height"], tb["width"]
                - style = 'max-width:525px;max-height:175px' if !height or !width
                - if link = tb["link"]
                  %a{:href => link_to(link)}
                    %img.media(height=height width=width style=style){:src => link_to(src)}
                - else
                  %img.media(height=height width=width style=style){:src => link_to(src)}
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
__EOS__

  CSS = <<__EOS__
img.media   {
  border: 1px solid #ccc;
  padding: 1px;
  vertical-align: text-top;
}
a img { border: none; }
p {
  margin-top: 1ex;
  margin-bottom: 1ex;
}
h2 {
  background-color: #ddf;
}
.entry {
  border-bottom: 1px solid #aaf;
}
.from, .comments { color: #666; }
__EOS__

  def initialize(feedname, title)
    @feedname = feedname
    @title = title
    @json_dir = File.join(JSON_DIR, @feedname)
    @html_dir = File.join(HTML_DIR, @feedname)
    @generator = GoogleMaps::URLGenerator.new(GOOGLE_MAPS_API_KEY)
    @logger = Logger.new(STDERR)
  end

  def link_to(url)
    if /i.friendfeed.com\/(.+)$/ =~ url
      name = $1
    elsif /friendfeed-media.com\/(.+)$/ =~ url
      name = $1
    else
      return url
    end
    [ASSET_DIR_NAME, name].join('/')
  end

  def map_url(lat, long)
    @generator.staticmap_url('mobile', lat, long, :zoom => 12, :width => 175, :height => 120)
  end

  def maplink_url(lat, long, body)
    @generator.link_url(lat, long, body)
  end

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

  def run
    Dir.foreach(@json_dir) do |dir|
      next unless /\d{6}/ =~ dir
      @logger.info "scanning #{dir}..."
      entries = {}
      Dir.foreach(File.join(@json_dir, dir)) do |file|
        next unless /.json\z/ =~ file
        path = File.join(@json_dir, dir, file)
        begin
          entry = JSON.parse(File.read(path))
          entry["date"] = Time.parse(entry["date"]).localtime # TODO tz?
          (entry["comments"] ||= []).each do |c|
            c["date"] = Time.parse(c["date"]).localtime # TODO tz?
          end
          (entries[entry["date"].day] ||= []) << entry
        rescue
          @logger.warn "parse error: #{path}"
          nil
        end
      end
      @logger.info "found #{entries.size} entries"
      html_dir = File.join(@html_dir, dir)
      haml = Haml::Engine.new(TEMPLATE)
      subject = dir.unpack("a4a2").join("-")
      locals = {
        :title => "#{@title} (#{subject})",
        :entries => entries
      }
      FileUtils.mkdir_p(@html_dir)
      html_path = File.join(@html_dir, dir + '.html')
      File.open(html_path, 'wb') do |f|
        f << haml.render(self, locals)
      end
      @logger.info "generated #{html_path}"
    end
    css_path = File.join(@html_dir, 'theme.css')
    File.open(css_path, 'wb') do |f|
      f << CSS
    end
    src = File.join(@json_dir, ASSET_DIR_NAME)
    dest = File.join(@html_dir, ASSET_DIR_NAME)
    if File.exist?(src)
      if File.exist?(dest)
        FileUtils.rm_r(dest)
      end
      FileUtils.cp_r(src, dest)
    end
  end
end


if $0 == __FILE__
  feedname = ARGV.shift or raise
  title = ARGV.shift or raise
  HtmlGenerator.new(feedname, title).run
end

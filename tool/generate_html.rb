require 'fileutils'
require 'erb'
require 'json'

JSON_DIR = './items'
HTML_DIR = './html'

FileUtils.mkdir_p(HTML_DIR)

template = DATA.read

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

Dir.open(JSON_DIR).each do |json_dir|
  next unless /\d{6}/ =~ json_dir
  entries = Dir[File.join(JSON_DIR, json_dir, '*')].sort.map { |path|
    begin
      entry = JSON.parse(File.read(path))
      if /\ABuzz by / !~ entry["body"]
        entry
      end
    rescue
      puts "parse error: #{path}"
      nil
    end
  }.compact
  html_dir = File.join(HTML_DIR, json_dir)
  erb = ERB.new(template)
  title = json_dir.unpack("a4a2").join("-")
  entry = nil
  File.open(File.join(HTML_DIR, json_dir + '.html'), 'wb') do |f|
    f << erb.result(binding)
  end
end

__END__
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"> 
<html xmlns="http://www.w3.org/1999/xhtml"> 
<head> 
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/> 
<title><%= title %></title>
</head>
<body>
<% entries.each do |entry| %>
  <div class="entry">
    <p>
      <%= entry["date"] %>
    </p>
    <p>
      <%= entry["body"] %>
      <% if thumbnails = entry["thumbnails"] %>
        <br />
        <% thumbnails.each do |tb| %>
          <% src = tb["url"] || 175 %>
          <% height = tb["height"] || 175 %>
          <% width = tb["width"] || 525 %>
          <% if link = tb["link"] %>
            <a href="<%= link_to(link) %>"><img src="<%= link_to(src) %>" height="<%= height %>" width="<%= width %>" /></a>
          <% else %>
            <img src="<%= link_to(src) %>" height="<%= height %>" width="<%= width %>" />
          <% end %>
        <% end %>
      <% end %>
      <% if from = entry["from"] %>
        from <%= from["name"] %>
      <% end %>
      <% if via = entry["via"] %>
        via <a href="<%= via["url"] %>"><%= via["name"] %></a>
      <% end %>
      <% if comments = entry["comments"] %>
        <div class="comments">
          <ul>
            <% comments.each do |comment| %>
              <li>
                <%= comment["date"] %> <%= comment["body"] %>
                by <%= comment["from"]["name"] %>
              </li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </p>
  </div>
  <hr />
<% end %>
</body>
</html>

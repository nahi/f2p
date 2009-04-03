require 'httpclient'
require 'fileutils'

httpclient = HTTPClient.new

dir = File.expand_path('icons', File.dirname(__FILE__))
FileUtils.mkdir_p(dir)

save_as = proc { |url, basename|
  filename = File.join(dir, basename + '.png')
  File.open(filename, 'wb') do |f|
      f.write(httpclient.get_content('http://friendfeed.com' + url))
  end
}

# internal.png is not listed on 'about' page.
save_as.call('/static/images/icons/internal.png', 'internal')

httpclient.get_content('http://friendfeed.com/about/') do |body|
  body.scan(%r[src="(/static/images/icons/([^/]+).png)]).each do |url, basename|
    save_as.call(url, basename)
  end
end

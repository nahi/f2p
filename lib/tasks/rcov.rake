begin
  require 'rcov/rcovtask'

  namespace :test do
    Rcov::RcovTask.new("coverage") do |rcov|
      rcov.libs << 'test'
      rcov.test_files = FileList['test/**/*_test.rb']
      rcov.verbose = true
      rcov.rcov_opts << '--rails' <<
        '-x' << File.expand_path('~/.gem') <<
        '-x' << 'lib'
    end
  end
rescue LoadError
end

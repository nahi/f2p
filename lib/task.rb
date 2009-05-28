require 'timeout'


class Task
  class << self
    def run(&block)
      new(&block)
    end
    private :new
  end

  attr_accessor :logger

  def initialize(logger = nil, &block)
    @logger = logger || ActiveRecord::Base.logger
    @result = nil
    @thread = Thread.new {
      @result = yield
    }
  end

  def result(timeout = F2P::Config.friendfeed_api_timeout)
    begin
      timeout(timeout) do
        @thread.join
        @result
      end
    rescue Timeout::Error => e
      logger.warn(e)
      @result = nil
    end
  end
end

module API
  def path(*args)
    args.compact.join('/')
  end

  def logger
    ActiveRecord::Base.logger
  end

  def protect(default = nil)
    begin
      yield
    rescue
      logger.error($!)
      default
    end
  end

  def with_perf(msg)
    logger.info(msg)
    begin
      start = Time.now
      yield
    rescue
      logger.warn($!)
      raise
    ensure
      logger.info("elapsed: #{((Time.now - start) * 1000).to_i}ms")
    end
  end
end

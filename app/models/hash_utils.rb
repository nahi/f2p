module HashUtils 
  module ClassModule
    def [](hash)
      new(hash) if hash
    end
  end

  def self.included(mod)
    mod.extend(ClassModule)
  end

  def initialize_with_hash(hash, *keys)
    keys.each do |key|
      instance_variable_set("@#{key}", hash[key])
    end
  end
end

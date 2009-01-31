require 'openssl'
require 'monitor'


module Encrypt
  def encrypt(key, *args)
    opt = args.last.is_a?(Hash) ? args.pop : {}
    algorithm = opt[:algorithm] || 'AES-256-CBC'
    block_size = opt[:block_size] || 16
    encrypter = Encrypter.new(algorithm, block_size, key, *args)
    before_save encrypter
    after_save encrypter
    after_find encrypter
    # placeholder
    define_method(:after_find) {}
  end
  module_function :encrypt

  class Encrypter
    def initialize(algorithm, block_size, key, *attrs)
      @algorithm = algorithm
      @block_size = block_size
      @key = key
      @attrs = attrs
    end

    def before_save(model)
      @attrs.each do |attr|
        model[attr] = pack(encrypt(model[attr]))
      end
    end

    def after_save(model)
      @attrs.each do |attr|
        model[attr] = decrypt(unpack(model[attr]))
      end
    end

    alias_method :after_find, :after_save

  private

    def pack(bytes)
      [bytes].pack('m*')
    end

    def unpack(packed)
      packed.unpack('m*')[0]
    end

    def encrypt(bytes)
      cipher = OpenSSL::Cipher::Cipher.new(@algorithm)
      iv = OpenSSL::Random.random_bytes(@block_size)
      cipher.encrypt
      cipher.key = @key
      cipher.iv = iv
      iv + cipher.update(bytes) + cipher.final
    end

    def decrypt(bytes)
      iv = bytes.slice!(0, @block_size)
      cipher = OpenSSL::Cipher::Cipher.new(@algorithm)
      cipher.decrypt
      cipher.key = @key
      cipher.iv = iv
      cipher.update(bytes) + cipher.final
    end
  end
end

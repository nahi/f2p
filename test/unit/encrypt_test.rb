require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'encrypt' do
    alg = 'AES-256-CBC'
    block_size = 16
    key = OpenSSL::Random.random_bytes(256/8)
    encrypter = Encrypt::Encrypter.new(alg, block_size, key, :foo, :bar)
    base = {
      :foo => '123',
      :bar => '456',
      :baz => '789'
    }
    encrypter.before_save(base)
    assert('123' != base[:foo])
    assert('456' != base[:bar])
    assert('789' == base[:baz])
    encrypter.after_find(base)
    assert('123' == base[:foo])
    assert('456' == base[:bar])
    assert('789' == base[:baz])
  end

  test 'alg' do
    alg = 'DES-EDE3'
    block_size = 8
    key = OpenSSL::Random.random_bytes(64*3/8)
    encrypter = Encrypt::Encrypter.new(alg, block_size, key, :foo, :bar)
    base = {
      :foo => '123',
      :bar => '456',
      :baz => '789'
    }
    encrypter.before_save(base)
    assert('123' != base[:foo])
    assert('456' != base[:bar])
    assert('789' == base[:baz])
    encrypter.after_find(base)
    assert('123' == base[:foo])
    assert('456' == base[:bar])
    assert('789' == base[:baz])
  end

  test 'iv' do
    alg = 'AES-256-CBC'
    block_size = 16
    key = OpenSSL::Random.random_bytes(256/8)
    encrypter = Encrypt::Encrypter.new(alg, block_size, key, :foo, :bar)
    base = {
      :foo => '123',
      :bar => '123'
    }
    encrypter.before_save(base)
    assert(base[:foo] != base[:bar])
    encrypter.after_find(base)
    assert(base[:foo] == base[:bar])
  end
end

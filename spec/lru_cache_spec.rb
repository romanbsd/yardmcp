# frozen_string_literal: true

require 'spec_helper'
require 'yardmcp/lru_cache'

RSpec.describe YardMCP::LRUCache do
  let(:cache) { described_class.new(capacity: 3, max_memory_mb: 1) }

  describe '#initialize' do
    it 'creates a cache with specified capacity' do
      expect(cache.capacity).to eq(3)
      expect(cache.max_memory_bytes).to eq(1024 * 1024)
    end
  end

  describe '#put and #get' do
    it 'stores and retrieves values' do
      cache.put('key1', 'value1')
      expect(cache.get('key1')).to eq('value1')
    end

    it 'returns nil for non-existent keys' do
      expect(cache.get('nonexistent')).to be_nil
    end

    it 'updates access order on get' do
      cache.put('key1', 'value1')
      cache.put('key2', 'value2')
      cache.put('key3', 'value3')

      # Access key1 to make it most recently used
      cache.get('key1')

      # Add a new key, which should evict key2 (LRU)
      cache.put('key4', 'value4')

      expect(cache.get('key1')).to eq('value1')
      expect(cache.get('key2')).to be_nil
      expect(cache.get('key3')).to eq('value3')
      expect(cache.get('key4')).to eq('value4')
    end
  end

  describe '#delete' do
    it 'removes a key from the cache' do
      cache.put('key1', 'value1')
      cache.delete('key1')
      expect(cache.get('key1')).to be_nil
    end
  end

  describe '#clear' do
    it 'removes all keys from the cache' do
      cache.put('key1', 'value1')
      cache.put('key2', 'value2')
      cache.clear

      expect(cache.size).to eq(0)
      expect(cache.get('key1')).to be_nil
      expect(cache.get('key2')).to be_nil
    end
  end

  describe '#size' do
    it 'returns the number of items in the cache' do
      expect(cache.size).to eq(0)

      cache.put('key1', 'value1')
      expect(cache.size).to eq(1)

      cache.put('key2', 'value2')
      expect(cache.size).to eq(2)
    end
  end

  describe '#stats' do
    it 'returns cache statistics' do
      cache.put('key1', 'value1')
      cache.put('key2', 'value2')

      stats = cache.stats

      expect(stats[:size]).to eq(2)
      expect(stats[:capacity]).to eq(3)
      expect(stats[:max_memory_mb]).to eq(1)
      expect(stats[:current_memory_mb]).to be >= 0
      expect(stats[:access_order]).to eq(%w[key1 key2])
    end
  end

  describe 'capacity eviction' do
    it 'evicts least recently used item when capacity is exceeded' do
      cache.put('key1', 'value1')
      cache.put('key2', 'value2')
      cache.put('key3', 'value3')

      # Cache is at capacity, adding another should evict key1
      cache.put('key4', 'value4')

      expect(cache.get('key1')).to be_nil
      expect(cache.get('key2')).to eq('value2')
      expect(cache.get('key3')).to eq('value3')
      expect(cache.get('key4')).to eq('value4')
    end

    it 'updates existing key without eviction' do
      cache.put('key1', 'value1')
      cache.put('key2', 'value2')
      cache.put('key3', 'value3')

      # Update existing key
      cache.put('key1', 'new_value1')

      expect(cache.size).to eq(3)
      expect(cache.get('key1')).to eq('new_value1')
      expect(cache.get('key2')).to eq('value2')
      expect(cache.get('key3')).to eq('value3')
    end
  end

  describe 'thread safety' do
    it 'handles concurrent operations safely' do
      threads = []

      10.times do |i|
        threads << Thread.new do
          cache.put("key#{i}", "value#{i}")
          cache.get("key#{i}")
        end
      end

      threads.each(&:join)

      # Should not raise any errors and maintain consistency
      expect(cache.size).to be <= cache.capacity
    end
  end
end

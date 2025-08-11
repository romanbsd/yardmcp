# frozen_string_literal: true

require 'objspace'

module YardMCP
  class LRUCache
    attr_reader :capacity, :max_memory_bytes

    def initialize(capacity: 10, max_memory_mb: 100)
      @capacity = capacity
      @max_memory_bytes = max_memory_mb * 1024 * 1024
      @cache = {}
      @access_order = []
      @mutex = Mutex.new
    end

    def get(key)
      @mutex.synchronize do
        return nil unless @cache.key?(key)

        @access_order.delete(key)
        @access_order.push(key)
        @cache[key]
      end
    end

    def put(key, value)
      @mutex.synchronize do
        if @cache.key?(key)
          @access_order.delete(key)
        else
          evict_if_needed
        end

        @cache[key] = value
        @access_order.push(key)
        evict_if_memory_exceeded
      end
    end

    def delete(key)
      @mutex.synchronize do
        @access_order.delete(key)
        @cache.delete(key)
      end
    end

    def clear
      @mutex.synchronize do
        @cache.clear
        @access_order.clear
      end
    end

    def size
      @mutex.synchronize { @cache.size }
    end

    def memory_usage
      @mutex.synchronize do
        calculate_memory_usage
      end
    end

    def stats
      @mutex.synchronize do
        {
          size: @cache.size,
          capacity: @capacity,
          max_memory_mb: @max_memory_bytes / (1024 * 1024),
          current_memory_mb: calculate_memory_usage / (1024 * 1024),
          access_order: @access_order.dup
        }
      end
    end

    private

    def evict_if_needed
      return unless @cache.size >= @capacity

      lru_key = @access_order.shift
      @cache.delete(lru_key)
    end

    def evict_if_memory_exceeded
      current_usage = calculate_memory_usage
      return unless current_usage > @max_memory_bytes

      while current_usage > @max_memory_bytes && !@access_order.empty?
        lru_key = @access_order.shift
        @cache.delete(lru_key)
        current_usage = calculate_memory_usage
      end
    end

    def calculate_memory_usage
      @cache.values.sum { |registry| estimate_registry_size(registry) }
    end

    def estimate_registry_size(registry)
      return 0 unless registry

      begin
        ObjectSpace.memsize_of(registry)
      rescue StandardError
        # Fallback: rough estimate based on object count
        YARD::Registry.all.size * 2048
      end
    end
  end
end

# frozen_string_literal: true

module YardMCP
  class Configuration
    attr_accessor :cache_capacity, :max_memory_mb, :enable_streaming, :stream_chunk_size

    def initialize
      @cache_capacity = ENV.fetch('YARDMCP_CACHE_CAPACITY', 10).to_i
      @max_memory_mb = ENV.fetch('YARDMCP_MAX_MEMORY_MB', 100).to_i
      @enable_streaming = ENV.fetch('YARDMCP_ENABLE_STREAMING', 'true') == 'true'
      @stream_chunk_size = ENV.fetch('YARDMCP_STREAM_CHUNK_SIZE', 4096).to_i
    end

    def to_h
      {
        cache_capacity: @cache_capacity,
        max_memory_mb: @max_memory_mb,
        enable_streaming: @enable_streaming,
        stream_chunk_size: @stream_chunk_size
      }
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end
  end
end

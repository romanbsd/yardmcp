# frozen_string_literal: true

module YardMCP
  class SourceStreamer
    def initialize(chunk_size: nil)
      @chunk_size = chunk_size || YardMCP.configuration.stream_chunk_size
    end

    def stream_source(source_text)
      return source_text unless YardMCP.configuration.enable_streaming
      return source_text if source_text.nil? || source_text.length <= @chunk_size

      Enumerator.new do |yielder|
        offset = 0
        while offset < source_text.length
          chunk = source_text[offset, @chunk_size]
          yielder << chunk
          offset += @chunk_size
        end
      end
    end

    def stream_to_string(enumerator)
      return enumerator unless enumerator.is_a?(Enumerator)

      enumerator.map { |chunk| chunk }.join
    end

    def should_stream?(text)
      return false unless YardMCP.configuration.enable_streaming
      return false if text.nil?

      text.length > @chunk_size
    end
  end
end

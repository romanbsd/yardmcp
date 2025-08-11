# frozen_string_literal: true

require 'spec_helper'
require 'yardmcp/configuration'
require 'yardmcp/source_streamer'

RSpec.describe YardMCP::SourceStreamer do
  let(:streamer) { described_class.new(chunk_size: 10) }

  before do
    allow(YardMCP.configuration).to receive(:enable_streaming).and_return(true)
    allow(YardMCP.configuration).to receive(:stream_chunk_size).and_return(10)
  end

  describe '#stream_source' do
    context 'when streaming is disabled' do
      before do
        allow(YardMCP.configuration).to receive(:enable_streaming).and_return(false)
      end

      it 'returns the source text unchanged' do
        text = 'a' * 100
        result = streamer.stream_source(text)
        expect(result).to eq(text)
      end
    end

    context 'when text is nil' do
      it 'returns nil' do
        expect(streamer.stream_source(nil)).to be_nil
      end
    end

    context 'when text is smaller than chunk size' do
      it 'returns the text unchanged' do
        text = 'small'
        result = streamer.stream_source(text)
        expect(result).to eq(text)
      end
    end

    context 'when text is larger than chunk size' do
      it 'returns an enumerator that yields chunks' do
        text = 'a' * 25
        result = streamer.stream_source(text)

        expect(result).to be_a(Enumerator)

        chunks = result.to_a
        expect(chunks.size).to eq(3)
        expect(chunks[0]).to eq('a' * 10)
        expect(chunks[1]).to eq('a' * 10)
        expect(chunks[2]).to eq('a' * 5)
      end
    end
  end

  describe '#stream_to_string' do
    context 'when given a regular string' do
      it 'returns the string unchanged' do
        text = 'regular string'
        result = streamer.stream_to_string(text)
        expect(result).to eq(text)
      end
    end

    context 'when given an enumerator' do
      it 'collects chunks and returns joined string' do
        enum = Enumerator.new do |yielder|
          yielder << 'chunk1'
          yielder << 'chunk2'
          yielder << 'chunk3'
        end

        result = streamer.stream_to_string(enum)
        expect(result).to eq('chunk1chunk2chunk3')
      end
    end
  end

  describe '#should_stream?' do
    context 'when streaming is disabled' do
      before do
        allow(YardMCP.configuration).to receive(:enable_streaming).and_return(false)
      end

      it 'returns false' do
        expect(streamer.should_stream?('a' * 100)).to be false
      end
    end

    context 'when text is nil' do
      it 'returns false' do
        expect(streamer.should_stream?(nil)).to be false
      end
    end

    context 'when text is smaller than chunk size' do
      it 'returns false' do
        expect(streamer.should_stream?('small')).to be false
      end
    end

    context 'when text is larger than chunk size' do
      it 'returns true' do
        expect(streamer.should_stream?('a' * 20)).to be true
      end
    end
  end

  describe 'with custom chunk size' do
    let(:custom_streamer) { described_class.new(chunk_size: 5) }

    it 'uses the custom chunk size' do
      text = 'a' * 12
      result = custom_streamer.stream_source(text)

      chunks = result.to_a
      expect(chunks.size).to eq(3)
      expect(chunks[0]).to eq('a' * 5)
      expect(chunks[1]).to eq('a' * 5)
      expect(chunks[2]).to eq('a' * 2)
    end
  end
end

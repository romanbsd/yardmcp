# frozen_string_literal: true

require 'spec_helper'
require 'yardmcp/configuration'

RSpec.describe YardMCP::Configuration do
  let(:config) { described_class.new }

  describe '#initialize' do
    context 'with default values' do
      it 'sets default configuration values' do
        expect(config.cache_capacity).to eq(10)
        expect(config.max_memory_mb).to eq(100)
        expect(config.enable_streaming).to be true
        expect(config.stream_chunk_size).to eq(4096)
      end
    end

    context 'with environment variables' do
      before do
        ENV['YARDMCP_CACHE_CAPACITY'] = '20'
        ENV['YARDMCP_MAX_MEMORY_MB'] = '200'
        ENV['YARDMCP_ENABLE_STREAMING'] = 'false'
        ENV['YARDMCP_STREAM_CHUNK_SIZE'] = '8192'
      end

      after do
        ENV.delete('YARDMCP_CACHE_CAPACITY')
        ENV.delete('YARDMCP_MAX_MEMORY_MB')
        ENV.delete('YARDMCP_ENABLE_STREAMING')
        ENV.delete('YARDMCP_STREAM_CHUNK_SIZE')
      end

      it 'reads configuration from environment variables' do
        config = described_class.new
        expect(config.cache_capacity).to eq(20)
        expect(config.max_memory_mb).to eq(200)
        expect(config.enable_streaming).to be false
        expect(config.stream_chunk_size).to eq(8192)
      end
    end
  end

  describe '#to_h' do
    it 'returns configuration as a hash' do
      hash = config.to_h

      expect(hash).to be_a(Hash)
      expect(hash[:cache_capacity]).to eq(10)
      expect(hash[:max_memory_mb]).to eq(100)
      expect(hash[:enable_streaming]).to be true
      expect(hash[:stream_chunk_size]).to eq(4096)
    end
  end
end

RSpec.describe YardMCP do
  describe '.configuration' do
    it 'returns a Configuration instance' do
      expect(described_class.configuration).to be_a(YardMCP::Configuration)
    end

    it 'returns the same instance on multiple calls' do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to be(config2)
    end
  end

  describe '.configure' do
    it 'yields the configuration object' do
      described_class.configure do |config|
        config.cache_capacity = 50
        config.max_memory_mb = 500
      end

      expect(described_class.configuration.cache_capacity).to eq(50)
      expect(described_class.configuration.max_memory_mb).to eq(500)
    end

    it 'returns the configuration object' do
      result = described_class.configure do |config|
        config.enable_streaming = false
      end

      expect(result).to be_a(YardMCP::Configuration)
      expect(result.enable_streaming).to be false
    end
  end
end

# frozen_string_literal: true

require 'timeout'
require 'open3'
require 'json'
require 'rspec'

RSpec.describe 'yardmcp FastMcp server' do # rubocop:disable Metrics/BlockLength
  let(:timeout) { 20 }
  @server_handles = {}
  @server_mutex = Mutex.new

  class << self
    attr_reader :server_handles
  end

  class << self
    attr_reader :server_mutex
  end

  before(:all) do
    stdin, stdout, stderr, wait_thr = Open3.popen3("ruby #{File.expand_path('../lib/yardmcp.rb', __dir__)}")
    # Wait for "Index built" on stderr
    ready = false
    while (line = stderr.gets)
      puts "SERVER STDERR: #{line.strip}"
      if line.include?('Index built')
        ready = true
        break
      end
    end
    raise 'Server failed to start' unless ready

    self.class.server_handles[:stdin] = stdin
    self.class.server_handles[:stdout] = stdout
    self.class.server_handles[:stderr] = stderr
    self.class.server_handles[:wait_thr] = wait_thr
  end

  after(:all) do
    self.class.server_handles[:stdin]&.close
    self.class.server_handles[:stdout]&.close
    self.class.server_handles[:stderr]&.close
    self.class.server_handles[:wait_thr]&.kill
  end

  def mcp_request(method, params = {})
    req = {
      jsonrpc: '2.0',
      id: rand(10_000),
      method:,
      params:
    }
    "#{req.to_json}\n"
  end

  def send_mcp_request(method, params = {}) # rubocop:disable Metrics/AbcSize
    self.class.server_mutex.synchronize do
      stdin = self.class.server_handles[:stdin]
      stdout = self.class.server_handles[:stdout]
      stdin.puts mcp_request(method, params)
      Timeout.timeout(timeout) do
        line = stdout.gets
        warn "RAW OUTPUT: #{line.inspect}" if ENV['DEBUG']
        begin
          return JSON.parse(line)['result']
        rescue StandardError
          { 'error' => 'invalid json', 'raw' => line }
        end
      end
    end
  rescue StandardError => e
    err = begin
      self.class.server_handles[:stderr].read_nonblock(4096)
    rescue StandardError
      nil
    end
    puts "STDERR: #{err}" if err && !err.empty?
    raise e
  end

  def invoke_mcp_tool(name, arguments = {})
    params = { name:, arguments: }
    send_mcp_request('tools/call', params)
  end

  it 'lists all available tools' do
    resp = send_mcp_request('tools/list')
    tools = resp['tools'].map { |tool| tool['name'] }
    expect(tools).to match_array(%w[ListGemsTool ListClassesTool GetDocTool ChildrenTool MethodsListTool HierarchyTool SearchTool SourceLocationTool CodeSnippetTool AncestorsTool RelatedObjectsTool])
  end

  it 'responds to ListGemsTool and includes yard' do
    resp = invoke_mcp_tool('ListGemsTool')
    expect(resp['content']).to include('yard')
  end

  it 'responds to ListClassesTool for yard gem' do
    resp = invoke_mcp_tool('ListClassesTool', { 'gem_name' => 'yard' })
    expect(resp['content']).to include('YARD', 'YARD::Registry')
  end

  it 'responds to GetDocTool for YARD::Registry' do
    resp = invoke_mcp_tool('GetDocTool', { 'path' => 'YARD::Registry', 'gem_name' => 'yard' })
    doc = resp['content']
    expect(doc['name']).to eq('Registry')
    expect(doc['type']).to eq('module')
    expect(doc['namespace']).to eq('YARD')
    expect(doc['docstring']).to be_a(String)
  end

  it 'responds to ChildrenTool for YARD' do
    resp = invoke_mcp_tool('ChildrenTool', { 'path' => 'YARD' })
    expect(resp['content']).to include('YARD::Registry')
  end

  it 'responds to MethodsListTool for YARD::Registry' do
    resp = invoke_mcp_tool('MethodsListTool', { 'path' => 'YARD::Registry' })
    expect(resp['content']).to include('YARD::Registry.load_yardoc')
  end

  it 'responds to HierarchyTool for YARD::Registry' do
    resp = invoke_mcp_tool('HierarchyTool', { 'path' => 'YARD::Registry' })
    expect(resp['content']).to have_key('superclass')
    expect(resp['content']).to have_key('included_modules')
    expect(resp['content']).to have_key('mixins')
  end

  it 'responds to SearchTool for "Registry"' do
    resp = invoke_mcp_tool('SearchTool', { 'query' => 'Registry' })
    expect(resp['content']&.map { |r| r['path'] }).to include('YARD::Registry')
  end

  it 'responds to SourceLocationTool for YARD::Registry' do
    resp = invoke_mcp_tool('SourceLocationTool', { 'path' => 'YARD::Registry' })
    expect(resp['content']).to have_key('file')
    expect(resp['content']).to have_key('line')
  end

  it 'responds to CodeSnippetTool for YARD::Registry' do
    resp = invoke_mcp_tool('CodeSnippetTool', { 'path' => 'YARD::CodeObjects::Base#name' })
    expect(resp['content']).to be_an(Array)
    expect(resp['content'].first['text']).to be_a(String)
  end

  it 'responds to AncestorsTool for YARD::Registry' do
    resp = invoke_mcp_tool('AncestorsTool', { 'path' => 'YARD::Registry' })
    expect(resp['content']).to be_an(Array)
    expect(resp['content']).to include('YARD::Registry')
  end

  it 'responds to RelatedObjectsTool for YARD::Registry' do
    resp = invoke_mcp_tool('RelatedObjectsTool', { 'path' => 'YARD::Registry' })
    expect(resp['content']).to have_key('included_modules')
    expect(resp['content']).to have_key('mixins')
  end
end

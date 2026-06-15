# frozen_string_literal: true

require 'timeout'
require 'open3'
require 'json'
require 'rspec'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/yardmcp'

RSpec.describe YardUtils do
  it 'reports ambiguous object candidates with gem names and versions' do
    utils = described_class.instance
    utils.object_to_gem['Ambiguous::Object'] = %w[yard yardmcp-spec-a yardmcp-spec-b]
    utils.libraries['yardmcp-spec-a'] = [YARD::Server::LibraryVersion.new('yardmcp-spec-a', '1.2.3', nil, :gem)]
    utils.libraries['yardmcp-spec-b'] = [YARD::Server::LibraryVersion.new('yardmcp-spec-b', '2.0.0', nil, :gem)]

    expect { utils.ensure_yardoc_loaded_for_object!('Ambiguous::Object') }
      .to raise_error(YardUtils::AmbiguousObjectError) { |error|
        expect(error.path).to eq('Ambiguous::Object')
        expect(error.candidates).to include(
          { gem_name: 'yardmcp-spec-a', versions: ['1.2.3'] },
          { gem_name: 'yardmcp-spec-b', versions: ['2.0.0'] }
        )
      }
  ensure
    utils&.object_to_gem&.delete('Ambiguous::Object')
    utils&.libraries&.delete('yardmcp-spec-a')
    utils&.libraries&.delete('yardmcp-spec-b')
  end
end

RSpec.describe YardTool do
  it 'formats ambiguous object errors with structured candidates' do
    candidates = [{ gem_name: 'alpha', versions: ['1.0.0'] }, { gem_name: 'beta', versions: ['2.0.0'] }]
    result = described_class.new.send(:with_yard_errors) do
      raise YardUtils::AmbiguousObjectError.new('Shared::Object', candidates)
    end

    expect(result[:isError]).to be(true)
    expect(result[:structuredContent]).to eq(
      error: 'ambiguous_object',
      path: 'Shared::Object',
      candidates:
    )
  end
end

RSpec.describe 'yardmcp FastMcp server' do # rubocop:disable Metrics/BlockLength
  let(:timeout) { 30 }
  @server_handles = {}
  @server_mutex = Mutex.new
  @test_home = nil

  class << self
    attr_reader :server_handles
  end

  class << self
    attr_reader :server_mutex
  end

  before(:all) do # rubocop:disable Metrics/BlockLength
    @test_home = Dir.mktmpdir('yardmcp-home')
    env = { 'HOME' => @test_home }
    build_cmd = [
      'ruby',
      '-e',
      "require 'yard'; YARD::CLI::Gems.new.run('yard')"
    ]
    raise 'Failed to build test YARD docs' unless system(env, *build_cmd, out: File::NULL, err: File::NULL)

    stdin, stdout, stderr, wait_thr = Open3.popen3(env, "ruby #{File.expand_path('../lib/yardmcp.rb', __dir__)}")
    # Wait for "Index built" on stderr
    ready = false
    while (line = stderr.gets)
      puts "SERVER STDERR: #{line.strip}"
      next unless line.include?('Index built')

      warn('Server started')
      ready = true
      break
    end
    raise 'Server failed to start' unless ready

    self.class.server_handles[:stdin] = stdin
    self.class.server_handles[:stdout] = stdout
    self.class.server_handles[:stderr] = stderr
    self.class.server_handles[:wait_thr] = wait_thr

    initialize_req = {
      jsonrpc: '2.0',
      id: 1,
      method: 'initialize',
      params: {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'yardmcp-spec', version: '1.0' }
      }
    }
    stdin.puts "#{initialize_req.to_json}\n"
    Timeout.timeout(20) { JSON.parse(stdout.gets) }
    initialized_notification = {
      jsonrpc: '2.0',
      method: 'notifications/initialized',
      params: {}
    }
    stdin.puts "#{initialized_notification.to_json}\n"
  end

  after(:all) do
    self.class.server_handles[:stdin]&.close
    self.class.server_handles[:stdout]&.close
    self.class.server_handles[:stderr]&.close
    self.class.server_handles[:wait_thr]&.kill
    FileUtils.rm_rf(@test_home) if @test_home
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
    expect(tools).to match_array(%w[ListGemsTool ListClassesTool GetDocTool ChildrenTool MethodsListTool HierarchyTool SearchTool SourceLocationTool CodeSnippetTool AncestorsTool RelatedObjectsTool BuildGemDocsTool])
    expect(resp['tools'].find { |tool| tool['name'] == 'BuildGemDocsTool' }['annotations']['readOnlyHint']).to be(false)
  end

  it 'advertises only implemented capabilities' do
    resp = send_mcp_request('initialize', {
                              'protocolVersion' => '2024-11-05',
                              'capabilities' => {},
                              'clientInfo' => { 'name' => 'yardmcp-spec', 'version' => '1.0' }
                            })
    expect(resp['capabilities']).to eq('tools' => {}, 'resources' => {})
  end

  it 'publishes output schemas for all tools' do
    resp = send_mcp_request('tools/list')
    tools_by_name = resp['tools'].to_h { |tool| [tool['name'], tool] }

    expect(tools_by_name.values).to all(include('outputSchema'))
    expect(tools_by_name['ListGemsTool']['outputSchema']['required']).to include('gems')
    expect(tools_by_name['ListClassesTool']['outputSchema']['required']).to include('gem_name', 'classes')
    expect(tools_by_name['GetDocTool']['outputSchema']['required']).to include('document')
    expect(tools_by_name['ChildrenTool']['outputSchema']['required']).to include('children')
    expect(tools_by_name['MethodsListTool']['outputSchema']['required']).to include('methods')
    expect(tools_by_name['SourceLocationTool']['outputSchema']['required']).to include('source_location')
    expect(tools_by_name['HierarchyTool']['outputSchema']['required']).to include('hierarchy')
    expect(tools_by_name['SearchTool']['outputSchema']['required']).to include('results')
    expect(tools_by_name['CodeSnippetTool']['outputSchema']['required']).to include('snippet')
    expect(tools_by_name['AncestorsTool']['outputSchema']['required']).to include('ancestors')
    expect(tools_by_name['RelatedObjectsTool']['outputSchema']['required']).to include('related_objects')
    expect(tools_by_name['BuildGemDocsTool']['outputSchema']['required']).to include('gem_name', 'indexed')
  end

  it 'lists YARD resource templates' do
    resp = send_mcp_request('resources/templates/list')
    templates = resp['resourceTemplates'].map { |template| template['uriTemplate'] }

    expect(templates).to include('yard://gem/{gem_name}/object/{+path}')
    expect(templates).to include('yard://gem/{gem_name}/source/{+path}')
  end

  it 'reads object documentation as an MCP resource' do
    resp = send_mcp_request('resources/read', { 'uri' => 'yard://gem/yard/object/YARD::Registry' })
    content = resp['contents'].first
    document = JSON.parse(content['text'])['document']

    expect(content['mimeType']).to eq('application/json')
    expect(document['name']).to eq('Registry')
    expect(document['type']).to eq('module')
  end

  it 'reads source as an MCP resource, including method paths with fragments' do
    resp = send_mcp_request('resources/read', { 'uri' => 'yard://gem/yard/source/YARD::CodeObjects::Base#name' })
    content = resp['contents'].first

    expect(content['mimeType']).to eq('text/plain')
    expect(content['text']).to include('def name')
  end

  it 'responds to ListGemsTool with text content and structured data' do
    resp = invoke_mcp_tool('ListGemsTool')
    expect(resp['isError']).to be(false)
    expect(resp['content']).to all(include('type' => 'text'))
    expect(resp['structuredContent']['gems']).to include('yard')
  end

  it 'responds to ListClassesTool for yard gem' do
    resp = invoke_mcp_tool('ListClassesTool', { 'gem_name' => 'yard' })
    expect(resp['isError']).to be(false)
    expect(resp['structuredContent']['classes']).to include('YARD', 'YARD::Registry')
  end

  it 'responds to GetDocTool for YARD::Registry' do
    resp = invoke_mcp_tool('GetDocTool', { 'path' => 'YARD::Registry', 'gem_name' => 'yard' })
    doc = resp['structuredContent']['document']
    resource_uris = resp['structuredContent']['resource_uris']
    expect(doc['name']).to eq('Registry')
    expect(doc['type']).to eq('module')
    expect(doc['namespace']).to eq('YARD')
    expect(doc['docstring']).to be_a(String)
    expect(resource_uris).to eq(
      'object' => 'yard://gem/yard/object/YARD::Registry',
      'source' => 'yard://gem/yard/source/YARD::Registry'
    )
  end

  it 'responds to ChildrenTool for YARD' do
    resp = invoke_mcp_tool('ChildrenTool', { 'path' => 'YARD', 'gem_name' => 'yard' })
    expect(resp['structuredContent']['children']).to include('YARD::Registry')
    expect(resp['structuredContent']['resource_uris']['object']).to eq('yard://gem/yard/object/YARD')
  end

  it 'responds to MethodsListTool for YARD::Registry' do
    resp = invoke_mcp_tool('MethodsListTool', { 'path' => 'YARD::Registry', 'gem_name' => 'yard' })
    expect(resp['structuredContent']['methods']).to include('YARD::Registry.load_yardoc')
  end

  it 'responds to HierarchyTool for YARD::Registry' do
    resp = invoke_mcp_tool('HierarchyTool', { 'path' => 'YARD::Registry', 'gem_name' => 'yard' })
    hierarchy = resp['structuredContent']['hierarchy']
    expect(hierarchy).to have_key('superclass')
    expect(hierarchy).to have_key('included_modules')
    expect(hierarchy).to have_key('mixins')
  end

  it 'responds to SearchTool for "Registry"' do
    resp = invoke_mcp_tool('SearchTool', { 'query' => 'Registry', 'gem_name' => 'yard', 'limit' => 10 })
    expect(resp['structuredContent']['results'].map { |r| r['path'] }).to include('YARD::Registry')
  end

  it 'limits SearchTool results' do
    resp = invoke_mcp_tool('SearchTool', { 'query' => 'YARD', 'gem_name' => 'yard', 'limit' => 3 })
    expect(resp['structuredContent']['results'].size).to be <= 3
  end

  it 'responds to SourceLocationTool for YARD::Registry' do
    resp = invoke_mcp_tool('SourceLocationTool', { 'path' => 'YARD::Registry', 'gem_name' => 'yard' })
    location = resp['structuredContent']['source_location']
    expect(location).to have_key('file')
    expect(location).to have_key('line')
  end

  it 'responds to CodeSnippetTool for YARD::Registry' do
    resp = invoke_mcp_tool('CodeSnippetTool', { 'path' => 'YARD::CodeObjects::Base#name', 'gem_name' => 'yard', 'max_chars' => 1000 })
    expect(resp['structuredContent']['snippet']).to be_a(String)
    expect(resp['structuredContent']['snippet'].length).to be <= 1050
    expect(resp['structuredContent']['resource_uris']).to eq(
      'object' => 'yard://gem/yard/object/YARD::CodeObjects::Base#name',
      'source' => 'yard://gem/yard/source/YARD::CodeObjects::Base#name'
    )
  end

  it 'responds to AncestorsTool for YARD::Registry' do
    resp = invoke_mcp_tool('AncestorsTool', { 'path' => 'YARD::Registry', 'gem_name' => 'yard' })
    expect(resp['structuredContent']['ancestors']).to include('YARD::Registry')
  end

  it 'responds to RelatedObjectsTool for YARD::Registry' do
    resp = invoke_mcp_tool('RelatedObjectsTool', { 'path' => 'YARD::Registry', 'gem_name' => 'yard' })
    related = resp['structuredContent']['related_objects']
    expect(related).to have_key('included_modules')
    expect(related).to have_key('mixins')
  end

  it 'returns a tool error instead of implicitly building missing documentation' do
    resp = invoke_mcp_tool('ListClassesTool', { 'gem_name' => 'rspec' })
    expect(resp['isError']).to be(true)
    expect(resp['content'].first['text']).to include("YARD documentation is not indexed for gem 'rspec'")
    expect(resp['content'].first['text']).not_to include('/lib/yardmcp.rb')
  end
end

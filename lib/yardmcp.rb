#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fast_mcp'
require 'json'
require 'logger'
require 'rubygems'
require 'yard'
require 'singleton'
require_relative 'yardmcp/version'

# Utility class for YARD operations
class YardUtils # rubocop:disable Metrics/ClassLength
  include Singleton

  MAX_SOURCE_CHARS = 20_000

  class DocumentationError < StandardError; end

  class AmbiguousObjectError < DocumentationError
    attr_reader :path, :candidates

    def initialize(path, candidates)
      @path = path
      @candidates = candidates
      super("Multiple gems contain '#{path}'. Pass gem_name.")
    end
  end

  attr_reader :libraries, :logger, :object_to_gem

  def initialize
    @libraries = {}
    @object_to_gem = {}
    @last_loaded_gem = nil
    @class_cache = {}
    @logger = Logger.new($stderr)
    @logger.level = Logger::INFO unless ENV['DEBUG']
    build_index
  end

  # Loads the .yardoc file for a given gem into the YARD registry.
  # Caches the last loaded gem to avoid unnecessary reloads.
  #
  # @param gem_name [String] The name of the gem to load.
  # @return [Boolean] True if the .yardoc file was loaded, false otherwise.
  def load_yardoc_for_gem(gem_name)
    return if @last_loaded_gem == gem_name

    spec = gem_spec!(gem_name)
    dir = yardoc_path_for(spec)
    raise DocumentationError, "YARD documentation is not indexed for gem '#{gem_name}'" unless yardoc_exists?(dir)

    YARD::Registry.load!(dir)
    @last_loaded_gem = gem_name
  end

  # Ensures the correct .yardoc is loaded for the given object path
  def ensure_yardoc_loaded_for_object!(object_path)
    gem_names = @object_to_gem[object_path]
    raise DocumentationError, "No indexed documentation contains '#{object_path}'. Pass gem_name if you know the gem." if gem_names.nil? || gem_names.empty?
    raise AmbiguousObjectError.new(object_path, gem_candidates(gem_names)) if gem_names.uniq.size > 1

    load_yardoc_for_gem(gem_names.first)
  end

  # Lists all installed gems that have a .yardoc file available.
  #
  # @return [Array<String>] An array of gem names with .yardoc files.
  def list_gems
    libraries.keys.select do |name|
      yardoc_exists?(yardoc_path_for(gem_spec!(name)))
    end.sort
  end

  def list_installed_gems
    libraries.keys.sort
  end

  def gem_candidates(gem_names)
    gem_names.uniq.sort.map do |gem_name|
      {
        gem_name:,
        versions: Array(libraries[gem_name]).map { |library| library.version.to_s }.uniq.sort
      }
    end
  end

  # Lists all classes and modules in the loaded YARD registry.
  #
  # @return [Array<String>] An array of fully qualified class/module paths.
  def list_classes(gem_name)
    load_yardoc_for_gem(gem_name)
    @class_cache[gem_name] ||= YARD::Registry.all(:class, :module).map(&:path).sort
  end

  # Fetches documentation and metadata for a YARD object (class/module/method).
  #
  # @param path [String] The YARD path (e.g., 'String#upcase').
  # @return [Hash] A hash containing type, name, namespace, visibility, docstring, parameters, return, and source.
  # @raise [RuntimeError] if the object is not found in the registry.
  def get_doc(path, gem_name = nil) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
    obj = object_for!(path, gem_name)

    tags = obj.tags.map do |tag|
      {
        tag_name: tag.tag_name,
        name: tag.respond_to?(:name) ? tag.name : nil,
        types: tag.respond_to?(:types) ? tag.types : nil,
        text: tag.text
      }
    end

    doc = {
      type: obj.type.to_s,
      name: obj.name.to_s,
      namespace: obj.namespace&.path,
      visibility: obj.respond_to?(:visibility) ? obj.visibility.to_s : nil,
      docstring: obj.docstring.to_s,
      parameters: obj.respond_to?(:parameters) ? obj.parameters : nil,
      return: if obj.respond_to?(:tag) && obj.tag('return')
                {
                  types: obj.tag('return').types,
                  text: obj.tag('return').text
                }
              end,
      source: capped_source(obj.respond_to?(:source) ? obj.source : nil),
      tags:
    }

    # Add subclass-specific info
    doc[:attributes] = obj.attributes if obj.respond_to?(:attributes) && obj.attributes
    doc[:constants] = obj.constants.map(&:path) if obj.respond_to?(:constants) && obj.constants
    doc[:superclass] = obj.superclass&.path if obj.respond_to?(:superclass) && obj.superclass
    doc[:scope] = obj.scope if obj.respond_to?(:scope) && obj.scope
    doc[:overridden_method] = obj.overridden_method&.path if obj.respond_to?(:overridden_method) && obj.overridden_method

    doc
  end

  # Lists the children (constants, classes, modules, methods, etc.) under a namespace.
  #
  # @param path [String] The YARD path of the namespace.
  # @return [Array<String>] An array of child object paths.
  # @raise [RuntimeError] if the object is not found in the registry.
  def children(path, gem_name = nil)
    obj = object_for!(path, gem_name)
    obj.respond_to?(:children) ? obj.children.map(&:path) : []
  end

  # Lists all methods for a class or module.
  #
  # @param path [String] The YARD path of the class/module.
  # @return [Array<String>] An array of method paths.
  # @raise [RuntimeError] if the object is not found in the registry.
  def methods_list(path, gem_name = nil)
    obj = object_for!(path, gem_name)
    obj.respond_to?(:meths) ? obj.meths.map(&:path) : []
  end

  # Returns inheritance and inclusion information for a class or module.
  #
  # @param path [String] The YARD path of the class/module.
  # @return [Hash] A hash with :superclass (String or nil), :included_modules (Array<String>), and :mixins (Array<String>).
  # @raise [RuntimeError] if the object is not found in the registry.
  def hierarchy(path, gem_name = nil)
    obj = object_for!(path, gem_name)
    {
      superclass: obj.respond_to?(:superclass) && obj.superclass ? obj.superclass.path : nil,
      included_modules: obj.respond_to?(:mixins) ? obj.mixins.map(&:path) : [],
      mixins: obj.respond_to?(:mixins) ? obj.mixins.map(&:path) : []
    }
  end

  # Returns the full ancestor chain (superclasses and included modules) for a class or module.
  #
  # @param path [String] The YARD path of the class/module.
  # @return [Array<String>] An array of ancestor paths.
  def ancestors(path, gem_name = nil)
    obj = object_for!(path, gem_name)
    obj.respond_to?(:inheritance_tree) ? obj.inheritance_tree(true).map(&:path) : []
  end

  # Returns related objects: included modules, mixins, and subclasses.
  #
  # @param path [String] The YARD path of the class/module.
  # @return [Hash] A hash with :included_modules, :mixins, :subclasses.
  def related_objects(path, gem_name = nil)
    obj = object_for!(path, gem_name)
    subclasses = YARD::Registry.all(:class).select { |c| c.superclass && c.superclass.path == obj.path }.map(&:path)
    mixins_list = obj.respond_to?(:mixins) ? obj.mixins.map(&:path) : []
    {
      included_modules: mixins_list,
      mixins: mixins_list,
      subclasses:
    }
  end

  # Performs a fuzzy/full-text search in the YARD registry for objects whose path or docstring matches the query.
  #
  # @param query [String] The search query string.
  # @return [Array<Hash>] An array of hashes with :path and :score for matching object paths, ranked by relevance.
  def search(query, gem_name = nil, limit: 25, offset: 0)
    require 'levenshtein' unless defined?(Levenshtein)
    candidates = gem_name ? loaded_objects_for_search(gem_name) : indexed_paths_for_search
    results = candidates.filter_map { |candidate| score_search_candidate(candidate, query) }
    # Sort by score descending, then alphabetically
    results.sort_by { |r| [-r[:score], r[:path]] }.slice(offset, limit) || []
  end

  # Returns the source file and line number for a YARD object (class/module/method).
  #
  # @param path [String] The YARD path (e.g., 'String#upcase').
  # @return [Hash] A hash with :file (String or nil) and :line (Integer or nil).
  # @raise [RuntimeError] if the object is not found in the registry.
  def source_location(path, gem_name = nil)
    obj = object_for!(path, gem_name)
    {
      file: obj.respond_to?(:file) ? obj.file : nil,
      line: obj.respond_to?(:line) ? obj.line : nil
    }
  end

  # Fetches the code snippet for a YARD object from installed gems.
  #
  # @param path [String] The YARD path (e.g., 'String#upcase').
  # @return [String, nil] The code snippet if available, otherwise nil.
  # @raise [RuntimeError] if the object is not found in the registry.
  def code_snippet(path, gem_name = nil, max_chars: MAX_SOURCE_CHARS)
    obj = object_for!(path, gem_name)
    capped_source(obj.respond_to?(:source) ? obj.source : nil, max_chars:)
  end

  def build_docs(gem_name)
    gem_spec!(gem_name)
    logger.info "Building docs for #{gem_name}..."
    YARD::CLI::Gems.new.run(gem_name)
    @class_cache.delete(gem_name)
    @last_loaded_gem = nil
    load_yardoc_for_gem(gem_name)
    merge_gem_results([collect_current_gem_objects(gem_name)])
    true
  end

  private

  def gem_spec!(gem_name)
    spec = libraries[gem_name]&.first
    raise DocumentationError, "Gem '#{gem_name}' is not installed" unless spec

    spec
  end

  def yardoc_path_for(spec)
    YARD::Registry.yardoc_file_for_gem(spec.name, "= #{spec.version}")
  end

  def yardoc_exists?(dir)
    dir && File.directory?(dir)
  end

  def object_for!(path, gem_name = nil)
    gem_name ? load_yardoc_for_gem(gem_name) : ensure_yardoc_loaded_for_object!(path)
    obj = YARD::Registry.at(path)
    raise DocumentationError, "Object '#{path}' was not found" unless obj

    obj
  end

  def capped_source(source, max_chars: MAX_SOURCE_CHARS)
    return source unless source && source.length > max_chars

    "#{source.byteslice(0, max_chars)}\n... truncated at #{max_chars} bytes"
  end

  def loaded_objects_for_search(gem_name)
    load_yardoc_for_gem(gem_name)
    YARD::Registry.all.map do |obj|
      { path: obj.path.to_s, docstring: obj.docstring.to_s }
    end
  end

  def indexed_paths_for_search
    @object_to_gem.keys.map { |path| { path:, docstring: '' } }
  end

  def score_search_candidate(candidate, query)
    path = candidate[:path]
    doc = candidate[:docstring]
    return if path.empty?

    score = search_score(path, doc, query)
    { path:, score: } if score
  end

  def search_score(path, doc, query)
    query_downcase = query.downcase
    path_downcase = path.downcase
    return 100 if path == query
    return 90 if path_downcase.start_with?(query_downcase)
    return 80 if path_downcase.include?(query_downcase)
    return 60 if doc.downcase.include?(query_downcase)

    distance = Levenshtein.distance(path_downcase, query_downcase)
    distance <= [2, query.length / 3].max ? 70 - distance : nil
  end

  # Build an index mapping object paths to gem names
  def build_index # rubocop:disable Metrics/AbcSize
    logger.info 'Building index...'
    YARD::GemIndex.each do |spec|
      (libraries[spec.name] ||= []) << YARD::Server::LibraryVersion.new(spec.name, spec.version.to_s, nil, :gem)
    end

    begin
      require 'parallel'
      logger.info 'Using parallel gem for index building'

      # Use processes to avoid YARD thread-safety issues
      # Each process returns a hash of object_path => [gem_names]
      results = Parallel.map(list_gems, in_processes: 8) { |gem| process_gem_for_index(gem) }
      merge_gem_results(results)
    rescue LoadError
      logger.warn 'parallel gem not found, falling back to single-threaded processing'
      results = list_gems.map { |gem| process_gem_for_index(gem) }
      merge_gem_results(results)
    end
    logger.info "Index built: #{libraries.size} gems, #{@object_to_gem.size} objects"
  end

  # Merge gem processing results into @object_to_gem
  def merge_gem_results(results)
    results.each do |gem_objects|
      gem_objects.each do |obj_path, gem_names|
        (@object_to_gem[obj_path] ||= []).concat(gem_names).uniq!
      end
    end
  end

  # Process a single gem and return its objects as a hash
  def process_gem_for_index(gem_name)
    logger.debug "Loading #{gem_name}..."
    begin
      load_yardoc_for_gem(gem_name)
    rescue StandardError => e
      logger.error "Error loading #{gem_name}: #{e.message}"
      return {}
    end

    collect_current_gem_objects(gem_name)
  end

  def collect_current_gem_objects(gem_name)
    gem_objects = {}
    YARD::Registry.all.each do |obj|
      logger.debug "Adding #{obj.path} to #{gem_name}"
      gem_objects[obj.path.to_s] = [gem_name]
    end
    gem_objects
  end
end

module YardSchemas
  RESOURCE_URIS_SCHEMA = {
    type: 'object',
    properties: {
      object: { type: 'string' },
      source: { type: 'string' }
    },
    required: %w[object source]
  }.freeze

  def self.array_schema(name)
    {
      type: 'object',
      properties: {
        name => { type: 'array', items: { type: 'string' } }
      },
      required: [name.to_s]
    }.freeze
  end

  def self.path_array_schema(name)
    {
      type: 'object',
      properties: {
        path: { type: 'string' },
        gem_name: { type: %w[string null] },
        resource_uris: RESOURCE_URIS_SCHEMA,
        name => { type: 'array', items: { type: 'string' } }
      },
      required: %w[path resource_uris] + [name.to_s]
    }.freeze
  end

  LIST_GEMS_SCHEMA = array_schema(:gems)

  LIST_CLASSES_SCHEMA = {
    type: 'object',
    properties: {
      gem_name: { type: 'string' },
      classes: { type: 'array', items: { type: 'string' } }
    },
    required: %w[gem_name classes]
  }.freeze

  DOC_OBJECT_SCHEMA = {
    type: 'object',
    properties: {
      path: { type: 'string' },
      gem_name: { type: %w[string null] },
      resource_uris: RESOURCE_URIS_SCHEMA,
      document: {
        type: 'object',
        properties: {
          type: { type: 'string' },
          name: { type: 'string' },
          namespace: { type: %w[string null] },
          visibility: { type: %w[string null] },
          docstring: { type: 'string' },
          parameters: { type: %w[array null] },
          return: { type: %w[object null] },
          source: { type: %w[string null] },
          tags: { type: 'array' }
        },
        required: %w[type name docstring tags]
      }
    },
    required: %w[resource_uris document]
  }.freeze

  CHILDREN_SCHEMA = path_array_schema(:children)

  METHODS_SCHEMA = path_array_schema(:methods)

  SOURCE_LOCATION_SCHEMA = {
    type: 'object',
    properties: {
      path: { type: 'string' },
      gem_name: { type: %w[string null] },
      resource_uris: RESOURCE_URIS_SCHEMA,
      source_location: {
        type: 'object',
        properties: {
          file: { type: %w[string null] },
          line: { type: %w[integer null] }
        },
        required: %w[file line]
      }
    },
    required: %w[path resource_uris source_location]
  }.freeze

  HIERARCHY_SCHEMA = {
    type: 'object',
    properties: {
      path: { type: 'string' },
      gem_name: { type: %w[string null] },
      resource_uris: RESOURCE_URIS_SCHEMA,
      hierarchy: {
        type: 'object',
        properties: {
          superclass: { type: %w[string null] },
          included_modules: { type: 'array', items: { type: 'string' } },
          mixins: { type: 'array', items: { type: 'string' } }
        },
        required: %w[superclass included_modules mixins]
      }
    },
    required: %w[path resource_uris hierarchy]
  }.freeze

  SEARCH_SCHEMA = {
    type: 'object',
    properties: {
      query: { type: 'string' },
      gem_name: { type: %w[string null] },
      limit: { type: 'integer' },
      offset: { type: 'integer' },
      results: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            path: { type: 'string' },
            score: { type: 'integer' }
          },
          required: %w[path score]
        }
      }
    },
    required: %w[query limit offset results]
  }.freeze

  CODE_SNIPPET_SCHEMA = {
    type: 'object',
    properties: {
      path: { type: 'string' },
      gem_name: { type: %w[string null] },
      resource_uris: RESOURCE_URIS_SCHEMA,
      snippet: { type: 'string' }
    },
    required: %w[path resource_uris snippet]
  }.freeze

  ANCESTORS_SCHEMA = path_array_schema(:ancestors)

  RELATED_OBJECTS_SCHEMA = {
    type: 'object',
    properties: {
      path: { type: 'string' },
      gem_name: { type: %w[string null] },
      resource_uris: RESOURCE_URIS_SCHEMA,
      related_objects: {
        type: 'object',
        properties: {
          included_modules: { type: 'array', items: { type: 'string' } },
          mixins: { type: 'array', items: { type: 'string' } },
          subclasses: { type: 'array', items: { type: 'string' } }
        },
        required: %w[included_modules mixins subclasses]
      }
    },
    required: %w[path resource_uris related_objects]
  }.freeze

  BUILD_GEM_DOCS_SCHEMA = {
    type: 'object',
    properties: {
      gem_name: { type: 'string' },
      indexed: { type: 'boolean' }
    },
    required: %w[gem_name indexed]
  }.freeze
end

module YardMcpToolListOutputSchema
  private

  def handle_tools_list(id)
    tools_list = @tools.values.map do |tool|
      tool_info = {
        name: tool.tool_name,
        description: tool.description || '',
        inputSchema: tool.input_schema_to_json || { type: 'object', properties: {}, required: [] }
      }
      tool_info[:outputSchema] = tool.output_schema if tool.respond_to?(:output_schema) && tool.output_schema
      tool_info[:annotations] = camel_case_annotations(tool.annotations) unless tool.annotations.empty?
      tool_info
    end

    send_result({ tools: tools_list }, id)
  end

  def camel_case_annotations(annotations)
    annotations.to_h do |key, value|
      camel_key = key.to_s.gsub(/_([a-z])/) { ::Regexp.last_match(1).upcase }.to_sym
      [camel_key, value]
    end
  end
end

FastMcp::Server.prepend(YardMcpToolListOutputSchema)

class YardTool < FastMcp::Tool
  class << self
    attr_reader :output_schema

    def returns(schema)
      @output_schema = schema
    end
  end

  private

  def ok(structured_content, text: nil)
    {
      content: [{ type: 'text', text: text || JSON.pretty_generate(structured_content) }],
      structuredContent: structured_content,
      isError: false
    }
  end

  def with_yard_errors
    yield
  rescue YardUtils::AmbiguousObjectError => e
    {
      content: [{ type: 'text', text: e.message }],
      structuredContent: {
        error: 'ambiguous_object',
        path: e.path,
        candidates: e.candidates
      },
      isError: true
    }
  rescue YardUtils::DocumentationError, ArgumentError => e
    {
      content: [{ type: 'text', text: e.message }],
      structuredContent: {
        error: 'documentation_error',
        message: e.message
      },
      isError: true
    }
  end

  def resource_uris(gem_name, path)
    return nil unless gem_name

    {
      object: "yard://gem/#{gem_name}/object/#{path}",
      source: "yard://gem/#{gem_name}/source/#{path}"
    }
  end
end

class YardObjectResource < FastMcp::Resource
  uri 'yard://gem/{gem_name}/object/{+path}'
  resource_name 'YARD object documentation'
  description 'Read structured YARD documentation for a gem object'
  mime_type 'application/json'

  def content
    JSON.pretty_generate(document: YardUtils.instance.get_doc(params[:path], params[:gem_name]))
  rescue YardUtils::DocumentationError, ArgumentError => e
    JSON.pretty_generate(error: e.message)
  end
end

class YardSourceResource < FastMcp::Resource
  uri 'yard://gem/{gem_name}/source/{+path}'
  resource_name 'YARD object source'
  description 'Read source code for a documented YARD object'
  mime_type 'text/plain'

  def content
    YardUtils.instance.code_snippet(params[:path], params[:gem_name]).to_s
  rescue YardUtils::DocumentationError, ArgumentError => e
    "Error: #{e.message}"
  end
end

# Tool: List all gems with .yardoc files
class ListGemsTool < YardTool
  description 'List all installed gems that have a .yardoc file'
  annotations(title: 'List all installed gems', read_only_hint: true)
  returns YardSchemas::LIST_GEMS_SCHEMA

  def call
    gems = YardUtils.instance.list_gems
    ok({ gems: }, text: gems.join("\n"))
  end
end

# Tool: List all classes and modules in the loaded YARD registry
class ListClassesTool < YardTool
  description 'List all classes and modules in the loaded YARD registry'
  annotations(title: 'List all classes and modules', read_only_hint: true)
  returns YardSchemas::LIST_CLASSES_SCHEMA
  arguments do
    required(:gem_name).filled(:string).description('Name of the gem to list classes for')
  end

  def call(gem_name:)
    with_yard_errors do
      classes = YardUtils.instance.list_classes(gem_name)
      ok({ gem_name:, classes: }, text: classes.join("\n"))
    end
  end
end

# Tool: Fetch documentation for a YARD object
class GetDocTool < YardTool
  description 'Fetch documentation and metadata for a class/module/method from YARD'
  annotations(title: 'Fetch documentation', read_only_hint: true)
  returns YardSchemas::DOC_OBJECT_SCHEMA
  arguments do
    required(:path).filled(:string).description("YARD path (e.g. 'String#upcase')")
    optional(:gem_name).filled(:string).description("Optional gem name to load specific gem's documentation")
  end

  def call(path:, gem_name: nil)
    with_yard_errors do
      doc = YardUtils.instance.get_doc(path, gem_name)
      ok({ path:, gem_name:, resource_uris: resource_uris(gem_name, path), document: doc }, text: JSON.pretty_generate(doc))
    end
  end
end

# Tool: List children under a namespace
class ChildrenTool < YardTool
  description 'List children under a namespace (class/module) in YARD'
  annotations(title: 'List children under a namespace', read_only_hint: true)
  returns YardSchemas::CHILDREN_SCHEMA
  arguments do
    required(:path).filled(:string).description('YARD path of the namespace')
    optional(:gem_name).filled(:string).description("Optional gem name to load specific gem's documentation")
  end

  def call(path:, gem_name: nil)
    with_yard_errors do
      children = YardUtils.instance.children(path, gem_name)
      ok({ path:, gem_name:, resource_uris: resource_uris(gem_name, path), children: }, text: children.join("\n"))
    end
  end
end

# Tool: List methods for a class/module
class MethodsListTool < YardTool
  description 'List methods for a class/module in YARD'
  annotations(title: 'List methods for a class/module', read_only_hint: true)
  returns YardSchemas::METHODS_SCHEMA
  arguments do
    required(:path).filled(:string).description('YARD path of the class/module')
    optional(:gem_name).filled(:string).description("Optional gem name to load specific gem's documentation")
  end

  def call(path:, gem_name: nil)
    with_yard_errors do
      methods = YardUtils.instance.methods_list(path, gem_name)
      ok({ path:, gem_name:, resource_uris: resource_uris(gem_name, path), methods: }, text: methods.join("\n"))
    end
  end
end

# Tool: Return inheritance and inclusion info
class HierarchyTool < YardTool
  description 'Return inheritance and inclusion info for a class/module in YARD'
  annotations(title: 'Return inheritance and inclusion info', read_only_hint: true)
  returns YardSchemas::HIERARCHY_SCHEMA
  arguments do
    required(:path).filled(:string).description('YARD path of the class/module')
    optional(:gem_name).filled(:string).description("Optional gem name to load specific gem's documentation")
  end

  def call(path:, gem_name: nil)
    with_yard_errors do
      hierarchy = YardUtils.instance.hierarchy(path, gem_name)
      ok({ path:, gem_name:, resource_uris: resource_uris(gem_name, path), hierarchy: })
    end
  end
end

# Tool: Perform fuzzy/full-text search
class SearchTool < YardTool
  description 'Perform fuzzy/full-text search in YARD registry'
  annotations(title: 'Perform fuzzy/full-text search', read_only_hint: true)
  returns YardSchemas::SEARCH_SCHEMA
  arguments do
    required(:query).filled(:string).description('Search query')
    optional(:gem_name).filled(:string).description('Optional gem name to search docstrings and paths within')
    optional(:limit).filled(:integer, gt?: 0, lteq?: 100).description('Maximum number of results to return')
    optional(:offset).filled(:integer, gteq?: 0).description('Number of results to skip')
  end

  def call(query:, gem_name: nil, limit: 25, offset: 0)
    with_yard_errors do
      results = YardUtils.instance.search(query, gem_name, limit:, offset:)
      ok({ query:, gem_name:, limit:, offset:, results: }, text: results.map { |result| "#{result[:score]}\t#{result[:path]}" }.join("\n"))
    end
  end
end

# Tool: Fetch source file and line number for a YARD object
class SourceLocationTool < YardTool
  description 'Fetch the source file and line number for a class/module/method from YARD'
  annotations(title: 'Fetch the source file and line number', read_only_hint: true)
  returns YardSchemas::SOURCE_LOCATION_SCHEMA
  arguments do
    required(:path).filled(:string).description("YARD path (e.g. 'String#upcase')")
    optional(:gem_name).filled(:string).description("Optional gem name to load specific gem's documentation")
  end

  def call(path:, gem_name: nil)
    with_yard_errors do
      location = YardUtils.instance.source_location(path, gem_name)
      ok({ path:, gem_name:, resource_uris: resource_uris(gem_name, path), source_location: location })
    end
  end
end

# Tool: Fetch code snippet for a YARD object from installed gems
class CodeSnippetTool < YardTool
  description 'Fetch the code snippet for a class/module/method from installed gems using YARD'
  annotations(title: 'Fetch the code snippet', read_only_hint: true)
  returns YardSchemas::CODE_SNIPPET_SCHEMA
  arguments do
    required(:path).filled(:string).description("YARD path (e.g. 'String#upcase')")
    optional(:gem_name).filled(:string).description("Optional gem name to load specific gem's documentation")
    optional(:max_chars).filled(:integer, gt?: 0, lteq?: 100_000).description('Maximum number of source characters to return')
  end

  def call(path:, gem_name: nil, max_chars: YardUtils::MAX_SOURCE_CHARS)
    with_yard_errors do
      snippet = YardUtils.instance.code_snippet(path, gem_name, max_chars:)
      ok({ path:, gem_name:, resource_uris: resource_uris(gem_name, path), snippet: }, text: snippet.to_s)
    end
  end
end

# Tool: Fetch the full ancestor chain (superclasses and included modules) for a class/module in YARD
class AncestorsTool < YardTool
  description 'Fetch the full ancestor chain (superclasses and included modules) for a class/module in YARD'
  annotations(title: 'Fetch the full ancestor chain', read_only_hint: true)
  returns YardSchemas::ANCESTORS_SCHEMA
  arguments do
    required(:path).filled(:string).description('YARD path of the class/module')
    optional(:gem_name).filled(:string).description("Optional gem name to load specific gem's documentation")
  end

  def call(path:, gem_name: nil)
    with_yard_errors do
      ancestors = YardUtils.instance.ancestors(path, gem_name)
      ok({ path:, gem_name:, resource_uris: resource_uris(gem_name, path), ancestors: }, text: ancestors.join("\n"))
    end
  end
end

# Tool: List related objects: included modules, mixins, and subclasses for a class/module in YARD
class RelatedObjectsTool < YardTool
  description 'List related objects: included modules, mixins, and subclasses for a class/module in YARD'
  annotations(title: 'List related objects', read_only_hint: true)
  returns YardSchemas::RELATED_OBJECTS_SCHEMA
  arguments do
    required(:path).filled(:string).description('YARD path of the class/module')
    optional(:gem_name).filled(:string).description("Optional gem name to load specific gem's documentation")
  end

  def call(path:, gem_name: nil)
    with_yard_errors do
      related = YardUtils.instance.related_objects(path, gem_name)
      ok({ path:, gem_name:, resource_uris: resource_uris(gem_name, path), related_objects: related })
    end
  end
end

# Tool: Explicitly build YARD docs for an installed gem
class BuildGemDocsTool < YardTool
  description 'Build the local YARD documentation index for an installed gem'
  annotations(title: 'Build YARD docs for a gem', read_only_hint: false)
  returns YardSchemas::BUILD_GEM_DOCS_SCHEMA
  arguments do
    required(:gem_name).filled(:string).description('Name of the installed gem to index')
  end

  def call(gem_name:)
    with_yard_errors do
      YardUtils.instance.build_docs(gem_name)
      ok({ gem_name:, indexed: true }, text: "Indexed #{gem_name}")
    end
  end
end

module YardMCP
  def self.start_server(preload: true)
    YardUtils.instance if preload
    server = FastMcp::Server.new(name: 'yard-mcp-server', version: YardMCP::VERSION)
    server.capabilities.clear
    server.capabilities[:tools] = {}
    server.capabilities[:resources] = {}
    register_tools(server)
    register_resources(server)
    server.start
  end

  def self.register_tools(server)
    server.register_tools(
      ListGemsTool,
      ListClassesTool,
      GetDocTool,
      ChildrenTool,
      MethodsListTool,
      HierarchyTool,
      SearchTool,
      SourceLocationTool,
      CodeSnippetTool,
      AncestorsTool,
      RelatedObjectsTool,
      BuildGemDocsTool
    )
  end

  def self.register_resources(server)
    server.register_resources(YardObjectResource, YardSourceResource)
  end
end

YardMCP.start_server(preload: true) if __FILE__ == $PROGRAM_NAME

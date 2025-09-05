#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fast_mcp'
require 'json'
require 'rubygems'
require 'yard'
require 'singleton'
require_relative 'yardmcp/version'

# Utility class for YARD operations
class YardUtils
  include Singleton

  attr_reader :libraries, :logger, :object_to_gem

  def initialize
    @libraries = {}
    @object_to_gem = {}
    @last_loaded_gem = nil
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

    spec = libraries[gem_name].first
    ver = "= #{spec.version}"
    dir = YARD::Registry.yardoc_file_for_gem(spec.name, ver)
    build_docs(gem_name) unless yardoc_exists?(dir)
    raise "Yardoc not found for #{gem_name}" unless yardoc_exists?(dir)

    YARD::Registry.load_yardoc(dir)
    @last_loaded_gem = gem_name
  end

  # Ensures the correct .yardoc is loaded for the given object path
  def ensure_yardoc_loaded_for_object!(object_path)
    # TODO: Handle multiple gems for the same object path, use some heuristic to determine the correct gem
    gem_name = @object_to_gem[object_path]&.first
    raise "No documentation found for #{object_path}" unless gem_name

    load_yardoc_for_gem(gem_name)
  end

  # Lists all installed gems that have a .yardoc file available.
  #
  # @return [Array<String>] An array of gem names with .yardoc files.
  def list_gems
    libraries.keys.sort
  end

  # Lists all classes and modules in the loaded YARD registry.
  #
  # @return [Array<String>] An array of fully qualified class/module paths.
  def list_classes(gem_name)
    load_yardoc_for_gem(gem_name)
    YARD::Registry.all(:class, :module).map(&:path).sort
  end

  # Fetches documentation and metadata for a YARD object (class/module/method).
  #
  # @param path [String] The YARD path (e.g., 'String#upcase').
  # @return [Hash] A hash containing type, name, namespace, visibility, docstring, parameters, return, and source.
  # @raise [RuntimeError] if the object is not found in the registry.
  def get_doc(path, gem_name = nil) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
    if gem_name
      # Load the specific gem's yardoc
      load_yardoc_for_gem(gem_name)
    else
      ensure_yardoc_loaded_for_object!(path)
    end
    obj = YARD::Registry.at(path)
    raise 'Object not found' unless obj

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
      source: obj.respond_to?(:source) ? obj.source : nil,
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
  def children(path)
    ensure_yardoc_loaded_for_object!(path)
    obj = YARD::Registry.at(path)
    unless obj
      logger.error "Object not found: #{path}"
      return []
    end
    obj.respond_to?(:children) ? obj.children.map(&:path) : []
  end

  # Lists all methods for a class or module.
  #
  # @param path [String] The YARD path of the class/module.
  # @return [Array<String>] An array of method paths.
  # @raise [RuntimeError] if the object is not found in the registry.
  def methods_list(path)
    ensure_yardoc_loaded_for_object!(path)
    obj = YARD::Registry.at(path)
    unless obj
      logger.error "Object not found: #{path}"
      return []
    end
    obj.respond_to?(:meths) ? obj.meths.map(&:path) : []
  end

  # Returns inheritance and inclusion information for a class or module.
  #
  # @param path [String] The YARD path of the class/module.
  # @return [Hash] A hash with :superclass (String or nil), :included_modules (Array<String>), and :mixins (Array<String>).
  # @raise [RuntimeError] if the object is not found in the registry.
  def hierarchy(path) # rubocop:disable Metrics/CyclomaticComplexity
    ensure_yardoc_loaded_for_object!(path)
    obj = YARD::Registry.at(path)
    unless obj
      logger.error "Object not found: #{path}"
      return []
    end
    {
      superclass: obj.respond_to?(:superclass) && obj.superclass ? obj.superclass.path : nil,
      included_modules: obj.respond_to?(:included_modules) ? obj.included_modules.map(&:path) : [],
      mixins: obj.respond_to?(:mixins) ? obj.mixins.map(&:path) : []
    }
  end

  # Returns the full ancestor chain (superclasses and included modules) for a class or module.
  #
  # @param path [String] The YARD path of the class/module.
  # @return [Array<String>] An array of ancestor paths.
  def ancestors(path)
    ensure_yardoc_loaded_for_object!(path)
    obj = YARD::Registry.at(path)
    unless obj
      logger.error "Object not found: #{path}"
      return []
    end
    obj.respond_to?(:inheritance_tree) ? obj.inheritance_tree(true).map(&:path) : []
  end

  # Returns related objects: included modules, mixins, and subclasses.
  #
  # @param path [String] The YARD path of the class/module.
  # @return [Hash] A hash with :included_modules, :mixins, :subclasses.
  def related_objects(path) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    ensure_yardoc_loaded_for_object!(path)
    obj = YARD::Registry.at(path)
    unless obj
      logger.error "Object not found: #{path}"
      return {}
    end
    subclasses = YARD::Registry.all(:class).select { |c| c.superclass && c.superclass.path == obj.path }.map(&:path)
    {
      included_modules: obj.respond_to?(:included_modules) ? obj.included_modules.map(&:path) : [],
      mixins: obj.respond_to?(:mixins) ? obj.mixins.map(&:path) : [],
      subclasses:
    }
  end

  # Performs a fuzzy/full-text search in the YARD registry for objects whose path or docstring matches the query.
  #
  # @param query [String] The search query string.
  # @return [Array<Hash>] An array of hashes with :path and :score for matching object paths, ranked by relevance.
  def search(query) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    require 'levenshtein' unless defined?(Levenshtein)
    results = []
    YARD::Registry.all.each do |obj|
      path = obj.path.to_s
      doc = obj.docstring.to_s
      next if path.empty?

      score = nil
      if path == query
        score = 100
      elsif path.start_with?(query)
        score = 90
      elsif path.include?(query)
        score = 80
      elsif doc.include?(query)
        score = 60
      else
        # Fuzzy match: allow up to 2 edits for short queries, 3 for longer
        dist = Levenshtein.distance(path.downcase, query.downcase)
        score = 70 - dist if dist <= [2, query.length / 3].max
      end
      results << { path:, score: } if score
    end
    # Sort by score descending, then alphabetically
    results.sort_by { |r| [-r[:score], r[:path]] }
  end

  # Returns the source file and line number for a YARD object (class/module/method).
  #
  # @param path [String] The YARD path (e.g., 'String#upcase').
  # @return [Hash] A hash with :file (String or nil) and :line (Integer or nil).
  # @raise [RuntimeError] if the object is not found in the registry.
  def source_location(path)
    ensure_yardoc_loaded_for_object!(path)
    obj = YARD::Registry.at(path)
    unless obj
      logger.error "Object not found: #{path}"
      return []
    end
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
  def code_snippet(path)
    ensure_yardoc_loaded_for_object!(path)
    obj = YARD::Registry.at(path)
    unless obj
      logger.error "Object not found: #{path}"
      return []
    end
    obj.respond_to?(:source) ? obj.source : nil
  end

  private

  def yardoc_exists?(dir)
    dir && File.directory?(dir)
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
        (@object_to_gem[obj_path] ||= []).concat(gem_names)
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

    # Collect all objects for this gem
    gem_objects = {}
    YARD::Registry.all.each do |obj|
      logger.debug "Adding #{obj.path} to #{gem_name}"
      gem_objects[obj.path.to_s] = [gem_name]
    end
    gem_objects
  end

  def build_docs(gem_name)
    logger.info "Building docs for #{gem_name}..."
    YARD::CLI::Gems.new.run(gem_name)
  end
end

# Tool: List all gems with .yardoc files
class ListGemsTool < FastMcp::Tool
  description 'List all installed gems that have a .yardoc file'

  def call
    gems = YardUtils.instance.list_gems
    { content: gems.map { |gem| { text: gem, type: 'gem' } } }
  end
end

# Tool: List all classes and modules in the loaded YARD registry
class ListClassesTool < FastMcp::Tool
  description 'List all classes and modules in the loaded YARD registry'
  arguments do
    required(:gem_name).filled(:string).description('Name of the gem to list classes for')
  end

  def call(gem_name:)
    classes = YardUtils.instance.list_classes(gem_name)
    { content: classes.map { |cls| { text: cls, type: 'class' } } }
  end
end

# Tool: Fetch documentation for a YARD object
class GetDocTool < FastMcp::Tool
  description 'Fetch documentation and metadata for a class/module/method from YARD'
  arguments do
    required(:path).filled(:string).description("YARD path (e.g. 'String#upcase')")
    optional(:gem_name).filled(:string).description("Optional gem name to load specific gem's documentation")
  end

  def call(path:, gem_name: nil)
    { content: YardUtils.instance.get_doc(path, gem_name) }
  end
end

# Tool: List children under a namespace
class ChildrenTool < FastMcp::Tool
  description 'List children under a namespace (class/module) in YARD'
  arguments do
    required(:path).filled(:string).description('YARD path of the namespace')
  end

  def call(path:)
    children = YardUtils.instance.children(path)
    { content: children.map { |child| { text: child, type: 'child' } } }
  end
end

# Tool: List methods for a class/module
class MethodsListTool < FastMcp::Tool
  description 'List methods for a class/module in YARD'
  arguments do
    required(:path).filled(:string).description('YARD path of the class/module')
  end

  def call(path:)
    methods = YardUtils.instance.methods_list(path)
    { content: methods.map { |method| { text: method, type: 'method' } } }
  end
end

# Tool: Return inheritance and inclusion info
class HierarchyTool < FastMcp::Tool
  description 'Return inheritance and inclusion info for a class/module in YARD'
  arguments do
    required(:path).filled(:string).description('YARD path of the class/module')
  end

  def call(path:)
    { content: YardUtils.instance.hierarchy(path) }
  end
end

# Tool: Perform fuzzy/full-text search
class SearchTool < FastMcp::Tool
  description 'Perform fuzzy/full-text search in YARD registry'
  arguments do
    required(:query).filled(:string).description('Search query')
  end

  def call(query:)
    # Enhanced search: ranked, fuzzy, and full-text
    results = YardUtils.instance.search(query)
    { content: results.map { |result| { text: result[:path], score: result[:score], type: 'search_result' } } }
  end
end

# Tool: Fetch source file and line number for a YARD object
class SourceLocationTool < FastMcp::Tool
  description 'Fetch the source file and line number for a class/module/method from YARD'
  arguments do
    required(:path).filled(:string).description("YARD path (e.g. 'String#upcase')")
  end

  def call(path:)
    { content: YardUtils.instance.source_location(path) }
  end
end

# Tool: Fetch code snippet for a YARD object from installed gems
class CodeSnippetTool < FastMcp::Tool
  description 'Fetch the code snippet for a class/module/method from installed gems using YARD'
  arguments do
    required(:path).filled(:string).description("YARD path (e.g. 'String#upcase')")
  end

  def call(path:)
    snippet = YardUtils.instance.code_snippet(path)
    { content: { text: snippet, type: 'code_snippet' } }
  end
end

# Tool: Fetch the full ancestor chain (superclasses and included modules) for a class/module in YARD
class AncestorsTool < FastMcp::Tool
  description 'Fetch the full ancestor chain (superclasses and included modules) for a class/module in YARD'
  arguments do
    required(:path).filled(:string).description('YARD path of the class/module')
  end

  def call(path:)
    ancestors = YardUtils.instance.ancestors(path)
    { content: ancestors.map { |ancestor| { text: ancestor, type: 'ancestor' } } }
  end
end

# Tool: List related objects: included modules, mixins, and subclasses for a class/module in YARD
class RelatedObjectsTool < FastMcp::Tool
  description 'List related objects: included modules, mixins, and subclasses for a class/module in YARD'
  arguments do
    required(:path).filled(:string).description('YARD path of the class/module')
  end

  def call(path:)
    { content: YardUtils.instance.related_objects(path) }
  end
end

module YardMCP
  def self.start_server(preload: true)
    YardUtils.instance if preload
    server = FastMcp::Server.new(name: 'yard-mcp-server', version: YardMCP::VERSION)
    server.register_tool(ListGemsTool)
    server.register_tool(ListClassesTool)
    server.register_tool(GetDocTool)
    server.register_tool(ChildrenTool)
    server.register_tool(MethodsListTool)
    server.register_tool(HierarchyTool)
    server.register_tool(SearchTool)
    server.register_tool(SourceLocationTool)
    server.register_tool(CodeSnippetTool)
    server.register_tool(AncestorsTool)
    server.register_tool(RelatedObjectsTool)
    server.start
  end
end

YardMCP.start_server(preload: true) if __FILE__ == $PROGRAM_NAME

# yardmcp

A programmable server for exploring and querying Ruby gem documentation using YARD and the FastMCP protocol.

## Overview

**yardmcp** exposes Ruby gem and YARD documentation as a set of programmable tools via a FastMCP server. It enables clients to:
- List installed gems with YARD docs
- Explore classes, modules, and methods
- Fetch documentation, code snippets, and source locations
- Perform fuzzy/full-text search across documentation
- Introspect inheritance, mixins, and related objects

This is useful for building documentation browsers, code assistants, or integrating Ruby/YARD docs into other systems.

## Features

- **List Gems:** See all installed gems with YARD documentation
- **List Classes/Modules:** Explore all classes/modules in a gem
- **Fetch Documentation:** Get docstrings, tags, parameters, return types, and more for any class/module/method
- **List Children:** List constants, classes, modules, and methods under a namespace
- **List Methods:** List all methods for a class/module
- **Hierarchy:** Get inheritance and inclusion info
- **Ancestors:** Get the full ancestor chain
- **Related Objects:** Find included modules, mixins, and subclasses
- **Search:** Fuzzy/full-text search across all documentation
- **Source Location:** Find the file and line number for any object
- **Code Snippet:** Fetch the source code for any object
- **Cache Management:** View cache statistics and clear cache to free memory
- **Memory Optimization:** LRU cache with configurable memory limits and automatic eviction

## Installation

### As a Gem

You can build and install the gem locally:

```sh
gem build yardmcp.gemspec
gem install yardmcp-0.1.0.gem
```

This will install the `yardmcp` executable in your PATH.

## Usage

### Running the Server

The server is designed to be run as a long-lived process with efficient memory management.
**Startup is now faster** as it builds only a gem index initially and loads documentation
on-demand with LRU caching.

Start the server:

```sh
yardmcp
```

### Memory Configuration

The server supports several environment variables for memory management:

- `YARDMCP_CACHE_CAPACITY`: Maximum number of gem registries to keep in cache (default: 10)
- `YARDMCP_MAX_MEMORY_MB`: Maximum memory usage in megabytes (default: 100)
- `YARDMCP_ENABLE_STREAMING`: Enable streaming for large source code (default: true)
- `YARDMCP_STREAM_CHUNK_SIZE`: Chunk size for streaming in bytes (default: 4096)

Example with custom settings:

```sh
YARDMCP_CACHE_CAPACITY=20 YARDMCP_MAX_MEMORY_MB=200 yardmcp
```

### Tool List

The following tools are available (use `tools/list` to discover):
- ListGemsTool
- ListClassesTool
- GetDocTool
- ChildrenTool
- MethodsListTool
- HierarchyTool
- SearchTool
- SourceLocationTool
- CodeSnippetTool
- AncestorsTool
- RelatedObjectsTool
- CacheStatsTool
- ClearCacheTool

See the code in `lib/yardmcp.rb` for argument details and return formats.

## Development

- **Run tests:**
  ```sh
  bundle exec rspec
  ```
  The test suite starts a persistent server process for all tests and waits for the server to be ready before running examples.
- **Code style:**
  ```sh
  bundle exec rubocop
  ```
- **Regenerate YARD docs for a gem:**
  ```sh
  yard gems <gemname>
  ```

## Requirements

- Ruby 3.2+
- Bundler
- Gems: `fast-mcp`, `levenshtein`, `yard`, `rspec` (for tests)

## License

MIT License. See [LICENSE](LICENSE) for details.
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

The server is designed to be run as a long-lived process. **Startup may take some time**
as it builds an index of all YARD documentation for installed gems. During startup,
progress and logs (including `Index built ...`) are printed to stderr.
Clients should wait for the `Index built` message on stderr before sending requests.

Start the server:

```sh
yardmcp
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
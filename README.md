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

1. Install the gem:

```sh
gem install yardmcp
```

2. Add to your MCP:

```json
{
  "mcpServers": {
    "yardmcp": {
      "command": "yardmcp"
    }
  }
}
```

or

```sh
claude mcp add-json "yardmcp" '{"command": "yardmcp", "args": []}'
```

### Usage Examples

Once configured in Claude Code or Cursor, you can ask questions like:

**Basic Documentation Queries:**
- "Show me the documentation for the String#upcase method"
- "What methods are available in the Array class?"
- "List all gems that have YARD documentation"
- "Show me the source code for ActiveRecord::Base.find"

**Exploring a Gem:**
- "List all classes in the rails gem"
- "Show me the methods in ActiveRecord::Base"
- "What modules are included in ActionController::Base?"
- "Show me the inheritance hierarchy for ActiveRecord::Migration"

**Search and Discovery:**
- "Search for methods related to 'validation' in Rails"
- "Find all classes that include the Enumerable module"
- "Show me the source location for the Sidekiq::Worker module"
- "What are the child classes of ApplicationController?"

**Code Understanding:**
- "Show me the parameters and return type for User.authenticate"
- "What exceptions does this method raise?"
- "Show me the ancestor chain for MyCustomClass"
- "What modules are mixed into this class?"

### Tool List

The following tools are available (use `tools/list` to discover):
- ListGemsTool - Lists all gems with YARD documentation
- ListClassesTool - Lists all classes/modules in a specific gem
- GetDocTool - Fetches detailed documentation for any object
- ChildrenTool - Lists child objects under a namespace
- MethodsListTool - Lists all methods for a class/module
- HierarchyTool - Shows inheritance and module inclusion hierarchy
- SearchTool - Performs fuzzy/full-text search across all docs
- SourceLocationTool - Gets file and line number for any object
- CodeSnippetTool - Fetches the actual source code
- AncestorsTool - Gets the complete ancestor chain
- RelatedObjectsTool - Finds mixins, subclasses, and related objects

See the code in `lib/yardmcp.rb` for argument details and return formats.

## Initial Setup

### Building YARD Documentation

Before using yardmcp, you need to build YARD documentation for your installed gems. This creates the `.yardoc` files that yardmcp reads.

**Build documentation for all gems:**
```sh
yard gems --rebuild
```
This may take several minutes depending on how many gems you have installed.

**Build documentation for specific gems:**
```sh
yard gems rails
yard gems rspec
```

**Note:** If you encounter errors with Ruby 3.4+, you may need to install YARD from the GitHub master branch:
```sh
gem install specific_install
gem specific_install -l https://github.com/lsegal/yard.git
```

The YARD documentation is stored in `~/.yard/` and will be automatically used by yardmcp.

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

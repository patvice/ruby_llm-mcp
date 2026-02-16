# frozen_string_literal: true

require_relative "lib/ruby_llm/mcp/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_llm-mcp"
  spec.version = RubyLLM::MCP::VERSION
  spec.authors = ["Patrick Vice"]
  spec.email = ["patrickgvice@gmail.com"]

  spec.summary = "A RubyLLM MCP Client"
  spec.description = <<~DESC
    A Ruby client for the Model Context Protocol (MCP) that seamlessly integrates with RubyLLM.
    Supports both native full-featured implementation and the official mcp-sdk gem.
    Connect to MCP servers via SSE, stdio, or HTTP transports, automatically convert MCP tools into
    RubyLLM-compatible tools, and enable AI models to interact with external data sources and
    services. Makes using MCP with RubyLLM as easy as possible.
  DESC

  spec.homepage = "https://www.rubyllm-mcp.com"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.1.3")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/patvice/ruby_llm-mcp"
  spec.metadata["changelog_uri"] = "#{spec.metadata['source_code_uri']}/commits/main"
  spec.metadata["documentation_uri"] = "#{spec.homepage}/guides/"
  spec.metadata["bug_tracker_uri"] = "#{spec.metadata['source_code_uri']}/issues"

  spec.metadata["rubygems_mfa_required"] = "true"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.glob("lib/**/*") + ["README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "httpx", "~> 1.4"
  spec.add_dependency "json_schemer", "~> 2.4"
  spec.add_dependency "json-schema", "~> 5.0"
  spec.add_dependency "ruby_llm", "~> 1.9"
  spec.add_dependency "zeitwerk", "~> 2"

  # Optional dependency for mcp_sdk adapter
  # Users who want to use adapter: :mcp_sdk should add to their Gemfile:
  #   gem 'mcp', '~> 0.4'
end

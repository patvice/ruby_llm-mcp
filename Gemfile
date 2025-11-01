# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development do
  # Development dependencies
  # TODO: Remove this when ruby_llm 1.9 is released
  gem "ruby_llm", git: "https://github.com/crmne/ruby_llm.git", branch: "main"

  gem "bundler", ">= 2.0"
  gem "debug"
  gem "dotenv", ">= 3.0"
  gem "rake", ">= 13.0"
  gem "rdoc"
  gem "reline"
  gem "rspec", "~> 3.12"
  gem "rubocop", ">= 1.76"
  gem "rubocop-rake", ">= 0.7"
  gem "rubocop-rspec", ">= 3.6"
  gem "simplecov"
  gem "vcr"
  gem "webmock", "~> 3.25"

  # For another MCP server test
  gem "fast-mcp"
  gem "puma"
  gem "rack"
end

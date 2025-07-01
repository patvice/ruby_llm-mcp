# frozen_string_literal: true

namespace :release do
  desc "Release a new version of the gem"
  task :version do
    # Load the current version from version.rb
    require_relative "../../lib/ruby_llm/schema/version"
    version = RubyLlm::Schema::VERSION

    puts "Releasing version #{version}..."

    # Make sure we are on the main branch
    system "git checkout main"
    system "git pull origin main"

    # Create a new tag for the version
    system "git tag -a v#{version} -m 'Release version #{version}'"
    system "git push origin v#{version}"

    system "gem build ruby_llm-mcp.gemspec"
    system "gem push ruby_llm-mcp-#{version}.gem"
  end
end

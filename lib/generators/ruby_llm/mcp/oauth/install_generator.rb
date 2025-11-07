# frozen_string_literal: true

require "rails/generators/base"
require "rails/generators/active_record"

module RubyLlm
  module Mcp
    module Oauth
      module Generators
        class InstallGenerator < Rails::Generators::Base
          include ActiveRecord::Generators::Migration

          source_root File.expand_path("templates", __dir__)

          desc "Install RubyLLM MCP OAuth configuration for multi-user authentication"

          def create_migrations
            migration_template "create_mcp_oauth_credentials.rb",
                               "db/migrate/create_mcp_oauth_credentials.rb"
            migration_template "create_mcp_oauth_states.rb",
                               "db/migrate/create_mcp_oauth_states.rb"
          end

          def create_models
            template "mcp_oauth_credential.rb", "app/models/mcp_oauth_credential.rb"
            template "mcp_oauth_state.rb", "app/models/mcp_oauth_state.rb"
          end

          def create_storage_adapter
            template "user_token_storage.rb", "app/services/oauth_storage/user_token_storage.rb"
          end

          def create_client_factory
            template "mcp_client_factory.rb", "app/services/mcp_client_factory.rb"
          end

          def create_controller
            template "mcp_connections_controller.rb", "app/controllers/mcp_connections_controller.rb"
          end

          def add_routes_snippet
            route_snippet = File.read(File.join(self.class.source_root, "routes.rb"))
            say "\n📋 Add these routes to config/routes.rb:\n\n", :yellow
            say route_snippet, :cyan
            say "\n"
          end

          def create_views
            template "views/index.html.erb", "app/views/mcp_connections/index.html.erb"
          end

          def create_user_concern
            template "user_mcp_oauth_concern.rb", "app/models/concerns/user_mcp_oauth.rb"
          end

          def create_example_job
            template "example_job.rb", "app/jobs/ai_research_job.rb"
          end

          def display_readme
            return unless behavior == :invoke

            display_header
            display_created_files
            display_next_steps
            display_documentation_links
            display_usage_example
          end

          private

          def display_header
            say "\n"
            say "=" * 70, :green
            say "✅ RubyLLM MCP OAuth installed successfully!", :green
            say "=" * 70, :green
            say "\n"
          end

          def display_created_files
            say "📦 Created files:", :blue
            say "  • db/migrate/..._create_mcp_oauth_credentials.rb"
            say "  • db/migrate/..._create_mcp_oauth_states.rb"
            say "  • app/models/mcp_oauth_credential.rb"
            say "  • app/models/mcp_oauth_state.rb"
            say "  • app/models/concerns/user_mcp_oauth.rb"
            say "  • app/services/oauth_storage/user_token_storage.rb"
            say "  • app/services/mcp_client_factory.rb"
            say "  • app/controllers/mcp_connections_controller.rb"
            say "  • app/views/mcp_connections/index.html.erb"
            say "  • app/jobs/ai_research_job.rb (example)"
            say "\n"
          end

          def display_next_steps
            say "📝 Next steps:", :yellow
            say "  1. Add routes (shown above) to config/routes.rb"
            say "  2. Run migrations: rails db:migrate"
            say "  3. Include concern in User model: include UserMcpOauth"
            say "  4. Configure: DEFAULT_MCP_SERVER_URL=https://mcp.example.com/api"
            say "  5. Generate encryption keys: rails db:encryption:init"
            say "  6. Restart server and visit /mcp_connections"
            say "\n"
          end

          def display_documentation_links
            say "📚 Documentation:", :cyan
            say "  • OAuth Guide: docs/guides/rails-oauth.md"
            say "  • Full OAuth Docs: OAUTH.md"
            say "  • Online: https://www.rubyllm-mcp.com/guides/rails-oauth"
            say "\n"
          end

          def display_usage_example
            say "💡 Usage: client = McpClientFactory.for_user(user)", :blue
            say "⭐ Star us: https://github.com/patvice/ruby_llm-mcp", :magenta
            say "\n"
          end
        end
      end
    end
  end
end

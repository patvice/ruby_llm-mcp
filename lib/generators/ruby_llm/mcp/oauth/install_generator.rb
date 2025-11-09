# frozen_string_literal: true

require "rails/generators/base"
require "rails/generators/active_record"

module RubyLLM
  module MCP
    module OAuth
      module Generators
        class InstallGenerator < Rails::Generators::Base
          include Rails::Generators::Migration

          source_root File.expand_path("templates", __dir__)

          namespace "ruby_llm:mcp:oauth"

          argument :user_model, type: :string, default: "User", banner: "UserModel",
                                desc: "The name of the user model (default: User)"

          class_option :namespace, type: :string, default: nil,
                                   desc: "Namespace for generated files (e.g., Admin)"
          class_option :controller_name, type: :string, default: "McpConnectionsController",
                                         desc: "Name of the controller to generate"
          class_option :skip_routes, type: :boolean, default: false,
                                     desc: "Skip adding routes to config/routes.rb"
          class_option :skip_views, type: :boolean, default: false,
                                    desc: "Skip generating view files"

          desc "Install RubyLLM MCP OAuth configuration for multi-user authentication\n" \
               "Usage: rails g ruby_llm:mcp:oauth:install [UserModel] [options]"

          def self.next_migration_number(dirname)
            ::ActiveRecord::Generators::Base.next_migration_number(dirname)
          end

          # Validation methods
          def check_dependencies
            check_user_model_exists
            check_rails_version
            check_encryption_configured
          end

          def create_migrations
            migration_template "migrations/create_mcp_oauth_credentials.rb.tt",
                               "db/migrate/create_mcp_oauth_credentials.rb"
            migration_template "migrations/create_mcp_oauth_states.rb.tt",
                               "db/migrate/create_mcp_oauth_states.rb"
          end

          def create_models
            template "models/mcp_oauth_credential.rb.tt", "app/models/mcp_oauth_credential.rb"
            template "models/mcp_oauth_state.rb.tt", "app/models/mcp_oauth_state.rb"
          end

          def create_token_storage_concern
            template "concerns/mcp_token_storage.rb.tt", "app/models/concerns/mcp_token_storage.rb"
          end

          def create_mcp_client
            template "lib/mcp_client.rb.tt", "app/lib/mcp_client.rb"
          end

          def create_controller
            controller_path = if namespace_name
                                "#{namespace_name.underscore}/mcp_connections_controller.rb"
                              else
                                "mcp_connections_controller.rb"
                              end
            template "controllers/mcp_connections_controller.rb.tt", "app/controllers/#{controller_path}"
          end

          def add_routes
            return if options[:skip_routes]

            routes_content = if namespace_name
                               <<~ROUTES.strip
                                 namespace :#{namespace_name.underscore} do
                                   resources :mcp_connections, only: [ :index, :create ] do
                                     collection do
                                       get :callback
                                     end
                                     member do
                                       delete :disconnect
                                       get :refresh
                                     end
                                   end
                                 end
                               ROUTES
                             else
                               <<~ROUTES.strip
                                 resources :mcp_connections, only: [ :index, :create ] do
                                   collection do
                                     get :callback
                                   end
                                   member do
                                     delete :disconnect
                                     get :refresh
                                   end
                                 end
                               ROUTES
                             end

            route routes_content
          end

          def create_views
            return if options[:skip_views]

            view_path = namespace_name ? "#{namespace_name.underscore}/mcp_connections" : "mcp_connections"
            copy_file "views/index.html.erb", "app/views/#{view_path}/index.html.erb"
          end

          def add_user_concern
            template "concerns/user_mcp_oauth_concern.rb.tt", "app/models/concerns/user_mcp_oauth.rb"
          end

          def inject_concern_into_user_model
            user_model_path = "app/models/#{user_model_name.underscore}.rb"
            return unless File.exist?(user_model_path)

            # Check if concern is already included
            if File.read(user_model_path).include?("include UserMcpOauth")
              say "  ⏭️  UserMcpOauth concern already included in #{user_model_name}", :yellow
              return
            end

            inject_into_class user_model_path, user_model_name do
              "  include UserMcpOauth\n"
            end

            say "  ✅ Added UserMcpOauth concern to #{user_model_name}", :green
          rescue StandardError => e
            say "  ⚠️  Could not automatically add concern to #{user_model_name}: #{e.message}", :yellow
            say "  Please manually add: include UserMcpOauth", :yellow
          end

          def create_example_job
            template "jobs/example_job.rb.tt", "app/jobs/ai_research_job.rb"
          end

          def create_cleanup_job
            template "jobs/cleanup_expired_oauth_states_job.rb.tt", "app/jobs/cleanup_expired_oauth_states_job.rb"
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

          # Validation methods
          def check_user_model_exists
            user_model_path = "app/models/#{user_model_name.underscore}.rb"
            return if File.exist?(user_model_path)

            say "\n⚠️  Warning: #{user_model_name} model not found at #{user_model_path}", :yellow
            say "The generator will continue, but you'll need to:", :yellow
            say "  1. Create the #{user_model_name} model", :yellow
            say "  2. Include the UserMcpOauth concern in your #{user_model_name} model", :yellow
            say "\n"
          end

          def check_rails_version
            return if defined?(Rails) && Rails::VERSION::MAJOR >= 7

            say "\n⚠️  Warning: Rails 7.0+ recommended for this generator", :yellow
            say "Current Rails version: #{Rails::VERSION::STRING}", :yellow
            say "\n"
          end

          def check_encryption_configured
            return unless defined?(ActiveRecord::Encryption)

            if ActiveRecord::Encryption.config.primary_key.blank?
              say "\n🔐 ActiveRecord::Encryption not configured. Generating encryption keys...", :yellow

              begin
                # Run rails db:encryption:init to generate keys
                run "bin/rails db:encryption:init", verbose: false

                say "✅ Encryption keys generated successfully!", :green
                say "   Keys have been added to your credentials file.", :green
                say "   ⚠️  Important: Restart your Rails server for changes to take effect.", :yellow
                say "\n"
              rescue StandardError => e
                say "\n⚠️  Warning: Could not automatically generate encryption keys", :yellow
                say "Error: #{e.message}", :yellow
                say "Please run manually: rails db:encryption:init", :yellow
                say "Then add the generated keys to your credentials or environment variables", :yellow
                say "\n"
              end
            end
          rescue StandardError => e
            # Encryption config check failed, but we'll continue
            say "\n⚠️  Could not check encryption configuration: #{e.message}", :yellow
            say "You may need to run: rails db:encryption:init", :yellow
            say "\n"
          end

          # Helper methods for template variables
          def user_model_name
            @user_model_name ||= user_model.camelize
          end

          def user_table_name
            @user_table_name ||= user_model_name.underscore.pluralize
          end

          def user_variable_name
            @user_variable_name ||= user_model_name.underscore
          end

          def controller_class_name
            @controller_class_name ||= if namespace_name
                                         "#{namespace_name}::#{options[:controller_name]}"
                                       else
                                         options[:controller_name]
                                       end
          end

          def controller_file_path
            @controller_file_path ||= if namespace_name
                                        "#{namespace_name.underscore}/#{controller_name.underscore}"
                                      else
                                        controller_name.underscore
                                      end
          end

          def controller_name
            @controller_name ||= options[:controller_name].sub(/Controller$/, "")
          end

          def current_user_method
            @current_user_method ||= "current_#{user_variable_name}"
          end

          def authenticate_method
            @authenticate_method ||= "authenticate_#{user_variable_name}!"
          end

          def credential_model_name
            @credential_model_name ||= "McpOauthCredential"
          end

          def credential_table_name
            @credential_table_name ||= "mcp_oauth_credentials"
          end

          def state_model_name
            @state_model_name ||= "McpOauthState"
          end

          def state_table_name
            @state_table_name ||= "mcp_oauth_states"
          end

          def namespace_name
            @namespace_name ||= options[:namespace]
          end

          def concern_module_name
            @concern_module_name ||= "UserMcpOauth"
          end

          # Display methods
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
            say "  • app/models/concerns/mcp_token_storage.rb"
            say "  • app/models/concerns/user_mcp_oauth.rb"

            # Show if concern was injected
            user_model_path = "app/models/#{user_model_name.underscore}.rb"
            if File.exist?(user_model_path) && File.read(user_model_path).include?("include UserMcpOauth")
              say "  • app/models/#{user_model_name.underscore}.rb (concern added)", :green
            end

            say "  • app/lib/mcp_client.rb"
            say "  • app/controllers/#{controller_file_path}_controller.rb"
            unless options[:skip_views]
              say "  • app/views/#{"#{namespace_name.underscore}/" if namespace_name}mcp_connections/index.html.erb"
            end
            say "  • app/jobs/ai_research_job.rb (example)"
            say "  • app/jobs/cleanup_expired_oauth_states_job.rb"
            say "\n"
          end

          def display_next_steps
            say "📝 Next steps:", :yellow

            routes_status = options[:skip_routes] ? "not added - add them manually" : "added automatically"
            say "  1. Routes #{routes_status}"
            say "  2. Run migrations: rails db:migrate"

            # Only show concern instruction if user model doesn't exist
            user_model_path = "app/models/#{user_model_name.underscore}.rb"
            unless File.exist?(user_model_path)
              say "  3. Include concern in #{user_model_name}: include UserMcpOauth"
            end

            connections_path = namespace_name ? "#{namespace_name.underscore}/mcp_connections" : "mcp_connections"
            say "  #{File.exist?(user_model_path) ? '3' : '4'}. Visit /#{connections_path} \
              and enter your MCP server URL to connect"
            say "\n"
          end

          def display_documentation_links
            say "📚 Documentation:", :cyan
            say "  • OAuth Guide: docs/guides/rails-oauth.md"
            say "  • Full OAuth Docs: docs/guides/oauth.md"
            say "  • Online: https://www.rubyllm-mcp.com/guides/rails-oauth"
            say "\n"
          end

          def display_usage_example
            say "💡 Usage Examples:", :blue
            say "   client = McpClient.for(#{user_variable_name}, server_url: 'https://mcp.example.com')"
            say "   or: #{user_variable_name}.mcp_client(server_url: 'https://mcp.example.com')"
            say "⭐ Star us: https://github.com/patvice/ruby_llm-mcp", :magenta
            say "\n"
          end
        end
      end
    end
  end
end

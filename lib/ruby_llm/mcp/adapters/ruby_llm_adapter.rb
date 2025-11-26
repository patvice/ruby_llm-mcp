# frozen_string_literal: true

require "forwardable"

module RubyLLM
  module MCP
    module Adapters
      # RubyLLM Adapter - wraps the Native protocol implementation
      # This is a thin bridge between the public API and Native::Client
      class RubyLLMAdapter < BaseAdapter
        extend Forwardable

        supports :tools, :prompts, :resources, :resource_templates,
                 :completions, :logging, :sampling, :roots,
                 :notifications, :progress_tracking, :human_in_the_loop,
                 :elicitation, :subscriptions, :list_changed_notifications

        supports_transport :stdio, :sse, :streamable, :streamable_http

        attr_reader :native_client

        def initialize(client, transport_type:, config: {})
          validate_transport!(transport_type)
          super

          request_timeout = config.delete(:request_timeout)
          transport_config = prepare_transport_config(config, transport_type)

          @native_client = Native::Client.new(
            name: client.name,
            transport_type: transport_type,
            transport_config: transport_config,
            request_timeout: request_timeout,
            human_in_the_loop_callback: build_human_in_the_loop_callback(client),
            roots_callback: -> { client.roots.paths },
            logging_enabled: client.logging_handler_enabled?,
            logging_level: client.on_logging_level,
            elicitation_enabled: client.elicitation_enabled?,
            progress_tracking_enabled: client.tracking_progress?,
            elicitation_callback: ->(elicitation) { client.on[:elicitation]&.call(elicitation) },
            sampling_callback: ->(sample) { client.on[:sampling]&.call(sample) },
            notification_callback: ->(notification) { NotificationHandler.new(client).execute(notification) }
          )
        end

        def_delegators :@native_client,
                       :start, :stop, :restart!, :alive?, :ping,
                       :capabilities, :client_capabilities, :protocol_version,
                       :tool_list, :execute_tool,
                       :resource_list, :resource_read, :resource_template_list,
                       :resources_subscribe,
                       :prompt_list, :execute_prompt,
                       :completion_resource, :completion_prompt,
                       :set_logging, :set_progress_tracking,
                       :initialize_notification, :cancelled_notification,
                       :roots_list_change_notification,
                       :ping_response, :roots_list_response,
                       :sampling_create_message_response,
                       :error_response, :elicitation_response,
                       :register_in_flight_request, :unregister_in_flight_request,
                       :cancel_in_flight_request

        def register_resource(resource)
          client.linked_resources << resource
          client.resources[resource.name] = resource
        end

        private

        def prepare_transport_config(config, transport_type)
          transport_config = config.dup

          if %i[sse streamable streamable_http].include?(transport_type)
            oauth_provider = Auth::TransportOauthHelper.create_oauth_provider(transport_config) if Auth::TransportOauthHelper.oauth_config_present?(transport_config)

            Auth::TransportOauthHelper.prepare_http_transport_config(transport_config, oauth_provider)
          elsif transport_type == :stdio
            Auth::TransportOauthHelper.prepare_stdio_transport_config(transport_config)
          else
            transport_config
          end
        end

        def build_human_in_the_loop_callback(client)
          lambda do |name, params|
            return true unless client.human_in_the_loop?

            handler_or_block = client.on[:human_in_the_loop]

            # Check if it's a handler class
            if Handlers.handler_class?(handler_or_block)
              execute_handler_class(handler_or_block, name, params, client)
            else
              # Legacy block-based callback
              handler_or_block.call(name, params)
            end
          end
        end

        def execute_handler_class(handler_class, name, params, _client)
          approval_id = SecureRandom.uuid

          handler_instance = handler_class.new(
            tool_name: name,
            parameters: params,
            approval_id: approval_id,
            coordinator: @native_client
          )

          result = handler_instance.call

          # Handle different return types
          case result
          when Hash
            result[:approved] == true
          when Handlers::Promise, TrueClass, FalseClass
            result # Return promise to Native::Client or boolean
          when :pending
            # Create and return promise for registry pattern
            promise = Handlers::Promise.new
            Handlers::HumanInTheLoopRegistry.store(approval_id, {
                                                     promise: promise,
                                                     timeout: handler_instance.timeout,
                                                     tool_name: name,
                                                     parameters: params
                                                   })
            promise
          else
            RubyLLM::MCP.logger.error("Handler returned unexpected type: #{result.class}")
            false
          end
        rescue StandardError => e
          RubyLLM::MCP.logger.error("Error in human-in-the-loop handler: #{e.message}\n#{e.backtrace.join("\n")}")
          false
        end
      end
    end
  end
end

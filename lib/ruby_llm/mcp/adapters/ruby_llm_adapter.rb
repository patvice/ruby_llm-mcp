# frozen_string_literal: true

require "forwardable"

module RubyLLM
  module MCP
    module Adapters
      # RubyLLM Adapter - wraps the Native protocol implementation
      # This is a thin bridge between the public API and Native::Client
      class RubyLLMAdapter < BaseAdapter
        extend Forwardable

        # Declare all supported features
        supports :tools, :prompts, :resources, :resource_templates,
                 :completions, :logging, :sampling, :roots,
                 :notifications, :progress_tracking, :human_in_the_loop,
                 :elicitation, :subscriptions, :list_changed_notifications

        # Declare all supported transports
        supports_transport :stdio, :sse, :streamable, :streamable_http

        attr_reader :native_client

        def initialize(client, transport_type:, config: {})
          validate_transport!(transport_type)
          super

          # Extract request_timeout from config to pass explicitly to Native::Client
          # This ensures the client's request_timeout is used instead of the global default
          request_timeout = config.delete(:request_timeout)

          @native_client = Native::Client.new(
            name: client.name,
            transport_type: transport_type,
            transport_config: config,
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

        # Delegate all protocol methods to Native::Client
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
                       :error_response, :elicitation_response

        # Handle resource registration in adapter (public API concern)
        def register_resource(resource)
          client.linked_resources << resource
          client.resources[resource.name] = resource
        end

        private

        def build_human_in_the_loop_callback(client)
          lambda do |name, params|
            !client.human_in_the_loop? || client.on[:human_in_the_loop].call(name, params)
          end
        end
      end
    end
  end
end

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
                 :elicitation, :subscriptions, :list_changed_notifications,
                 :tasks

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
            elicitation_callback: build_elicitation_callback(client),
            sampling_callback: build_sampling_callback(client),
            notification_callback: ->(notification) { NotificationHandler.new(client).execute(notification) }
          )
        end

        def_delegators :@native_client,
                       :start, :stop, :restart!, :alive?, :ping,
                       :capabilities, :client_capabilities, :protocol_version,
                       :tool_list, :execute_tool,
                       :resource_list, :resource_read, :resource_template_list,
                       :resources_subscribe, :resources_unsubscribe,
                       :prompt_list, :execute_prompt,
                       :tasks_list, :task_get, :task_result, :task_cancel, :task_status_notification,
                       :completion_resource, :completion_prompt,
                       :set_logging, :set_progress_tracking,
                       :set_elicitation_enabled,
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
            return Handlers::ApprovalDecision.approved unless client.human_in_the_loop?

            handler_config = normalize_human_in_the_loop_handler(client.on[:human_in_the_loop])
            unless handler_config
              RubyLLM::MCP.logger.error(
                "Human-in-the-loop callback must be a handler class configuration"
              )
              return Handlers::ApprovalDecision.denied(reason: "Invalid approval handler configuration")
            end

            execute_handler_class(
              handler_config[:class],
              name,
              params,
              handler_options: handler_config[:options]
            )
          end
        end

        def build_sampling_callback(client)
          lambda do |sample|
            return nil unless client.sampling_callback_enabled?

            handler_or_block = client.on[:sampling]

            if Handlers.handler_class?(handler_or_block)
              handler_or_block.new(sample: sample, coordinator: @native_client).call
            else
              handler_or_block.call(sample)
            end
          end
        end

        def build_elicitation_callback(client)
          lambda do |elicitation|
            return nil unless client.elicitation_enabled?

            handler_or_block = client.on[:elicitation]
            return false unless handler_or_block

            if Handlers.handler_class?(handler_or_block)
              handler_or_block.new(elicitation: elicitation, coordinator: @native_client).call
            else
              handler_or_block.call(elicitation)
            end
          end
        end

        def execute_handler_class(handler_class, name, params, handler_options: {})
          approval_id = "#{@native_client.registry_owner_id}:#{SecureRandom.uuid}"

          handler_instance = handler_class.new(
            tool_name: name,
            parameters: params,
            approval_id: approval_id,
            coordinator: @native_client,
            **handler_options
          )

          result = handler_instance.call
          decision = Handlers::ApprovalDecision.from_handler_result(
            result,
            approval_id: approval_id,
            default_timeout: handler_instance.timeout
          )

          if decision.deferred?
            promise = Handlers::Promise.new
            @native_client.human_in_the_loop_registry.store(
              approval_id,
              {
                promise: promise,
                timeout: decision.timeout,
                tool_name: name,
                parameters: params
              }
            )
            return decision.with_promise(promise)
          end

          decision
        rescue Errors::InvalidApprovalDecision => e
          RubyLLM::MCP.logger.error("Invalid human-in-the-loop handler decision: #{e.message}")
          Handlers::ApprovalDecision.denied(reason: "Invalid approval decision")
        rescue StandardError => e
          RubyLLM::MCP.logger.error("Error in human-in-the-loop handler: #{e.message}\n#{e.backtrace.join("\n")}")
          Handlers::ApprovalDecision.denied(reason: "Approval handler error")
        end

        def normalize_human_in_the_loop_handler(handler_config)
          if handler_config.is_a?(Hash)
            handler_class = handler_config[:class] || handler_config["class"]
            options = handler_config[:options] || handler_config["options"] || {}
            return nil unless Handlers.handler_class?(handler_class)

            { class: handler_class, options: options }
          elsif Handlers.handler_class?(handler_config)
            { class: handler_config, options: {} }
          end
        end
      end
    end
  end
end

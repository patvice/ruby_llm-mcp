# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      class ResponseHandler
        attr_reader :coordinator

        def initialize(coordinator)
          @coordinator = coordinator
        end

        def execute(result) # rubocop:disable Naming/PredicateMethod
          if result.ping?
            coordinator.ping_response(id: result.id)
            true
          elsif result.roots?
            handle_roots_response(result)
            true
          elsif result.sampling?
            handle_sampling_response(result)
            true
          elsif result.elicitation?
            handle_elicitation_response(result)
            true
          else
            handle_unknown_request(result)
            RubyLLM::MCP.logger.error("MCP client was sent unknown method type and \
              could not respond: #{result.inspect}.")
            false
          end
        end

        private

        def handle_roots_response(result)
          RubyLLM::MCP.logger.info("Roots request: #{result.inspect}")
          roots_paths = coordinator.roots_paths
          if roots_paths&.any?
            coordinator.roots_list_response(id: result.id)
          else
            coordinator.error_response(id: result.id, message: "Roots are not enabled", code: -32_000)
          end
        end

        def handle_sampling_response(result)
          unless MCP.config.sampling.enabled?
            RubyLLM::MCP.logger.info("Sampling is disabled, yet server requested sampling")
            coordinator.error_response(id: result.id, message: "Sampling is disabled", code: -32_000)
            return
          end

          RubyLLM::MCP.logger.info("Sampling request: #{result.inspect}")
          Sample.new(result, coordinator).execute
        rescue StandardError => e
          RubyLLM::MCP.logger.error("Error in sampling request: #{e.message}\n#{e.backtrace.join("\n")}")
          coordinator.error_response(
            id: result.id,
            message: "Error processing sampling request: #{e.message}",
            code: -32_000
          )
        end

        def handle_elicitation_response(result)
          RubyLLM::MCP.logger.info("Elicitation request: #{result.inspect}")
          Elicitation.new(coordinator, result).execute
        end

        def handle_unknown_request(result)
          coordinator.error_response(id: result.id,
                                     message: "Unknown method and could not respond: #{result.method}",
                                     code: -32_000)
        end
      end
    end
  end
end

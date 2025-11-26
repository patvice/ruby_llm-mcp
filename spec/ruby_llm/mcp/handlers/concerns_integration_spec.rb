# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Handlers::Concerns Integration" do
  describe "Complete handler with all concerns" do
    let(:notification_service) { double("NotificationService") }

    let(:approval_handler_class) do
      Class.new do
        include RubyLLM::MCP::Handlers::Concerns::Options
        include RubyLLM::MCP::Handlers::Concerns::Lifecycle
        include RubyLLM::MCP::Handlers::Concerns::Logging
        include RubyLLM::MCP::Handlers::Concerns::ErrorHandling
        include RubyLLM::MCP::Handlers::Concerns::GuardChecks
        include RubyLLM::MCP::Handlers::Concerns::ToolFiltering
        include RubyLLM::MCP::Handlers::Concerns::ApprovalActions

        allow_tools # Will be set via options
        deny_tools "rm", "delete_all"

        guard :check_tool_safety

        before_execute do
          logger.info("Processing approval for: #{tool_name}")
        end

        def initialize(tool_name:, parameters:, approval_id:, **options)
          @tool_name = tool_name
          @parameters = parameters
          @approval_id = approval_id
          super(**options)
        end

        def execute
          return deny("Tool is denied") if tool_denied?
          approve
        end

        private

        def check_tool_safety
          return "Tool not in safe list" unless tool_allowed?
          true
        end
      end
    end

    it "combines all concerns successfully" do
      handler = approval_handler_class.new(
        tool_name: "read_file",
        parameters: { path: "/tmp/test.txt" },
        approval_id: "test-123",
        allowed_tools: ["read_file", "list_files"]
      )

      expect(RubyLLM::MCP.logger).to receive(:info).with(/Processing approval/)

      result = handler.call
      expect(result).to eq({ approved: true })
    end

    it "denies if tool is in deny list" do
      handler = approval_handler_class.new(
        tool_name: "rm",
        parameters: { path: "/tmp/test.txt" },
        approval_id: "test-123",
        allowed_tools: ["rm"]
      )

      result = handler.call
      expect(result).to eq({ approved: false, reason: "Tool is denied" })
    end

    it "fails guard if tool not in allowed list" do
      handler = approval_handler_class.new(
        tool_name: "dangerous_tool",
        parameters: {},
        approval_id: "test-123",
        allowed_tools: ["read_file"]
      )

      result = handler.call
      expect(result).to eq({ approved: false, reason: "Tool not in safe list" })
    end
  end

  describe "Async handler with registry" do
    let(:async_handler_class) do
      Class.new do
        include RubyLLM::MCP::Handlers::Concerns::Options
        include RubyLLM::MCP::Handlers::Concerns::Lifecycle
        include RubyLLM::MCP::Handlers::Concerns::AsyncExecution
        include RubyLLM::MCP::Handlers::Concerns::Timeouts
        include RubyLLM::MCP::Handlers::Concerns::ElicitationActions
        include RubyLLM::MCP::Handlers::Concerns::RegistryIntegration

        async_execution timeout: 300

        option :notification_service, required: true

        on_timeout :handle_elicitation_timeout

        def initialize(elicitation:, **options)
          @elicitation = elicitation
          super(**options)
        end

        def execute
          # Send notification
          options[:notification_service].notify(elicitation.id)

          # Store in registry
          store_in_elicitation_registry(elicitation.id, elicitation)

          # Return deferred response
          defer(
            elicitation_id: elicitation.id,
            timeout_handler: self.class.timeout_handler
          )
        end

        private

        def handle_elicitation_timeout
          reject("Request timed out after #{timeout} seconds")
        end
      end
    end

    it "creates async handler with registry integration" do
      elicitation = double("Elicitation", id: "elic-123")
      notification_service = double("NotificationService")

      allow(notification_service).to receive(:notify)
      allow(RubyLLM::MCP::Handlers::ElicitationRegistry).to receive(:store)

      handler = async_handler_class.new(
        elicitation: elicitation,
        notification_service: notification_service
      )

      expect(handler.async?).to be true
      expect(handler.timeout).to eq(300)

      result = handler.call

      expect(result).to be_a(RubyLLM::MCP::Handlers::AsyncResponse)
      expect(result.elicitation_id).to eq("elic-123")
      expect(notification_service).to have_received(:notify).with("elic-123")
    end
  end

  describe "Sampling handler with guards" do
    let(:sampling_handler_class) do
      Class.new do
        include RubyLLM::MCP::Handlers::Concerns::Options
        include RubyLLM::MCP::Handlers::Concerns::Lifecycle
        include RubyLLM::MCP::Handlers::Concerns::GuardChecks
        include RubyLLM::MCP::Handlers::Concerns::ModelFiltering
        include RubyLLM::MCP::Handlers::Concerns::SamplingActions

        allow_models "gpt-4", "claude-3-opus"

        guard :check_model_allowed
        guard :check_token_limit

        option :max_tokens, default: 4000

        def initialize(sample:, **options)
          @sample = sample
          super(**options)
        end

        def execute
          accept("Mock response")
        end

        private

        def check_model_allowed
          return "Model #{sample.model} not allowed" unless model_allowed?(sample.model)
          true
        end

        def check_token_limit
          return "Too many tokens requested" if sample.max_tokens > options[:max_tokens]
          true
        end
      end
    end

    it "accepts valid sampling request" do
      sample = double("Sample", model: "gpt-4", max_tokens: 1000)

      handler = sampling_handler_class.new(sample: sample)
      result = handler.call

      expect(result).to eq({ accepted: true, response: "Mock response" })
    end

    it "rejects if model not allowed" do
      sample = double("Sample", model: "unknown-model", max_tokens: 1000)

      handler = sampling_handler_class.new(sample: sample)
      result = handler.call

      expect(result).to eq({ accepted: false, message: "Model unknown-model not allowed" })
    end

    it "rejects if token limit exceeded" do
      sample = double("Sample", model: "gpt-4", max_tokens: 5000)

      handler = sampling_handler_class.new(sample: sample, max_tokens: 4000)
      result = handler.call

      expect(result).to eq({ accepted: false, message: "Too many tokens requested" })
    end
  end
end

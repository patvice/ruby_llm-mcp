# frozen_string_literal: true

require "spec_helper"
require "json_schemer"

RSpec.describe RubyLLM::MCP::Native::Messages do
  let(:schema_path) { File.join(__dir__, "../../../fixtures/mcp_definition/2025-11-25-schema.json") }
  let(:schema_json) { JSON.parse(File.read(schema_path)) }
  let(:schemer) { JSONSchemer.schema(schema_json) }

  # Mock client for testing
  let(:mock_client) do
    instance_double(
      RubyLLM::MCP::Native::Client,
      protocol_version: "2025-11-25",
      client_capabilities: { roots: { listChanged: true } },
      tracking_progress?: false
    )
  end

  let(:mock_client_with_progress) do
    instance_double(
      RubyLLM::MCP::Native::Client,
      protocol_version: "2025-11-25",
      client_capabilities: { roots: { listChanged: true } },
      tracking_progress?: true
    )
  end

  describe "Constants" do
    it "defines JSONRPC_VERSION" do
      expect(described_class::JSONRPC_VERSION).to eq("2.0")
    end

    it "defines all method constants" do
      expect(described_class::METHOD_INITIALIZE).to eq("initialize")
      expect(described_class::METHOD_PING).to eq("ping")
      expect(described_class::METHOD_TOOLS_LIST).to eq("tools/list")
      expect(described_class::METHOD_TOOLS_CALL).to eq("tools/call")
      expect(described_class::METHOD_TASKS_LIST).to eq("tasks/list")
      expect(described_class::METHOD_TASKS_GET).to eq("tasks/get")
      expect(described_class::METHOD_TASKS_RESULT).to eq("tasks/result")
      expect(described_class::METHOD_TASKS_CANCEL).to eq("tasks/cancel")
      expect(described_class::METHOD_NOTIFICATION_ELICITATION_COMPLETE).to eq("notifications/elicitation/complete")
    end
  end

  describe "Helpers" do
    # Test helpers indirectly through their usage in Requests
    # since they're extended into modules, not called directly

    describe "UUID generation" do
      it "generates valid UUIDs for requests" do
        body = described_class::Requests.ping
        expect(body[:id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      end

      it "generates unique IDs for each request" do
        id1 = described_class::Requests.ping[:id]
        id2 = described_class::Requests.ping[:id]
        expect(id1).not_to eq(id2)
      end
    end

    describe "progress token handling" do
      it "adds progress token when tracking is enabled" do
        body = described_class::Requests.ping(tracking_progress: true)
        expect(body[:params]).to be_a(Hash)
        expect(body[:params][:_meta]).to be_a(Hash)
        expect(body[:params][:_meta][:progressToken]).to be_a(String)
      end

      it "does not add progress token when tracking is disabled" do
        body = described_class::Requests.ping(tracking_progress: false)
        # params should be empty and deleted when no progress tracking
        expect(body[:params]).to be_nil
      end
    end

    describe "cursor handling" do
      it "adds cursor when provided" do
        body = described_class::Requests.tool_list(cursor: "cursor-123")
        expect(body[:params][:cursor]).to eq("cursor-123")
      end

      it "does not add cursor when nil" do
        body = described_class::Requests.tool_list(cursor: nil)
        # When no cursor and no progress tracking, params is empty and deleted
        if body[:params]
          expect(body[:params][:cursor]).to be_nil
        else
          expect(body[:params]).to be_nil
        end
      end
    end
  end

  describe "Requests" do
    describe ".initialize" do
      let(:body) do
        described_class::Requests.initialize(
          protocol_version: "2025-11-25",
          capabilities: { roots: { listChanged: true } }
        )
      end

      it "creates a valid initialize request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("initialize")
        expect(body[:params]).to be_a(Hash)
        expect(body[:params][:protocolVersion]).to eq("2025-11-25")
        expect(body[:params][:capabilities]).to be_a(Hash)
        expect(body[:params][:clientInfo]).to be_a(Hash)
      end

      it "validates against InitializeRequest schema" do
        # Convert symbols to strings for schema validation
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".ping" do
      let(:body) { described_class::Requests.ping }

      it "creates a valid ping request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("ping")
      end

      it "validates against PingRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end

      it "includes progress token when tracking is enabled" do
        body = described_class::Requests.ping(tracking_progress: true)
        expect(body[:params]).to be_a(Hash)
        expect(body[:params][:_meta]).to be_a(Hash)
        expect(body[:params][:_meta][:progressToken]).to be_a(String)
      end
    end

    describe ".tool_list" do
      let(:body) { described_class::Requests.tool_list }

      it "creates a valid tool list request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("tools/list")
      end

      it "validates against ListToolsRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end

      it "includes cursor when provided" do
        body = described_class::Requests.tool_list(cursor: "cursor-123")
        expect(body[:params][:cursor]).to eq("cursor-123")
      end
    end

    describe ".tool_call" do
      let(:body) { described_class::Requests.tool_call(name: "test_tool", parameters: { arg: "value" }) }

      it "creates a valid tool call request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("tools/call")
        expect(body[:params][:name]).to eq("test_tool")
        expect(body[:params][:arguments]).to eq({ arg: "value" })
      end

      it "validates against CallToolRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".resource_list" do
      let(:body) { described_class::Requests.resource_list }

      it "creates a valid resource list request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("resources/list")
      end

      it "validates against ListResourcesRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".resource_read" do
      let(:body) { described_class::Requests.resource_read(uri: "file:///test.txt") }

      it "creates a valid resource read request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("resources/read")
        expect(body[:params][:uri]).to eq("file:///test.txt")
      end

      it "validates against ReadResourceRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".resource_template_list" do
      let(:body) { described_class::Requests.resource_template_list }

      it "creates a valid resource template list request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("resources/templates/list")
      end

      it "validates against ListResourceTemplatesRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".resources_subscribe" do
      let(:body) { described_class::Requests.resources_subscribe(uri: "file:///test.txt") }

      it "creates a valid resources subscribe request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("resources/subscribe")
        expect(body[:params][:uri]).to eq("file:///test.txt")
      end

      it "validates against SubscribeRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".resources_unsubscribe" do
      let(:body) { described_class::Requests.resources_unsubscribe(uri: "file:///test.txt") }

      it "creates a valid resources unsubscribe request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("resources/unsubscribe")
        expect(body[:params][:uri]).to eq("file:///test.txt")
      end

      it "validates against UnsubscribeRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".prompt_list" do
      let(:body) { described_class::Requests.prompt_list }

      it "creates a valid prompt list request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("prompts/list")
      end

      it "validates against ListPromptsRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".prompt_call" do
      let(:body) do
        described_class::Requests.prompt_call(name: "test_prompt", arguments: { arg: "value" })
      end

      it "creates a valid prompt call request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("prompts/get")
        expect(body[:params][:name]).to eq("test_prompt")
        expect(body[:params][:arguments]).to eq({ arg: "value" })
      end

      it "validates against GetPromptRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".completion_resource" do
      let(:body) do
        described_class::Requests.completion_resource(
          uri: "file:///test.txt",
          argument: "arg1",
          value: "val1"
        )
      end

      it "creates a valid completion resource request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("completion/complete")
        expect(body[:params][:ref][:type]).to eq("ref/resource")
        expect(body[:params][:ref][:uri]).to eq("file:///test.txt")
        expect(body[:params][:argument][:name]).to eq("arg1")
        expect(body[:params][:argument][:value]).to eq("val1")
      end

      it "validates against CompleteRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end

      it "includes context when provided" do
        body = described_class::Requests.completion_resource(
          uri: "file:///test.txt",
          argument: "arg1",
          value: "val1",
          context: { key: "value" }
        )
        expect(body[:params][:context][:arguments]).to eq({ key: "value" })
      end
    end

    describe ".completion_prompt" do
      let(:body) do
        described_class::Requests.completion_prompt(
          name: "test_prompt",
          argument: "arg1",
          value: "val1"
        )
      end

      it "creates a valid completion prompt request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("completion/complete")
        expect(body[:params][:ref][:type]).to eq("ref/prompt")
        expect(body[:params][:ref][:name]).to eq("test_prompt")
        expect(body[:params][:argument][:name]).to eq("arg1")
        expect(body[:params][:argument][:value]).to eq("val1")
      end

      it "validates against CompleteRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".logging_set_level" do
      let(:body) { described_class::Requests.logging_set_level(level: "info") }

      it "creates a valid logging set level request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("logging/setLevel")
        expect(body[:params][:level]).to eq("info")
      end

      it "validates against SetLevelRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".tasks_list" do
      let(:body) { described_class::Requests.tasks_list }

      it "creates a valid tasks list request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("tasks/list")
      end

      it "validates against ListTasksRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".task_get" do
      let(:body) { described_class::Requests.task_get(task_id: "task-123") }

      it "creates a valid task get request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("tasks/get")
        expect(body[:params][:taskId]).to eq("task-123")
      end

      it "validates against GetTaskRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".task_result" do
      let(:body) { described_class::Requests.task_result(task_id: "task-123") }

      it "creates a valid task result request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("tasks/result")
        expect(body[:params][:taskId]).to eq("task-123")
      end

      it "validates against GetTaskPayloadRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".task_cancel" do
      let(:body) { described_class::Requests.task_cancel(task_id: "task-123") }

      it "creates a valid task cancel request" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_a(String)
        expect(body[:method]).to eq("tasks/cancel")
        expect(body[:params][:taskId]).to eq("task-123")
      end

      it "validates against CancelTaskRequest schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end
  end

  describe "Notifications" do
    describe ".initialized" do
      let(:body) { described_class::Notifications.initialized }

      it "creates a valid initialized notification" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_nil
        expect(body[:method]).to eq("notifications/initialized")
      end

      it "validates against InitializedNotification schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".cancelled" do
      let(:body) { described_class::Notifications.cancelled(request_id: "req-123", reason: "timeout") }

      it "creates a valid cancelled notification" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_nil
        expect(body[:method]).to eq("notifications/cancelled")
        expect(body[:params][:requestId]).to eq("req-123")
        expect(body[:params][:reason]).to eq("timeout")
      end

      it "validates against CancelledNotification schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".roots_list_changed" do
      let(:body) { described_class::Notifications.roots_list_changed }

      it "creates a valid roots list changed notification" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_nil
        expect(body[:method]).to eq("notifications/roots/list_changed")
      end

      it "validates against RootsListChangedNotification schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".tasks_status" do
      let(:task) do
        timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        {
          taskId: "task-123",
          status: "working",
          createdAt: timestamp,
          lastUpdatedAt: timestamp,
          ttl: 60_000
        }
      end
      let(:body) { described_class::Notifications.tasks_status(task: task) }

      it "creates a valid task status notification" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_nil
        expect(body[:method]).to eq("notifications/tasks/status")
        expect(body[:params][:taskId]).to eq("task-123")
      end

      it "validates against TaskStatusNotification schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".elicitation_complete" do
      let(:body) { described_class::Notifications.elicitation_complete(elicitation_id: "elicitation-123") }

      it "creates a valid elicitation complete notification" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to be_nil
        expect(body[:method]).to eq("notifications/elicitation/complete")
        expect(body[:params][:elicitationId]).to eq("elicitation-123")
      end
    end
  end

  describe "Responses" do
    describe ".ping" do
      let(:body) { described_class::Responses.ping(id: "req-123") }

      it "creates a valid ping response" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to eq("req-123")
        expect(body[:result]).to eq({})
      end

      it "validates against JSONRPCResponse schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".roots_list" do
      let(:body) { described_class::Responses.roots_list(id: "req-123", roots_paths: ["/path/to/root"]) }

      it "creates a valid roots list response" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to eq("req-123")
        expect(body[:result][:roots]).to be_an(Array)
        expect(body[:result][:roots].first[:uri]).to eq("file:///path/to/root")
        expect(body[:result][:roots].first[:name]).to eq("root")
      end

      it "validates against ListRootsResult schema" do
        body_json = JSON.parse(body.to_json)
        # Wrap in a response structure for validation
        response_json = {
          "jsonrpc" => "2.0",
          "id" => body_json["id"],
          "result" => body_json["result"]
        }
        errors = schemer.validate(response_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".sampling_create_message stop_reason normalization" do
      it "maps snake_case stop reasons to MCP camelCase values" do
        message = double(
          "Message",
          role: "assistant",
          content: "Done",
          stop_reason: "max_tokens"
        )

        body = described_class::Responses.sampling_create_message(
          id: "req-123",
          model: "gpt-4o",
          message: message
        )

        expect(body[:result][:stopReason]).to eq("maxTokens")
      end

      it "defaults stop reason to endTurn when message does not provide one" do
        message = double(
          "Message",
          role: "assistant",
          content: "Done",
          stop_reason: nil
        )

        body = described_class::Responses.sampling_create_message(
          id: "req-123",
          model: "gpt-4o",
          message: message
        )

        expect(body[:result][:stopReason]).to eq("endTurn")
      end
    end

    describe ".error" do
      let(:body) { described_class::Responses.error(id: "req-123", message: "Test error", code: -32_000) }

      it "creates a valid error response" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to eq("req-123")
        expect(body[:error][:code]).to eq(-32_000)
        expect(body[:error][:message]).to eq("Test error")
      end

      it "validates against JSONRPCError schema" do
        body_json = JSON.parse(body.to_json)
        errors = schemer.validate(body_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end
    end

    describe ".result" do
      let(:body) { described_class::Responses.result(id: "req-123", value: { "tasks" => [] }) }

      it "creates a valid generic result response" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to eq("req-123")
        expect(body[:result]).to eq({ "tasks" => [] })
      end
    end

    describe ".elicitation" do
      let(:body) do
        described_class::Responses.elicitation(
          id: "req-123",
          action: "accept",
          content: { field: "value" }
        )
      end

      it "creates a valid elicitation response" do
        expect(body[:jsonrpc]).to eq("2.0")
        expect(body[:id]).to eq("req-123")
        expect(body[:result][:action]).to eq("accept")
        expect(body[:result][:content]).to eq({ field: "value" })
      end

      it "validates against ElicitResult schema" do
        body_json = JSON.parse(body.to_json)
        # Wrap in a response structure for validation
        response_json = {
          "jsonrpc" => "2.0",
          "id" => body_json["id"],
          "result" => body_json["result"]
        }
        errors = schemer.validate(response_json).to_a
        expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
      end

      it "omits content when not provided" do
        body = described_class::Responses.elicitation(id: "req-123", action: "decline")
        expect(body[:result][:content]).to be_nil
      end
    end

    describe ".sampling_create_message" do
      let(:mock_content) do
        double("Content", text: "Hello, world!")
      end

      context "when message has no stop_reason" do
        let(:mock_message) do
          double(
            "Message",
            role: "assistant",
            content: mock_content
          ).tap do |msg|
            allow(msg).to receive(:respond_to?).with(:stop_reason).and_return(false)
          end
        end

        let(:body) do
          described_class::Responses.sampling_create_message(
            id: "req-123",
            message: mock_message,
            model: "gpt-4"
          )
        end

        it "creates a valid sampling response with default stopReason" do
          expect(body[:jsonrpc]).to eq("2.0")
          expect(body[:id]).to eq("req-123")
          expect(body[:result][:role]).to eq("assistant")
          expect(body[:result][:model]).to eq("gpt-4")
          expect(body[:result][:stopReason]).to eq("endTurn")
        end

        it "validates against CreateMessageResult schema" do
          body_json = JSON.parse(body.to_json)
          response_json = {
            "jsonrpc" => "2.0",
            "id" => body_json["id"],
            "result" => body_json["result"]
          }
          errors = schemer.validate(response_json).to_a
          expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
        end
      end

      context "when message has stop_reason nil" do
        let(:mock_message) do
          double(
            "Message",
            role: "assistant",
            content: mock_content,
            stop_reason: nil
          ).tap do |msg|
            allow(msg).to receive(:respond_to?).with(:stop_reason).and_return(true)
          end
        end

        let(:body) do
          described_class::Responses.sampling_create_message(
            id: "req-123",
            message: mock_message,
            model: "gpt-4"
          )
        end

        it "uses default stopReason when nil" do
          expect(body[:result][:stopReason]).to eq("endTurn")
        end
      end

      context "when message has stop_reason values" do
        shared_examples "converts stop_reason correctly" do |snake_case_value, camel_case_value|
          let(:mock_message) do
            double(
              "Message",
              role: "assistant",
              content: mock_content,
              stop_reason: snake_case_value
            ).tap do |msg|
              allow(msg).to receive(:respond_to?).with(:stop_reason).and_return(true)
            end
          end

          let(:body) do
            described_class::Responses.sampling_create_message(
              id: "req-123",
              message: mock_message,
              model: "gpt-4"
            )
          end

          it "converts #{snake_case_value} to #{camel_case_value}" do
            expect(body[:result][:stopReason]).to eq(camel_case_value)
          end

          it "validates against CreateMessageResult schema" do
            body_json = JSON.parse(body.to_json)
            response_json = {
              "jsonrpc" => "2.0",
              "id" => body_json["id"],
              "result" => body_json["result"]
            }
            errors = schemer.validate(response_json).to_a
            expect(errors).to be_empty, "Schema validation errors: #{errors.map(&:to_h)}"
          end
        end

        context "with stop_reason: end_turn" do
          it_behaves_like "converts stop_reason correctly", "end_turn", "endTurn"
        end

        context "with stop_reason: max_tokens" do
          it_behaves_like "converts stop_reason correctly", "max_tokens", "maxTokens"
        end

        context "with stop_reason: stop_sequence" do
          it_behaves_like "converts stop_reason correctly", "stop_sequence", "stopSequence"
        end

        context "with stop_reason: tool_use" do
          it_behaves_like "converts stop_reason correctly", "tool_use", "toolUse"
        end

        context "with stop_reason: pause_turn" do
          it_behaves_like "converts stop_reason correctly", "pause_turn", "pauseTurn"
        end

        context "with stop_reason: refusal" do
          it_behaves_like "converts stop_reason correctly", "refusal", "refusal"
        end
      end

      context "with custom stop_reason values" do
        let(:mock_message) do
          double(
            "Message",
            role: "assistant",
            content: mock_content,
            stop_reason: "custom_stop_reason"
          ).tap do |msg|
            allow(msg).to receive(:respond_to?).with(:stop_reason).and_return(true)
          end
        end

        let(:body) do
          described_class::Responses.sampling_create_message(
            id: "req-123",
            message: mock_message,
            model: "gpt-4"
          )
        end

        it "converts unknown snake_case values to camelCase" do
          expect(body[:result][:stopReason]).to eq("customStopReason")
        end
      end
      # rubocop:enable RSpec/VerifiedDoubles
    end
  end

  describe "UUID generation consistency" do
    it "generates unique IDs for each request" do
      ids = 10.times.map { described_class::Requests.ping[:id] }
      expect(ids.uniq.length).to eq(10)
    end

    it "generates valid UUID format for all requests" do
      uuid_pattern = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

      [
        described_class::Requests.initialize(protocol_version: "2025-11-25", capabilities: {}),
        described_class::Requests.ping,
        described_class::Requests.tool_list,
        described_class::Requests.resource_list
      ].each do |body|
        expect(body[:id]).to match(uuid_pattern)
      end
    end
  end
end

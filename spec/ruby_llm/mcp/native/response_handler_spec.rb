# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Native::ResponseHandler do
  let(:client) { instance_double(RubyLLM::MCP::Native::Client) }
  let(:request_handler) { RubyLLM::MCP::Native::ResponseHandler.new(client) }
  let(:task_registry) { RubyLLM::MCP::Native::TaskRegistry.new }

  before do
    allow(client).to receive_messages(
      error_response: true,
      result_response: true,
      task_registry: task_registry
    )
    allow(client).to receive(:register_in_flight_request)
    allow(client).to receive(:unregister_in_flight_request)
  end

  it "response with an error code if the request is unknown" do
    result = RubyLLM::MCP::Result.new(
      { "id" => "123", "method" => "unknown/request", "params" => {} }
    )

    request_handler.execute(result)
    error_message = "Method not found: #{result.method}"
    expect(client).to have_received(:error_response).with(
      id: "123",
      message: error_message,
      code: RubyLLM::MCP::Native::JsonRpc::ErrorCodes::METHOD_NOT_FOUND
    )
  end

  describe "cancellation handling" do
    it "registers and unregisters in-flight requests" do
      allow(client).to receive(:ping_response)
      result = RubyLLM::MCP::Result.new(
        { "id" => "456", "method" => "ping", "params" => {} }
      )

      request_handler.execute(result)

      expect(client).to have_received(:register_in_flight_request).with("456", instance_of(RubyLLM::MCP::Native::CancellableOperation))
      expect(client).to have_received(:unregister_in_flight_request).with("456")
    end

    it "does not send a response when a request is cancelled" do
      allow(client).to receive(:roots_paths).and_return(["/path"])
      allow(client).to receive(:roots_list_response)

      result = RubyLLM::MCP::Result.new(
        { "id" => "789", "method" => "roots/list", "params" => {} }
      )

      # Simulate cancellation by stubbing the CancellableOperation to raise RequestCancelled
      cancelled_operation = instance_double(RubyLLM::MCP::Native::CancellableOperation)
      allow(RubyLLM::MCP::Native::CancellableOperation).to receive(:new).with("789").and_return(cancelled_operation)
      allow(cancelled_operation).to receive(:execute).and_raise(
        RubyLLM::MCP::Errors::RequestCancelled.new(message: "Cancelled", request_id: "789")
      )

      result = request_handler.execute(result)

      expect(result).to be true
      expect(client).not_to have_received(:roots_list_response)
      expect(client).to have_received(:unregister_in_flight_request).with("789")
    end
  end

  describe "tasks request handling" do
    it "responds to tasks/list with cached tasks" do
      timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      task_registry.upsert(
        {
          "taskId" => "task-1",
          "status" => "working",
          "createdAt" => timestamp,
          "lastUpdatedAt" => timestamp,
          "ttl" => 60_000
        }
      )

      result = RubyLLM::MCP::Result.new(
        { "id" => "tasks-list-1", "method" => "tasks/list", "params" => {} }
      )

      request_handler.execute(result)

      expect(client).to have_received(:result_response).with(
        id: "tasks-list-1",
        value: {
          tasks: [hash_including("taskId" => "task-1", "status" => "working")]
        }
      )
    end

    it "responds to tasks/get with task details when known" do
      timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      task_registry.upsert(
        {
          "taskId" => "task-1",
          "status" => "working",
          "createdAt" => timestamp,
          "lastUpdatedAt" => timestamp,
          "ttl" => 60_000
        }
      )

      result = RubyLLM::MCP::Result.new(
        { "id" => "tasks-get-1", "method" => "tasks/get", "params" => { "taskId" => "task-1" } }
      )

      request_handler.execute(result)

      expect(client).to have_received(:result_response).with(
        id: "tasks-get-1",
        value: hash_including("taskId" => "task-1")
      )
    end

    it "returns an invalid params error for tasks/get when task is unknown" do
      result = RubyLLM::MCP::Result.new(
        { "id" => "tasks-get-unknown", "method" => "tasks/get", "params" => { "taskId" => "missing-task" } }
      )

      request_handler.execute(result)

      expect(client).to have_received(:error_response).with(
        id: "tasks-get-unknown",
        message: "Task not found: missing-task",
        code: RubyLLM::MCP::Native::JsonRpc::ErrorCodes::INVALID_PARAMS
      )
    end

    it "returns a cancelled task payload for unknown tasks/cancel requests" do
      result = RubyLLM::MCP::Result.new(
        { "id" => "tasks-cancel-1", "method" => "tasks/cancel", "params" => { "taskId" => "missing-task" } }
      )

      request_handler.execute(result)

      expect(client).to have_received(:result_response).with(
        id: "tasks-cancel-1",
        value: hash_including("taskId" => "missing-task", "status" => "cancelled")
      )
    end
  end
end

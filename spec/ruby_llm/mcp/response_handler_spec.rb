# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::ResponseHandler do
  let(:coordinator) { instance_double(RubyLLM::MCP::Coordinator) }
  let(:request_handler) { RubyLLM::MCP::ResponseHandler.new(coordinator) }

  before do
    allow(coordinator).to receive(:client)
    allow(coordinator).to receive(:error_response).and_return(true)
  end

  it "response with an error code if the request is unknown" do
    result = RubyLLM::MCP::Result.new(
      { "id" => "123", "method" => "unknown/request", "params" => {} }
    )

    request_handler.execute(result)
    error_message = "Unknown method and could not respond: #{result.method}"
    expect(coordinator).to have_received(:error_response).with(id: "123", message: error_message, code: -32_000)
  end
end

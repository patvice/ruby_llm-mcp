# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Native::ResponseHandler do
  let(:client) { instance_double(RubyLLM::MCP::Native::Client) }
  let(:request_handler) { RubyLLM::MCP::Native::ResponseHandler.new(client) }

  before do
    allow(client).to receive(:error_response).and_return(true)
  end

  it "response with an error code if the request is unknown" do
    result = RubyLLM::MCP::Result.new(
      { "id" => "123", "method" => "unknown/request", "params" => {} }
    )

    request_handler.execute(result)
    error_message = "Unknown method and could not respond: #{result.method}"
    expect(client).to have_received(:error_response).with(id: "123", message: error_message, code: -32_000)
  end
end

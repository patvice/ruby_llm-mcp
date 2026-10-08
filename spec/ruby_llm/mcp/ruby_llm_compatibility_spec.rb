# frozen_string_literal: true

# Can also run without the MCP fixture servers:
# bundle exec rspec --options /dev/null spec/ruby_llm/mcp/ruby_llm_compatibility_spec.rb
require "ruby_llm/mcp"

RSpec.describe "RubyLLM compatibility" do # rubocop:disable RSpec/DescribeClass
  let(:adapter) { double("Adapter") }
  let(:schema) do
    { "type" => "object", "properties" => { "query" => { "type" => "string" } }, "required" => ["query"] }
  end
  let(:tool) do
    RubyLLM::MCP::Tool.new(adapter, { "name" => "search", "description" => "Search", "inputSchema" => schema })
  end
  let(:image) { { "type" => "image", "data" => Base64.strict_encode64("image bytes"), "mimeType" => "image/png" } }
  let(:audio) { { "type" => "audio", "data" => Base64.strict_encode64("audio bytes"), "mimeType" => "audio/wav" } }

  def stub_result(value)
    result = RubyLLM::MCP::Result.new({ "result" => value })
    allow(adapter).to receive(:execute_tool).with(name: "search", parameters: { query: "hello" }).and_return(result)
  end

  def split_result(result)
    if defined?(RubyLLM::Content)
      [result.text, result.attachments]
    else
      RubyLLM::Tool.split_result(result)
    end
  end

  it "exposes the complete server schema through both RubyLLM APIs" do
    expect(tool.params_schema).to eq(schema)
    expect(tool.parameters_schema).to eq(schema)
  end

  it "returns text through RubyLLM's tool invocation" do
    stub_result("content" => [{ "type" => "text", "text" => "hello" }])

    expect(split_result(tool.call(query: "hello"))).to eq(["hello", []])
  end

  it "preserves every text and attachment block in a mixed result" do
    stub_result("content" => [{ "type" => "text", "text" => "first" }, image,
                              { "type" => "text", "text" => "second" }, audio, image])

    text, attachments = split_result(tool.call(query: "hello"))

    expect(text).to eq("first\nsecond")
    expect(attachments.map(&:mime_type)).to eq(%w[image/png audio/wav image/png])
    expect(attachments.map(&:content)).to eq(["image bytes", "audio bytes", "image bytes"])
    expect(attachments.first.encoded).to eq(image["data"])
    expect(attachments.first.source).to be_a(StringIO)
  end

  it "preserves all attachments in a result without text" do
    stub_result("content" => [image, audio])

    text, attachments = split_result(tool.call(query: "hello"))

    expect(text).to eq("")
    expect(attachments.map(&:mime_type)).to eq(%w[image/png audio/wav])
  end

  it "handles empty results" do
    stub_result("content" => [])

    expect(split_result(tool.call(query: "hello"))).to eq(["", []])
  end

  it "keeps execution errors visible" do
    stub_result("isError" => true, "content" => [{ "type" => "text", "text" => "failed" }])

    expect(tool.call(query: "hello")).to eq(error: "Tool execution error: failed")
  end

  it "keeps validated structured content authoritative" do
    tool = RubyLLM::MCP::Tool.new(adapter, { "name" => "search", "inputSchema" => schema, "outputSchema" => schema })
    stub_result("structuredContent" => { "query" => "answer" }, "content" => [image])

    text, attachments = split_result(tool.call(query: "hello"))

    expect(JSON.parse(text)).to eq("query" => "answer")
    expect(attachments).to be_empty
  end

  it "preserves embedded resources alongside other tool blocks" do
    resource = { "type" => "resource", "resource" => { "uri" => "file:///result.png",
                                                       "mimeType" => "image/png", "blob" => image["data"] } }
    stub_result("content" => [resource, audio])

    text, attachments = split_result(tool.call(query: "hello"))

    expect(text).to include("search: Search")
    expect(attachments.map(&:content)).to eq(["image bytes", "audio bytes"])
  end

  it "builds messages from resource content without losing attachments" do
    resource = RubyLLM::MCP::Resource.new(adapter, "name" => "Picture", "uri" => "file:///result.png",
                                                   "mimeType" => "image/png",
                                                   "content_response" => { "blob" => image["data"] })
    chat = double("Chat")
    expect(chat).to receive(:add_message) do |message|
      content = defined?(RubyLLM::Content) ? message.content : message
      expect(defined?(RubyLLM::Content) ? content.text : content.content).to include("Picture")
      expect(content.attachments.first.content).to eq("image bytes")
    end

    resource.include(chat)
  end

  it "builds messages from MCP prompt images" do
    prompt = RubyLLM::MCP::Prompt.new(adapter, "name" => "picture")
    result = RubyLLM::MCP::Result.new({ "result" => { "messages" => [{ "role" => "user", "content" => image }] } })
    allow(adapter).to receive(:execute_prompt).with(name: "picture", arguments: {}).and_return(result)

    message = prompt.fetch.first
    content = defined?(RubyLLM::Content) ? message.content : message

    expect(content.attachments.first.content).to eq("image bytes")
  end

  it "formats text sampling responses with the installed RubyLLM message API" do
    message = RubyLLM::Message.new(role: :assistant, content: "hello")
    response = RubyLLM::MCP::Native::Messages::Responses.sampling_create_message(id: 1, message: message, model: "test")

    expect(response[:result][:content]).to eq(type: "text", text: "hello")
  end

  it "formats image sampling responses with base64 data" do
    attachment = RubyLLM::MCP::Attachment.new(image["data"], image["mimeType"])
    content = RubyLLM::MCP::Content.new(attachments: [attachment])
    message = RubyLLM::Message.new(role: :assistant, **content.message_options)
    response = RubyLLM::MCP::Native::Messages::Responses.sampling_create_message(id: 1, message: message, model: "test")

    expect(response[:result][:content]).to eq(type: :image, data: image["data"], mimeType: "image/png")
  end
end

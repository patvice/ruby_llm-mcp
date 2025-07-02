# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Sample do
  before do
    MCPTestConfiguration.reset_config!
  end

  let(:coordinator) { instance_double(RubyLLM::MCP::Coordinator) }
  let(:result) do
    RubyLLM::MCP::Result.new(
      { "id" => "123",
        "params" => { "messages" => [
          { "role" => "user",
            "content" => { "type" => "text", "text" => "Hello, how are you?" } },
          { "role" => "assistant",
            "content" => { "type" => "text", "text" => "I'm good, thank you!" } }
        ] } }
    )
  end

  it "messages will be a string of all the messages" do
    sample = RubyLLM::MCP::Sample.new(
      result,
      coordinator
    )
    expect(sample.messages).to eq("Hello, how are you?\nI'm good, thank you!")
  end

  CLIENT_OPTIONS.each do |config|
    context "with #{config[:name]}" do
      let(:client) do
        options = config[:options].merge(start: false)
        RubyLLM::MCP::Client.new(**options)
      end

      after do
        client.stop
      end

      it "client is setup to have sampling capabilities" do
        RubyLLM::MCP.configure do |config|
          config.sampling.enabled = true
        end
        client.start

        capabilities = client.client_capabilities

        expect(capabilities[:sampling]).to eq({})
      end

      it "client is setup to not have sampling capabilities when sampling option is disabled" do
        RubyLLM::MCP.configure do |config|
          config.sampling.enabled = false
        end
        client.start

        capabilities = client.client_capabilities

        expect(capabilities.key?(:sampling)).to be(false)
      end

      it "sampling capabilities is disabled by default" do
        client.start

        capabilities = client.client_capabilities

        expect(capabilities.key?(:sampling)).to be(false)
      end

      it "client will response with an error message if server requests sample and sampling is not enabled" do
        client.start

        tool = client.tool("sampling-test")
        result = tool.execute

        expect(result.to_s).to include("Sampling is disabled")
      end

      it "client will send failed message if guard returns false" do
        RubyLLM::MCP.configure do |config|
          config.sampling.enabled = true

          config.sampling.guard do
            false
          end
        end
        client.start

        tool = client.tool("sampling-test")
        result = tool.execute

        expect(result.to_s).to include("Sampling test failed")
      end

      it "client will respond with a failure message if guard raises an error" do
        RubyLLM::MCP.configure do |config|
          config.sampling.enabled = true

          config.sampling.guard do
            raise "Error in guard"
          end
        end

        client.start

        tool = client.tool("sampling-test")
        result = tool.execute

        expect(result.to_s).to include("Error executing sampling request")
      end

      it "client will provide a sample object to the guard for validation" do # rubocop:disable RSpec/MultipleExpectations
        sample = nil
        RubyLLM::MCP.configure do |config|
          config.sampling.enabled = true

          config.sampling.guard do |incoming_sample|
            sample = incoming_sample
            false
          end
        end
        client.start

        tool = client.tool("sampling-test")
        tool.execute

        expect(sample).to be_a(RubyLLM::MCP::Sample)
        expect(sample.raw_messages).to eq([
                                            {
                                              "role" => "user",
                                              "content" => {
                                                "type" => "text",
                                                "text" => "Hello, how are you?"
                                              }
                                            }
                                          ])
        expect(sample.system_prompt).to eq("You are a helpful assistant.")
        expect(sample.max_tokens).to eq(100)
        expect(sample.model_preferences.model).to eq("gpt-4o")
        expect(sample.model_preferences.hints).to eq(["gpt-4o"])
        expect(sample.model_preferences.cost_priority).to eq(1)
        expect(sample.model_preferences.speed_priority).to eq(1)
        expect(sample.model_preferences.intelligence_priority).to eq(1)
      end

      COMPLEX_FUNCTION_MODELS.each do |model|
        context "with #{model[:provider]} #{model[:model]}" do
          it "executes a chat message and provides information to the server, without a guard" do
            RubyLLM::MCP.configure do |config|
              config.sampling.enabled = true
              config.sampling.prefered_model = model[:model]
            end
            client.start

            tool = client.tool("sampling-test")
            result = tool.execute

            expect(result.to_s).to include("Sampling test completed")
          end

          it "provides information about the sample, with a guard" do
            RubyLLM::MCP.configure do |config|
              config.sampling.enabled = true
              config.sampling.prefered_model = model[:model]

              config.sampling.guard do
                true
              end
            end
            client.start

            tool = client.tool("sampling-test")
            result = tool.execute

            expect(result.to_s).to include("Sampling test completed")
          end
        end
      end
    end
  end
end

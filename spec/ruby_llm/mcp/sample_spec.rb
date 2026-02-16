# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Sample do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
  end

  before do
    MCPTestConfiguration.reset_config!
    MCPTestConfiguration.configure_ruby_llm!
  end

  let(:client) { instance_double(RubyLLM::MCP::Client) }
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

  around do |example|
    cassette_name = example.full_description
                           .delete_prefix("RubyLLM::MCP::")
                           .downcase
                           .gsub(", ", "")
                           .gsub(" ", "_")
                           .gsub("/", "_")

    VCR.use_cassette(cassette_name, allow_playback_repeats: true) do
      example.run
    end
  end

  it "messages will be a string of all the messages" do
    sample = RubyLLM::MCP::Sample.new(
      result,
      client
    )
    expect(sample.message).to eq("Hello, how are you?\nI'm good, thank you!")
  end

  each_client_supporting(:sampling) do |config|
    let(:client) { RubyLLM::MCP::Client.new(**config[:options], start: false) }

    after do
      client.stop
    end

    it "client is setup to have sampling capabilities" do
      RubyLLM::MCP.configure do |config|
        config.sampling.enabled = true
      end
      client.start

      capabilities = client.client_capabilities

      expect(capabilities[:sampling]).to eq({ context: {} })
    end

    it "advertises tools and context sampling capability flags when enabled" do
      RubyLLM::MCP.configure do |config|
        config.sampling.enabled = true
        config.sampling.tools = true
        config.sampling.context = true
      end
      client.start

      capabilities = client.client_capabilities

      expect(capabilities[:sampling]).to eq({ tools: {}, context: {} })
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

      tool = wait_for_tool(client, "sampling-test")
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

      tool = wait_for_tool(client, "sampling-test")
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

      tool = wait_for_tool(client, "sampling-test")
      result = begin
        tool.execute
      rescue RubyLLM::MCP::Errors::TransportError => e
        retriable_streamable_init_race = RUBY_ENGINE == "jruby" &&
          config[:name] == "streamable-native" &&
          e.message.include?("Server not initialized")
        raise unless retriable_streamable_init_race

        sleep 0.2
        tool.execute
      end

      expect(result.to_s).to include("Error executing sampling request")
    end

    it "client will provide a sample object to the guard for validation" do
      sample = nil
      RubyLLM::MCP.configure do |config|
        config.sampling.enabled = true

        config.sampling.guard do |incoming_sample|
          sample = incoming_sample
          false
        end
      end
      client.start

      tool = wait_for_tool(client, "sampling-test")
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
      expect(sample.model_preferences.hints).to eq(["gemini-2.0-flash", "gpt-4o"])
      expect(sample.model_preferences.cost_priority).to eq(1)
      expect(sample.model_preferences.speed_priority).to eq(1)
      expect(sample.model_preferences.intelligence_priority).to eq(1)
    end

    it "client can call a block to determine the preferred model accessing the model preferences" do
      model_preferences = nil
      RubyLLM::MCP.configure do |config|
        config.sampling.enabled = true

        config.sampling.preferred_model do |incoming_model_preferences|
          model_preferences = incoming_model_preferences
          incoming_model_preferences&.hints&.first
        end
      end

      client.start

      tool = wait_for_tool(client, "sampling-test")
      result = tool.execute

      expect(result.to_s).to include("gemini-2.0-flash")
      expect(model_preferences).to be_a(RubyLLM::MCP::Sample::Hint)
    end

    it "client calls a block to determine the preferred model and raises an error it will send an error back" do
      RubyLLM::MCP.configure do |config|
        config.sampling.enabled = true

        config.sampling.preferred_model do
          raise "Error in preferred model"
        end
      end

      client.start

      tool = wait_for_tool(client, "sampling-test")
      result = tool.execute

      expect(result.to_s).to include("Failed to determine preferred model")
      expect(result.to_s).to include("Error in preferred model")
    end

    it "supports handler classes configured via client.on_sampling" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::SamplingHandler) do
        def execute
          reject("handler class rejection")
        end
      end

      RubyLLM::MCP.configure do |config|
        config.sampling.enabled = true
        config.sampling.preferred_model = "gpt-4o"
      end

      client.on_sampling(handler_class)
      client.start

      tool = wait_for_tool(client, "sampling-test")
      result = tool.execute

      expect(result.to_s).to include("handler class rejection")
    end

    COMPLEX_FUNCTION_MODELS.each do |model|
      context "with #{model[:provider]} #{model[:model]}" do
        it "executes a chat message and provides information to the server without a guard" do
          RubyLLM::MCP.configure do |config|
            config.sampling.enabled = true
            config.sampling.preferred_model = model[:model]
          end
          client.start

          tool = wait_for_tool(client, "sampling-test")
          result = tool.execute

          expect(result.to_s).to include("Sampling test completed")
        end

        it "provides information about the sample with a guard" do
          RubyLLM::MCP.configure do |config|
            config.sampling.enabled = true
            config.sampling.preferred_model = model[:model]

            config.sampling.guard do
              true
            end
          end
          client.start

          tool = wait_for_tool(client, "sampling-test")
          result = tool.execute

          expect(result.to_s).to include("Sampling test completed")
        end
      end
    end
  end

  describe "Handler Class Support" do
    it "works with custom handler classes" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::SamplingHandler) do
        def execute
          accept("Handler response")
        end
      end

      coordinator = double("Coordinator", sampling_callback_enabled?: true)
      allow(coordinator).to receive(:sampling_callback).and_return(handler_class)
      allow(coordinator).to receive(:sampling_create_message_response)
      allow(RubyLLM::MCP.config.sampling).to receive(:preferred_model).and_return("gpt-4")

      sample = RubyLLM::MCP::Sample.new(result, coordinator)

      expect(coordinator).to receive(:sampling_create_message_response).with(
        hash_including(message: "Handler response")
      )

      sample.execute
    end

    it "maintains backward compatibility with block callbacks" do
      coordinator = double("Coordinator", sampling_callback_enabled?: true)
      block_callback = ->(s) { s.message.length < 100 }
      allow(coordinator).to receive(:sampling_callback).and_return(block_callback)
      allow(coordinator).to receive(:sampling_create_message_response)
      allow(RubyLLM::MCP.config.sampling).to receive(:preferred_model).and_return("gpt-4")

      # Mock chat
      chat = double("Chat")
      allow(RubyLLM::Chat).to receive(:new).and_return(chat)
      allow(chat).to receive(:add_message)
      allow(chat).to receive(:complete).and_return("Block response")

      sample = RubyLLM::MCP::Sample.new(result, coordinator)

      expect(coordinator).to receive(:sampling_create_message_response).with(
        hash_including(message: "Block response")
      )

      sample.execute
    end
  end
end

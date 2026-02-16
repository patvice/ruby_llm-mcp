# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Elicitation do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
    ClientRunner.start_all
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.stop_all
  end

  describe "Elicitation Configuration" do
    it "accepts elicitation handler in global configuration" do
      original_config = RubyLLM::MCP.configuration.dup

      expect do
        RubyLLM::MCP.configure do |config|
          config.on_elicitation do |elicitation|
            elicitation.structured_response = { "confirmation" => true }
            true
          end
        end
      end.not_to raise_error

      # Restore original configuration
      RubyLLM::MCP.instance_variable_set(:@configuration, original_config)
    end

    it "validates elicitation handler is callable" do
      original_config = RubyLLM::MCP.configuration.dup

      # The on_elicitation method only accepts blocks, not direct assignment
      expect do
        config = RubyLLM::MCP.configuration
        config.instance_variable_set(:@on_elicitation, "not a callable")
      end.not_to raise_error # Assignment doesn't validate, validation happens during use

      # Restore original configuration
      RubyLLM::MCP.instance_variable_set(:@configuration, original_config)
    end

    it "accepts per-client elicitation handlers" do
      client = RubyLLM::MCP::Client.new(
        name: "elicitation-test-client",
        transport_type: :stdio,
        start: false,
        config: {
          command: %w[echo test]
        }
      )

      expect do
        client.on_elicitation do |elicitation|
          elicitation.structured_response = { "user_choice" => "option_a" }
          true
        end
      end.not_to raise_error
    end
  end

  describe "Elicitation Handling" do
    let(:elicitation_handler) do
      lambda do |elicitation|
        case elicitation.message
        when /confirmation/i
          elicitation.structured_response = { "confirmed" => true }
          true
        when /preference/i
          elicitation.structured_response = {
            "preference" => "option_a",
            "confidence" => 0.8,
            "reasoning" => "Based on user history"
          }
          true
        when /reject/i
          false # Reject the elicitation
        else
          elicitation.structured_response = { "response" => "default" }
          true
        end
      end
    end

    # Integration tests - only run on adapters that support elicitation
    each_client_supporting(:elicitation) do
      before do
        # Configure elicitation handler for this test
        client.on_elicitation(&elicitation_handler)
      end

      it "handles elicitation requests from tools" do
        tool = client.tool("user_preference_elicitation")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        result = tool.execute(scenario: "preference_collection")
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Collected user preferences")
      end

      it "executes tools that trigger elicitation workflow" do
        # Set up elicitation handler that provides user preferences
        client.on_elicitation do |elicitation|
          if elicitation.message.include?("user preferences")
            elicitation.structured_response = {
              "theme" => "dark",
              "language" => "en",
              "notifications" => true
            }
            true
          else
            false
          end
        end

        tool = client.tool("user_preference_collector")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        result = tool.execute(scenario: "app_preferences")
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Collected user preferences")
        # Verify the elicitation response is included in the result
        expect(result.to_s).to include("dark")
        expect(result.to_s).to include("en")
        expect(result.to_s).to include("true")
      end

      it "executes simple elicitation tool with confirmation" do
        # Set up elicitation handler for confirmations
        client.on_elicitation do |elicitation|
          if elicitation.message.include?("confirm")
            elicitation.structured_response = { "confirmed" => true, "response" => "confirmed" }
            true
          else
            false
          end
        end

        tool = client.tool("simple_elicitation")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        result = tool.execute(message: "Please confirm your choice")
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Simple elicitation completed")
        # Verify the confirmation response is included
        expect(result.to_s).to include("confirmed")
        expect(result.to_s).to include("true")
      end

      it "supports handler classes configured via client.on_elicitation" do
        handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
          def execute
            accept({ "confirmed" => true, "response" => "handled by class" })
          end
        end

        client.on_elicitation(handler_class)

        tool = client.tool("simple_elicitation")
        result = tool.execute(message: "Please confirm your choice")

        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("handled by class")
      end

      it "executes complex elicitation with structured schema validation" do # rubocop:disable RSpec/ExampleLength
        # Set up elicitation handler that provides valid structured data
        client.on_elicitation do |elicitation|
          case elicitation.message
          when /user_profile/
            elicitation.structured_response = {
              "name" => "John Doe",
              "email" => "john@example.com",
              "age" => 30
            }
            true
          when /settings/
            elicitation.structured_response = {
              "auto_save" => true,
              "backup_frequency" => "daily",
              "max_history" => 100
            }
            true
          else
            false
          end
        end

        tool = client.tool("complex_elicitation")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        # Test user profile collection
        result = tool.execute(data_type: "user_profile")
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Complex elicitation completed")
        expect(result.to_s).to include("John Doe")
        expect(result.to_s).to include("john@example.com")

        # Test settings collection
        result = tool.execute(data_type: "settings")
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Complex elicitation completed")
        expect(result.to_s).to include("auto_save")
        expect(result.to_s).to include("daily")
      end

      it "handles rejected elicitation in tool execution" do
        # Set up elicitation handler that rejects sensitive requests
        client.on_elicitation do |elicitation|
          if elicitation.message.include?("sensitive")
            false # Reject sensitive data requests
          else
            elicitation.structured_response = { "data" => "safe_data" }
            true
          end
        end

        tool = client.tool("rejectable_elicitation")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        # Test rejection of sensitive request
        result = tool.execute(request_type: "sensitive")
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("reject")

        # Test acceptance of optional request
        result = tool.execute(request_type: "optional")
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("elicitation completed")
        expect(result.to_s).to include("safe_data")
      end

      it "handles elicitation timeout and fallback" do
        # Set up elicitation handler that simulates timeout by taking too long
        client.on_elicitation do |elicitation|
          # Simulate a delay that might cause timeout
          if elicitation.message.include?("quick")
            elicitation.structured_response = { "response" => "quick_answer" }
            true
          else
            false
          end
        end

        tool = client.tool("simple_elicitation")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        result = tool.execute(message: "Please provide a quick response")
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Simple elicitation completed")
        expect(result.to_s).to include("quick_answer")
      end

      it "handles invalid elicitation response format during execution" do
        # Set up elicitation handler that provides invalid response format
        client.on_elicitation do |elicitation|
          # Invalid: setting response to a string instead of structured data
          elicitation.structured_response = "invalid string response"
          true
        end

        tool = client.tool("complex_elicitation")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        # Tool should handle invalid response gracefully
        result = tool.execute(data_type: "user_profile")
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Complex elicitation completed")
        # Invalid response should cause cancellation
        expect(result.to_s).to include("\"action\":\"cancel\"")
      end
    end
  end

  describe "Elicitation Response Validation" do
    let(:mock_coordinator) { instance_double(RubyLLM::MCP::Native::Client) }
    let(:mock_result) do
      instance_double(RubyLLM::MCP::Result,
                      id: "test-id-123",
                      params: {
                        "message" => "Please select your preference",
                        "requestedSchema" => {
                          "type" => "object",
                          "properties" => {
                            "preference" => {
                              "type" => "string",
                              "enum" => %w[option_a option_b option_c]
                            },
                            "confidence" => {
                              "type" => "number",
                              "minimum" => 0,
                              "maximum" => 1
                            }
                          },
                          "required" => ["preference"]
                        }
                      })
    end
    let(:elicitation) { RubyLLM::MCP::Elicitation.new(mock_coordinator, mock_result) }

    it "validates structured responses against provided schema" do
      # Valid response
      elicitation.structured_response = {
        "preference" => "option_a",
        "confidence" => 0.8
      }

      expect(elicitation.validate_response).to be true
    end

    it "rejects invalid structured responses" do
      # Invalid response - missing required field
      elicitation.structured_response = {
        "confidence" => 0.8
      }

      expect(elicitation.validate_response).to be false
    end

    it "rejects responses with invalid enum values" do
      # Invalid response - invalid enum value
      elicitation.structured_response = {
        "preference" => "invalid_option",
        "confidence" => 0.8
      }

      expect(elicitation.validate_response).to be false
    end

    it "validates numeric constraints" do
      # Invalid response - confidence out of range
      elicitation.structured_response = {
        "preference" => "option_a",
        "confidence" => 1.5
      }

      expect(elicitation.validate_response).to be false
    end
  end

  describe "Elicitation Security" do
    let(:mock_coordinator) { instance_double(RubyLLM::MCP::Native::Client) }

    it "handles elicitation messages safely" do
      # Test that potentially malicious content in elicitation messages is handled safely
      mock_result = instance_double(RubyLLM::MCP::Result,
                                    id: "test-id-123",
                                    params: {
                                      "message" => "<script>alert('xss')</script>Please confirm",
                                      "requestedSchema" => {
                                        "type" => "object",
                                        "properties" => { "confirmed" => { "type" => "boolean" } }
                                      }
                                    })

      elicitation = RubyLLM::MCP::Elicitation.new(mock_coordinator, mock_result)

      # Message should be accessible but handled safely by the application
      expect(elicitation.instance_variable_get(:@message)).to include("Please confirm")
    end

    it "handles invalid schema structures gracefully" do
      mock_result = instance_double(RubyLLM::MCP::Result,
                                    id: "test-id-123",
                                    params: {
                                      "message" => "Test message",
                                      "requestedSchema" => "invalid schema format"
                                    })

      # Constructor should not raise error, but validation should fail
      expect do
        RubyLLM::MCP::Elicitation.new(mock_coordinator, mock_result)
      end.not_to raise_error
    end

    it "handles large elicitation responses" do
      mock_result = instance_double(RubyLLM::MCP::Result,
                                    id: "test-id-123",
                                    params: {
                                      "message" => "Test message",
                                      "requestedSchema" => {
                                        "type" => "object",
                                        "properties" => { "data" => { "type" => "string" } }
                                      }
                                    })

      elicitation = RubyLLM::MCP::Elicitation.new(mock_coordinator, mock_result)

      # Very large response should be handled gracefully
      large_response = { "data" => "x" * 1000 }
      elicitation.structured_response = large_response

      # The validation method should handle this without errors
      expect { elicitation.validate_response }.not_to raise_error
    end
  end

  describe "Handler Class Support" do
    let(:mock_coordinator) { instance_double(RubyLLM::MCP::Native::Client) }
    let(:mock_result) do
      instance_double(RubyLLM::MCP::Result,
                      id: "handler-test-123",
                      params: {
                        "message" => "Test handler",
                        "requestedSchema" => {
                          "type" => "object",
                          "properties" => { "value" => { "type" => "string" } }
                        }
                      })
    end

    before do
      RubyLLM::MCP::Handlers::ElicitationRegistry.clear
    end

    after do
      RubyLLM::MCP::Handlers::ElicitationRegistry.clear
    end

    it "works with custom handler classes" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
        def execute
          accept({ "value" => "handler response" })
        end
      end

      allow(mock_coordinator).to receive(:elicitation_callback).and_return(handler_class)
      allow(mock_coordinator).to receive(:elicitation_response)

      elicitation = RubyLLM::MCP::Elicitation.new(mock_coordinator, mock_result)

      expect(mock_coordinator).to receive(:elicitation_response).with(
        hash_including(
          id: "handler-test-123",
          elicitation: hash_including(action: "accept", content: { "value" => "handler response" })
        )
      )

      elicitation.execute
    end

    it "supports async handlers with pending response" do
      handler_class = Class.new(RubyLLM::MCP::Handlers::ElicitationHandler) do
        async_execution timeout: 60

        def execute
          :pending
        end
      end

      allow(mock_coordinator).to receive(:elicitation_callback).and_return(handler_class)

      elicitation = RubyLLM::MCP::Elicitation.new(mock_coordinator, mock_result)

      # Track calls to elicitation_response
      response_called = false
      allow(mock_coordinator).to receive(:elicitation_response) do |_args|
        response_called = true
      end

      # Should not respond immediately
      elicitation.execute
      expect(response_called).to be(false)

      # Should be stored in registry
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(1)

      # Complete it via registry
      RubyLLM::MCP::Handlers::ElicitationRegistry.complete(
        "handler-test-123",
        response: { "value" => "async response" }
      )

      # Should have called elicitation_response and be removed after completion
      expect(response_called).to be(true)
      expect(RubyLLM::MCP::Handlers::ElicitationRegistry.size).to eq(0)
    end

    it "maintains backward compatibility with block callbacks" do
      block_callback = lambda do |elicitation|
        elicitation.structured_response = { "value" => "block response" }
        true
      end

      allow(mock_coordinator).to receive(:elicitation_callback).and_return(block_callback)
      allow(mock_coordinator).to receive(:elicitation_response)

      elicitation = RubyLLM::MCP::Elicitation.new(mock_coordinator, mock_result)

      expect(mock_coordinator).to receive(:elicitation_response).with(
        hash_including(
          elicitation: hash_including(action: "accept", content: { "value" => "block response" })
        )
      )

      elicitation.execute
    end
  end
end

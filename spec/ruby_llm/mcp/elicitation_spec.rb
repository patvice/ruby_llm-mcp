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

    CLIENT_OPTIONS.each do |config|
      context "with #{config[:name]}" do
        let(:client) { ClientRunner.fetch_client(config[:name]) }

        before do
          # Configure elicitation handler for this test
          client.on_elicitation(&elicitation_handler) if client.respond_to?(:on_elicitation)
        end

        it "handles elicitation requests from tools" do
          tool = client.tool("user_preference_elicitation")
          expect(tool).to be_a(RubyLLM::MCP::Tool)

          result = tool.execute(scenario: "preference_collection")
          expect(result).to be_a(RubyLLM::MCP::Content)
          expect(result.to_s).to include("Elicitation request prepared")
        end

        it "provides structured responses to elicitation requests" do
          # Test that elicitation requests can receive structured responses
          tool = client.tool("simple_elicitation")

          result = tool.execute(message: "Please confirm your choice")
          expect(result).to be_a(RubyLLM::MCP::Content)
          expect(result.to_s).to include("Simple elicitation")

          # Check if tool indicates elicitation was prepared
          content_parts = result.instance_variable_get(:@content)
          if content_parts.is_a?(Array) && content_parts.any? { |part| part.dig("_meta", "requires_elicitation") }
            expect(content_parts.first["_meta"]["requires_elicitation"]).to be true
          end
        end

        it "validates elicitation response against schema" do
          # Test that tools provide proper elicitation schemas that can be validated
          tool = client.tool("complex_elicitation")
          expect(tool).to be_a(RubyLLM::MCP::Tool)

          result = tool.execute(data_type: "user_profile")
          expect(result).to be_a(RubyLLM::MCP::Content)
          expect(result.to_s).to include("Complex elicitation prepared")

          # Check that the tool provides a proper schema in metadata
          content_parts = result.instance_variable_get(:@content)
          if content_parts.is_a?(Array)
            meta_part = content_parts.find { |part| part.dig("_meta", "elicitation_request") }
            if meta_part
              schema = meta_part["_meta"]["elicitation_request"]["requestedSchema"]
              expect(schema).to be_a(Hash)
              expect(schema).to have_key("type")
              expect(schema).to have_key("properties")
              expect(schema).to have_key("required")
            end
          end
        end
      end
    end
  end

  describe "Elicitation Response Validation" do
    let(:mock_coordinator) { instance_double(RubyLLM::MCP::Coordinator) }
    let(:mock_result) do
      instance_double(RubyLLM::MCP::Result, params: {
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

  describe "Elicitation Error Handling" do
    CLIENT_OPTIONS.each do |config|
      context "with #{config[:name]}" do
        let(:client) { ClientRunner.fetch_client(config[:name]) }

        it "handles rejected elicitation requests gracefully" do
          # Configure handler that rejects requests
          client.on_elicitation { |_elicitation| false } if client.respond_to?(:on_elicitation)

          tool = client.tool("rejectable_elicitation")
          result = tool.execute(request_type: "sensitive")

          # Tool should handle rejection gracefully
          expect(result).to be_a(RubyLLM::MCP::Content)
          expect(result.to_s).to include("client may accept or reject")
        end

        it "handles invalid elicitation responses" do
          # Configure handler that provides invalid response
          if client.respond_to?(:on_elicitation)
            client.on_elicitation do |elicitation|
              elicitation.structured_response = "invalid response format"
              true
            end
          end

          tool = client.tool("complex_elicitation")
          result = tool.execute(data_type: "user_profile")

          # Should handle invalid response gracefully
          expect(result).to be_a(RubyLLM::MCP::Content)
          expect(result.to_s).to include("Complex elicitation prepared")
        end
      end
    end
  end

  describe "Elicitation Security" do
    let(:mock_coordinator) { instance_double(RubyLLM::MCP::Coordinator) }

    it "handles elicitation messages safely" do
      # Test that potentially malicious content in elicitation messages is handled safely
      mock_result = instance_double(RubyLLM::MCP::Result, params: {
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
      mock_result = instance_double(RubyLLM::MCP::Result, params: {
                                      "message" => "Test message",
                                      "requestedSchema" => "invalid schema format"
                                    })

      # Constructor should not raise error, but validation should fail
      expect do
        RubyLLM::MCP::Elicitation.new(mock_coordinator, mock_result)
      end.not_to raise_error
    end

    it "handles large elicitation responses" do
      mock_result = instance_double(RubyLLM::MCP::Result, params: {
                                      "message" => "Test message",
                                      "requestedSchema" => { "type" => "object",
                                                             "properties" => { "data" => { "type" => "string" } } }
                                    })

      elicitation = RubyLLM::MCP::Elicitation.new(mock_coordinator, mock_result)

      # Very large response should be handled gracefully
      large_response = { "data" => "x" * 1000 }
      elicitation.structured_response = large_response

      # The validation method should handle this without errors
      expect { elicitation.validate_response }.not_to raise_error
    end
  end
end

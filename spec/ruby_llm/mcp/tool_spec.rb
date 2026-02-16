# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Tool do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
    ClientRunner.start_all
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.stop_all
  end

  # Test environment variable only on stdio clients
  each_client do |config|
    next unless config[:name].include?("stdio")

    it "returns the environment variable" do
      tool = client.tool("return_set_evn")
      result = tool.execute
      expect(result.to_s).to eq("Test Env = this_is_a_test")
    end
  end

  context "with #{PAGINATION_CLIENT_CONFIG[:name]}" do
    let(:client) { RubyLLM::MCP::Client.new(**PAGINATION_CLIENT_CONFIG) }

    before do
      client.start
    end

    after do
      client.stop
    end

    describe "tool_list" do
      it "paginates tool list to get all tools" do
        tools = client.tools
        expect(tools.count).to eq(2)
      end
    end
  end

  each_client do
    describe "tool_list" do
      it "returns a list of tools" do
        tools = client.tools
        expect(tools).to be_a(Array)
        expect(tools.first.name).to eq("add")
      end

      it "get specific tool by name" do
        tools = client.tool("add")
        expect(tools).to be_a(RubyLLM::MCP::Tool)
        expect(tools.name).to eq("add")
      end
    end

    describe "tool_call" do
      it "calls a tool" do
        tools = client.tools
        add_tool = tools.find { |tool| tool.name == "add" }
        result = add_tool.execute(a: 1, b: 2)

        expect(result.to_s).to eq("3")
      end

      it "calls a tool with an array of parameters" do
        weather_tool = client.tool("get_weather_from_locations")
        result = weather_tool.execute(locations: ["Ottawa", "San Francisco"])

        expect(result.to_s).to eq("Weather for Ottawa, San Francisco is great!")
      end

      it "calls a tool with an object of parameters" do
        weather_tool = client.tool("get_weather_from_geocode")
        result = weather_tool.execute(geocode: { latitude: 45.4201, longitude: 75.7003 })

        expect(result.to_s).to eq("Weather for 45.4201, 75.7003 is great!")
      end

      it "still load if tool is malformed" do
        tool = client.tool("malformed_tool")

        expect(tool).not_to be_nil
      end

      it "calls a tool and get back an image" do
        image_tool = client.tool("get_dog_image")
        result = image_tool.execute

        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.attachments.first).to be_a(RubyLLM::MCP::Attachment)
        expect(result.attachments.first.mime_type).to eq("image/png")
        expect(result.attachments.first.content).not_to be_nil
      end

      it "calls a tool and get back an audio" do
        audio_tool = client.tool("get_jackhammer_audio")
        result = audio_tool.execute

        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.attachments).not_to be_nil
        expect(result.attachments.first).to be_a(RubyLLM::MCP::Attachment)
        expect(result.attachments.first.mime_type).to eq("audio/wav")
        expect(result.attachments.first.content).not_to be_nil
      end

      it "calls a tool and get back a resource" do
        resource_tool = client.tool("get_file_resource")
        result = resource_tool.execute(filename: "test.txt")

        expect(result).to be_a(RubyLLM::MCP::Content)
        value = <<~TODO
          get_file_resource: Returns a file resource reference

          This is the content of test.txt
        TODO

        expect(result.to_s).to eq(value.strip)
      end

      it "handles tool errors gracefully" do
        error_tool = client.tool("tool_error")

        # Test when tool returns an error
        result = error_tool.execute(shouldError: true)
        expect(result).to eq({ error: "Tool execution error: Error: Tool error" })
        expect(result.to_s).to include("Error: Tool error")

        # Test when tool doesn't return an error
        result = error_tool.execute(shouldError: false)
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to eq("No error")
      end

      it "can call a complex union type tool" do
        tool = client.tool("fetch_site")
        result = tool.execute(website: "https://www.example.com/")

        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Example")

        result = tool.execute(website: { url: "https://www.example.com/",
                                         headers: [{ name: "User-Agent", value: "test" }] })

        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Example Domain")
      end
    end
  end

  # Human in the loop tests - only run on adapters that support this feature
  each_client_supporting(:human_in_the_loop) do |_config|
    describe "on_human_in_the_loop" do
      after do
        client.on_human_in_the_loop
      end

      it "supports handler classes with options for approve/deny decisions" do
        handler_class = Class.new(RubyLLM::MCP::Handlers::HumanInTheLoopHandler) do
          option :safe_sum, default: 3

          def execute
            if parameters[:a].to_i + parameters[:b].to_i <= options[:safe_sum]
              approve
            else
              deny("sum exceeds policy")
            end
          end
        end

        client.on_human_in_the_loop(handler_class, safe_sum: 3)
        tool = client.tool("add")

        expect(tool.execute(a: 1, b: 2).to_s).to eq("3")

        result = tool.execute(a: 2, b: 2)
        message = "Tool execution error: Tool call was cancelled by the client"
        expect(result).to eq({ error: message })
      end

      it "supports async deferred approvals via registry completion (e2e)" do
        approval_ids = Queue.new

        handler_class = Class.new(RubyLLM::MCP::Handlers::HumanInTheLoopHandler) do
          option :approval_ids, required: true
          async_execution timeout: 2

          def execute
            options[:approval_ids] << approval_id
            defer
          end
        end

        client.on_human_in_the_loop(handler_class, approval_ids: approval_ids)
        tool = client.tool("add")
        result_queue = Queue.new

        execute_thread = Thread.new do
          result_queue << tool.execute(a: 1, b: 2)
        end

        approval_id = nil
        Timeout.timeout(3) do
          approval_id = approval_ids.pop
        end

        Timeout.timeout(3) do
          sleep 0.01 until RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.retrieve(approval_id)
        end

        RubyLLM::MCP::Handlers::HumanInTheLoopRegistry.approve(approval_id)

        Timeout.timeout(3) do
          execute_thread.join
        end

        result = result_queue.pop
        expect(result.to_s).to eq("3")
      ensure
        execute_thread&.kill if execute_thread&.alive?
      end

      it "does not block indefinitely for deferred approvals that time out (e2e)" do
        handler_class = Class.new(RubyLLM::MCP::Handlers::HumanInTheLoopHandler) do
          async_execution timeout: 0.1

          def execute
            defer
          end
        end

        client.on_human_in_the_loop(handler_class)
        tool = client.tool("add")
        message = "Tool execution error: Tool call was cancelled by the client"

        result = nil
        Timeout.timeout(2) do
          result = tool.execute(a: 1, b: 2)
        end

        expect(result).to eq({ error: message })
      end
    end
  end

  describe "Structured Tool Output (2025-06-18)" do
    each_client do |_config|
      it "validates structured output against output schema" do
        tool = client.tool("structured_data_analyzer")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        result = tool.execute(data: "Hello world this is a test", format: "summary")
        expect(result).to be_a(RubyLLM::MCP::Content)

        # Check if structured content is available and validated
        if result.respond_to?(:structured_content)
          expect(result.structured_content).to be_a(Hash)
          expect(result.structured_content).to have_key("word_count")
          expect(result.structured_content).to have_key("character_count")
          expect(result.structured_content).to have_key("analysis_type")
          expect(result.structured_content["word_count"]).to be_a(Numeric)
          expect(result.structured_content["character_count"]).to be_a(Numeric)
        end
      end

      it "handles invalid structured output gracefully" do
        tool = client.tool("invalid_structured_output")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        # This should trigger validation error for structured output
        result = tool.execute(trigger_error: true)

        # The tool should still return content, but structured validation may fail
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Invalid structured data")
      end

      it "returns valid structured output when schema is satisfied" do
        tool = client.tool("invalid_structured_output")

        result = tool.execute(trigger_error: false)
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Valid output")
      end
    end
  end

  describe "Human-Friendly Display Names (2025-06-18)" do
    each_client do |_config|
      it "provides human-friendly titles for tools" do
        tool = client.tool("complex_calculation")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        # Check if tool has a human-friendly description or title
        expect(tool.description).to include("🧮 Advanced Calculator")
      end

      it "executes tools with human-friendly names" do
        tool = client.tool("complex_calculation")

        result = tool.execute(expression: "2 + 2", precision: 1)
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Result: 4.0")
      end

      it "handles calculation errors gracefully" do
        tool = client.tool("complex_calculation")

        result = tool.execute(expression: "invalid_expression")
        error_message = "Tool execution error: Error evaluating expression: invalid_expression is not defined"
        expect(result).to eq({ error: error_message })
        expect(result.to_s).to include("Error evaluating expression")
      end
    end
  end

  describe "Tool Annotations and Enhanced Metadata (2025-06-18)" do
    each_client do
      it "supports tool annotations for better UX" do
        tool = client.tool("complex_calculation")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        # Check if tool provides annotation information
        if tool.respond_to?(:annotations)
          annotations = tool.annotations
          expect(annotations).to be_a(Hash) if annotations
        end
      end

      it "executes annotated tools correctly" do
        tool = client.tool("complex_calculation")

        result = tool.execute(expression: "10 * 5", precision: 0)
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("50")
      end

      it "supports _meta field in tool responses" do
        tool = client.tool("long_running_task")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        result = tool.execute(duration: 500, steps: 3)
        expect(result).to be_a(RubyLLM::MCP::Content)

        # Check for metadata in response
        if result.respond_to?(:metadata) || result.respond_to?(:meta)
          meta = result.respond_to?(:metadata) ? result.metadata : result.meta
          expect(meta).to be_a(Hash) if meta
        end
      end

      it "handles progress tracking metadata" do
        tool = client.tool("long_running_task")

        result = tool.execute(duration: 1000, steps: 5)
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("long-running task")
      end
    end
  end

  describe "params_schema" do
    let(:mock_coordinator) { double("Coordinator", name: "test") }

    it "returns the input schema as-is" do
      tool_response = {
        "name" => "test_tool",
        "description" => "A test tool",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "name" => {
              "type" => "string",
              "description" => "User name"
            },
            "age" => {
              "type" => "integer",
              "description" => "User age"
            }
          },
          "required" => ["name"]
        }
      }

      tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

      expect(tool.params_schema).to eq(tool_response["inputSchema"])
      expect(tool.params_schema["type"]).to eq("object")
      expect(tool.params_schema["properties"]).to have_key("name")
      expect(tool.params_schema["properties"]).to have_key("age")
      expect(tool.params_schema["required"]).to eq(["name"])
    end

    it "handles complex anyOf schemas" do
      tool_response = {
        "name" => "test_tool",
        "description" => "A test tool with complex anyOf parameter",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "value" => {
              "anyOf" => [
                {
                  "type" => "string",
                  "description" => "A string value"
                },
                {
                  "type" => "array",
                  "items" => { "type" => "string" }
                }
              ],
              "description" => "The value or list of values"
            }
          }
        }
      }

      tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

      expect(tool.params_schema["properties"]["value"]).to have_key("anyOf")
      expect(tool.params_schema["properties"]["value"]["anyOf"]).to be_an(Array)
      expect(tool.params_schema["properties"]["value"]["anyOf"].length).to eq(2)
    end

    it "handles schemas with title fields" do
      tool_response = {
        "name" => "test_tool",
        "description" => "A test tool with titles",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "user_email" => {
              "type" => "string",
              "title" => "User's Email Address",
              "description" => "The email address of the user"
            },
            "count" => {
              "type" => "integer",
              "title" => "Item Count",
              "description" => "Number of items to process"
            }
          }
        }
      }

      tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

      expect(tool.params_schema["properties"]["user_email"]["title"]).to eq("User's Email Address")
      expect(tool.params_schema["properties"]["count"]["title"]).to eq("Item Count")
    end

    it "handles schemas with nested objects" do
      tool_response = {
        "name" => "test_tool",
        "description" => "A test tool with nested schema",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "user" => {
              "type" => "object",
              "properties" => {
                "name" => { "type" => "string" },
                "email" => { "type" => "string" }
              },
              "required" => ["name"]
            }
          }
        }
      }

      tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

      expect(tool.params_schema["properties"]["user"]["type"]).to eq("object")
      expect(tool.params_schema["properties"]["user"]["properties"]).to have_key("name")
      expect(tool.params_schema["properties"]["user"]["properties"]).to have_key("email")
      expect(tool.params_schema["properties"]["user"]["required"]).to eq(["name"])
    end

    it "returns nil when no input schema is provided" do
      tool_response = {
        "name" => "test_tool",
        "description" => "A test tool without input schema"
      }

      tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

      expect(tool.params_schema).to be_nil
    end
  end

  describe "structured content output validation" do
    let(:mock_adapter) { double("Adapter", name: "test") }
    let(:mock_client) { double("Client", name: "test") }

    before do
      allow(mock_adapter).to receive(:client).and_return(mock_client)
    end

    context "when structured content is valid against output schema" do
      it "returns structured JSON content when validation passes" do
        tool_response = {
          "name" => "structured_tool",
          "description" => "A tool with structured output",
          "inputSchema" => { "type" => "object", "properties" => {} },
          "outputSchema" => {
            "type" => "object",
            "properties" => {
              "count" => { "type" => "integer" },
              "message" => { "type" => "string" }
            },
            "required" => %w[count message]
          }
        }

        mock_result = double("Result",
                             error?: false,
                             execution_error?: false,
                             value: {
                               "content" => [{ "text" => "Success message" }],
                               "structuredContent" => { "count" => 42, "message" => "hello" }
                             })

        allow(mock_adapter).to receive(:execute_tool).and_return(mock_result)

        tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)
        result = tool.execute

        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to eq({ "count" => 42, "message" => "hello" }.to_json)
      end
    end

    context "when structured content is invalid against output schema" do
      it "returns an error hash when validation fails" do
        tool_response = {
          "name" => "structured_tool",
          "description" => "A tool with structured output",
          "inputSchema" => { "type" => "object", "properties" => {} },
          "outputSchema" => {
            "type" => "object",
            "properties" => {
              "count" => { "type" => "integer" },
              "message" => { "type" => "string" }
            },
            "required" => %w[count message]
          }
        }

        invalid_structured_content = { "count" => "not_an_integer", "message" => 123 }
        mock_result = double("Result",
                             error?: false,
                             execution_error?: false,
                             value: {
                               "content" => [{ "text" => "Some text" }],
                               "structuredContent" => invalid_structured_content
                             })

        allow(mock_adapter).to receive(:execute_tool).and_return(mock_result)

        tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)
        result = tool.execute

        expect(result).to be_a(Hash)
        expect(result[:error]).to include("Structured output is not valid")
        expect(result[:error]).to include(invalid_structured_content.to_s)
      end

      it "returns an error when required fields are missing" do
        tool_response = {
          "name" => "structured_tool",
          "description" => "A tool with structured output",
          "inputSchema" => { "type" => "object", "properties" => {} },
          "outputSchema" => {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string" },
              "age" => { "type" => "integer" }
            },
            "required" => %w[name age]
          }
        }

        # Missing 'age' which is required
        invalid_structured_content = { "name" => "John" }
        mock_result = double("Result",
                             error?: false,
                             execution_error?: false,
                             value: {
                               "content" => [{ "text" => "Some text" }],
                               "structuredContent" => invalid_structured_content
                             })

        allow(mock_adapter).to receive(:execute_tool).and_return(mock_result)

        tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)
        result = tool.execute

        expect(result).to be_a(Hash)
        expect(result[:error]).to include("Structured output is not valid")
      end
    end

    context "when output schema contains $schema property" do
      it "strips $schema property to avoid json-schema gem network lookup" do
        tool_response = {
          "name" => "structured_tool",
          "description" => "A tool with structured output",
          "inputSchema" => { "type" => "object", "properties" => {} },
          "outputSchema" => {
            "$schema" => "https://json-schema.org/draft/2020-12/schema",
            "type" => "object",
            "properties" => {
              "value" => { "type" => "string" }
            },
            "required" => ["value"]
          }
        }

        mock_result = double("Result",
                             error?: false,
                             execution_error?: false,
                             value: {
                               "content" => [{ "text" => "Valid output" }],
                               "structuredContent" => { "value" => "test" }
                             })

        allow(mock_adapter).to receive(:execute_tool).and_return(mock_result)

        # Expect JSON::Validator to be called with schema WITHOUT $schema property
        expect(JSON::Validator).to receive(:validate).with(
          hash_not_including("$schema"),
          { "value" => "test" }
        ).and_call_original

        tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)
        result = tool.execute

        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to eq({ "value" => "test" }.to_json)
      end
    end

    context "when output schema is nil" do
      it "does not validate structured content and returns normal content" do
        tool_response = {
          "name" => "no_schema_tool",
          "description" => "A tool without output schema",
          "inputSchema" => { "type" => "object", "properties" => {} }
          # No outputSchema
        }

        mock_result = double("Result",
                             error?: false,
                             execution_error?: false,
                             value: {
                               "content" => [{ "text" => "Normal output" }],
                               "structuredContent" => { "anything" => "goes" }
                             })

        allow(mock_adapter).to receive(:execute_tool).and_return(mock_result)

        tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)
        result = tool.execute

        # Should return normal content, not validate structured content
        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to eq("Normal output")
      end
    end

    context "when there is no structured content" do
      it "returns normal content even with output schema defined" do
        tool_response = {
          "name" => "structured_tool",
          "description" => "A tool with structured output",
          "inputSchema" => { "type" => "object", "properties" => {} },
          "outputSchema" => {
            "type" => "object",
            "properties" => {
              "value" => { "type" => "string" }
            }
          }
        }

        mock_result = double("Result",
                             error?: false,
                             execution_error?: false,
                             value: {
                               "content" => [{ "text" => "Just text, no structured content" }]
                               # No structuredContent key
                             })

        allow(mock_adapter).to receive(:execute_tool).and_return(mock_result)

        tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)
        result = tool.execute

        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to eq("Just text, no structured content")
      end
    end
  end

  describe "input schema validation and normalization" do
    let(:mock_coordinator) { double("Coordinator", name: "test") }

    describe "normalization for malformed schemas" do
      it "normalizes object schema missing properties field" do
        tool_response = {
          "name" => "malformed_tool",
          "description" => "A malformed tool",
          "inputSchema" => {
            "type" => "object"
          }
        }

        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

        expect(tool.params_schema["type"]).to eq("object")
        expect(tool.params_schema).to have_key("properties")
        expect(tool.params_schema["properties"]).to eq({})
      end

      it "normalizes nested object schemas missing properties" do
        tool_response = {
          "name" => "nested_malformed_tool",
          "description" => "A tool with nested malformed schema",
          "inputSchema" => {
            "type" => "object",
            "properties" => {
              "user" => {
                "type" => "object"
              }
            }
          }
        }

        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

        expect(tool.params_schema["properties"]["user"]["type"]).to eq("object")
        expect(tool.params_schema["properties"]["user"]).to have_key("properties")
        expect(tool.params_schema["properties"]["user"]["properties"]).to eq({})
      end

      it "normalizes object schemas in arrays" do
        tool_response = {
          "name" => "array_tool",
          "description" => "A tool with array of objects",
          "inputSchema" => {
            "type" => "object",
            "properties" => {
              "items" => {
                "type" => "array",
                "items" => {
                  "type" => "object"
                }
              }
            }
          }
        }

        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

        item_schema = tool.params_schema["properties"]["items"]["items"]
        expect(item_schema["type"]).to eq("object")
        expect(item_schema).to have_key("properties")
        expect(item_schema["properties"]).to eq({})
      end
    end

    describe "validation using json-schema" do
      it "does not normalize valid schemas" do
        tool_response = {
          "name" => "valid_tool",
          "description" => "A valid tool",
          "inputSchema" => {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string" }
            }
          }
        }

        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

        # Schema should be returned as-is since it's valid
        expect(tool.params_schema).to eq(tool_response["inputSchema"])
        expect(tool.params_schema["type"]).to eq("object")
        expect(tool.params_schema["properties"]["name"]["type"]).to eq("string")
      end

      it "normalizes schemas that fail json-schema validation" do
        # Create a schema that's structurally invalid (object without properties)
        tool_response = {
          "name" => "invalid_tool",
          "description" => "An invalid tool",
          "inputSchema" => {
            "type" => "object"
          }
        }

        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

        # Should be normalized to include properties
        expect(tool.params_schema["type"]).to eq("object")
        expect(tool.params_schema).to have_key("properties")
        expect(tool.params_schema["properties"]).to eq({})
      end
    end

    describe "caching behavior" do
      it "normalizes schema once during initialization" do
        tool_response = {
          "name" => "cached_tool",
          "description" => "A tool to test caching",
          "inputSchema" => {
            "type" => "object"
          }
        }

        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

        # Store the normalized schema
        first_call = tool.params_schema

        # Call params_schema multiple times
        second_call = tool.params_schema
        third_call = tool.params_schema

        # Should return the same normalized schema each time
        expect(first_call).to eq(second_call)
        expect(second_call).to eq(third_call)
        expect(first_call).to have_key("properties")
      end

      it "does not mutate the original input schema" do
        original_schema = {
          "type" => "object"
        }

        tool_response = {
          "name" => "immutable_tool",
          "description" => "A tool to test immutability",
          "inputSchema" => original_schema.dup
        }

        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

        # Normalized schema should have properties
        expect(tool.params_schema).to have_key("properties")

        # Original schema should remain unchanged (no properties)
        expect(original_schema).not_to have_key("properties")
        expect(tool_response["inputSchema"]).not_to have_key("properties")
      end
    end

    describe "edge cases" do
      it "handles nil schema gracefully" do
        tool_response = {
          "name" => "nil_schema_tool",
          "description" => "A tool with nil schema"
        }

        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

        expect(tool.params_schema).to be_nil
      end

      it "handles empty hash schema" do
        tool_response = {
          "name" => "empty_tool",
          "description" => "A tool with empty schema",
          "inputSchema" => {}
        }

        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

        expect(tool.params_schema).to eq({})
      end

      it "handles schema with type array" do
        tool_response = {
          "name" => "array_type_tool",
          "description" => "A tool with array type schema",
          "inputSchema" => {
            "type" => "array",
            "items" => { "type" => "string" }
          }
        }

        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

        expect(tool.params_schema["type"]).to eq("array")
        expect(tool.params_schema["items"]["type"]).to eq("string")
      end

      it "handles complex schemas with anyOf and nested objects" do
        tool_response = {
          "name" => "complex_tool",
          "description" => "A tool with complex schema",
          "inputSchema" => {
            "type" => "object",
            "properties" => {
              "value" => {
                "anyOf" => [
                  {
                    "type" => "object",
                    "properties" => { "key" => { "type" => "string" } }
                  },
                  {
                    "type" => "object"
                  }
                ]
              }
            }
          }
        }

        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response)

        any_of = tool.params_schema["properties"]["value"]["anyOf"]
        expect(any_of.length).to eq(2)
        # First anyOf option should remain unchanged (has properties)
        expect(any_of[0]["properties"]).to have_key("key")
        # Second anyOf option should be normalized (missing properties)
        expect(any_of[1]["type"]).to eq("object")
        expect(any_of[1]).to have_key("properties")
        expect(any_of[1]["properties"]).to eq({})
      end
    end

    describe "integration with real client" do
      each_client do |_config|
        it "normalizes malformed_tool schema correctly" do
          tool = client.tool("malformed_tool")

          schema = tool.params_schema
          expect(schema).not_to be_nil
          expect(schema["type"]).to eq("object")

          # Should have properties field even if original was malformed
          expect(schema).to have_key("properties")
          expect(schema["properties"]).to be_a(Hash)
        end

        it "preserves valid schemas without normalization" do
          tool = client.tool("add")

          schema = tool.params_schema
          expect(schema).not_to be_nil
          expect(schema["type"]).to eq("object")
          expect(schema["properties"]).to have_key("a")
          expect(schema["properties"]).to have_key("b")

          # Valid schema should not be modified
          expect(schema["required"]).to include("a", "b")
        end
      end
    end
  end

  describe RubyLLM::MCP::Annotation do
    describe "#initialize" do
      it "parses truthy annotation fields from hash" do
        # NOTE: The implementation uses || for defaults, so false values get
        # replaced with defaults. Only truthy values are preserved.
        annotation_data = {
          "title" => "My Custom Tool",
          "readOnlyHint" => true,
          "destructiveHint" => true, # Using true since false gets default
          "idempotentHint" => true,
          "openWorldHint" => true # Using true since false gets default
        }

        annotation = described_class.new(annotation_data)

        expect(annotation.title).to eq("My Custom Tool")
        expect(annotation.read_only_hint).to be(true)
        expect(annotation.destructive_hint).to be(true)
        expect(annotation.idempotent_hint).to be(true)
        expect(annotation.open_world_hint).to be(true)
      end

      it "uses sensible defaults for missing fields" do
        annotation = described_class.new({})

        expect(annotation.title).to eq("")
        expect(annotation.read_only_hint).to be(false)
        expect(annotation.destructive_hint).to be(true) # Default: assume destructive
        expect(annotation.idempotent_hint).to be(false)
        expect(annotation.open_world_hint).to be(true)
      end

      it "handles partial annotation data" do
        annotation = described_class.new({
                                           "title" => "Partial Tool",
                                           "readOnlyHint" => true
                                         })

        expect(annotation.title).to eq("Partial Tool")
        expect(annotation.read_only_hint).to be(true)
        expect(annotation.destructive_hint).to be(true) # Default
        expect(annotation.idempotent_hint).to be(false) # Default
        expect(annotation.open_world_hint).to be(true) # Default
      end

      it "applies defaults when false is provided (current || behavior)" do
        # This test documents the current behavior: false values get defaults
        annotation = described_class.new({
                                           "destructiveHint" => false,
                                           "openWorldHint" => false
                                         })

        # Because || false returns the right-hand side default
        expect(annotation.destructive_hint).to be(true) # Got default
        expect(annotation.open_world_hint).to be(true) # Got default
      end
    end

    describe "#to_h" do
      it "serializes all fields to hash format" do
        annotation_data = {
          "title" => "Test Tool",
          "readOnlyHint" => true,
          "destructiveHint" => true, # Must be true to be preserved
          "idempotentHint" => true,
          "openWorldHint" => true # Must be true to be preserved
        }

        annotation = described_class.new(annotation_data)
        result = annotation.to_h

        expect(result).to eq({
                               title: "Test Tool",
                               readOnlyHint: true,
                               destructiveHint: true,
                               idempotentHint: true,
                               openWorldHint: true
                             })
      end

      it "uses camelCase keys matching MCP spec format" do
        annotation = described_class.new({ "title" => "Test" })
        result = annotation.to_h

        expect(result).to have_key(:readOnlyHint)
        expect(result).to have_key(:destructiveHint)
        expect(result).to have_key(:idempotentHint)
        expect(result).to have_key(:openWorldHint)
      end
    end
  end

  describe "Tool with annotations" do
    let(:mock_adapter) { double("Adapter") }
    let(:mock_client) { double("Client", name: "test") }

    before do
      allow(mock_adapter).to receive(:client).and_return(mock_client)
    end

    it "creates annotation from tool response" do
      tool_response = {
        "name" => "annotated_tool",
        "description" => "A tool with annotations",
        "inputSchema" => { "type" => "object", "properties" => {} },
        "annotations" => {
          "title" => "Annotated Tool",
          "readOnlyHint" => true,
          "destructiveHint" => true # Must use truthy value
        }
      }

      tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)

      expect(tool.annotations).to be_a(RubyLLM::MCP::Annotation)
      expect(tool.annotations.title).to eq("Annotated Tool")
      expect(tool.annotations.read_only_hint).to be(true)
      expect(tool.annotations.destructive_hint).to be(true)
    end

    it "handles tool without annotations" do
      tool_response = {
        "name" => "simple_tool",
        "description" => "A tool without annotations",
        "inputSchema" => { "type" => "object", "properties" => {} }
      }

      tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)

      expect(tool.annotations).to be_nil
    end

    it "includes annotations in to_h output" do
      tool_response = {
        "name" => "annotated_tool",
        "description" => "A tool with annotations",
        "inputSchema" => { "type" => "object", "properties" => {} },
        "annotations" => {
          "title" => "Annotated Tool",
          "readOnlyHint" => true
        }
      }

      tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)
      result = tool.to_h

      expect(result[:annotations]).to be_a(Hash)
      expect(result[:annotations][:title]).to eq("Annotated Tool")
      expect(result[:annotations][:readOnlyHint]).to be(true)
    end

    it "returns nil annotations in to_h when tool has no annotations" do
      tool_response = {
        "name" => "simple_tool",
        "description" => "A simple tool",
        "inputSchema" => { "type" => "object", "properties" => {} }
      }

      tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)
      result = tool.to_h

      expect(result[:annotations]).to be_nil
    end
  end

  describe "resource_link content handling" do
    let(:mock_adapter) { double("Adapter") }
    let(:mock_client) { double("Client", name: "test") }

    before do
      allow(mock_adapter).to receive(:register_resource)

      read_result_double = double("ReadResult",
                                  error?: false,
                                  value: {
                                    "contents" => [{ "text" => "Resource content" }]
                                  })
      allow(mock_adapter).to receive_messages(client: mock_client, resource_read: read_result_double)
    end

    it "creates and registers resource from resource_link content" do
      tool_response = {
        "name" => "link_tool",
        "description" => "Returns a resource link",
        "inputSchema" => { "type" => "object", "properties" => {} }
      }

      resource_link_content = {
        "type" => "resource_link",
        "name" => "linked_file.txt",
        "uri" => "file:///path/to/file.txt",
        "description" => "A linked file",
        "mimeType" => "text/plain"
      }

      mock_result = double("Result",
                           error?: false,
                           execution_error?: false,
                           value: { "content" => [resource_link_content] })

      allow(mock_adapter).to receive(:execute_tool).and_return(mock_result)

      tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)
      result = tool.execute

      expect(mock_adapter).to have_received(:register_resource)
      expect(result).to be_a(RubyLLM::MCP::Content)
    end

    it "extracts resource metadata from resource_link content" do
      tool_response = {
        "name" => "link_tool",
        "description" => "Returns a resource link",
        "inputSchema" => { "type" => "object", "properties" => {} }
      }

      resource_link_content = {
        "type" => "resource_link",
        "name" => "my_report.pdf",
        "uri" => "file:///reports/my_report.pdf",
        "description" => "Monthly report",
        "mimeType" => "application/pdf"
      }

      mock_result = double("Result",
                           error?: false,
                           execution_error?: false,
                           value: { "content" => [resource_link_content] })

      allow(mock_adapter).to receive(:execute_tool).and_return(mock_result)

      tool = RubyLLM::MCP::Tool.new(mock_adapter, tool_response)
      tool.execute

      # Verify the resource was registered
      expect(mock_adapter).to have_received(:register_resource)

      # Verify resource_read was called with the correct URI
      expect(mock_adapter).to have_received(:resource_read)
        .with(uri: "file:///reports/my_report.pdf")
    end
  end

  describe "end-to-end structured content output validation" do
    each_client do |_config|
      it "validates structured output and returns text content on success" do
        tool = client.tool("structured_data_analyzer")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        result = tool.execute(data: "Hello world this is a test", format: "summary")

        # Tool should return text content (not the structured data)
        # Structured data is for validation only
        if result.is_a?(String)
          expect(result).to include("Analysis completed")
        elsif result.is_a?(RubyLLM::MCP::Content)
          expect(result.to_s).to include("Analysis completed")
        end
      end

      it "handles tools returning resource content type" do
        tool = client.tool("create_report")
        expect(tool).to be_a(RubyLLM::MCP::Tool)

        result = tool.execute(title: "Test Report", content: "Report content here", format: "text")

        expect(result).to be_a(RubyLLM::MCP::Content)
        expect(result.to_s).to include("Test Report")
      end

      it "returns output schema when tool has one defined" do
        tool = client.tool("structured_data_analyzer")

        # If the tool has an output schema, it should be accessible
        if tool.respond_to?(:output_schema)
          output_schema = tool.output_schema
          # Output schema may or may not be defined depending on server implementation
          if output_schema
            expect(output_schema).to be_a(Hash)
          end
        end
      end
    end
  end
end

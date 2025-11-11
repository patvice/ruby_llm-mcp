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
      it "calls a human in the loop and cancels the tool call if returns false" do
        called = false
        client.on_human_in_the_loop do |name, params|
          called = true
          name == "add" && params[:a] == 1 && params[:b] == 2
        end

        tool = client.tool("add")
        result = tool.execute(a: 1, b: 2)
        expect(result.to_s).to eq("3")
        expect(called).to be(true)
        client.on_human_in_the_loop
      end

      it "calls a human in the loop and calls the tool if returns true" do
        called = false
        client.on_human_in_the_loop do |name, params|
          called = true
          name == "add" && params[:a] == 1 && params[:b] == 2
        end

        tool = client.tool("add")
        result = tool.execute(a: 2, b: 2)
        message = "Tool execution error: Tool call was cancelled by the client"
        expect(result).to eq({ error: message })
        expect(called).to be(true)

        client.on_human_in_the_loop
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
    let(:mock_coordinator) { double("Coordinator", name: "test") } # rubocop:disable RSpec/VerifiedDoubles

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

  describe "input schema validation and normalization" do
    let(:mock_coordinator) { double("Coordinator", name: "test") } # rubocop:disable RSpec/VerifiedDoubles

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
end

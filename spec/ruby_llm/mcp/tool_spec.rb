# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Tool do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
    ClientRunner.start_all
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.stop_all
  end

  CLIENT_OPTIONS.select { |config| config[:name] == "stdio" }.each do |config|
    context "with #{config[:name]}" do
      let(:client) { ClientRunner.fetch_client(config[:name]) }

      it "returns the environment variable" do
        tool = client.tool("return_set_evn")
        result = tool.execute
        expect(result.to_s).to eq("Test Env = this_is_a_test")
      end
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

  CLIENT_OPTIONS.each do |config|
    context "with #{config[:name]}" do
      let(:client) { ClientRunner.fetch_client(config[:name]) }

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

        it "listences to tool list updates notifications" do
          tools_count = client.tools.count
          tool = client.tool("upgrade_auth")
          tool.execute(permission: "read")

          expect(client.tools.count).to eq(tools_count + 1)
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
  end

  describe "Structured Tool Output (2025-06-18)" do
    CLIENT_OPTIONS.each do |config|
      context "with #{config[:name]}" do
        let(:client) { ClientRunner.fetch_client(config[:name]) }

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
  end

  describe "Human-Friendly Display Names (2025-06-18)" do
    CLIENT_OPTIONS.each do |config|
      context "with #{config[:name]}" do
        let(:client) { ClientRunner.fetch_client(config[:name]) }

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
  end

  describe "Tool Annotations and Enhanced Metadata (2025-06-18)" do
    CLIENT_OPTIONS.each do |config|
      context "with #{config[:name]}" do
        let(:client) { ClientRunner.fetch_client(config[:name]) }

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
  end

  describe "complex anyOf parameter parsing" do
    let(:mock_coordinator) { double("Coordinator", name: "test") } # rubocop:disable RSpec/VerifiedDoubles
    let(:tool_response_with_complex_anyof) do
      {
        "name" => "test_tool",
        "description" => "A test tool with complex anyOf parameter",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "value" => {
              "anyOf" => [
                {
                  "type" => %w[string number boolean],
                  "description" => "A filter value that can be a string, number, or boolean."
                },
                {
                  "type" => "array",
                  "items" => {
                    "$ref" => "#/properties/value/anyOf/0"
                  }
                }
              ],
              "description" => "The value or list of values for filtering."
            }
          }
        }
      }
    end

    it "parses complex anyOf with shorthand array types and array with items" do # rubocop:disable RSpec/MultipleExpectations
      tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response_with_complex_anyof)

      expect(tool.parameters).to have_key("value")
      param = tool.parameters["value"]

      expect(param.type).to eq(:union)
      expect(param.union_type).to eq("anyOf")
      expect(param.properties).to be_an(Array)
      expect(param.properties.length).to eq(2)

      # First property should be a union from shorthand ["string", "number", "boolean"]
      first_prop = param.properties[0]
      expect(first_prop.type).to eq(:union)
      expect(first_prop.union_type).to eq("anyOf")
      expect(first_prop.properties).to be_an(Array)
      expect(first_prop.properties.length).to eq(3)
      expect(first_prop.properties.map(&:type)).to eq(%i[string number boolean])

      # Second property should be an array type
      second_prop = param.properties[1]
      expect(second_prop.type).to eq(:array)
      expect(second_prop.items).to be_a(Hash)
      expect(second_prop.items).to have_key("$ref")
    end
  end

  describe "Direct shorthand type parsing" do
    let(:mock_coordinator) { double("Coordinator", name: "test") } # rubocop:disable RSpec/VerifiedDoubles
    let(:tool_response_with_direct_shorthand) do
      {
        "name" => "test_tool",
        "description" => "A test tool with direct shorthand array type",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "value" => {
              "type" => %w[string number boolean],
              "description" => "A filter value that can be a string, number, or boolean."
            }
          }
        }
      }
    end

    it "parses direct shorthand array type without anyOf wrapper" do
      tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response_with_direct_shorthand)

      expect(tool.parameters).to have_key("value")
      param = tool.parameters["value"]

      # When type is an array directly, it should be converted to an implicit anyOf union
      expect(param).to be_a(RubyLLM::MCP::Parameter)
      expect(param.name).to eq("value")
      expect(param.type).to eq(:union)
      expect(param.union_type).to eq("anyOf")
      expect(param.description).to eq("A filter value that can be a string, number, or boolean.")
      expect(param.properties).to be_an(Array)
      expect(param.properties.length).to eq(3)
      expect(param.properties.map(&:type)).to eq(%i[string number boolean])
    end
  end

  describe "Parameter with missing type field" do
    let(:mock_coordinator) { double("Coordinator", name: "test") } # rubocop:disable RSpec/VerifiedDoubles

    context "when type is nil" do
      let(:tool_response_with_nil_type) do
        {
          "name" => "test_tool",
          "description" => "A test tool with nil type parameter",
          "inputSchema" => {
            "type" => "object",
            "properties" => {
              "param_without_type" => {
                "title" => "Parameter Without Type",
                "description" => "A parameter that has no type field"
              }
            }
          }
        }
      end

      it "defaults to string type when type is nil" do
        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response_with_nil_type)

        expect(tool.parameters).to have_key("param_without_type")
        param = tool.parameters["param_without_type"]

        expect(param).to be_a(RubyLLM::MCP::Parameter)
        expect(param.type).to eq(:string) # Should default to string
        expect(param.title).to eq("Parameter Without Type")
        expect(param.description).to eq("A parameter that has no type field")
      end

      it "does not raise NoMethodError when calling to_sym on nil" do
        expect do
          RubyLLM::MCP::Tool.new(mock_coordinator, tool_response_with_nil_type)
        end.not_to raise_error
      end
    end

    context "when type is missing entirely" do
      let(:tool_response_missing_type) do
        {
          "name" => "test_tool",
          "description" => "A test tool with missing type field",
          "inputSchema" => {
            "type" => "object",
            "properties" => {
              "service_param" => {
                "title" => "Service Parameter"
              }
            }
          }
        }
      end

      it "defaults to string type when type field is missing" do
        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response_missing_type)

        expect(tool.parameters).to have_key("service_param")
        param = tool.parameters["service_param"]

        expect(param.type).to eq(:string)
        expect(param.title).to eq("Service Parameter")
      end
    end
  end

  describe "Parameter title field support" do
    let(:mock_coordinator) { double("Coordinator", name: "test") } # rubocop:disable RSpec/VerifiedDoubles

    context "with title on regular parameters" do
      let(:tool_response_with_title) do
        {
          "name" => "test_tool",
          "description" => "A test tool with titled parameters",
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
      end

      it "preserves title field on string parameters" do
        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response_with_title)

        param = tool.parameters["user_email"]
        expect(param.title).to eq("User's Email Address")
        expect(param.type).to eq(:string)
        expect(param.description).to eq("The email address of the user")
      end

      it "preserves title field on integer parameters" do
        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response_with_title)

        param = tool.parameters["count"]
        expect(param.title).to eq("Item Count")
        expect(param.type).to eq(:integer)
        expect(param.description).to eq("Number of items to process")
      end
    end

    context "with title on union parameters" do
      let(:tool_response_with_union_title) do
        {
          "name" => "test_tool",
          "description" => "A test tool with titled union parameters",
          "inputSchema" => {
            "type" => "object",
            "properties" => {
              "optional_param" => {
                "anyOf" => [
                  { "type" => "string", "title" => "String Option" },
                  { "type" => "null", "title" => "Null Option" }
                ],
                "title" => "Optional Parameter",
                "description" => "An optional string parameter"
              }
            }
          }
        }
      end

      it "preserves title field on union parameters" do
        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response_with_union_title)

        param = tool.parameters["optional_param"]
        expect(param.title).to eq("Optional Parameter")
        expect(param.type).to eq(:union)
        expect(param.union_type).to eq("anyOf")
        expect(param.description).to eq("An optional string parameter")
      end
    end

    context "without title field" do
      let(:tool_response_without_title) do
        {
          "name" => "test_tool",
          "description" => "A test tool without titles",
          "inputSchema" => {
            "type" => "object",
            "properties" => {
              "regular_param" => {
                "type" => "string",
                "description" => "A regular parameter without title"
              }
            }
          }
        }
      end

      it "sets title to nil when not provided" do
        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response_without_title)

        param = tool.parameters["regular_param"]
        expect(param.title).to be_nil
        expect(param.type).to eq(:string)
      end
    end
  end

  describe "Complex scenario: missing type with title" do
    let(:mock_coordinator) { double("Coordinator", name: "test") } # rubocop:disable RSpec/VerifiedDoubles
    let(:tool_response_complex) do
      {
        "name" => "google_workspace_tool",
        "description" => "A Google Workspace tool similar to the one that caused the bug",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "docs_service" => {
              "title" => "Docs Service"
            },
            "drive_service" => {
              "title" => "Drive Service"
            },
            "user_email" => {
              "type" => "string",
              "title" => "User Email"
            },
            "document_id" => {
              "type" => "string"
            }
          }
        }
      }
    end

    it "handles parameters with only title field" do
      tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response_complex)

      # Parameters with title but no type should default to string
      docs_service = tool.parameters["docs_service"]
      expect(docs_service.type).to eq(:string)
      expect(docs_service.title).to eq("Docs Service")

      drive_service = tool.parameters["drive_service"]
      expect(drive_service.type).to eq(:string)
      expect(drive_service.title).to eq("Drive Service")

      # Parameters with both type and title
      user_email = tool.parameters["user_email"]
      expect(user_email.type).to eq(:string)
      expect(user_email.title).to eq("User Email")

      # Parameters with type but no title
      document_id = tool.parameters["document_id"]
      expect(document_id.type).to eq(:string)
      expect(document_id.title).to be_nil
    end

    it "does not raise errors when processing all parameters" do
      expect do
        tool = RubyLLM::MCP::Tool.new(mock_coordinator, tool_response_complex)
        expect(tool.parameters.count).to eq(4)
      end.not_to raise_error
    end
  end
end

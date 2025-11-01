# frozen_string_literal: true

RSpec.describe RubyLLM::Chat do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
    ClientRunner.start_all
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.stop_all
  end

  before do
    MCPTestConfiguration.configure_ruby_llm!
  end

  around do |example|
    cassette_name = example.full_description
                           .delete_prefix("RubyLLM::Chat ")
                           .gsub(" ", "_")
                           .gsub("/", "_")

    VCR.use_cassette(cassette_name) do
      example.run
    end
  end

  CLIENT_OPTIONS.each do |client_config|
    context "with #{client_config[:name]}" do
      let(:client) { ClientRunner.fetch_client(client_config[:name]) }

      COMPLEX_FUNCTION_MODELS.each do |config|
        context "with #{config[:provider]}/#{config[:model]}" do
          describe "with_tools" do
            it "adds tools to the chat" do
              chat = RubyLLM.chat(model: config[:model])
              chat.with_tools(*client.tools)

              response = chat.ask("Can you add 1 and 2?")
              expect(response.content).to include("3")
            end

            it "adds a select amount of tools" do
              chat = RubyLLM.chat(model: config[:model])
              weather_tools = client.tools.select { |tool| tool.name.include?("weather") }

              chat.with_tools(*weather_tools)

              response = chat.ask("Can you tell me the weather for Ottawa and San Francisco?")
              expect(response.content).to include("Ottawa")
              expect(response.content).to include("San Francisco")
              expect(response.content).to include("great")
            end
          end

          describe "with_tool" do
            it "adds a tool to the chat" do
              chat = RubyLLM.chat(model: config[:model])
              tool = client.tool("list_messages")
              chat.with_tool(tool)

              response = chat.ask("Can you pull messages for ruby channel and let me know what they say?")
              expect(response.content).to include("Ruby is a great language")
            end

            it "can you a complex tool" do
              chat = RubyLLM.chat(model: config[:model])
              tool = client.tool("fetch_site")
              chat.with_tool(tool)

              prompt = "Can you fetch the website https://www.example.com/ and see if the site say what they do?"
              response = chat.ask(prompt)
              expect(response.content.downcase).to include("documentation examples")
            end
          end

          describe "with_resources" do
            it "adds multiple resources to the chat" do
              chat = RubyLLM.chat(model: config[:model])
              text_resources = client.resources.select { |resource| resource.mime_type&.include?("text") }
              chat.with_resources(*text_resources)

              response = chat.ask("What information do you have from the provided resources?")
              expect(response.content).to include("test")
            end

            it "adds binary resources to the chat" do
              chat = RubyLLM.chat(model: config[:model])
              binary_resources = client.resources.select do |resource|
                resource.mime_type&.include?("image")
              end
              chat.with_resources(*binary_resources)

              response = chat.ask("What resources do you have access to?")
              expect(response.content).to match(/dog|jackhammer|image/i)
            end
          end

          describe "with_resource" do
            it "adds a single text resource to the chat" do
              chat = RubyLLM.chat(model: config[:model])
              resource = client.resource("test.txt")
              chat.with_resource(resource)

              response = chat.ask("What does the test file contain?")
              expect(response.content).to include("test")
            end

            it "adds a markdown resource to the chat" do
              chat = RubyLLM.chat(model: config[:model])
              resource = client.resource("my.md")
              chat.with_resource(resource)

              response = chat.ask("What does the markdown file say?")
              expect(response.content).to match(/markdown|header|content/i)
            end

            it "adds an image resource to the chat" do
              chat = RubyLLM.chat(model: config[:model])
              resource = client.resource("dog.png")
              chat.with_resource(resource)

              response = chat.ask("What image do you have?")
              expect(response.content).to match(/dog|image|picture|png/i)
            end
          end

          describe "with_resource_template" do
            it "adds resource templates to the chat and uses them" do
              chat = RubyLLM.chat(model: config[:model])
              template = client.resource_templates.first
              chat.with_resource_template(template, arguments: { name: "Alice" })

              response = chat.ask("Can you greet Alice using the greeting template?")
              expect(response.content).to include("Alice")
            end

            it "handles template arguments correctly" do
              chat = RubyLLM.chat(model: config[:model])
              template = client.resource_template("greeting")
              chat.with_resource_template(template, arguments: { name: "Bob" })

              response = chat.ask("Use the greeting template to say hello to Bob")
              expect(response.content).to include("Bob")
            end
          end

          describe "ask_prompt" do
            it "handles prompts when available" do
              chat = RubyLLM.chat(model: config[:model])
              prompts = client.prompts

              prompt = prompts.first
              response = chat.ask_prompt(prompt)
              expect(response.content.downcase).to include("hello")
            end

            it "get one prompts by name" do
              chat = RubyLLM.chat(model: config[:model])
              prompt = client.prompt("poem_of_the_day")
              response = chat.ask_prompt(prompt)
              expect(response.content).to include("poem")
            end

            it "handles prompts with arguments" do
              chat = RubyLLM.chat(model: config[:model])
              prompt = client.prompt("specific_language_greeting")
              response = chat.ask_prompt(prompt, arguments: { name: "John", language: "Spanish" })
              expect(response.content).to include("John")
            end
          end

          describe "with_prompt" do
            it "adds prompt to the chat when available" do
              chat = RubyLLM.chat(model: config[:model])
              prompts = client.prompts

              prompt = prompts.first
              chat.with_prompt(prompt)
              response = chat.ask("Please respond based on the prompt provided.")
              expect(response.content.downcase).to include("hello")
            end

            it "adds one prompt by name to the chat" do
              chat = RubyLLM.chat(model: config[:model])
              prompt = client.prompt("poem_of_the_day")
              chat.with_prompt(prompt)
              response = chat.ask("Please provide the content from the prompt.")
              expect(response.content).to include("poem")
            end

            it "adds prompt with arguments to the chat" do
              chat = RubyLLM.chat(model: config[:model])
              prompt = client.prompt("specific_language_greeting")
              chat.with_prompt(prompt, arguments: { name: "Alice", language: "French" })
              response = chat.ask("Please use the prompt to create a greeting.")
              expect(response.content).to include("Alice")
            end
          end

          describe "mixed parameter types" do
            it "handles both RubyLLM::Parameter and MCP::Parameter tools in same chat" do
              chat = RubyLLM.chat(model: config[:model])
              mcp_tool = client.tool("add")

              chat.with_tools(SimpleMultiplyTool, mcp_tool)
              response = chat.ask("Can you multiply 3 and 4, then add 5 and 7?")

              # Verify response includes results from both tools
              # 3 * 4 = 12, 5 + 7 = 12
              expect(response.content).to include("12")
            end
          end
        end
      end
    end
  end
end

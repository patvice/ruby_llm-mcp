# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Tool do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
    ClientRunner.start_all
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.stop_all
  end

  CLIENT_OPTIONS.select { |options| options[:name] == "stdio" }.each do |options|
    context "with #{options[:name]}" do
      let(:client) do
        ClientRunner.client_runners[options[:name]].client
      end

      it "returns the environment variable" do
        tool = client.tool("return_set_evn")
        result = tool.execute
        expect(result.to_s).to eq("Test Env = this_is_a_test")
      end
    end
  end

  CLIENT_OPTIONS.each do |options|
    context "with #{options[:name]}" do
      let(:client) do
        ClientRunner.client_runners[options[:name]].client
      end

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
          result = tool.execute(permission: "read")
          puts result.inspect

          client.resources

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

            Hello, this is a test file!
            This content will be served by the MCP resource.
            You can modify this file and it will be cached for 5 minutes.
          TODO

          expect(result.to_s).to eq(value)
        end

        it "handles tool errors gracefully" do
          error_tool = client.tool("tool_error")

          # Test when tool returns an error
          result = error_tool.execute(shouldError: true)
          expect(result).to eq({ error: "Error: Tool error" })
          expect(result.to_s).to include("Error: Tool error")

          # Test when tool doesn't return an error
          result = error_tool.execute(shouldError: false)
          expect(result).to be_a(RubyLLM::MCP::Content)
          expect(result.to_s).to eq("No error")
        end

        it "can call a complex union type tool" do
          tool = client.tool("fetch_site")
          result = tool.execute(website: "https://www.google.com")

          expect(result).to be_a(RubyLLM::MCP::Content)
          expect(result.to_s).to include("Google")

          result = tool.execute(website: { url: "https://www.google.com",
                                           headers: [{ name: "User-Agent", value: "test" }] })

          expect(result).to be_a(RubyLLM::MCP::Content)
          expect(result.to_s).to include("Google")
        end
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Resource do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
    ClientRunner.start_all
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.stop_all
  end

  context "with #{PAGINATION_CLIENT_CONFIG[:name]}" do
    let(:client) { RubyLLM::MCP::Client.new(**PAGINATION_CLIENT_CONFIG) }

    before do
      client.start
    end

    after do
      client.stop
    end

    describe "resource_list" do
      it "paginates resources list to get all resources" do
        resources = client.resources
        expect(resources.count).to eq(2)
      end
    end
  end

  CLIENT_OPTIONS.each do |config|
    context "with #{config[:name]}" do
      let(:client) { ClientRunner.fetch_client(config[:name]) }

      describe "resource_list" do
        it "returns a list of resources" do
          resources = client.resources
          expect(resources).to be_a(Array)
          expect(resources).not_to be_empty
          expect(resources.first).to be_a(RubyLLM::MCP::Resource)
        end

        it "can get a specific resource by name" do
          resource = client.resource("test.txt")
          expect(resource).to be_a(RubyLLM::MCP::Resource)
          expect(resource.name).to eq("test.txt")
          expect(resource.uri).to eq("file://test.txt/")
        end

        it "refreshes prompts when requested" do
          tool = client.tool("send_list_changed")
          resource_count = client.resources.count
          tool.execute(type: "resources")

          expect(client.resources.count).to eq(resource_count + 1)
        end
      end

      describe "resource_content" do
        it "retrieves content from a non-template resource" do
          resource = client.resource("test.txt")
          content = resource.content

          expect(content).to be_a(String)
          expect(content).not_to be_empty
        end

        it "handles different file types" do
          md_resource = client.resource("my.md")
          content = md_resource.content

          expect(content).to be_a(String)
          expect(content).not_to be_empty
        end
      end

      describe "to_content" do
        it "converts resource to MCP::Content" do
          resource = client.resource("test.txt")
          content = resource.to_content

          expect(content).to be_a(RubyLLM::MCP::Content)
          expect(content.text).not_to be_nil
        end
      end

      describe "resource_properties" do
        it "has correct properties for non-template resources" do
          resource = client.resource("test.txt")

          expect(resource.name).to eq("test.txt")
          expect(resource.uri).to eq("file://test.txt/")
        end
      end

      describe "error_handling" do
        it "handles invalid resource names gracefully" do
          resource = client.resource("nonexistent.txt")
          expect(resource).to be_nil
        end
      end

      describe "multiple_resources" do
        it "can retrieve content from multiple resources" do
          test_resource = client.resource("test.txt")
          second_resource = client.resource("second_file.txt")

          test_content = test_resource.content
          second_content = second_resource.content

          expect(test_content).to be_a(String)
          expect(second_content).to be_a(String)
          expect(test_content).not_to eq(second_content)
        end
      end

      describe "binary_content_resources" do
        it "can retrieve image resource content" do
          image_resource = client.resource("dog.png")

          expect(image_resource).to be_a(RubyLLM::MCP::Resource)
          expect(image_resource.name).to eq("dog.png")
          expect(image_resource.mime_type).to eq("image/png")

          content = image_resource.content
          expect(content).to be_a(String)
          expect(content).not_to be_empty
        end

        it "can retrieve audio resource content" do
          audio_resource = client.resource("jackhammer.wav")

          expect(audio_resource).to be_a(RubyLLM::MCP::Resource)
          expect(audio_resource.name).to eq("jackhammer.wav")
          expect(audio_resource.mime_type).to eq("audio/wav")

          content = audio_resource.content
          expect(content).to be_a(String)
          expect(content).not_to be_empty
        end

        it "converts image resource to MCP::Content with attachment" do
          image_resource = client.resource("dog.png")
          content = image_resource.to_content

          expect(content).to be_a(RubyLLM::MCP::Content)
          expect(content.attachments.first).to be_a(RubyLLM::MCP::Attachment)
          expect(content.attachments.first.mime_type).to eq("image/png")
          expect(content.attachments.first.content).not_to be_nil
          expect(content.text).to include("dog.png")
        end

        it "converts audio resource to MCP::Content with attachment" do
          audio_resource = client.resource("jackhammer.wav")
          content = audio_resource.to_content

          expect(content).to be_a(RubyLLM::MCP::Content)
          expect(content.attachments.first).to be_a(RubyLLM::MCP::Attachment)
          expect(content.attachments.first.mime_type).to eq("audio/wav")
          expect(content.attachments.first.content).not_to be_nil
          expect(content.text).to include("jackhammer.wav")
        end
      end

      describe "resource_subscription" do
        it "can subscribe to a resource and mark it as dirty if changed" do
          resource = client.resource("plain_text.txt")
          expect(resource.content).to eq("Plan text information")

          resource.subscribe!

          tool = client.tool("changes_plain_text_resource")
          tool.execute

          expect(resource.content).to eq("New text information")

          tool = client.tool("changes_plain_text_resource")
          tool.execute
        end
      end

      describe "refresh_functionality" do
        it "can refresh resource list" do
          resources1 = client.resources
          resources2 = client.resources(refresh: true)

          expect(resources1.size).to eq(resources2.size)
          expect(resources1.map(&:name)).to eq(resources2.map(&:name))
        end

        it "can refresh specific resource" do
          resource1 = client.resource("test.txt")
          resource2 = client.resource("test.txt", refresh: true)

          expect(resource1.name).to eq(resource2.name)
          expect(resource1.uri).to eq(resource2.uri)
        end
      end
    end
  end

  describe "Resource Links in Tool Results (2025-06-18)" do
    CLIENT_OPTIONS.each do |config|
      context "with #{config[:name]}" do
        let(:client) { ClientRunner.fetch_client(config[:name]) }

        it "creates resources from tool execution results" do
          tool = client.tool("create_report")
          expect(tool).to be_a(RubyLLM::MCP::Tool)

          result = tool.execute(
            title: "Test Report",
            content: "This is a test report with important data",
            format: "text"
          )

          expect(result).to be_a(RubyLLM::MCP::Content)
          expect(result.to_s).to include("Test Report")
          expect(result.to_s).to include("created successfully")

          # Check if resource content is included
          content_parts = result.instance_variable_get(:@content)
          if content_parts.is_a?(Array)
            resource_part = content_parts.find { |part| part["type"] == "resource" }
            if resource_part
              expect(resource_part["resource"]).to be_a(Hash)
              expect(resource_part["resource"]["name"]).to include("test_report")
              expect(resource_part["resource"]["text"]).to include("This is a test report")
            end
          end
        end

        it "creates JSON format resources" do
          tool = client.tool("create_report")

          result = tool.execute(
            title: "JSON Report",
            content: "Structured data analysis",
            format: "json"
          )

          expect(result).to be_a(RubyLLM::MCP::Content)
          expect(result.to_s).to include("JSON Report")
        end
      end
    end
  end
end

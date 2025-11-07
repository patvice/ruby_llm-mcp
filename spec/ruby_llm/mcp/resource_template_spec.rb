# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::ResourceTemplate do
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

    describe "resource_template_list" do
      it "paginates resource templates list to get all resource templates" do
        resource_templates = client.resource_templates
        expect(resource_templates.count).to eq(2)
      end
    end
  end

  each_client_supporting(:resource_templates) do
    describe "resource_template_list" do
      it "returns a list of resource templates" do
        templates = client.resource_templates
        expect(templates).to be_a(Array)
        expect(templates).not_to be_empty
        expect(templates.first).to be_a(RubyLLM::MCP::ResourceTemplate)
      end

      it "can get a specific resource template by name" do
        template = client.resource_template("greeting")
        expect(template).to be_a(RubyLLM::MCP::ResourceTemplate)
        expect(template.name).to eq("greeting")
      end
    end

    describe "initialization" do
      it "initializes with correct properties" do
        template = client.resource_template("greeting")

        expect(template.name).to eq("greeting")
        expect(template.uri).to include("greeting://")
      end

      it "handles templates with URI templates" do
        template = client.resource_template("greeting")

        expect(template.uri).to include("{name}")
        expect(template.uri).to match(%r{greeting://.*\{name\}})
      end
    end

    describe "template_content_retrieval" do
      it "retrieves content from template with arguments" do
        template = client.resource_template("greeting")
        content = template.to_content(arguments: { name: "Alice" })

        expect(content).to be_a(RubyLLM::MCP::Content)
        expect(content.to_s).to include("greeting (greeting://Alice): A greeting resource\n\nHello, Alice!")
      end

      it "retrieves content with different argument values" do
        template = client.resource_template("greeting")

        alice_content = template.to_content(arguments: { name: "Alice" })
        bob_content = template.to_content(arguments: { name: "Bob" })

        expect(alice_content.to_s).to include("Hello, Alice!")
        expect(bob_content.to_s).to include("Hello, Bob!")
        expect(alice_content).not_to eq(bob_content)
      end
    end

    describe "to_content_conversion" do
      it "converts template to MCP::Content with arguments" do
        template = client.resource_template("greeting")
        content = template.to_content(arguments: { name: "Bob" })

        expect(content).to be_a(RubyLLM::MCP::Content)
        expect(content.text).to include("Hello, Bob!")
      end

      it "handles different argument combinations" do
        template = client.resource_template("greeting")

        content1 = template.to_content(arguments: { name: "Charlie" })
        content2 = template.to_content(arguments: { name: "David" })

        expect(content1.text).to include("Charlie")
        expect(content2.text).to include("David")
        expect(content1.text).not_to eq(content2.text)
      end
    end

    describe "template_uri_processing" do
      it "processes URI templates correctly" do
        template = client.resource_template("greeting")
        original_uri = template.uri

        expect(original_uri).to include("{name}")
        expect(original_uri).to match(%r{greeting://.*\{name\}})
      end

      it "substitutes template variables in URI" do
        template = client.resource_template("greeting")

        # This tests the internal URI template processing
        # by checking that content retrieval works with different names
        content1 = template.to_content(arguments: { name: "Test1" })
        content2 = template.to_content(arguments: { name: "Test2" })

        expect(content1.to_s).to include("Test1")
        expect(content2.to_s).to include("Test2")
      end
    end

    describe "error_handling" do
      it "handles invalid template names gracefully" do
        template = client.resource_template("nonexistent_template")
        expect(template).to be_nil
      end

      it "handles malformed argument search gracefully" do
        template = client.resource_template("greeting")

        if client.capabilities.completion?
          expect do
            template.complete("invalid_argument", "value")
          end.not_to raise_error
        else
          expect do
            template.complete("name", "A")
          end.to raise_error(RubyLLM::MCP::Errors::CompletionNotAvailable)
        end
      end
    end

    describe "template_argument_handling" do
      it "handles string arguments" do
        template = client.resource_template("greeting")
        content = template.to_content(arguments: { "name" => "StringTest" })

        expect(content.to_s).to include("StringTest")
      end

      it "handles symbol keys in arguments" do
        template = client.resource_template("greeting")
        content = template.to_content(arguments: { name: "SymbolTest" })

        expect(content.to_s).to include("SymbolTest")
      end
    end
  end

  # Refresh functionality - only supported by native adapter
  each_client(adapter: :ruby_llm) do
    describe "refresh_functionality" do
      it "can refresh template list" do
        templates1 = client.resource_templates
        templates2 = client.resource_templates(refresh: true)

        expect(templates1.size).to eq(templates2.size)
        expect(templates1.map(&:name)).to eq(templates2.map(&:name))
      end

      it "can refresh specific template" do
        template1 = client.resource_template("greeting")
        template2 = client.resource_template("greeting", refresh: true)

        expect(template1.name).to eq(template2.name)
        expect(template1.uri).to eq(template2.uri)
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Completion do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.build_client_runners(CLIENT_OPTIONS)
    ClientRunner.start_all
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ClientRunner.stop_all
  end

  # Completion tests - only run on adapters that support completions
  each_client_supporting(:completions) do
    describe "resource_template_complete" do
      it "performs completion for template arguments if supported" do
        template = client.resource_template("greeting")

        completion = template.complete("name", "A")
        expect(completion).to be_a(RubyLLM::MCP::Completion)
        expect(completion.values).to be_a(Array)
        expect(completion.values).to include("Alice")
      end

      it "throws an error if completion is not supported" do
        template = client.resource_template("greeting")

        client.capabilities.capabilities.delete("completions")

        expect do
          template.complete("name", "A")
        end.to raise_error(RubyLLM::MCP::Errors::Capabilities::CompletionNotAvailable)

        client.capabilities.capabilities["completions"] = {}
      end

      it "returns filtered completion results" do
        template = client.resource_template("greeting")

        if client.capabilities.completion?
          completion = template.complete("name", "B")
          expect(completion.values).to include("Bob")
          expect(completion.values).not_to include("Alice")
        else
          skip "Completion not supported by this transport"
        end
      end

      it "returns all values when no filter provided" do
        template = client.resource_template("greeting")

        completion = template.complete("name", "")
        expect(completion.values).to include("Alice", "Bob", "Charlie")
      end

      it "has proper completion metadata" do
        template = client.resource_template("greeting")
        completion = template.complete("name", "A")

        expect(completion.total).to eq(2)
        expect(completion.values).to eq(%w[Alice Charlie])
        expect(completion.has_more).to be(false)
      end
    end

    describe "prompt_complete" do
      let(:languages) do
        %w[
          English
          Spanish
          French
          German
          Italian
          Portuguese
          Russian
          Chinese
          Japanese
          Korean
        ]
      end

      it "performs completion for prompt arguments if supported" do
        prompt = client.prompt("specific_language_greeting")
        completion = prompt.complete("language", "Korean")

        expect(completion).to be_a(RubyLLM::MCP::Completion)
        expect(completion.values).to be_a(Array)
        expect(completion.values).to include("Korean")
      end

      it "performs completion for prompt when argument is empty if supported" do
        prompt = client.prompt("specific_language_greeting")
        completion = prompt.complete("language", "")

        expect(completion).to be_a(RubyLLM::MCP::Completion)
        expect(completion.values).to be_a(Array)
        expect(completion.values).to eq(languages)
      end

      it "throws an error if completion is not supported" do
        prompt = client.prompt("specific_language_greeting")
        client.capabilities.capabilities.delete("completions")

        expect do
          prompt.complete("language", "Korean")
        end.to raise_error(RubyLLM::MCP::Errors::Capabilities::CompletionNotAvailable)

        client.capabilities.capabilities["completions"] = {}
      end
    end

    describe "Context in Completion Requests (2025-06-18)" do
      it "supports context-aware completions" do
        prompt = client.prompt("context_aware_search")
        expect(prompt).to be_a(RubyLLM::MCP::Prompt)

        # Test completion with context
        completion = prompt.complete(
          "domain",
          "proj",
          context: {
            "department" => "engineering",
            "user_role" => "developer"
          }
        )

        expect(completion).to be_a(RubyLLM::MCP::Completion)
        expect(completion.values).to be_an(Array)

        # Should include engineering-specific options
        expect(completion.values).to include("projects")
      end

      it "filters completion results based on context" do
        prompt = client.prompt("user_selector")
        expect(prompt).to be_a(RubyLLM::MCP::Prompt)

        completion = prompt.complete(
          "username_prefix",
          "a",
          context: {
            "department" => "engineering",
            "project" => "web_platform"
          }
        )

        expect(completion).to be_a(RubyLLM::MCP::Completion)
        expect(completion.values).to be_an(Array)
        expect(completion.values).to include("alice")
      end

      it "provides default completion when no context" do
        prompt = client.prompt("user_selector")

        completion = prompt.complete("username_prefix", "a")
        expect(completion).to be_a(RubyLLM::MCP::Completion)
        expect(completion.values).to be_an(Array)
        expect(completion.values).to include("alice")
        expect(completion.values).to include("admin")
      end
    end
  end
end

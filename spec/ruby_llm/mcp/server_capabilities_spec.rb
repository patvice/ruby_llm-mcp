# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::ServerCapabilities do
  describe "#initialize" do
    context "when no capabilities are provided" do
      let(:capabilities) { described_class.new }

      it "initializes with empty capabilities hash" do
        expect(capabilities.capabilities).to eq({})
      end
    end

    context "when capabilities are provided" do
      let(:capabilities_hash) { { "tools" => {}, "resources" => { "listChanged" => true } } }
      let(:capabilities) { described_class.new(capabilities_hash) }

      it "initializes with the provided capabilities" do
        expect(capabilities.capabilities).to eq(capabilities_hash)
      end
    end
  end

  describe "#resources_list?" do
    context "when resources capability is present" do
      let(:capabilities) { described_class.new("resources" => {}) }

      it "returns true" do
        expect(capabilities.resources_list?).to be true
      end
    end

    context "when resources capability is nil" do
      let(:capabilities) { described_class.new("resources" => nil) }

      it "returns false" do
        expect(capabilities.resources_list?).to be false
      end
    end

    context "when resources capability is missing" do
      let(:capabilities) { described_class.new({}) }

      it "returns false" do
        expect(capabilities.resources_list?).to be false
      end
    end
  end

  describe "#resources_list_changes?" do
    context "when resources listChanged is true" do
      let(:capabilities) { described_class.new("resources" => { "listChanged" => true }) }

      it "returns true" do
        expect(capabilities.resources_list_changes?).to be true
      end
    end

    context "when resources listChanged is false" do
      let(:capabilities) { described_class.new("resources" => { "listChanged" => false }) }

      it "returns false" do
        expect(capabilities.resources_list_changes?).to be false
      end
    end

    context "when resources exists but listChanged is missing" do
      let(:capabilities) { described_class.new("resources" => {}) }

      it "returns false" do
        expect(capabilities.resources_list_changes?).to be false
      end
    end

    context "when resources capability is missing" do
      let(:capabilities) { described_class.new({}) }

      it "returns false" do
        expect(capabilities.resources_list_changes?).to be false
      end
    end
  end

  describe "#resource_subscribe?" do
    context "when resources subscribe is true" do
      let(:capabilities) { described_class.new("resources" => { "subscribe" => true }) }

      it "returns true" do
        expect(capabilities.resource_subscribe?).to be true
      end
    end

    context "when resources subscribe is false" do
      let(:capabilities) { described_class.new("resources" => { "subscribe" => false }) }

      it "returns false" do
        expect(capabilities.resource_subscribe?).to be false
      end
    end

    context "when resources exists but subscribe is missing" do
      let(:capabilities) { described_class.new("resources" => {}) }

      it "returns false" do
        expect(capabilities.resource_subscribe?).to be false
      end
    end

    context "when resources capability is missing" do
      let(:capabilities) { described_class.new({}) }

      it "returns false" do
        expect(capabilities.resource_subscribe?).to be false
      end
    end
  end

  describe "#tools_list?" do
    context "when tools capability is present" do
      let(:capabilities) { described_class.new("tools" => {}) }

      it "returns true" do
        expect(capabilities.tools_list?).to be true
      end
    end

    context "when tools capability is nil" do
      let(:capabilities) { described_class.new("tools" => nil) }

      it "returns false" do
        expect(capabilities.tools_list?).to be false
      end
    end

    context "when tools capability is missing" do
      let(:capabilities) { described_class.new({}) }

      it "returns false" do
        expect(capabilities.tools_list?).to be false
      end
    end
  end

  describe "#tools_list_changes?" do
    context "when tools listChanged is true" do
      let(:capabilities) { described_class.new("tools" => { "listChanged" => true }) }

      it "returns true" do
        expect(capabilities.tools_list_changes?).to be true
      end
    end

    context "when tools listChanged is false" do
      let(:capabilities) { described_class.new("tools" => { "listChanged" => false }) }

      it "returns false" do
        expect(capabilities.tools_list_changes?).to be false
      end
    end

    context "when tools exists but listChanged is missing" do
      let(:capabilities) { described_class.new("tools" => {}) }

      it "returns false" do
        expect(capabilities.tools_list_changes?).to be false
      end
    end

    context "when tools capability is missing" do
      let(:capabilities) { described_class.new({}) }

      it "returns false" do
        expect(capabilities.tools_list_changes?).to be false
      end
    end
  end

  describe "#prompt_list?" do
    context "when prompts capability is present" do
      let(:capabilities) { described_class.new("prompts" => {}) }

      it "returns true" do
        expect(capabilities.prompt_list?).to be true
      end
    end

    context "when prompts capability is nil" do
      let(:capabilities) { described_class.new("prompts" => nil) }

      it "returns false" do
        expect(capabilities.prompt_list?).to be false
      end
    end

    context "when prompts capability is missing" do
      let(:capabilities) { described_class.new({}) }

      it "returns false" do
        expect(capabilities.prompt_list?).to be false
      end
    end
  end

  describe "#prompt_list_changes?" do
    context "when prompts listChanged is true" do
      let(:capabilities) { described_class.new("prompts" => { "listChanged" => true }) }

      it "returns true" do
        expect(capabilities.prompt_list_changes?).to be true
      end
    end

    context "when prompts listChanged is false" do
      let(:capabilities) { described_class.new("prompts" => { "listChanged" => false }) }

      it "returns false" do
        expect(capabilities.prompt_list_changes?).to be false
      end
    end

    context "when prompts exists but listChanged is missing" do
      let(:capabilities) { described_class.new("prompts" => {}) }

      it "returns false" do
        expect(capabilities.prompt_list_changes?).to be false
      end
    end

    context "when prompts capability is missing" do
      let(:capabilities) { described_class.new({}) }

      it "returns false" do
        expect(capabilities.prompt_list_changes?).to be false
      end
    end
  end

  describe "#completion?" do
    context "when completions capability is present" do
      let(:capabilities) { described_class.new("completions" => {}) }

      it "returns true" do
        expect(capabilities.completion?).to be true
      end
    end

    context "when completions capability is nil" do
      let(:capabilities) { described_class.new("completions" => nil) }

      it "returns false" do
        expect(capabilities.completion?).to be false
      end
    end

    context "when completions capability is missing" do
      let(:capabilities) { described_class.new({}) }

      it "returns false" do
        expect(capabilities.completion?).to be false
      end
    end
  end

  describe "#logging?" do
    context "when logging capability is present" do
      let(:capabilities) { described_class.new("logging" => {}) }

      it "returns true" do
        expect(capabilities.logging?).to be true
      end
    end

    context "when logging capability is nil" do
      let(:capabilities) { described_class.new("logging" => nil) }

      it "returns false" do
        expect(capabilities.logging?).to be false
      end
    end

    context "when logging capability is missing" do
      let(:capabilities) { described_class.new({}) }

      it "returns false" do
        expect(capabilities.logging?).to be false
      end
    end
  end

  describe "integration scenarios" do
    context "with complex capabilities hash" do
      let(:complex_capabilities) do
        {
          "resources" => {
            "listChanged" => true,
            "subscribe" => false
          },
          "tools" => {
            "listChanged" => false
          },
          "prompts" => {
            "listChanged" => true
          },
          "completions" => {},
          "logging" => {}
        }
      end

      let(:capabilities) { described_class.new(complex_capabilities) }

      it "correctly identifies all capabilities" do # rubocop:disable RSpec/MultipleExpectations
        expect(capabilities.resources_list?).to be true
        expect(capabilities.resources_list_changes?).to be true
        expect(capabilities.resource_subscribe?).to be false
        expect(capabilities.tools_list?).to be true
        expect(capabilities.tools_list_changes?).to be false
        expect(capabilities.prompt_list?).to be true
        expect(capabilities.prompt_list_changes?).to be true
        expect(capabilities.completion?).to be true
        expect(capabilities.logging?).to be true
      end
    end

    context "with minimal capabilities" do
      let(:capabilities) { described_class.new("tools" => {}) }

      it "returns false for missing capabilities" do
        expect(capabilities.tools_list?).to be true
        expect(capabilities.resources_list?).to be false
        expect(capabilities.prompt_list?).to be false
        expect(capabilities.completion?).to be false
        expect(capabilities.logging?).to be false
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Parameter do
  describe "#item_type" do
    context "when @items is nil" do
      it "returns nil" do
        parameter = described_class.new("test_param", type: "string")
        expect(parameter.item_type).to be_nil
      end
    end

    context "when @items is empty hash" do
      it "returns nil" do
        parameter = described_class.new("test_param", type: "string")
        parameter.items = {}
        expect(parameter.item_type).to be_nil
      end
    end

    context "when @items['type'] is nil" do
      it "returns nil" do
        parameter = described_class.new("test_param", type: "string")
        parameter.items = { "other_key" => "value" }
        expect(parameter.item_type).to be_nil
      end
    end

    context "when @items['type'] has a value" do
      it "returns the type as a symbol" do
        parameter = described_class.new("test_param", type: "array")
        parameter.items = { "type" => "string" }
        expect(parameter.item_type).to eq(:string)
      end
    end
  end

  describe "#initialize" do
    it "creates a parameter with default values" do
      parameter = described_class.new("test_param")
      expect(parameter.name).to eq("test_param")
      expect(parameter.type).to eq(:string)
      expect(parameter.required).to be(true)
      expect(parameter.items).to be_nil
    end

    it "creates a parameter with custom values" do
      parameter = described_class.new("test_param", type: "array", desc: "Test description", required: false)
      expect(parameter.name).to eq("test_param")
      expect(parameter.type).to eq(:array)
      expect(parameter.desc).to eq("Test description")
      expect(parameter.required).to be(false)
    end
  end
end
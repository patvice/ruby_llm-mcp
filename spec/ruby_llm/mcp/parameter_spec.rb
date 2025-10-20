# frozen_string_literal: true

RSpec.describe RubyLLM::MCP::Parameter do
  describe "#item_type" do
    it "when @items is nil will return nil" do
      parameter = described_class.new("test_param", type: "string")
      expect(parameter.item_type).to be_nil
    end

    it "when @items is empty hash it will returns nil" do
      parameter = described_class.new("test_param", type: "string")
      parameter.items = {}
      expect(parameter.item_type).to be_nil
    end

    it "when @items['type'] is nil it will return nil" do
      parameter = described_class.new("test_param", type: "string")
      parameter.items = { "other_key" => "value" }
      expect(parameter.item_type).to be_nil
    end

    it "when type is an array and item is not defined it will return nill" do
      parameter = described_class.new("test_param", type: "array")
      expect(parameter.item_type).to be_nil
    end

    it "when @items['type'] has a value it will returns the type as a symbol" do
      parameter = described_class.new("test_param", type: "array")
      parameter.items = { "type" => "string" }
      expect(parameter.item_type).to eq("string")
    end
  end

  describe "#initialize" do
    it "creates a parameter with default values" do
      parameter = described_class.new("test_param")
      expect(parameter.name).to eq("test_param")
      expect(parameter.type).to eq("string")
      expect(parameter.required).to be(true)
      expect(parameter.items).to be_nil
    end

    it "creates a parameter with custom values" do
      parameter = described_class.new("test_param", type: "array", desc: "Test description", required: false)
      expect(parameter.name).to eq("test_param")
      expect(parameter.type).to eq("array")
      expect(parameter.description).to eq("Test description")
      expect(parameter.required).to be(false)
    end
  end
end

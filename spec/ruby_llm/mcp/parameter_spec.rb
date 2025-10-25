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
      expect(parameter.item_type).to eq(:string)
    end
  end

  describe "#initialize" do
    it "creates a parameter with default values" do
      parameter = described_class.new("test_param")
      expect(parameter.name).to eq("test_param")
      expect(parameter.type).to eq(:string)
      expect(parameter.required).to be(true)
      expect(parameter.items).to be_nil
      expect(parameter.title).to be_nil
    end

    it "creates a parameter with custom values" do
      parameter = described_class.new("test_param", type: "array", desc: "Test description", required: false)
      expect(parameter.name).to eq("test_param")
      expect(parameter.type).to eq(:array)
      expect(parameter.description).to eq("Test description")
      expect(parameter.required).to be(false)
    end

    it "creates a parameter with title" do
      parameter = described_class.new("test_param", type: "string", title: "Test Parameter Title")
      expect(parameter.name).to eq("test_param")
      expect(parameter.title).to eq("Test Parameter Title")
      expect(parameter.type).to eq(:string)
    end

    it "handles nil title gracefully" do
      parameter = described_class.new("test_param", type: "string", title: nil)
      expect(parameter.title).to be_nil
    end

    it "handles shorthand anyOf with array of types" do
      parameter = described_class.new("value", type: "union", union_type: "anyOf")
      parameter.properties = [
        described_class.new("value", type: "string", desc: "A filter value that can be a string, number, or boolean."),
        described_class.new("value", type: "number", desc: "A filter value that can be a string, number, or boolean."),
        described_class.new("value", type: "boolean", desc: "A filter value that can be a string, number, or boolean."),
        described_class.new("value", type: "array", desc: "The value or list of values for filtering.")
      ]

      expect(parameter.name).to eq("value")
      expect(parameter.type).to eq(:union)
      expect(parameter.union_type).to eq("anyOf")
      expect(parameter.properties.length).to eq(4)
      expect(parameter.properties.map(&:type)).to eq(%i[string number boolean array])
    end

    it "handles shorthand anyOf with string and null types" do
      parameter = described_class.new("nullable_string", type: "union", union_type: "anyOf")
      parameter.properties = [
        described_class.new("nullable_string", type: "string", desc: "A string value"),
        described_class.new("nullable_string", type: "null", desc: "Null value")
      ]

      expect(parameter.name).to eq("nullable_string")
      expect(parameter.type).to eq(:union)
      expect(parameter.union_type).to eq("anyOf")
      expect(parameter.properties.length).to eq(2)
      expect(parameter.properties.map(&:type)).to eq(%i[string null])
    end
  end
end

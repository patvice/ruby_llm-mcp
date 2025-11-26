# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Handlers::Concerns::Options do
  let(:test_handler_class) do
    Class.new do
      include RubyLLM::MCP::Handlers::Concerns::Options

      option :test_option, default: "default_value"
      option :required_option, required: true
      option :dynamic_option, default: -> { "dynamic_#{Time.now.to_i}" }
    end
  end

  describe ".option" do
    it "defines an option with default value" do
      handler = test_handler_class.new(required_option: "req")
      expect(handler.test_option).to eq("default_value")
    end

    it "allows overriding default value" do
      handler = test_handler_class.new(
        test_option: "custom",
        required_option: "req"
      )
      expect(handler.test_option).to eq("custom")
    end

    it "evaluates proc defaults at initialization" do
      handler1 = test_handler_class.new(required_option: "req")
      sleep 1.1
      handler2 = test_handler_class.new(required_option: "req")

      expect(handler1.dynamic_option).not_to eq(handler2.dynamic_option)
    end

    it "raises error when required option is missing" do
      expect do
        test_handler_class.new
      end.to raise_error(ArgumentError, /Required option 'required_option'/)
    end

    it "allows additional options not defined in config" do
      handler = test_handler_class.new(
        required_option: "req",
        extra_option: "extra"
      )
      expect(handler.options[:extra_option]).to eq("extra")
    end
  end

  describe "inheritance" do
    it "inherits options from parent class" do
      child_class = Class.new(test_handler_class) do
        option :child_option, default: "child_value"
      end

      handler = child_class.new(required_option: "req")
      expect(handler.test_option).to eq("default_value")
      expect(handler.child_option).to eq("child_value")
    end
  end
end

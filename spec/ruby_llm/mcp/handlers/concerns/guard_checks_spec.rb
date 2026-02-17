# frozen_string_literal: true

require "spec_helper"

# rubocop:disable Naming/PredicateMethod
RSpec.describe RubyLLM::MCP::Handlers::Concerns::GuardChecks do
  let(:base_handler_class) do
    Class.new do
      include RubyLLM::MCP::Handlers::Concerns::Lifecycle
      include RubyLLM::MCP::Handlers::Concerns::GuardChecks

      def execute
        "success"
      end
    end
  end

  describe ".guard" do
    it "registers guard methods" do
      handler_class = Class.new(base_handler_class) do
        guard :check_something
        guard :check_another

        def check_something
          true
        end

        def check_another
          true
        end
      end

      expect(handler_class.guards).to eq(%i[check_something check_another])
    end

    it "executes guards before execute" do
      guard_called = false

      handler_class = Class.new(base_handler_class) do
        guard :check_it

        define_method(:check_it) do
          guard_called = true
          true
        end
      end

      handler = handler_class.new
      handler.call

      expect(guard_called).to be true
    end

    it "calls guard_failed if guard returns false" do
      handler_class = Class.new(base_handler_class) do
        guard :failing_guard

        def failing_guard
          false
        end

        def guard_failed(message)
          "guard failed: #{message}"
        end
      end

      handler = handler_class.new
      result = handler.call

      expect(result).to include("guard failed")
    end

    it "passes string message from guard to guard_failed" do
      handler_class = Class.new(base_handler_class) do
        guard :custom_message_guard

        def custom_message_guard
          "Custom failure reason"
        end

        def guard_failed(message)
          "failed: #{message}"
        end
      end

      handler = handler_class.new
      result = handler.call

      expect(result).to eq("failed: Custom failure reason")
    end

    it "allows execution if all guards pass" do
      handler_class = Class.new(base_handler_class) do
        guard :passing_guard

        def passing_guard
          true
        end
      end

      handler = handler_class.new
      result = handler.call

      expect(result).to eq("success")
    end

    it "treats nil guard result as passing" do
      handler_class = Class.new(base_handler_class) do
        guard :nil_guard

        def nil_guard
          nil
        end
      end

      handler = handler_class.new
      result = handler.call

      expect(result).to eq("success")
    end
  end

  describe "inheritance" do
    it "inherits guards from parent class" do
      parent_class = Class.new(base_handler_class) do
        guard :parent_guard

        def parent_guard
          true
        end
      end

      child_class = Class.new(parent_class) do
        guard :child_guard

        def child_guard
          true
        end
      end

      expect(child_class.guards).to eq(%i[parent_guard child_guard])
    end
  end
end
# rubocop:enable Naming/PredicateMethod

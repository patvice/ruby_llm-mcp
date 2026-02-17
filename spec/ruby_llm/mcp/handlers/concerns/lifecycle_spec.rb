# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLLM::MCP::Handlers::Concerns::Lifecycle do
  let(:test_handler_class) do
    Class.new do
      include RubyLLM::MCP::Handlers::Concerns::Lifecycle

      before_execute :before_hook
      after_execute :after_hook

      attr_reader :before_called, :after_called, :execute_called

      def execute
        @execute_called = true
        "result"
      end

      def before_hook
        @before_called = true
      end

      def after_hook(result)
        @after_called = result
      end
    end
  end

  describe ".before_execute and .after_execute" do
    it "executes hooks in correct order" do
      handler = test_handler_class.new
      result = handler.call

      expect(handler.before_called).to be true
      expect(handler.execute_called).to be true
      expect(handler.after_called).to eq("result")
      expect(result).to eq("result")
    end

    it "supports block-based hooks" do
      handler_class = Class.new do
        include RubyLLM::MCP::Handlers::Concerns::Lifecycle

        before_execute { @before_block = true }
        after_execute { |result| @after_block = result }

        attr_reader :before_block, :after_block

        def execute
          "block_result"
        end
      end

      handler = handler_class.new
      handler.call

      expect(handler.before_block).to be true
      expect(handler.after_block).to eq("block_result")
    end

    it "supports multiple hooks" do
      handler_class = Class.new do
        include RubyLLM::MCP::Handlers::Concerns::Lifecycle

        before_execute { @hook1 = true }
        before_execute { @hook2 = true }

        attr_reader :hook1, :hook2

        def execute
          "result"
        end
      end

      handler = handler_class.new
      handler.call

      expect(handler.hook1).to be true
      expect(handler.hook2).to be true
    end
  end

  describe "inheritance" do
    it "inherits hooks from parent class" do
      child_class = Class.new(test_handler_class) do
        before_execute { @child_before = true }

        attr_reader :child_before

        def execute
          "child_result"
        end
      end

      handler = child_class.new
      handler.call

      expect(handler.before_called).to be true
      expect(handler.child_before).to be true
    end
  end

  describe "#execute" do
    it "raises NotImplementedError when not overridden" do
      handler_class = Class.new do
        include RubyLLM::MCP::Handlers::Concerns::Lifecycle
      end

      handler = handler_class.new
      expect { handler.call }.to raise_error(NotImplementedError, /must implement #execute/)
    end
  end
end

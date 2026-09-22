# frozen_string_literal: true

# Simple test tool class using the base RubyLLM::Tool parameter DSL
class SimpleMultiplyTool < RubyLLM::Tool
  description "Multiply two numbers together"

  parameter :x, type: :number, description: "First number", required: true
  parameter :y, type: :number, description: "Second number", required: true

  def execute(x:, y:) # rubocop:disable Naming/MethodParameterName
    (x * y).to_s
  end
end

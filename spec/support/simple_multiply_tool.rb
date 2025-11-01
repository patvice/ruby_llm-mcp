# frozen_string_literal: true

# Simple test tool class using base RubyLLM::Parameter
class SimpleMultiplyTool < RubyLLM::Tool
  description "Multiply two numbers together"

  param :x, type: :number, desc: "First number", required: true
  param :y, type: :number, desc: "Second number", required: true

  def execute(x:, y:) # rubocop:disable Naming/MethodParameterName
    (x * y).to_s
  end
end

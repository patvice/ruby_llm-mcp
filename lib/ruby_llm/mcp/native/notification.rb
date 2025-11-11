# frozen_string_literal: true

module RubyLLM
  module MCP
    module Native
      class Notification
        attr_reader :type, :params

        def initialize(response)
          @type = response["method"]
          @params = response["params"]
        end
      end
    end
  end
end

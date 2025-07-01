# frozen_string_literal: true

module RubyLLM
  module MCP
    module Requests
      module Shared
        module Pagination
          def merge_pagination(body)
            body[:params] ||= {}
            body[:params].merge!({ cursor: @cursor }) if @cursor
            body
          end
        end
      end
    end
  end
end

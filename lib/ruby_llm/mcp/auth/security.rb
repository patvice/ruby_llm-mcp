# frozen_string_literal: true

module RubyLLM
  module MCP
    module Auth
      # Security utilities for OAuth implementation
      module Security
        module_function

        # Constant-time string comparison to prevent timing attacks
        # @param a [String] first string
        # @param b [String] second string
        # @return [Boolean] true if strings are equal
        def secure_compare(first, second)
          # Handle nil values
          return false if first.nil? || second.nil?

          # Use Rails/ActiveSupport's secure_compare if available (more battle-tested)
          if defined?(ActiveSupport::SecurityUtils) && ActiveSupport::SecurityUtils.respond_to?(:secure_compare)
            return ActiveSupport::SecurityUtils.secure_compare(first, second)
          end

          # Fallback to our own implementation
          constant_time_compare?(first, second)
        end

        # Constant-time comparison implementation
        # @param a [String] first string
        # @param b [String] second string
        # @return [Boolean] true if strings are equal
        def constant_time_compare?(first, second)
          return false unless first.bytesize == second.bytesize

          l = first.unpack("C*")
          r = 0
          i = -1

          second.each_byte { |v| r |= v ^ l[i += 1] }
          r.zero?
        end
      end
    end
  end
end

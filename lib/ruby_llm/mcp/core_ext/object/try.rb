# frozen_string_literal: true

# Ported from activesupport/lib/active_support/core_ext/object/try.rb
class Object
  def try(method_name, *args, &block)
    public_send(method_name, *args, &block) if respond_to?(method_name)
  end unless method_defined?(:try)
end

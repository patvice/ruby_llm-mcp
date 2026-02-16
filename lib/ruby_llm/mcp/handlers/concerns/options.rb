# frozen_string_literal: true

module RubyLLM
  module MCP
    module Handlers
      module Concerns
        # Provides option management with defaults and validation
        module Options
          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods
            # Define a handler option with optional default value
            # @param name [Symbol] the option name
            # @param default [Object] default value if not provided
            # @param required [Boolean] whether the option is required
            def option(name, default: nil, required: false)
              options_config[name] = { default: default, required: required }

              # Create accessor for this option in instances
              define_method(name) do
                @options[name]
              end
            end

            # Store option configurations
            def options_config
              @options_config ||= {}
            end

            # Inherit options from parent classes
            def inherited(subclass)
              super
              subclass.instance_variable_set(:@options_config, options_config.dup)
            end
          end

          attr_reader :options

          # Initialize with options
          # @param options [Hash] handler-specific options
          def initialize(**options)
            @options = build_options(options)
            validate_required_options!
            super() if defined?(super)
          end

          protected

          # Build final options hash with defaults
          def build_options(provided_options)
            final_options = {}

            self.class.options_config.each do |name, config|
              if provided_options.key?(name)
                final_options[name] = provided_options[name]
              elsif config.key?(:default)
                final_options[name] = config[:default].is_a?(Proc) ? config[:default].call : config[:default]
              end
            end

            # Include any additional options not defined in config
            provided_options.each do |name, value|
              final_options[name] = value unless final_options.key?(name)
            end

            final_options
          end

          # Validate that required options are present
          def validate_required_options!
            self.class.options_config.each do |name, config|
              if config[:required] && (!@options.key?(name) || @options[name].nil?)
                raise ArgumentError, "Required option '#{name}' not provided for #{self.class.name}"
              end
            end
          end
        end
      end
    end
  end
end



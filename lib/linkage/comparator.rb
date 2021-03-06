module Linkage
  # @abstract Abstract class to represent record comparators.
  class Comparator
    # Register a new comparator.
    #
    # @param [Class] klass Comparator subclass
    def self.register(klass)
      name = nil
      begin
        name = klass.comparator_name
      rescue NotImplementedError
        raise ArgumentError, "comparator_name class method must be defined"
      end

      if !klass.instance_methods(false).include?(:score)
        raise ArgumentError, "class must define the score method"
      end

      begin
        if klass.parameters.length > 0
          @comparators ||= {}
          @comparators[name] = klass
        else
          raise ArgumentError, "class must have at least one parameter"
        end
      rescue NotImplementedError
        raise ArgumentError, "parameters class method must be defined"
      end
    end

    def self.[](name)
      @comparators ? @comparators[name] : nil
    end

    # @abstract Override this to return the name of the comparator.
    # @return [String]
    def self.comparator_name
      raise NotImplementedError
    end

    # @abstract Override this to require a specific number of arguments of a
    #   certain class. To require two parameters of either String or Integer,
    #   do something like this:
    #
    #     @@parameters = [[String, Integer], [String, Integer]]
    #     def self.parameters
    #       @@parameters
    #     end
    #
    #   At least one argument must be defined.
    # @return [Array]
    def self.parameters
      raise NotImplementedError
    end

    attr_reader :args, :lhs_args, :rhs_args

    # Create a new Comparator object.
    # @param [Linkage::MetaObject, Hash] args Comparator arguments
    def initialize(*args)
      @args = args
      @lhs_args = []
      @rhs_args = []
      @options = args.last.is_a?(Hash) ? args.pop : {}
      process_args
    end

    # @abstract Override this to return the score of the linkage strength of
    #   two records.
    # @return [Numeric]
    def score(record_1, record_2)
      raise NotImplementedError
    end

    private

    def process_args
      parameters = self.class.parameters
      if parameters.length != @args.length
        raise ArgumentError, "wrong number of arguments (#{@args.length} for #{parameters.length})"
      end

      first_side = nil
      second_side = nil
      @args.each_with_index do |arg, i|
        type = arg.ruby_type[:type]

        parameter_types = parameters[i]
        if parameter_types.last.is_a?(Hash)
          parameter_options = parameter_types[-1]
          parameter_types = parameter_types[0..-2]
        else
          parameter_options = {}
        end

        if parameter_types[0] != :any && !parameter_types.include?(type)
          raise TypeError, "expected type #{parameters[i].join(" or ")}, got #{type}"
        end

        if parameter_options.has_key?(:values) && arg.raw? && !parameter_options[:values].include?(arg.object)
          raise ArgumentError, "argument #{i + 1} (#{arg.object.inspect}) was not one of the expected values: #{parameter_options[:values].inspect}"
        end

        if parameter_options.has_key?(:same_type_as)
          arg_index = parameter_options[:same_type_as]
          other_type = @args[arg_index].ruby_type[:type]
          if type != other_type
            raise TypeError, "argument #{i + 1} (#{type}) was expected to have the same type as argument #{arg_index + 1} (#{other_type})"
          end
        end

        if parameter_options.has_key?(:static) &&
              parameter_options[:static] != arg.static?
          raise TypeError, "argument #{i + 1} was expected to #{arg.static? ? "not be" : "be"} static"
        end

        if !arg.static?
          if first_side.nil?
            first_side = arg.side
          elsif arg.side != first_side && second_side.nil?
            second_side = arg.side
          end

          valid_side = true
          case parameter_options[:side]
          when :first
            if arg.side != first_side
              valid_side = false
            end
          when :second
            if second_side.nil? || arg.side != second_side
              valid_side = false
            end
          end

          if !valid_side
            raise TypeError, "argument #{i + 1} was expected to have a different side value"
          end

          case arg.side
          when :lhs
            @lhs_args << arg
          when :rhs
            @rhs_args << arg
          end
        end
      end
    end
  end
end

path = File.expand_path(File.join(File.dirname(__FILE__), "comparators"))
require File.join(path, "compare")
require File.join(path, "within")
require File.join(path, "strcompare")

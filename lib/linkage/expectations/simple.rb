module Linkage
  module Expectations
    class Simple < Expectation
      # The dataset this expectation applies to: `:lhs` or `:rhs`. This
      # only applies to filter expectations.
      # @return [Symbol]
      attr_reader :side

      attr_reader :meta_object_1, :meta_object_2, :operator

      VALID_OPERATORS = [:==, :'!=', :>, :<, :>=, :<=]

      # Automatically create an expectation type depending on the arguments.
      #
      # @param [Linkage::MetaObject] meta_object_1
      # @param [Linkage::MetaObject] meta_object_2
      # @param [Symbol] operator Valid operators: `:==`, `:'!='`, `:>`, `:<`, `:>=`, `:<=`
      def self.create(meta_object_1, meta_object_2, operator)
        klass =
          if meta_object_1.static? && meta_object_2.static?
            raise ArgumentError, "An expectation with two static objects is invalid"
          elsif meta_object_1.static? || meta_object_2.static?
            Filter
          elsif meta_object_1.side == meta_object_2.side
            if !meta_object_1.datasets_equal?(meta_object_2)
              raise ArgumentError, "An expectation with two dynamic objects with the same side but different datasets is invalid"
            end
            Filter
          elsif meta_object_1.objects_equal?(meta_object_2)
            Self
          elsif meta_object_1.datasets_equal?(meta_object_2)
            Cross
          else
            Dual
          end

        klass.new(meta_object_1, meta_object_2, operator)
      end

      # Creates a new Simple.
      #
      # @param [Linkage::MetaObject] meta_object_1
      # @param [Linkage::MetaObject] meta_object_2
      # @param [Symbol] operator Valid operators: `:==`, `:'!='`, `:>`, `:<`, `:>=`, `:<=`
      def initialize(meta_object_1, meta_object_2, operator)
        @meta_object_1 = meta_object_1
        @meta_object_2 = meta_object_2
        @operator = operator

        if !VALID_OPERATORS.include?(operator)
          raise ArgumentError, "Invalid operator: #{operator.inspect}"
        end

        after_initialize
      end

      def same_except_side?(other)
        other.is_a?(Simple) &&
          operator == other.operator &&
          meta_object_1.objects_equal?(other.meta_object_1) &&
          meta_object_2.objects_equal?(other.meta_object_2)
      end

      def exactly!
        function_1 = Function['binary'].new(@meta_object_1.object, :dataset => @meta_object_1.dataset)
        function_2 = Function['binary'].new(@meta_object_2.object, :dataset => @meta_object_2.dataset)
        @meta_object_1 = MetaObject.new(function_1, @meta_object_1.side)
        @meta_object_2 = MetaObject.new(function_2, @meta_object_2.side)
      end

      # Display any warnings about this expectation.
      def display_warnings
      end

      def decollation_needed?
        merged_field.ruby_type[:type] == String && (
          @meta_object_1.collation != @meta_object_2.collation ||
          @meta_object_1.database_type != @meta_object_2.database_type
        )
      end

      protected

      def after_initialize
      end
    end

    class Filter < Simple
      def kind; :filter; end

      def to_expr
        case @operator
        when :==, :'!='
          expr = { @meta_object_1.to_expr => @meta_object_2.to_expr }
          @operator == :== ? expr : ~expr
        else
          Sequel::SQL::BooleanExpression.new(@operator,
            @meta_object_1.to_identifier, @meta_object_2.to_identifier)
        end
      end

      def apply_to(dataset, side)
        if side != @side
          return dataset
        end

        dataset.filter(self.to_expr)
      end

      def decollation_needed?
        false
      end

      private

      def after_initialize
        super
        @side = @meta_object_1.static? ? @meta_object_2.side : @meta_object_1.side
      end
    end

    class Match < Simple
      def apply_to(dataset, side)
        target =
          if @meta_object_1.side == side
            @meta_object_1
          elsif @meta_object_2.side == side
            @meta_object_2
          else
            raise ArgumentError, "Invalid `side` argument: #{side}"
          end

        dataset.group_match_more({
          :meta_object => target,
          :alias => merged_field.name
        })
      end

      def merged_field
        @merged_field ||= @meta_object_1.merge(@meta_object_2)
      end

      def display_warnings
        object_1 = @meta_object_1.object
        object_2 = @meta_object_2.object
        if object_1.ruby_type[:type] == String && object_2.ruby_type[:type] == String
          if @meta_object_1.dataset.database_type != @meta_object_2.dataset.database_type
            warn "NOTE: You are comparing two string fields (#{object_1.name} and #{object_2.name}) from different databases. This may result in unexpected results, as different databases compare strings differently. Consider using the =binary= function."
          elsif object_1.respond_to?(:collation) && object_1.respond_to?(:collation) && object_1.collation != object_2.collation
            warn "NOTE: The two string fields you are comparing (#{object_1.name} and #{object_2.name}) have different collations (#{ldata.collation} vs. #{rdata.collation}). This may result in unexpected results, as the database may compare them differently. Consider using the =exactly= method."
          end
        end
      end
    end

    class Self < Match
      def kind; :self; end
    end

    class Cross < Match
      def kind; :cross; end
    end

    class Dual < Match
      def kind; :dual; end
    end
  end
end

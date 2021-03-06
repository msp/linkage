module Linkage
  class Configuration
    class DSL
      # Class for visually comparing matched records
      class VisualComparisonWrapper
        attr_reader :dsl, :lhs, :rhs

        def initialize(dsl, lhs, rhs)
          @dsl = dsl
          @lhs = lhs
          @rhs = rhs

          if @lhs.is_a?(DataWrapper) && @rhs.is_a?(DataWrapper)
            if @lhs.side == @rhs.side
              raise ArgumentError, "Can't visually compare two data sources on the same side"
            end
          else
            raise ArgumentError, "Must supply two data sources for visual comparison"
          end

          @dsl.add_visual_comparison(self)
        end
      end

      class ExpectationWrapper
        VALID_OPERATORS = [:==, :>, :<, :>=, :<=]
        OPERATOR_OPPOSITES = {
          :==   => :'!=',
          :>    => :<=,
          :<=   => :>,
          :<    => :>=,
          :>=   => :<
        }

        def initialize(dsl, type, lhs, *args)
          @dsl = dsl
          @type = type
          @lhs = lhs
        end

        def compare_with(operator, rhs)
          # NOTE: lhs is always a DataWrapper

          if !rhs.is_a?(DataWrapper) || @lhs.static? || rhs.static? || @lhs.side == rhs.side
            @side = !@lhs.static? ? @lhs.side : rhs.side

            # If one of the objects in this comparison is a static function, we need to set the side
            # and the dataset based on the other object
            if rhs.is_a?(DataWrapper) && !rhs.static? && @lhs.is_a?(FunctionWrapper) && @lhs.static?
              @lhs.dataset = rhs.dataset
              @lhs.side = @side
            elsif @lhs.is_a?(DataWrapper) && !@lhs.static? && rhs.is_a?(FunctionWrapper) && rhs.static?
              rhs.dataset = @lhs.dataset
              rhs.side = @side
            end
          elsif rhs.is_a?(DataWrapper) && operator != :==
            # create an exhaustive expectation with the Compare comparator instead
            comparator = Comparators::Compare.new(@lhs.meta_object,
              MetaObject.new(operator.to_s), rhs.meta_object)

            threshold = @type == :must ? 1 : 0

            expectation = Expectations::Exhaustive.new(comparator, threshold, :equal)
            @dsl.add_exhaustive_expectation(expectation)
            return self
          end

          exp_operator = @type == :must_not ? OPERATOR_OPPOSITES[operator] : operator

          rhs_meta_object = rhs.is_a?(DataWrapper) ? rhs.meta_object : MetaObject.new(rhs)
          @expectation = Expectations::Simple.create(@lhs.meta_object,
            rhs_meta_object, exp_operator)
          @dsl.add_simple_expectation(@expectation)
          self
        end

        VALID_OPERATORS.each do |operator|
          define_method(operator) do |rhs|
            compare_with(operator, rhs)
          end
        end

        def exactly
          if !@exact_match
            @expectation.exactly!
          end
        end
      end

      class DataWrapper
        attr_reader :meta_object

        def initialize
          raise NotImplementedError
        end

        [:must, :must_not].each do |type|
          define_method(type) do |*args|
            if args.length > 0
              wrapper = args[0]
              comparator = wrapper.to_comparator(self)

              threshold = type == :must ? 1 : 0

              expectation = Expectations::Exhaustive.new(comparator, threshold, :equal)
              @dsl.add_exhaustive_expectation(expectation)
            else
              ExpectationWrapper.new(@dsl, type, self)
            end
          end
        end

        def compare_with(other)
          VisualComparisonWrapper.new(@dsl, self, other)
        end

        def method_missing(m, *args, &block)
          if meta_object.respond_to?(m)
            meta_object.send(m, *args, &block)
          else
            super(m, *args, &block)
          end
        end
      end

      class FieldWrapper < DataWrapper
        attr_reader :name

        def initialize(dsl, side, dataset, name)
          @dsl = dsl
          @meta_object = MetaObject.new(dataset.field_set[name], side)
        end
      end

      class FunctionWrapper < DataWrapper
        def initialize(dsl, klass, args)
          @dsl = dsl

          side = dataset = nil
          static = true
          function_args = []
          args.each do |arg|
            if arg.kind_of?(DataWrapper)
              raise "conflicting sides" if side && side != arg.side
              side = arg.side
              static &&= arg.static?
              dataset = arg.dataset
              function_args << arg.object
            else
              function_args << arg
            end
          end
          @meta_object = MetaObject.new(klass.new(*function_args), side)
        end
      end

      class ComparatorWrapper
        attr_reader :klass, :args

        def initialize(dsl, klass, args)
          @dsl = dsl
          @klass = klass
          @args = args
        end

        def of(*args)
          @args.push(*args)
          self
        end

        def to_comparator(receiver)
          comparator_args = ([receiver] + @args).collect do |arg|
            arg.is_a?(DataWrapper) ? arg.meta_object : MetaObject.new(arg)
          end
          comparator = klass.new(*comparator_args)
        end
      end

      class DatasetWrapper
        attr_reader :dataset

        def initialize(dsl, side, dataset)
          @dsl = dsl
          @dataset = dataset
          @side = side
        end

        def [](field_name)
          if @dataset.field_set.has_key?(field_name)
            FieldWrapper.new(@dsl, @side, @dataset, field_name)
          else
            raise ArgumentError, "The '#{field_name}' field doesn't exist for the #{@side} dataset!"
          end
        end
      end

      def initialize(config, &block)
        @config = config
        @lhs_filters = []
        @rhs_filters = []
        instance_eval(&block)
      end

      def lhs
        DatasetWrapper.new(self, :lhs, @config.dataset_1)
      end

      def rhs
        DatasetWrapper.new(self, :rhs, @config.dataset_2)
      end

      def save_results_in(uri, options = {})
        @config.results_uri = uri
        @config.results_uri_options = options
      end

      def set_record_cache_size(num)
        @config.record_cache_size = num
      end

      def add_simple_expectation(expectation)
        @config.add_simple_expectation(expectation)

        if @config.linkage_type == :self
          case expectation.kind
          when :cross
            @config.linkage_type = :cross
          when :filter
            # If there different filters on both 'sides' of a self-linkage,
            # it turns into a cross linkage.
            these_filters, other_filters =
              case expectation.side
              when :lhs
                [@lhs_filters, @rhs_filters]
              when :rhs
                [@rhs_filters, @lhs_filters]
              end

            these_filters << expectation
            other_filters.each do |other|
              if !expectation.same_except_side?(other)
                @config.linkage_type = :cross
                break
              end
            end
          end
        end
      end

      def add_exhaustive_expectation(expectation)
        @config.add_exhaustive_expectation(expectation)
        if @config.linkage_type == :self
          @config.linkage_type = expectation.kind
        end
      end

      def add_visual_comparison(visual_comparison)
        @config.visual_comparisons << visual_comparison
      end

      def groups_table_name(new_name)
        @config.groups_table_name = new_name
      end

      def original_groups_table_name(new_name)
        @config.original_groups_table_name = new_name
      end

      def scores_table_name(new_name)
        @config.scores_table_name = new_name
      end

      def matches_table_name(new_name)
        @config.matches_table_name = new_name
      end

      def method_missing(name, *args, &block)
        # check for comparators
        md = name.to_s.match(/^be_(.+)$/)
        if md
          klass = Comparator[md[1]]
          if klass
            ComparatorWrapper.new(self, klass, args)
          else
            super
          end
        else
          # check for functions
          klass = Function[name.to_s]
          if klass
            FunctionWrapper.new(self, klass, args)
          else
            super
          end
        end
      end
    end

    attr_reader :dataset_1, :dataset_2, :simple_expectations,
      :exhaustive_expectations, :visual_comparisons
    attr_accessor :linkage_type, :results_uri, :results_uri_options,
      :record_cache_size, :groups_table_name, :original_groups_table_name,
      :scores_table_name, :matches_table_name

    def initialize(dataset_1, dataset_2)
      @dataset_1 = dataset_1
      @dataset_2 = dataset_2
      @linkage_type = dataset_1 == dataset_2 ? :self : :dual
      @simple_expectations = []
      @exhaustive_expectations = []
      @visual_comparisons = []
      @results_uri_options = {}
      @decollation_needed = false
      @record_cache_size = 10_000
      @groups_table_name = :groups
      @original_groups_table_name = :original_groups
      @scores_table_name = :scores
      @matches_table_name = :matches
    end

    def configure(&block)
      DSL.new(self, &block)
    end

    def results_uri=(uri)
      @results_uri = uri
      if !@decollation_needed
        @simple_expectations.each do |expectation|
          if decollation_needed_for_simple_expectation?(expectation)
            @decollation_needed = true
            break
          end
        end
      end
      uri
    end

    def decollation_needed?
      @decollation_needed
    end

    def groups_table_schema
      schema = []

      # add id
      schema << [:id, Integer, {:primary_key => true}]

      # add values
      @simple_expectations.each do |exp|
        next  if exp.kind == :filter

        merged_field = exp.merged_field
        merged_type = merged_field.ruby_type

        # if the merged field's database type is different than the result
        # database, strip collation information
        result_db_type = nil
        result_set.database do |db|
          result_db_type = db.database_type
        end
        if merged_field.database_type != result_db_type && merged_type.has_key?(:opts)
          new_opts = merged_type[:opts].reject { |k, v| k == :collate }
          merged_type = merged_type.merge(:opts => new_opts)
        end

        col = [merged_field.name, merged_type[:type], merged_type[:opts] || {}]
        schema << col
      end

      schema
    end

    def scores_table_schema
      schema = []

      # add id
      schema << [:id, Integer, {:primary_key => true}]

      # add comparator id
      schema << [:comparator_id, Integer, {}]

      # add record ids
      pk = dataset_1.field_set.primary_key
      ruby_type = pk.ruby_type
      schema << [:record_1_id, ruby_type[:type], ruby_type[:opts] || {}]

      pk = dataset_2.field_set.primary_key
      ruby_type = pk.ruby_type
      schema << [:record_2_id, ruby_type[:type], ruby_type[:opts] || {}]

      # add score
      schema << [:score, Integer, {}]

      schema
    end

    def matches_table_schema
      schema = []

      # add id
      schema << [:id, Integer, {:primary_key => true}]

      # add record ids
      pk = dataset_1.field_set.primary_key
      ruby_type = pk.ruby_type
      schema << [:record_1_id, ruby_type[:type], ruby_type[:opts] || {}]

      pk = dataset_2.field_set.primary_key
      ruby_type = pk.ruby_type
      schema << [:record_2_id, ruby_type[:type], ruby_type[:opts] || {}]

      # add score
      schema << [:total_score, Integer, {}]

      schema
    end

    def add_simple_expectation(expectation)
      @simple_expectations << expectation
      @decollation_needed ||= decollation_needed_for_simple_expectation?(expectation)
      expectation
    end

    def add_exhaustive_expectation(expectation)
      @exhaustive_expectations << expectation
      expectation
    end

    def result_set
      @result_set ||= ResultSet.new(self)
    end

    def datasets_with_applied_simple_expectations
      dataset_1 = @dataset_1
      dataset_2 = @dataset_2
      @simple_expectations.each do |exp|
        dataset_1 = exp.apply_to(dataset_1, :lhs)
        dataset_2 = exp.apply_to(dataset_2, :rhs) if @linkage_type != :self
      end
      @linkage_type == :self ? [dataset_1, dataset_1] : [dataset_1, dataset_2]
    end

    def datasets_with_applied_exhaustive_expectations
      apply_exhaustive_expectations(@dataset_1, @dataset_2)
    end

    def apply_exhaustive_expectations(dataset_1, dataset_2)
      dataset_1 = dataset_1.select(dataset_1.field_set.primary_key.to_expr)
      dataset_2 = dataset_2.select(dataset_2.field_set.primary_key.to_expr)
      @exhaustive_expectations.each do |exp|
        dataset_1 = exp.apply_to(dataset_1, :lhs)
        dataset_2 = exp.apply_to(dataset_2, :rhs)
      end
      [dataset_1, dataset_2]
    end

    def groups_table_needed?
      has_simple_expectations?
    end

    def scores_table_needed?
      has_exhaustive_expectations?
    end

    def has_simple_expectations?
      !@simple_expectations.empty?
    end

    def has_exhaustive_expectations?
      !@exhaustive_expectations.empty?
    end

    private

    def decollation_needed_for_simple_expectation?(expectation)
      if expectation.decollation_needed?
        true
      elsif results_uri && expectation.kind != :filter
        result_set_database_type = ResultSet.new(self).database.database_type
        database_types_differ =
          result_set_database_type != dataset_1.database_type ||
          result_set_database_type != dataset_2.database_type

        merged_field = expectation.merged_field
        merged_field.ruby_type[:type] == String &&
          !merged_field.collation.nil? && database_types_differ
      else
        false
      end
    end
  end
end

require 'helper'

class UnitTests::TestComparator < Test::Unit::TestCase
  def setup
    super
    @_comparators = Linkage::Comparator.instance_variable_get("@comparators")
  end

  def teardown
    Linkage::Comparator.instance_variable_set("@comparators", @_comparators)
    super
  end

  test "comparator_name raises error in base class" do
    assert_raises(NotImplementedError) { Linkage::Comparator.comparator_name }
  end

  test "registering subclass requires comparator_name" do
    klass = Class.new(Linkage::Comparator)
    assert_raises(ArgumentError) { Linkage::Comparator.register(klass) }
  end

  test "getting a registered subclass" do
    klass = new_comparator('foo', [[String]])
    Linkage::Comparator.register(klass)
    assert_equal klass, Linkage::Comparator['foo']
  end

  test "parameters raises error in base class" do
    assert_raises(NotImplementedError) { Linkage::Comparator.parameters }
  end

  test "subclasses required to define parameters class method" do
    klass = new_comparator('foo')
    assert_raises(ArgumentError) { Linkage::Comparator.register(klass) }
  end

  test "subclasses required to define at least one parameter" do
    klass = new_comparator('foo', [])
    assert_raises(ArgumentError) { Linkage::Comparator.register(klass) }
  end

  test "subclasses required to define score method" do
    klass = new_comparator('foo', [[String]]) do
      remove_method :score
    end
    assert_raises(ArgumentError) { Linkage::Comparator.register(klass) }
  end

  test "comparator with one valid argument" do
    klass = new_comparator('foo', [[String]])
    meta_object = stub('meta_object', :ruby_type => { :type => String }, :static? => false)
    f = klass.new(meta_object)
  end

  test "comparator with one invalid argument" do
    klass = new_comparator('foo', [[String]])
    meta_object = stub('meta_object', :ruby_type => { :type => Fixnum }, :static? => false)
    assert_raises(TypeError) { klass.new(meta_object) }
  end

  test "comparator with too few arguments" do
    klass = new_comparator('foo', [[String]])
    assert_raises(ArgumentError) { klass.new }
  end

  test "comparator with too many arguments" do
    klass = new_comparator('foo', [[String]])
    meta_object = stub('meta_object', :ruby_type => { :type => String }, :static? => false)
    assert_raises(ArgumentError) { klass.new(meta_object, meta_object) }
  end

  test "requires first argument to be non-static" do
    klass = new_comparator('foo', [[String]])
    meta_object = stub('meta_object', :ruby_type => { :type => String }, :static? => true)
    assert_raises(TypeError) { klass.new(meta_object) }
  end

  test "special :any parameter" do
    klass = new_comparator('foo', [[:any]])
    meta_object_1 = stub('meta_object', :ruby_type => { :type => String }, :static? => false)
    meta_object_2 = stub('meta_object', :ruby_type => { :type => Fixnum }, :static? => false)
    assert_nothing_raised do
      klass.new(meta_object_1)
      klass.new(meta_object_2)
    end
  end
end

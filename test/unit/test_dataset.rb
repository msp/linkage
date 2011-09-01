require 'helper'

class UnitTests::TestDataset < Test::Unit::TestCase
  def setup
    @database = stub("database")
    Sequel.stubs(:connect).with("foo:/bar").returns(@database)
    @schema = [
      [:id, {:allow_null=>true, :default=>nil, :primary_key=>true, :db_type=>"integer", :type=>:integer, :ruby_default=>nil}],
      [:first_name, {:allow_null=>true, :default=>nil, :primary_key=>false, :db_type=>"varchar(255)", :type=>:string, :ruby_default=>nil}],
      [:last_name, {:allow_null=>true, :default=>nil, :primary_key=>false, :db_type=>"varchar(255)", :type=>:string, :ruby_default=>nil}]
    ]
    @database.stubs(:schema).with(:baz).returns(@schema)
    @dataset = stub("dataset")
    @database.stubs(:[]).with(:baz).returns(@dataset)
  end

  test "initialize with uri and table name" do
    Sequel.expects(:connect).with("foo:/bar").returns(@database)
    @database.expects(:schema).with(:baz).returns(@schema)
    primary_key_field = mock(:dataset= => nil)
    Linkage::Field.expects(:new).with(*@schema[0]).returns(primary_key_field)
    Linkage::Field.expects(:new).with(*@schema[1]).returns(mock(:dataset= => nil))
    Linkage::Field.expects(:new).with(*@schema[2]).returns(mock(:dataset= => nil))
    @database.expects(:[]).with(:baz).returns(@dataset)

    ds = Linkage::Dataset.new("foo:/bar", "baz")
    assert_equal primary_key_field, ds.primary_key
  end

  test "link dataset with itself" do
    dataset = Linkage::Dataset.new("foo:/bar", "baz")
    result = dataset.link_with(dataset) do
      lhs[:first_name].must == rhs[:first_name]
    end
    assert_kind_of Linkage::Configuration, result
  end
end

require 'helper'

class UnitTests::TestFieldSet < Test::Unit::TestCase
  def setup
    super
    @schema = {
      :id => {:allow_null=>true, :default=>nil, :primary_key=>true, :db_type=>"integer", :type=>:integer, :ruby_default=>nil},
      :first_name => {:allow_null=>true, :default=>nil, :primary_key=>false, :db_type=>"varchar(255)", :type=>:string, :ruby_default=>nil},
      :last_name => {:allow_null=>true, :default=>nil, :primary_key=>false, :db_type=>"varchar(255)", :type=>:string, :ruby_default=>nil}
    }
  end

  test "subclass of Hash" do
    assert_equal Hash, Linkage::FieldSet.superclass
  end

  test "creates fields on initialization" do
    dataset = mock('dataset', :schema => @schema)

    field_1 = stub('id field')
    field_2 = stub('first_name field')
    field_3 = stub('last_name field')
    Linkage::Field.expects(:new).with(dataset, :id, @schema[:id]).returns(field_1)
    Linkage::Field.expects(:new).with(dataset, :first_name, @schema[:first_name]).returns(field_2)
    Linkage::Field.expects(:new).with(dataset, :last_name, @schema[:last_name]).returns(field_3)

    fs = Linkage::FieldSet.new(dataset)
    assert_equal field_1, fs.primary_key
    assert_equal field_1, fs[:id]
    assert_equal field_2, fs[:first_name]
    assert_equal field_3, fs[:last_name]
  end

  test "case-insensitive names" do
    dataset = stub('dataset', :schema => @schema)

    field_1 = stub('id field')
    field_2 = stub('first_name field')
    field_3 = stub('last_name field')
    Linkage::Field.stubs(:new).with(dataset, :id, @schema[:id]).returns(field_1)
    Linkage::Field.stubs(:new).with(dataset, :first_name, @schema[:first_name]).returns(field_2)
    Linkage::Field.stubs(:new).with(dataset, :last_name, @schema[:last_name]).returns(field_3)

    fs = Linkage::FieldSet.new(dataset)
    assert_equal field_1, fs.primary_key
    assert_equal field_1, fs[:Id]
    assert_equal field_2, fs[:fIrst_name]
    assert_equal field_3, fs[:laSt_name]
  end
end

require 'test/unit'
require 'webloc'

class WeblocTest < Test::Unit::TestCase
  def test_webloc_object_requires_url
    assert_raise(ArgumentError) { Webloc.new }
  end
  
  def test_webloc_object_created_with_url
    assert_equal 'http://example.com', Webloc.new('http://example.com').url
  end
  
  def test_webloc_object_loaded_from_old_style_file
    assert_equal 'https://github.com/peterc/webloc', Webloc.load(File.dirname(__FILE__) + '/oldstyle.webloc').url
  end

  def test_webloc_object_loaded_from_plist_file
    assert_equal 'https://github.com/peterc/webloc', Webloc.load(File.dirname(__FILE__) + '/pliststyle.webloc').url
  end
  
  def test_webloc_generates_valid_data
    data = File.read(File.dirname(__FILE__) + '/oldstyle.webloc')
    data = data.force_encoding('binary') rescue data
    assert_equal data, Webloc.new('https://github.com/peterc/webloc').data
  end
end
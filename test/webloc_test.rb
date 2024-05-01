require 'test/unit'
require 'webloc'
require 'tempfile'

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
    data = File.read(File.dirname(__FILE__) + '/oldstyle.webloc').b
    assert_equal data, Webloc.new('https://github.com/peterc/webloc').data
  end

  def test_webloc_can_handle_long_urls
    url = "http://example.com/this-is-a-very-long-url-indeed-it-should-easily-go-over-110-characters-for-our-testing-purposes-lets-make-it-a-big-longer-to-get-up-to-the-two-hundred-and-fifty-five-limit-just-a-little-bit-further-to-go-nearly-there-123456782178327136726831267836821736721"
    assert_nothing_raised { Webloc.new(url).data }
    file = Tempfile.new('test-long-webloc')
    begin
      Webloc.new(url).save(file.path)
      assert_equal url, Webloc.load(file.path).url
    ensure
      file.close
      file.unlink
    end
  end

  def test_webloc_can_write_file
    file = Tempfile.new('test-webloc')
    begin
      Webloc.new('https://github.com/peterc/webloc').save(file.path)
      assert_equal Webloc.new('https://github.com/peterc/webloc').data, File.read(file.path).b
    ensure
      file.close
      file.unlink
    end    
  end
end
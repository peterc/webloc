require 'test/unit'
require 'webloc'
require 'tempfile'

class WeblocTest < Test::Unit::TestCase
  def test_webloc_object_requires_url
    assert_raise(ArgumentError) { Webloc.new }
  end

  def test_webloc_object_rejects_nil_url
    error = assert_raise(ArgumentError) { Webloc.new(nil) }
    assert_equal "URL cannot be nil or empty", error.message
  end

  def test_webloc_object_rejects_empty_url
    error = assert_raise(ArgumentError) { Webloc.new("") }
    assert_equal "URL cannot be nil or empty", error.message
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
    url = "http://example.com/this-is-a-very-long-url-abcde" + ('a' * 2000)
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

  def test_load_nonexistent_file_raises_file_not_found_error
    error = assert_raise(Webloc::FileNotFoundError) { Webloc.load('nonexistent.webloc') }
    assert_match(/File not found: nonexistent\.webloc/, error.message)
  end

  def test_load_empty_file_raises_empty_file_error
    file = Tempfile.new('empty-webloc')
    begin
      file.close
      error = assert_raise(Webloc::EmptyFileError) { Webloc.load(file.path) }
      assert_match(/File is empty:/, error.message)
    ensure
      file.unlink
    end
  end

  def test_load_corrupted_binary_file_raises_invalid_format_error
    file = Tempfile.new('corrupted-webloc')
    begin
      file.write("corrupted binary data without SURL marker")
      file.close
      error = assert_raise(Webloc::InvalidFormatError) { Webloc.load(file.path) }
      assert_match(/Invalid binary webloc format - missing SURL marker/, error.message)
    ensure
      file.unlink
    end
  end

  def test_load_invalid_xml_file_raises_invalid_format_error
    file = Tempfile.new('invalid-xml-webloc')
    begin
      file.write("<plist><invalid>xml</invalid>")
      file.close
      error = assert_raise(Webloc::InvalidFormatError) { Webloc.load(file.path) }
      assert_match(/Invalid XML plist format/, error.message)
    ensure
      file.unlink
    end
  end

  def test_load_xml_without_url_key_raises_invalid_format_error
    file = Tempfile.new('no-url-xml-webloc')
    begin
      file.write('<?xml version="1.0"?><plist><dict><key>NotURL</key><string>value</string></dict></plist>')
      file.close
      error = assert_raise(Webloc::InvalidFormatError) { Webloc.load(file.path) }
      assert_match(/No 'URL' key found in plist file/, error.message)
    ensure
      file.unlink
    end
  end

  def test_save_with_nil_filename_raises_argument_error
    webloc = Webloc.new('http://example.com')
    error = assert_raise(ArgumentError) { webloc.save(nil) }
    assert_equal "Filename cannot be nil or empty", error.message
  end

  def test_save_with_empty_filename_raises_argument_error
    webloc = Webloc.new('http://example.com')
    error = assert_raise(ArgumentError) { webloc.save("") }
    assert_equal "Filename cannot be nil or empty", error.message
  end

  def test_save_to_invalid_path_raises_webloc_error
    webloc = Webloc.new('http://example.com')
    error = assert_raise(Webloc::WeblocError) { webloc.save('/invalid/path/that/does/not/exist/file.webloc') }
    assert_match(/Failed to save webloc file/, error.message)
  end
end
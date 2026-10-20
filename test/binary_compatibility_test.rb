require 'minitest/autorun'
require 'webloc'
require 'tempfile'
require 'open3'
require 'json'

class BinaryCompatibilityTest < Minitest::Test
  FIXTURES = File.expand_path('fixtures', __dir__)
  PREFIX = 'https://example.com/'
  LENGTHS = [1, 14, 15, 237, 238, 255, 256, 2048, 65_517, 65_518, 65_535, 65_536].freeze

  def with_file(data)
    Tempfile.create(['webloc-compatibility', '.webloc']) do |file|
      file.binmode
      file.write(data)
      file.flush
      yield file.path
    end
  end

  def test_reads_independently_generated_binary_files
    {
      'binary-short' => 'https://a.co',
      'binary-metadata' => 'https://example.com/path',
      'binary-unicode' => 'https://example.com/café/😀',
      'binary-many-objects' => 'https://example.com/many',
      'binary-root-last' => 'https://a.co',
      'binary-plist-in-url' => 'https://example.com/<plist'
    }.each do |name, url|
      assert_equal url, Webloc.load(File.join(FIXTURES, "#{name}.webloc")).url, name
    end
  end

  def test_reads_files_written_by_previous_releases
    [238, 256, 2048, 65_535].each do |length|
      expected = PREFIX + 'a' * (length - PREFIX.length)
      assert_equal expected, Webloc.load(File.join(FIXTURES, "legacy-#{length}.webloc")).url
    end
  end

  def test_round_trips_length_boundaries
    LENGTHS.each do |length|
      url = 'a' * length
      with_file(Webloc.new(url).data) do |path|
        assert_equal url, Webloc.load(path).url, "length #{length}"
      end
    end
  end

  def test_round_trips_unicode_and_encoded_strings
    ['https://example.com/café/😀', 'https://例え.jp/道',
     'https://example.com/café'.encode('ISO-8859-1')].each do |url|
      with_file(Webloc.new(url).data) do |path|
        assert_equal url.encode('UTF-8'), Webloc.load(path).url
      end
    end
  end

  def test_rejects_missing_empty_and_nonstring_urls
    %w[binary-missing-url binary-empty-url binary-nonstring-url binary-nondictionary].each do |name|
      assert_raises(Webloc::WeblocError, name) do
        Webloc.load(File.join(FIXTURES, "#{name}.webloc"))
      end
    end
  end

  def test_rejects_nonstring_xml_url_with_a_library_error
    with_file('<plist><dict><key>URL</key><integer>42</integer></dict></plist>') do |path|
      assert_raises(Webloc::CorruptedFileError) { Webloc.load(path) }
    end
  end

  def test_does_not_accept_a_marker_in_arbitrary_data
    with_file("SURL_\x10\x0ahttps:".b) do |path|
      assert_raises(Webloc::InvalidFormatError) { Webloc.load(path) }
    end
  end

  def test_rejects_truncated_files_including_legacy_files
    %w[binary-short legacy-256].each do |name|
      data = File.binread(File.join(FIXTURES, "#{name}.webloc"))
      [7, 20, data.bytesize - 1].each do |size|
        with_file(data.byteslice(0, size)) do |path|
          assert_raises(Webloc::WeblocError, "#{name} truncated at #{size}") { Webloc.load(path) }
        end
      end
      # Remove a URL byte but retain the original trailer and offset table.
      data.slice!(20)
      with_file(data) do |path|
        assert_raises(Webloc::WeblocError) { Webloc.load(path) }
      end
    end
  end

  def test_rejects_invalid_offsets_references_and_lengths
    original = File.binread(File.expand_path('oldstyle.webloc', __dir__))
    corruptions = [
      [-26, "\0"],                         # zero offset width
      [-25, "\0"],                         # zero reference width
      [-24, [0].pack('Q>')],               # no objects
      [-16, [99].pack('Q>')],              # invalid root reference
      [-8, [original.bytesize].pack('Q>')], # offset table outside the file
      [-35, "\0"],                        # root object points into header
      [10, "\xff".b],                     # dictionary value reference outside table
      [17, "\xff".b]                      # string extends beyond its object
    ]
    corruptions.each do |offset, bytes|
      data = original.dup
      data[offset, bytes.bytesize] = bytes
      with_file(data) do |path|
        assert_raises(Webloc::WeblocError, "corruption at #{offset}") { Webloc.load(path) }
      end
    end
  end

  def test_url_remains_mutable_and_data_is_binary
    webloc = Webloc.new('https://example.com')
    webloc.url = 'https://rubyweekly.com/'
    assert_equal Encoding::BINARY, webloc.data.encoding
    with_file(webloc.data) { |path| assert_equal webloc.url, Webloc.load(path).url }
  end

  def test_unsupported_length_encoding_retains_its_error_class
    data = File.binread(File.expand_path('oldstyle.webloc', __dir__))
    data.setbyte(16, 0x14)
    with_file(data) do |path|
      error = assert_raises(Webloc::InvalidFormatError) { Webloc.load(path) }
      assert_includes error.message, 'Unsupported length encoding'
    end
  end

  def test_preserves_urls_without_requiring_http_or_modifying_input
    ['mailto:hello@example.com', 'file:///tmp/example', 'custom:example',
     'https://example.com/a%20b?q=1&other=2#part'].each do |url|
      url.freeze
      webloc = Webloc.new(url)
      assert_same url, webloc.url
      Tempfile.create(['webloc-api', '.webloc']) do |file|
        bytes_written = webloc.save(file.path)
        assert_equal File.size(file.path), bytes_written
        assert_equal url, Webloc.load(file.path).url
      end
    end
  end

  def test_output_with_independent_python_plist_reader
    urls = LENGTHS.map { |length| 'a' * length } + ['https://example.com/café/😀']
    urls.each do |url|
      with_file(Webloc.new(url).data) do |path|
        output, error, status = Open3.capture3(
          'python3', '-c',
          'import json,plistlib,sys; print(json.dumps(plistlib.load(open(sys.argv[1],"rb"))))',
          path
        )
        assert status.success?, error
        assert_equal({ 'URL' => url }, JSON.parse(output), "length #{url.length}")
      end
    end
  rescue Errno::ENOENT
    skip 'Install Python 3 to run the independent plist interoperability check'
  end

  def test_output_with_apple_plist_reader
    skip 'Apple plutil is only available on macOS' unless RUBY_PLATFORM.include?('darwin')

    [237, 238, 255, 256, 2048, 65_536].each do |length|
      url = PREFIX + 'a' * (length - PREFIX.length)
      with_file(Webloc.new(url).data) do |path|
        output, error, status = Open3.capture3('/usr/bin/plutil', '-convert', 'json', '-o', '-', path)
        assert status.success?, "#{output}\n#{error}"
        assert_equal({ 'URL' => url }, JSON.parse(output))
      end
    end
    with_file(Webloc.new('https://example.com/café/😀').data) do |path|
      output, error, status = Open3.capture3('/usr/bin/plutil', '-convert', 'json', '-o', '-', path)
      assert status.success?, error
      assert_equal({ 'URL' => 'https://example.com/café/😀' }, JSON.parse(output))
    end
  end
end

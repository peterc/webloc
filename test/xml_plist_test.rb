require 'minitest/autorun'
require 'webloc'
require 'tempfile'
require 'timeout'

class XMLPlistTest < Minitest::Test
  def with_file(data)
    Tempfile.create(['webloc-xml', '.webloc']) do |file|
      file.binmode
      file.write(data)
      file.flush
      yield file.path
    end
  end

  def load_url(xml)
    with_file(xml) { |path| Webloc.load(path).url }
  end

  def assert_load_error(error_class, xml, pattern = nil)
    error = assert_raises(error_class, xml[0, 80]) { load_url(xml) }
    assert_match(pattern, error.message) if pattern
    error
  end

  def plist(body)
    "<plist version=\"1.0\"><dict>#{body}</dict></plist>"
  end

  def test_has_no_runtime_dependencies
    gemspec = Gem::Specification.load(File.expand_path('../webloc.gemspec', __dir__))
    assert_empty gemspec.runtime_dependencies
  end

  def test_reads_apple_style_document
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <!-- written by hand -->
      <plist version="1.0">
      <dict>
      \t<key>URL</key>
      \t<string>https://example.com/path</string>
      </dict>
      </plist>
    XML
    assert_equal 'https://example.com/path', load_url(xml)
  end

  def test_returns_utf8_strings
    url = load_url(plist('<key>URL</key><string>https://example.com/café/😀</string>'))
    assert_equal 'https://example.com/café/😀', url
    assert_equal Encoding::UTF_8, url.encoding
  end

  def test_accepts_a_byte_order_mark_and_crlf_line_endings
    xml = "\xEF\xBB\xBF<?xml version=\"1.0\"?>\r\n<plist>\r\n<dict>\r\n" \
          "<key>URL</key>\r\n<string>https://a.co</string>\r\n</dict>\r\n</plist>\r\n"
    assert_equal 'https://a.co', load_url(xml)
  end

  def test_decodes_predefined_and_numeric_entities
    xml = plist('<key>URL</key><string>https://a.co/?a=1&amp;b=&lt;&gt;&quot;&apos;&#233;&#xE9;&#x1F600;</string>')
    assert_equal "https://a.co/?a=1&b=<>\"'éé😀", load_url(xml)
  end

  def test_decodes_entities_once
    assert_equal 'https://a.co/&lt;', load_url(plist('<key>URL</key><string>https://a.co/&amp;lt;</string>'))
  end

  def test_keeps_unrecognized_ampersand_sequences
    assert_equal 'https://a.co/?a=1&b=2&foo;', load_url(plist('<key>URL</key><string>https://a.co/?a=1&b=2&foo;</string>'))
  end

  def test_decodes_a_reference_to_nul
    ['&#0;', '&#x0;', '&#000;'].each do |reference|
      assert_equal "a\u0000b", load_url(plist("<key>URL</key><string>a#{reference}b</string>"))
    end
  end

  def test_rejects_invalid_character_references
    ['&#xD800;', '&#xDFFF;', '&#x110000;', '&#99999999999999999999;'].each do |reference|
      assert_load_error Webloc::InvalidFormatError, plist("<key>URL</key><string>a#{reference}</string>"),
                        /Invalid XML plist format/
    end
  end

  def test_reads_cdata_sections_without_decoding_them
    {
      '<![CDATA[https://a.co/?a=1&b=<2>&amp;]]>' => 'https://a.co/?a=1&b=<2>&amp;',
      'https://<![CDATA[a.co]]>/&amp;<![CDATA[]]><![CDATA[x]]>' => 'https://a.co/&x',
    }.each do |content, url|
      assert_equal url, load_url(plist("<key>URL</key><string>#{content}</string>"))
    end
    assert_equal 'https://a.co', load_url(plist('<key><![CDATA[URL]]></key><string>https://a.co</string>'))
  end

  def test_skips_cdata_sections_in_other_values
    url = '<key>URL</key><string>https://a.co</string>'
    [
      "<key>Name</key><string><![CDATA[A & <B>]]></string>#{url}",
      "<key>List</key><array><string>a<![CDATA[</string>]]>b</string></array>#{url}",
    ].each do |body|
      assert_equal 'https://a.co', load_url(plist(body))
    end
    assert_load_error Webloc::InvalidFormatError, plist("<key>Name</key><string><![CDATA[A</string>#{url}"),
                      /Unterminated CDATA section/
    assert_load_error Webloc::InvalidFormatError, plist("<![CDATA[x]]>#{url}"), /Invalid XML plist format/
  end

  def test_rejects_unterminated_cdata_and_comments_inside_strings
    ['<![CDATA[https://a.co', '<![CDATA[https://a.co]]', 'https://a<!-- c -->.co'].each do |content|
      assert_load_error Webloc::InvalidFormatError, plist("<key>URL</key><string>#{content}</string>"),
                        /Invalid XML plist format/
    end
  end

  def test_preserves_whitespace_inside_the_string
    assert_equal "\n  https://a.co\n", load_url(plist("<key>URL</key><string>\n  https://a.co\n</string>"))
  end

  def test_finds_url_among_other_keys_and_value_types
    xml = plist(<<~XML)
      <key>Name</key><string>Example</string>
      <key>Count</key><integer>3</integer>
      <key>Flag</key><true/>
      <key>Blob</key><data>AAEC</data>
      <key>List</key><array><string>URL</string><dict><key>URL</key><string>https://nested.example</string></dict></array>
      <key>Nested</key><dict><key>URL</key><string>https://nested.example</string></dict>
      <key>URL</key><string>https://example.com</string>
      <key>Empty</key><dict/>
    XML
    assert_equal 'https://example.com', load_url(xml)
  end

  def test_ignores_url_keys_outside_the_root_dictionary
    xml = plist('<key>Nested</key><dict><key>URL</key><string>https://nested.example</string></dict>')
    assert_load_error Webloc::InvalidFormatError, xml, /No 'URL' key found in plist file/
  end

  def test_last_duplicate_url_key_wins
    xml = plist('<key>URL</key><string>https://first.example</string><key>URL</key><string>https://second.example</string>')
    assert_equal 'https://second.example', load_url(xml)
  end

  def test_matches_the_key_after_entity_decoding
    assert_equal 'https://a.co', load_url(plist('<key>&#85;RL</key><string>https://a.co</string>'))
  end

  def test_rejects_nonstring_url_values
    ['<integer>42</integer>', '<true/>', '<data>AAEC</data>', '<array><string>https://a.co</string></array>',
     '<dict><key>URL</key><string>https://a.co</string></dict>'].each do |value|
      assert_load_error Webloc::CorruptedFileError, plist("<key>URL</key>#{value}"), /URL must be a string/
    end
  end

  def test_rejects_empty_url_values
    ['<string></string>', '<string/>'].each do |value|
      assert_load_error Webloc::CorruptedFileError, plist("<key>URL</key>#{value}"), /No URL found/
    end
  end

  def test_rejects_documents_whose_root_is_not_a_dictionary
    ['<plist><array><string>https://a.co</string></array></plist>',
     '<plist><string>https://a.co</string></plist>',
     '<plist></plist>',
     '<plist/>',
     '<html><plist><dict><key>URL</key><string>https://a.co</string></dict></plist></html>'].each do |xml|
      assert_load_error Webloc::InvalidFormatError, xml, /Invalid XML plist format/
    end
  end

  def test_ignores_content_after_the_root_element
    xml = plist('<key>URL</key><string>https://a.co</string>')
    ['trailing', '<plist/>', '<dict>', '<!-- unterminated', '<?pi', '<', '>', "\0\0"].each do |extra|
      assert_equal 'https://a.co', load_url(xml.b + extra.b), extra.inspect
    end
  end

  def test_rejects_elements_that_are_not_plist_types
    url = '<key>URL</key><string>https://a.co</string>'
    ['<key>A</key><foo>bar</foo>', '<key>A</key><foo/>', '<key>A</key><array><foo>x</foo></array>',
     '<key>A</key><dict><key>k</key><foo/></dict>', '<key>A</key><string>a<b>c</b></string>',
     '<key>A</key><STRING>x</STRING>'].each do |body|
      assert_load_error Webloc::InvalidFormatError, plist(body + url), /Unknown element/
    end
  end

  def test_accepts_key_and_plist_elements_as_values_like_apple
    url = '<key>URL</key><string>https://a.co</string>'
    ['<key>A</key><key>B</key>', '<key>A</key><plist><string>x</string></plist>',
     '<key>A</key><array><key>k</key></array>'].each do |body|
      assert_equal 'https://a.co', load_url(plist(body + url)), body
    end
  end

  def test_rejects_malformed_documents
    [
      '<plist><dict><key>URL</key><string>https://a.co</string></dict>',
      '<plist><dict><key>URL</key><string>https://a.co</string>',
      '<plist><dict><key>URL</key><string>https://a.co',
      '<plist><dict><key>URL</key><string>https://a.co</string></dict></plist',
      '<plist><dict><key>URL</key><string>https://a.co</key></dict></plist>',
      '<plist><dict><key>URL</key><string>https://a.co</string></array></plist>',
      '<plist><dict><key>URL</key><string>https://a.co</string><key>Other</key></dict></plist>',
      '<plist><dict><string>https://a.co</string></dict></plist>',
      '<plist><dict><key>Other</key><key>URL</key><string>https://a.co</string></dict></plist>',
      '<plist><dict><key>URL</key>https://a.co</dict></plist>',
      '<plist>text<dict><key>URL</key><string>https://a.co</string></dict></plist>',
      '<plist><dict><key>URL</key><string>https://a.co</string></dict><dict/></plist>',
      '<plist><dict><key>URL</key><string>https://<b>a.co</b></string></dict></plist>',
      '<plist><dict><key>URL</key><string>https://a.co</string><key>X</key><array><string>a</array></dict></plist>',
      '<plist><!-- unterminated <dict><key>URL</key><string>https://a.co</string></dict></plist>',
    ].each do |xml|
      assert_load_error Webloc::InvalidFormatError, xml, /Invalid XML plist format/
    end
  end

  def test_rejects_internal_dtd_subsets
    xml = '<!DOCTYPE plist [<!ENTITY u "https://a.co">]><plist><dict><key>URL</key><string>&u;</string></dict></plist>'
    assert_load_error Webloc::InvalidFormatError, xml, /Invalid XML plist format/
  end

  def test_rejects_documents_that_are_not_valid_utf8
    assert_load_error Webloc::InvalidFormatError, plist("<key>URL</key><string>https://a.co/caf\xE9</string>".b),
                      /Document is not valid UTF-8/
    xml = '<?xml version="1.0" encoding="UTF-8"?>'.b + plist("<key>URL</key><string>https://a.co/caf\xE9</string>".b)
    assert_load_error Webloc::InvalidFormatError, xml, /Document is not valid UTF-8/
  end

  def test_reads_the_declared_encoding_like_apple
    {
      ['ISO-8859-1', "https://a.co/caf\xE9".b] => 'https://a.co/café',
      ['ISO-8859-1', "https://a.co/\xC3\xA9".b] => 'https://a.co/Ã©',
      ['iso_8859-1', "https://a.co/\xC3\xA9".b] => 'https://a.co/Ã©',
      ['latin1', "https://a.co/\xC3\xA9".b] => 'https://a.co/Ã©',
      ['windows-1252', "https://a.co/\xC3\xA9".b] => 'https://a.co/Ã©',
      ['CP1252', "https://a.co/\x80".b] => 'https://a.co/€',
      ['utf-8', 'https://a.co/café'.b] => 'https://a.co/café',
      ['UTF8', 'https://a.co/café'.b] => 'https://a.co/café',
      ['US-ASCII', 'https://a.co'.b] => 'https://a.co',
      ['ascii', 'https://a.co'.b] => 'https://a.co',
    }.each do |(encoding, bytes), url|
      ["<?xml version=\"1.0\" encoding=\"#{encoding}\"?>", "<?xml encoding='#{encoding}' version='1.0'?>"].each do |declaration|
        loaded = load_url(declaration.b + plist("<key>URL</key><string>#{bytes}</string>".b))
        assert_equal url, loaded, declaration
        assert_equal Encoding::UTF_8, loaded.encoding
      end
    end
  end

  def test_reads_utf8_when_apple_ignores_the_declaration
    body = plist("<key>URL</key><string>https://a.co/\xC3\xA9</string>".b)
    declaration = '<?xml version="1.0" encoding="ISO-8859-1"?>'.b
    ["\n".b + declaration, "\xEF\xBB\xBF".b + declaration, '<!-- c -->'.b + declaration,
     '<?XML version="1.0" encoding="ISO-8859-1"?>'.b, '<?xml version="1.0"?>'.b].each do |prolog|
      assert_equal 'https://a.co/é', load_url(prolog + body), prolog
    end
    assert_equal 'https://a.co/é', load_url("<plist>#{declaration}<dict><key>URL</key><string>https://a.co/é</string></dict></plist>")
    assert_equal 'https://a.co/é', load_url('<?xml version="1.0" encoding = "utf-8"?>'.b + body)
  end

  def test_rejects_other_declared_encodings
    utf7 = '<key>URL</key><string>https://first.example</string><key>x</key><string>' \
           '+ADw-/string+AD4APA-key+AD4-URL+ADw-/key+AD4APA-string+AD4-https://second.example</string>'
    {
      'UTF-7' => utf7,
      'Shift_JIS' => '<key>URL</key><string>https://a.co/\\</string>',
      'ISO-2022-JP' => "<key>URL</key><string>https://a.co/\e$B0!\e(B</string>",
      'internal' => "<key>URL</key><string>https://a.co/\xC3\xA9</string>",
      'locale' => '<key>URL</key><string>https://a.co</string>',
      'external' => '<key>URL</key><string>https://a.co</string>',
      'nope' => '<key>URL</key><string>https://a.co</string>',
      'UTF-16' => '<key>URL</key><string>https://a.co</string>',
      'ISO-8859-2' => "<key>URL</key><string>https://a.co/\xB1</string>",
      '' => '<key>URL</key><string>https://a.co</string>',
    }.each do |encoding, body|
      xml = "<?xml version='1.0' encoding='#{encoding}'?>".b + plist(body.b)
      assert_load_error Webloc::InvalidFormatError, xml, /Unsupported encoding/
    end
  end

  def test_rejects_bytes_that_do_not_fit_the_declared_encoding
    { 'US-ASCII' => "\xE9", 'windows-1252' => "\x81", 'UTF-8' => "\xE9" }.each do |encoding, byte|
      xml = "<?xml version=\"1.0\" encoding=\"#{encoding}\"?>".b + plist("<key>URL</key><string>https://a.co/#{byte}</string>".b)
      assert_load_error Webloc::InvalidFormatError, xml, /Invalid XML plist format/
    end
  end

  def test_rejects_declarations_apple_might_read_differently
    body = plist("<key>URL</key><string>https://a.co/\xC3\xA9</string>".b)
    ['<?xml version="1.0" encoding = "ISO-8859-1"?>', '<?xml version="1.0" ENCODING="ISO-8859-1"?>',
     '<?xml version="1.0" encoding="ISO-8859-1?>', '<?xml version="1.0" encoding=ISO-8859-1?>',
     "<?xml version=\"1.0\" encoding= encoding='ISO-8859-1'?>", "<?xml encoding=UTF-8 encoding='ISO-8859-1'?>",
     "<?xml encoding== Encoding= encoding='ISO-8859-1'?>", "<?xml myencoding encoding='ISO-8859-1'?>"].each do |declaration|
      assert_load_error Webloc::InvalidFormatError, declaration.b + body, /Unsupported encoding/
    end
  end

  def test_raises_only_library_errors_for_deep_nesting
    depth = 200_000
    xml = plist("<key>Deep</key>#{'<array>' * depth}#{'</array>' * depth}<key>URL</key><string>https://a.co</string>")
    assert_equal 'https://a.co', load_url(xml)
    assert_load_error Webloc::InvalidFormatError, "<plist>#{'<dict><key>a</key>' * depth}"
  end

  def test_parses_hostile_input_in_linear_time
    size = 400_000
    inputs = [
      '<plist>' + '<!--' * (size / 4),
      '<plist>' + '<' * size,
      '<plist><' + 'a' * size,
      '<plist><a ' + 'b' * size,
      '<plist></' + 'a' * size,
      '<plist><dict><key>URL</key><string>' + 'a' * size,
      '<plist><dict><key>URL</key><string>' + '&' * size,
      '<plist><dict><key>URL</key><string>' + '&#' * (size / 2),
      '<plist><dict>' + '<key>' * (size / 5),
      '<plist><dict><key>URL</key><string>' + '<![CDATA[' * (size / 9),
      '<plist><dict><key>URL</key><string>' + '<![CDATA[]]>' * (size / 12),
      '<plist><dict><key>a</key><string>' + '<![CDATA[' * (size / 9),
      '<!DOCTYPE plist ' + 'a' * size,
      '<?xml <plist ' + '?' * size,
      '<plist>' + ' ' * size,
      '<plist>' + '<!-- -' * (size / 6),
    ]
    Timeout.timeout(10) do
      inputs.each { |xml| assert_load_error Webloc::InvalidFormatError, xml }
    end
  end
end

require 'minitest/autorun'
require 'webloc'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'json'

class ReadmeTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  README = File.read(File.join(ROOT, 'README.md'))
  EXAMPLES = README.scan(/```ruby\n(.*?)```/m).flatten +
    README.scan(/(?:^    .*\n)+/).map { |block| block.gsub(/^    /, '') }.select { |block| block.include?('Webloc') }

  def test_readme_examples_are_present
    assert_equal 5, EXAMPLES.length
  end

  EXAMPLES.each_with_index do |code, index|
    define_method("test_readme_example_#{index + 1}") do
      Dir.mktmpdir('webloc-readme') do |directory|
        %w[bookmark suspicious].each do |name|
          FileUtils.cp(File.join(ROOT, 'test/pliststyle.webloc'), File.join(directory, "#{name}.webloc"))
        end
        output, error, status = Open3.capture3(
          RbConfig.ruby, '-I', File.join(ROOT, 'lib'), '-e', code, chdir: directory
        )
        assert status.success?, "#{code}\n#{output}\n#{error}"
        if code.include?('create_webloc_safely')
          assert_equal 'https://example.com', Webloc.load(File.join(directory, 'example.webloc')).url
          assert_includes output, 'Invalid URL scheme: invalid-url'
          refute File.exist?(File.join(directory, 'invalid.webloc'))
        elsif code.include?('JSON.parse')
          assert_equal 'https://github.com/peterc/webloc', Webloc.load(File.join(directory, 'restored.webloc')).url
          assert_equal 'bookmark', JSON.parse(File.read(File.join(directory, 'bookmark.json')))['title']
        elsif code.include?('rubyweekly.webloc')
          assert_equal 'https://rubyweekly.com/', Webloc.load(File.join(directory, 'rubyweekly.webloc')).url
        else
          assert_includes output, 'https://github.com/peterc/webloc'
        end
      end
    end
  end
end

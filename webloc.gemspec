# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "webloc/version"

Gem::Specification.new do |s|
  s.name        = "webloc"
  s.version     = Webloc::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Peter Cooper"]
  s.email       = ["git@peterc.org"]
  s.homepage    = "https://github.com/peterc/webloc"
  s.summary     = %q{Reads and writes .webloc files on macOS}
  s.description = %q{Webloc reads and writes .webloc files on macOS}

  s.rubyforge_project = "webloc"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  
  s.add_dependency 'plist'
end

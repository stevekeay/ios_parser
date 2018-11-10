$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'ios_parser/version'

Gem::Specification.new do |s|
  s.name        = 'ios_parser'
  s.version     = IOSParser.version
  s.summary     = 'convert network switch and router config files to '\
                  'structured data'
  s.authors     = ['Ben Miller']
  s.email       = 'bjmllr@gmail.com'
  s.homepage    = 'https://github.com/bjmllr/ios_parser'
  s.license     = 'GPL-3.0'
  s.files       = `git ls-files`.split("\n")
  s.test_files  = `git ls-files -- {spec,features}/*`.split("\n")

  if RUBY_PLATFORM == 'java'
    s.platform = 'java'
  else
    s.extensions << 'ext/ios_parser/c_lexer/extconf.rb'
  end

  s.add_development_dependency 'rake-compiler', '~>0.9'
  s.add_development_dependency 'rspec', '~>3.2'
  s.add_development_dependency 'rubocop', '~> 0.54' if RUBY_VERSION > '2.1'
end

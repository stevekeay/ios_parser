$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
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

  s.extensions << 'ext/ios_parser/c_lexer/extconf.rb'

  s.add_development_dependency 'rspec', '~>3.2'
  s.add_development_dependency 'rubocop', '~>0.37'
  s.add_development_dependency 'guard', '~>2.0'
  s.add_development_dependency 'guard-rake', '~>1.0'
  s.add_development_dependency 'guard-rspec', '~>4.5'
  s.add_development_dependency 'guard-rubocop', '~>1.2'
  s.add_development_dependency 'rake-compiler', '~>0.9'
end

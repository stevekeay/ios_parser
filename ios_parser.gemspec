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

  s.add_dependency 'ffi-compiler', '~> 1.0'
  s.add_dependency 'rake', '>= 9', '< 12'

  s.extensions = ['ext/ios_parser/Rakefile']

  s.add_development_dependency 'rspec', '~>3.2'
  s.add_development_dependency 'rubocop', '~>0.42'
end

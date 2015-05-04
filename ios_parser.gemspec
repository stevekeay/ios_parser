$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "ios_parser/version"

Gem::Specification.new do |s|
  s.name        = "ios_parser"
  s.version     = IOSParser.version
  s.date        = "2014-08-29"
  s.summary     = "convert network switch and router config files to "\
                  "structured data"
  s.authors     = ["Ben Miller"]
  s.email       = "bmiller@rackspace.com"
  s.homepage    = "https://github.rackspace.com/bmiller/ios_parser"
  s.license     = "MIT"
  s.files       = `git ls-files`.split("\n")
  s.test_files  = `git ls-files -- {spec,features}/*`.split("\n")

  s.add_dependency "multi_json", "~>1.11"

  s.extensions << "ext/ios_parser/c_lexer/extconf.rb"

  s.add_development_dependency "bundler", "~>1.8"
  s.add_development_dependency "rspec", "~>3.2"
  s.add_development_dependency "guard", "~>0.9"
  s.add_development_dependency "guard-rspec", "~>4.5"
  s.add_development_dependency "rake-compiler", "~>0.9"
end

require 'rake/extensiontask'
spec = Gem::Specification.load('ios_parser.gemspec')
Rake::ExtensionTask.new do |ext|
  ext.name = 'c_lexer'
  ext.ext_dir = 'ext/ios_parser/c_lexer'
  ext.lib_dir = 'lib/ios_parser'
  ext.gem_spec = spec
end

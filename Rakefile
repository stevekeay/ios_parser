require 'bundler/setup'
require 'bundler/gem_tasks'

require 'rspec/core/rake_task'

require 'rake'
require 'rake/clean'

require 'ffi'
require 'ffi-compiler/compile_task'

CLEAN.include('ext/ios_parser/*{.o,.log,.so,.bundle}')
CLEAN.include('lib/**/*{.o,.log,.so,.bundle}')

RSpec::Core::RakeTask.new(:spec)

require 'ffi-compiler/compile_task'
desc 'FFI compiler'
namespace 'ffi-compiler' do
  FFI::Compiler::CompileTask.new('ext/ios_parser/ios_parser_ext')
end
task compile_ffi: ['ffi-compiler:default']

task rebuild: [:clean, :compile_ffi]
task default: [:clean, :compile_ffi, :spec]

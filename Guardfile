group :main, halt_on_fail: true do
  guard :rake, task: 'rebuild' do
    watch('lib/ios_parser/ffi_lexer.rb')
    watch(%r{^ext/(.+)\.[ch]$})
  end

  guard :rspec,
        cmd: 'bundle exec rspec --color --fail-fast -f d',
        run_all: { cmd: 'bundle exec rspec --fail-fast -f p' } do

    watch(%r{^spec/.+_spec\.rb$})
    watch(%r{^lib/(.+)\.rb$})     { |m| "spec/lib/#{m[1]}_spec.rb" }
    watch('spec/spec_helper.rb')  { 'spec' }
    watch(%r{^ext/(.+)\.[ch]$})   { 'spec' }
    watch('lib/ios_parser/ffi_lexer.rb') { 'spec' }
  end

  guard :rubocop, all_on_start: false, cli: '-D -a' do
    watch(/.+\.rb$/)
    watch(%r{(?:.+/)?\.rubocop\.yml$}) { |m| File.dirname(m[0]) }
  end
end

$LOAD_PATH << File.dirname(__FILE__) + '/../lib'

RSpec.configure do |rspec|
  rspec.filter_run_when_matching(focus: true)
end

def klass
  described_class
end

def text_fixture(name)
  File.read(File.expand_path(__dir__ + "/../fixtures/#{name}.txt"))
end

class String
  def unindent
    indent = split("\n")
             .reject { |line| line.strip.empty? }
             .map { |line| line.index(/[^\s]/) }
             .compact.min || 0
    gsub(/^[[:blank:]]{#{indent}}/, '')
  end
end

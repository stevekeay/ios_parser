$LOAD_PATH << File.dirname(__FILE__) + '/../lib'
require 'pp'

def klass
  described_class
end

def text_fixture(name)
  File.read(File.expand_path(__dir__ + "/../fixtures/#{name}.txt"))
end

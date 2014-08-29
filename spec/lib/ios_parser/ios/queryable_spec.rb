require_relative '../../../spec_helper'
require 'ios_parser'

module IOSParser
  class IOS
    describe Queryable do

      let(:input) { <<-END }
policy-map mypolicy_in
 class some_service
  police 300000000 1000000 exceed-action policed-dscp-transmit
   set dscp cs1
 class my_service
  police 600000000 1000000 exceed-action policed-dscp-transmit
   set dscp cs2
   command_with_no_args
END

      let(:expectation) { 'set dscp cs1' }

      subject { IOSParser.parse(input).find(matcher).line }

      describe '#find' do
        context 'shortcut matcher' do

          describe String do
            let(:matcher) { 'set dscp cs1' }
            it { should == expectation }
          end

          describe Regexp do
            let(:matcher) { /set .* cs1/ }
            it { should == expectation }
          end

          describe Proc do
            let(:expectation) { 'command_with_no_args' }
            let(:matcher) { ->(c){ c.args.count == 1 } }
            it { should == expectation }
          end
        end

        context 'explicit matcher form of shortcut matcher' do
          describe String do
            let(:matcher) { { starts_with: 'set dscp cs1' } }
            it { should == expectation }
          end

          describe Regexp do
            let(:matcher) { { line: /set .* cs1/ } }
            it { should == expectation }
          end

          describe Proc do
            let(:expectation) { 'command_with_no_args' }
            let(:matcher) { { procedure: ->(c){ c.args.count == 1 } } }
            it { should == expectation }
          end
        end

        context 'matcher: contains' do
          describe String do
            let(:matcher) { { contains: 'dscp cs1' } }
            it { should == expectation }
          end

          describe Array do
            let(:matcher) { { contains: ['dscp', 'cs1'] } }
            it { should == expectation }
          end
        end

        context 'matcher: ends_with' do
          let(:expectation) { 'class my_service' }

          describe String do
            let(:matcher) { { ends_with: 'my_service' } }
            it { should == expectation }
          end

          describe Array do
            let(:matcher) { { ends_with: ['my_service'] } }
            it { should == expectation }
          end
        end

        context 'matcher: all' do
          let(:matcher) { { all: ['set', /cs1/] } }
          it { should == expectation }
        end

        context 'matcher: parent' do
          let(:matcher) { { parent: /police 3/ } }
          it { should == expectation }
        end

        context 'matcher: any' do
          let(:matcher) { { any: [/asdf/, /cs1/, /qwerwqe/] } }
          it { should == expectation }
        end

        context 'matcher: depth' do
          let(:matcher) { { depth: 3 } }
          it { should == expectation }
        end
      end

    end # describe Queryable
  end # class IOS
end # module IOSParser

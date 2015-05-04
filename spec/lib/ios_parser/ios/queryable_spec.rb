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
      let(:parsed) { IOSParser.parse(input) }
      subject { parsed.find(matcher).line }

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
            let(:matcher) { ->(c) { c.args.count == 1 } }
            it { should == expectation }
          end
        end # context 'shortcut matcher' do

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
            let(:matcher) { { procedure: ->(c) { c.args.count == 1 } } }
            it { should == expectation }
          end
        end # context 'explicit matcher form of shortcut matcher' do

        context 'matcher: contains' do
          describe String do
            let(:matcher) { { contains: 'dscp cs1' } }
            it { should == expectation }
          end

          describe Array do
            let(:matcher) { { contains: ['dscp', 'cs1'] } }
            it { should == expectation }
          end
        end # context 'matcher: contains' do

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
        end # context 'matcher: ends_with' do

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

        context 'matcher: none' do
          let(:matcher) do
            { none: [/policy/, /class/, /police/] }
          end
          it { should == expectation }
        end

        context 'matcher: not_all' do
          let(:matcher)  do
            {
              all: {
                none: /policy/,
                not: /class/,
                not_all: /police/
              }
            }
          end

          it do
            expect(parsed.find(not_all: [/policy/, /class/]).line)
              .to eq "policy-map mypolicy_in"
          end
          it { should == expectation }
        end

        context "matcher: any_child" do
          let(:matcher) { { not: { any_child: /dscp/ } } }
          it { should == expectation }
        end

        context "matcher: no_child" do
          let(:matcher) { { no_child: /dscp/ } }
          it { should == expectation }
        end
      end # describe '#find' do
    end # describe Queryable
  end # class IOS
end # module IOSParser

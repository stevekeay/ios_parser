require_relative '../spec_helper'
require 'ios_parser'

describe IOSParser do
  describe '.parse' do
    context 'with blank line at start' do
      it 'parses and extracts sections' do
        parser = IOSParser.parse("\ntest config")
        expect(parser.find_all(name: "test").count).to eq 1
      end
    end

    context 'with blank line in middle' do
      it 'parses and extracts sections' do
        parser = IOSParser.parse("preamble\n\ntest config")
        expect(parser.find_all(name: "test").count).to eq 1
      end
    end

    context 'indented region' do
      let(:input) { <<-END.unindent }
        policy-map mypolicy_in
         class myservice_service
          police 300000000 1000000 exceed-action policed-dscp-transmit
           set dscp cs1
         class other_service
          police 600000000 1000000 exceed-action policed-dscp-transmit
           set dscp cs2
           command_with_no_args
      END

      let(:output) do
        {
          commands:
            [{ args: ['policy-map', 'mypolicy_in'],
               commands:
                 [{ args: %w[class myservice_service],
                    commands: [{ args: ['police', 300_000_000, 1_000_000,
                                        'exceed-action',
                                        'policed-dscp-transmit'],
                                 commands: [
                                   { args: %w[set dscp cs1],
                                     commands: [], pos: 114, indent: 3 }
                                 ],
                                 pos: 50, indent: 2 }],
                    pos: 24, indent: 1 },

                  { args: %w[class other_service],
                    commands: [{ args: ['police', 600_000_000, 1_000_000,
                                        'exceed-action',
                                        'policed-dscp-transmit'],
                                 commands: [
                                   { args: %w[set dscp cs2],
                                     commands: [], pos: 214, indent: 3 },
                                   { args: ['command_with_no_args'],
                                     commands: [], pos: 230, indent: 3 }
                                 ],
                                 pos: 150, indent: 2 }],
                    pos: 128, indent: 1 }],
               pos: 0, indent: 0 }]
        }
      end

      subject { described_class.parse(input) }

      it('constructs the right AST') do
        should be_a IOSParser::IOS::Document
        expect(subject.to_hash).to eq output
      end
    end # context 'indented region'

    context 'partial outdent' do
      let(:input) do
        <<-END.unindent
        class-map match-any foobar
          description blah blah blah
         match access-group fred
        END
      end

      let(:output) do
        {
          commands:
            [
              {
                args: ['class-map', 'match-any', 'foobar'],
                commands: [
                  {
                    args: %w[description blah blah blah],
                    commands: [],
                    pos: 29,
                    indent: 1
                  },
                  {
                    args: ['match', 'access-group', 'fred'],
                    commands: [],
                    pos: 57,
                    indent: 1
                  }
                ],
                pos: 0,
                indent: 0
              }
            ]
        }
      end

      subject { described_class.parse(input) }

      it 'constructs the right AST' do
        should be_a IOSParser::IOS::Document
        actual = subject.to_hash
        expect(actual).to eq(output)
      end
    end # context "partial outdent" do

    context 'comment at end of line' do
      let(:input) do
        <<END.unindent
          description !
          switchport access vlan 2
END
      end

      subject { described_class.parse(input) }

      it 'parses both commands' do
        should be_a IOSParser::IOS::Document
        expect(subject.find(starts_with: 'description')).not_to be_nil
        expect(subject.find(starts_with: 'switchport')).not_to be_nil
      end
    end
  end # describe '.parse'
end # describe IOSParser

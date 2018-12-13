require_relative '../../spec_helper'
require 'ios_parser'
require 'ios_parser/lexer'

module IOSParser
  describe Lexer do
    describe '#call' do
      subject { klass.new.call(input) }

      let(:subject_pure) do
        IOSParser::PureLexer.new.call(input)
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
END

        let(:output) do
          ['policy-map', 'mypolicy_in', :EOL,
           :INDENT,
           'class', 'myservice_service', :EOL,
           :INDENT,
           'police', 300_000_000, 1_000_000, 'exceed-action',
           'policed-dscp-transmit', :EOL,
           :INDENT,
           'set', 'dscp', 'cs1', :EOL,
           :DEDENT, :DEDENT,
           'class', 'other_service', :EOL,
           :INDENT,
           'police', 600_000_000, 1_000_000, 'exceed-action',
           'policed-dscp-transmit', :EOL,
           :INDENT,
           'set', 'dscp', 'cs2', :EOL, :DEDENT, :DEDENT, :DEDENT]
        end

        subject { klass.new.call(input).map(&:value) }
        it('enclosed in symbols') { should == output }

        it('enclosed in symbols (using the pure ruby lexer)') do
          expect(subject_pure.map(&:value)).to eq output
        end
      end

      context 'ASR indented regions' do
        context 'indented region' do
          let(:input) { <<-END.unindent }
            router static
             vrf MGMT
              address-family ipv4 unicast
               0.0.0.0/0 1.2.3.4
              !
             !
            !
            router ospf 12345
             nsr
END

          let(:expectation) do
            ['router', 'static', :EOL,
             :INDENT, 'vrf', 'MGMT', :EOL,
             :INDENT, 'address-family', 'ipv4', 'unicast', :EOL,
             :INDENT, '0.0.0.0/0', '1.2.3.4', :EOL,
             :DEDENT, :DEDENT, :DEDENT,
             'router', 'ospf', 12_345, :EOL,
             :INDENT, 'nsr', :EOL,
             :DEDENT]
          end

          it 'pure' do
            tokens = IOSParser::PureLexer.new.call(input)
            expect(tokens.map(&:value)).to eq expectation
          end # it 'pure' do

          it 'default' do
            tokens = IOSParser.lexer.new.call(input)
            expect(tokens.map(&:value)).to eq expectation
          end # it 'c' do
        end # context 'indented region' do
      end # context 'ASR indented regions' do

      context 'banners' do
        let(:input) do
          <<-END.unindent
            banner foobar ^
            asdf 1234 9786 asdf
            line 2
            line 3
              ^
END
        end

        let(:output) do
          [[0, 1, 'banner'], [7, 1, 'foobar'],
           [14, 1, :BANNER_BEGIN],
           [16, 2, "asdf 1234 9786 asdf\nline 2\nline 3\n  "],
           [52, 5, :BANNER_END], [53, 5, :EOL]]
            .map { |pos, line, val| Token.new(val, pos, line) }
        end

        it('tokenized and enclosed in symbols') { should == output }

        it('tokenized and enclodes in symbols (using the pure ruby lexer)') do
          expect(subject_pure).to eq output
        end
      end

      context 'complex banner' do
        let(:input) do
          text_fixture('complex_banner')
        end

        let(:output) do
          content = text_fixture('complex_banner').lines[1..-2].join
          ['banner', 'exec', :BANNER_BEGIN, content, :BANNER_END, :EOL]
        end

        it { expect(subject.map(&:value)).to eq output }
        it { expect(subject_pure.map(&:value)).to eq output }
      end

      context 'complex eos banner' do
        let(:input) { "banner motd\n'''\nEOF\n" }

        let(:output) do
          content = input.lines[1..-2].join
          ['banner', 'motd', :BANNER_BEGIN, content, :BANNER_END, :EOL]
        end

        it { expect(subject.map(&:value)).to eq output }
        it { expect(subject_pure.map(&:value)).to eq output }
      end

      context 'decimal number' do
        let(:input) { 'boson levels at 93.2' }
        let(:output) { ['boson', 'levels', 'at', 93.2] }
        subject { klass.new.call(input).map(&:value) }
        it('converts to Float') { should == output }
      end

      context 'cryptographic certificate' do
        let(:input) do
          <<END.unindent
            crypto pki certificate chain TP-self-signed-0123456789
             certificate self-signed 01
              FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF
              EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE
              DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD AAAA
                    quit
            !
END
        end

        let(:output) do
          [[0, 1, 'crypto'],
           [7, 1, 'pki'],
           [11, 1, 'certificate'],
           [23, 1, 'chain'],
           [29, 1, 'TP-self-signed-0123456789'],
           [54, 1, :EOL],
           [56, 2, :INDENT],
           [56, 2, 'certificate'],
           [68, 2, 'self-signed'],
           [80, 2, '01'],
           [85, 3, :CERTIFICATE_BEGIN],
           [85, 3,
            'FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF '\
            'FFFFFFFF EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE '\
            'EEEEEEEE EEEEEEEE DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD '\
            'DDDDDDDD DDDDDDDD DDDDDDDD AAAA'],
           [323, 6, :CERTIFICATE_END],
           [323, 6, :EOL],
           [323, 7, :DEDENT]]
            .map { |pos, line, val| Token.new(val, pos, line) }
        end

        subject { klass.new.call(input) }

        it('tokenized') do
          expect(subject).to eq output
        end

        it('tokenized (using the pure ruby lexer)') do
          expect(subject_pure).to eq output
        end
      end

      context 'comments' do
        let(:input) { 'ip addr 127.0.0.0.1 ! asdfsdf' }
        let(:output) { ['ip', 'addr', '127.0.0.0.1'] }
        subject { klass.new.call(input).map(&:value) }
        it('dropped') { should == output }
      end

      context 'quoted octothorpe' do
        let(:input) { <<-EOS.unindent }
          vlan 1
           name "a #"
          vlan 2
           name d
      EOS

        let(:output) do
          [
            'vlan', 1, :EOL,
            :INDENT, 'name', '"a #"', :EOL,
            :DEDENT,
            'vlan', 2, :EOL,
            :INDENT, 'name', 'd', :EOL,
            :DEDENT
          ]
        end

        it { expect(subject_pure.map(&:value)).to eq output }
        it { expect(subject.map(&:value)).to eq output }
      end # context 'quoted octothorpe' do

      context 'vlan range' do
        let(:input) { 'switchport trunk allowed vlan 50-90' }
        let(:output) do
          [
            [0,  1, 'switchport'],
            [11, 1, 'trunk'],
            [17, 1, 'allowed'],
            [25, 1, 'vlan'],
            [30, 1, '50-90']
          ].map { |pos, line, val| Token.new(val, pos, line) }
        end
        it { should == output }
      end # context 'vlan range' do

      context 'partial dedent' do
        let(:input) do
          <<END.unindent
            class-map match-any foobar
              description blahblahblah
             match access-group fred
END
        end

        let(:output) do
          [
            'class-map', 'match-any', 'foobar', :EOL,
            :INDENT, 'description', 'blahblahblah', :EOL,
            'match', 'access-group', 'fred', :EOL,
            :DEDENT
          ]
        end

        it { expect(subject_pure.map(&:value)).to eq output }
      end

      context '# in the middle of a line is not a comment' do
        let(:input) { "vlan 1\n name #31337" }
        let(:output) { ['vlan', 1, :EOL, :INDENT, 'name', '#31337', :DEDENT] }

        it { expect(subject_pure.map(&:value)).to eq output }
        it { expect(subject.map(&:value)).to eq output }
      end

      context '# at the start of a line is a comment' do
        let(:input) { "vlan 1\n# comment\nvlan 2" }
        let(:output) { ['vlan', 1, :EOL, 'vlan', 2] }

        it { expect(subject_pure.map(&:value)).to eq output }
        it { expect(subject.map(&:value)).to eq output }
      end

      context '# after indentation is a comment' do
        let(:input) { "vlan 1\n # comment\nvlan 2" }
        let(:output) { ['vlan', 1, :EOL, :INDENT, :DEDENT, 'vlan', 2] }

        it { expect(subject_pure.map(&:value)).to eq output }
        it { expect(subject.map(&:value)).to eq output }
      end

      context 'unterminated quoted string' do
        let(:input) { '"asdf' }
        it 'raises a lex error' do
          expect { subject_pure }.to raise_error IOSParser::LexError
          expect { subject }.to raise_error IOSParser::LexError

          pattern = /Unterminated quoted string starting at 0: #{input}/
          expect { subject_pure }.to raise_error(pattern)
          expect { subject }.to raise_error(pattern)
        end
      end

      context 'subcommands separated by comment line' do
        let(:input) do
          <<-END.unindent
            router static
             address-family ipv4 unicast
             !
             address-family ipv6 unicast
          END
        end

        let(:expected) do
          expected_full.map(&:value)
        end

        let(:expected_full) do
          [
            [0, 1, 'router'], [7, 1, 'static'],
            [13, 1, :EOL],
            [15, 2, :INDENT],
            [15, 2, 'address-family'], [30, 2, 'ipv4'], [35, 2, 'unicast'],
            [42, 2, :EOL],
            [47, 4, 'address-family'], [62, 4, 'ipv6'], [67, 4, 'unicast'],
            [74, 4, :EOL],
            [74, 4, :DEDENT]
          ].map { |pos, line, val| Token.new(val, pos, line) }
        end

        it 'lexes both subcommands' do
          expect(subject.map(&:value)).to eq expected
        end

        it 'lexes both subcommands (with the pure ruby lexer)' do
          expect(subject_pure.map(&:value)).to eq expected
        end

        it 'lexes position and line' do
          expect(subject).to eq expected_full
        end

        it 'lexes position and line (with the pure ruby lexer)' do
          expect(subject_pure).to eq expected_full
        end
      end
    end
  end
end

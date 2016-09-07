require_relative '../../spec_helper'
require 'ios_parser'
require 'ios_parser/lexer'

module IOSParser
  describe Lexer do
    it 'should load the appropriate constants' do
      [
        FFILexer,
        PureLexer
      ]
    end

    describe '#call' do
      let(:pure_values) { PureLexer.new.call(input).map(&:last) }
      let(:ffi_values) { FFILexer.new.call(input).map(&:last) }

      let(:pure_tokens) { PureLexer.new.call(input) }
      let(:ffi_tokens) { FFILexer.new.call(input) }

      context 'indented region' do
        let(:input) { <<-END }
policy-map mypolicy_in
 class myservice_service
  police 300000000 1000000 exceed-action policed-dscp-transmit
   set dscp cs1
 class other_service
  police 600000000 1000000 exceed-action policed-dscp-transmit
   set dscp cs2
END

        let(:expected) do
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

        it { expect(pure_values).to eq(expected) }
        it { expect(ffi_values).to eq(expected) }
      end

      context 'simple indented region' do
        let(:input) { <<-END }
zero
 one
  two
 one
END

        let(:expected) do
          [
            'zero', :EOL,
            :INDENT, 'one', :EOL,
            :INDENT, 'two', :EOL,
            :DEDENT, 'one', :EOL,
            :DEDENT
          ]
        end

        it { expect(pure_values).to eq(expected) }
        it { expect(ffi_values).to eq(expected) }
      end

      context 'ASR indented regions' do
        context 'indented region' do
          let(:input) { <<-END }
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

          let(:expected) do
            ['router', 'static', :EOL,
             :INDENT, 'vrf', 'MGMT', :EOL,
             :INDENT, 'address-family', 'ipv4', 'unicast', :EOL,
             :INDENT, '0.0.0.0/0', '1.2.3.4', :EOL,
             :DEDENT, :DEDENT, :DEDENT,
             'router', 'ospf', 12_345, :EOL,
             :INDENT, 'nsr', :EOL,
             :DEDENT]
          end

          it { expect(pure_values).to eq(expected) }
          it { expect(ffi_values).to eq(expected) }
        end # context 'indented region' do
      end # context 'ASR indented regions' do

      context 'banners' do
        let(:input) do
          <<-END
banner foobar ^
asdf 1234 9786 asdf
line 2
line 3
  ^
END
        end

        let(:expected) do
          [[0, 'banner'], [7, 'foobar'], [14, :BANNER_BEGIN],
           [16, "asdf 1234 9786 asdf\nline 2\nline 3\n  "],
           [52, :BANNER_END], [53, :EOL]]
        end

        it { expect(pure_tokens).to eq(expected) }
        it { expect(ffi_tokens).to eq(expected) }
      end

      context 'complex banner' do
        let(:input) { text_fixture('complex_banner') }

        let(:expected) do
          content = text_fixture('complex_banner').lines[1..-2].join
          ['banner', 'exec', :BANNER_BEGIN, content, :BANNER_END, :EOL]
        end

        it { expect(pure_values).to eq(expected) }
        it { expect(ffi_values).to eq(expected) }
      end

      context 'decimal number' do
        let(:input) { 'boson levels at 93.2' }
        let(:expected) { ['boson', 'levels', 'at', 93.2] }
        it { expect(pure_values).to eq(expected) }
        it { expect(ffi_values).to eq(expected) }
      end

      context 'cryptographic certificate' do
        let(:input) do
          <<END
crypto pki certificate chain TP-self-signed-0123456789
 certificate self-signed 01
  FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF
  EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE
  DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD AAAA
        quit
!
END
        end

        let(:expected) do
          [[0, 'crypto'],
           [7, 'pki'],
           [11, 'certificate'],
           [23, 'chain'],
           [29, 'TP-self-signed-0123456789'],
           [54, :EOL],
           [56, :INDENT],
           [56, 'certificate'],
           [68, 'self-signed'],
           [80, '01'],
           [85, :CERTIFICATE_BEGIN],
           [85,
            'FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF '\
            'FFFFFFFF EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE '\
            'EEEEEEEE EEEEEEEE DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD '\
            'DDDDDDDD DDDDDDDD DDDDDDDD AAAA'],
           [323, :CERTIFICATE_END],
           [323, :EOL],
           [323, :DEDENT]]
        end

        it { expect(pure_tokens).to eq(expected) }
        it { expect(ffi_tokens).to eq(expected) }
      end

      context 'comments' do
        let(:input) { 'ip addr 127.0.0.0.1 ! asdfsdf' }
        let(:expected) { ['ip', 'addr', '127.0.0.0.1'] }
        it { expect(pure_values).to eq(expected) }
        it { expect(ffi_values).to eq(expected) }
      end

      context 'quoted octothorpe' do
        let(:input) { <<-EOS }
vlan 1
 name "a #"
vlan 2
 name d
      EOS

        let(:expected) do
          [
            'vlan', 1, :EOL,
            :INDENT, 'name', '"a #"', :EOL,
            :DEDENT,
            'vlan', 2, :EOL,
            :INDENT, 'name', 'd', :EOL,
            :DEDENT
          ]
        end

        it { expect(pure_values).to eq(expected) }
        it { expect(ffi_values).to eq(expected) }
      end # context 'quoted octothorpe' do

      context 'vlan range' do
        let(:input) { 'switchport trunk allowed vlan 50-90' }

        let(:expected) do
          [
            [0, 'switchport'],
            [11, 'trunk'],
            [17, 'allowed'],
            [25, 'vlan'],
            [30, '50-90']
          ]
        end

        it { expect(pure_tokens).to eq(expected) }
        it { expect(ffi_tokens).to eq(expected) }
      end # context 'vlan range' do

      context 'partial dedent' do
        let(:input) do
          <<END
class-map match-any foobar
  description blahblahblah
 match access-group fred
END
        end

        let(:expected) do
          [
            'class-map', 'match-any', 'foobar', :EOL,
            :INDENT, 'description', 'blahblahblah', :EOL,
            'match', 'access-group', 'fred', :EOL,
            :DEDENT
          ]
        end

        it { expect(pure_values).to eq(expected) }
        it { expect(ffi_values).to eq(expected) }
      end

      context '# in the middle of a line is not a comment' do
        let(:input) { "vlan 1\n name #31337" }
        let(:expected) { ['vlan', 1, :EOL, :INDENT, 'name', '#31337', :DEDENT] }
        it { expect(pure_values).to eq(expected) }
        it { expect(ffi_values).to eq(expected) }
      end

      context '# at the start of a line is a comment' do
        let(:input) { "vlan 1\n# comment\nvlan 2" }
        let(:expected) { ['vlan', 1, :EOL, 'vlan', 2] }
        it { expect(pure_values).to eq(expected) }
        it { expect(ffi_values).to eq(expected) }
      end

      context '# after indentation is a comment' do
        let(:input) { "vlan 1\n # comment\nvlan 2" }
        let(:expected) { ['vlan', 1, :EOL, :INDENT, :DEDENT, 'vlan', 2] }
        it { expect(pure_values).to eq(expected) }
        it { expect(ffi_values).to eq(expected) }
      end

      context 'unterminated quoted string' do
        let(:input) { '"asdf' }

        it 'raises a lex error' do
          expect { pure_tokens }.to raise_error IOSParser::LexError
          expect { ffi_tokens }.to raise_error IOSParser::LexError

          pattern = /Unterminated quoted string starting at 0: #{input}/
          expect { pure_tokens }.to raise_error(pattern)
          expect { ffi_tokens }.to raise_error(pattern)
        end
      end
    end
  end
end

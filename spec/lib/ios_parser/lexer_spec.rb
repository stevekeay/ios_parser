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
        let(:input) { <<-END }
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
           'set', 'dscp', 'cs2', :EOL, :DEDENT, :DEDENT, :DEDENT
          ]
        end

        subject { klass.new.call(input).map(&:last) }
        it('enclosed in symbols') { should == output }

        it('enclosed in symbols (using the pure ruby lexer)') do
          expect(subject_pure.map(&:last)).to eq output
        end
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

          let(:expectation) do
            ["router", "static", :EOL,
             :INDENT, "vrf", "MGMT", :EOL,
             :INDENT, "address-family", "ipv4", "unicast", :EOL,
             :INDENT, "0.0.0.0/0", "1.2.3.4", :EOL,
             :DEDENT, :DEDENT, :DEDENT,
             "router", "ospf", 12_345, :EOL,
             :INDENT, "nsr", :EOL,
             :DEDENT
            ]
          end

          it 'pure' do
            tokens = IOSParser::PureLexer.new.call(input)
            expect(tokens.map(&:last)).to eq expectation
          end # it 'pure' do

          it 'c' do
            tokens = IOSParser::CLexer.new.call(input)
            expect(tokens.map(&:last)).to eq expectation
          end # it 'c' do
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

        let(:output) do
          [[0, 'banner'], [7, 'foobar'], [14, :BANNER_BEGIN],
           [16, "asdf 1234 9786 asdf\nline 2\nline 3\n  "],
           [52, :BANNER_END], [53, :EOL]]
        end

        it('tokenized and enclosed in symbols') { should == output }

        it('tokenized and enclodes in symbols (using the pure ruby lexer)') do
          expect(subject_pure).to eq output
        end
      end

      context 'decimal number' do
        let(:input) { 'boson levels at 93.2' }
        let(:output) { ['boson', 'levels', 'at', 93.2] }
        subject { klass.new.call(input).map(&:last) }
        it('converts to Float') { should == output }
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

        let(:output) do
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
           [323, :DEDENT]
          ]
        end

        subject { klass.new.call(input) }
        it('tokenized') { expect(subject).to eq output }

        it('tokenized (using the pure ruby lexer)') do
          expect(subject_pure).to eq output
        end
      end

      context 'comments' do
        let(:input) { 'ip addr 127.0.0.0.1 ! asdfsdf' }
        let(:output) { ['ip', 'addr', '127.0.0.0.1'] }
        subject { klass.new.call(input).map(&:last) }
        it('dropped') { should == output }
      end
    end
  end
end

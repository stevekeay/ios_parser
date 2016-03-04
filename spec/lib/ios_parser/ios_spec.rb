require_relative '../../spec_helper'
require 'ios_parser'
require 'ios_parser/lexer'

module IOSParser
  describe IOS do
    context 'indented region' do
      let(:input) { <<-END }
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
                 [{ args: %w(class myservice_service),
                    commands: [{ args: ['police', 300_000_000, 1_000_000,
                                        'exceed-action',
                                        'policed-dscp-transmit'],
                                 commands: [{ args: %w(set dscp cs1),
                                              commands: [], pos: 114 }],
                                 pos: 50
                               }],
                    pos: 24
                  },

                  { args: %w(class other_service),
                    commands: [{ args: ['police', 600_000_000, 1_000_000,
                                        'exceed-action',
                                        'policed-dscp-transmit'],
                                 commands: [{ args: %w(set dscp cs2),
                                              commands: [], pos: 214 },
                                            { args: ['command_with_no_args'],
                                              commands: [], pos: 230 }],
                                 pos: 150
                               }],
                    pos: 128
                  }],
               pos: 0
             }]
        }
      end

      describe '#call' do
        subject { klass.new.call(input) }
        let(:subject_pure) do
          klass.new(lexer: IOSParser::PureLexer.new).call(input)
        end

        it('constructs the right AST') { expect(subject.to_hash).to eq output }

        it('constructs the right AST (using the pure-ruby lexer)') do
          expect(subject_pure.to_hash[:commands]).to eq output[:commands]
        end

        it('can be searched by an exact command') do
          expect(subject.find_all(name: 'set').map(&:to_hash))
            .to eq [{ args: %w(set dscp cs1),
                      commands: [], pos: 114 },
                    { args: %w(set dscp cs2),
                      commands: [], pos: 214 }]
        end

        context 'can be searched by name and the first argument' do
          let(:result) do
            expect(subject.find_all(starts_with: starts_with).map(&:to_hash))
              .to eq expectation
          end

          let(:expectation) { [output[:commands][0][:commands][1]] }

          context 'with an array of strings' do
            let(:starts_with) { %w(class other_service) }
            it { result }
          end

          context 'with an array of regular expressions' do
            let(:starts_with) { [/.lass/, /^other_[a-z]+$/] }
            it { result }
          end

          context 'with a string, space-separated' do
            let(:starts_with) { 'class other_service' }
            it { result }
          end

          context 'integer argument' do
            let(:expectation) do
              [{ args: ['police', 300_000_000, 1_000_000, 'exceed-action',
                        'policed-dscp-transmit'],
                 commands: [{ args: %w(set dscp cs1),
                              commands: [], pos: 114 }],
                 pos: 50
               }]
            end

            context 'integer query' do
              let(:starts_with) { ['police', 300_000_000] }
              it { result }
            end # context 'integer query'

            context 'string query' do
              let(:starts_with) { 'police 300000000' }
              it { result }
            end # context 'string query'
          end
        end # context 'integer argument'

        context 'nested search' do
          it 'queries can be chained' do
            expect(subject
                    .find('policy-map').find('class').find('police')
                    .find('set')
                    .to_hash)
              .to eq(args: %w(set dscp cs1),
                     commands: [], pos: 114)
          end
        end # context 'nested search'

        context 'pass a block' do
          it 'is evaluated for each matching command' do
            ary = []
            subject.find_all('class') { |cmd| ary << cmd.args[1] }
            expect(ary).to eq %w(myservice_service other_service)
          end
        end # context 'pass a block'
      end # end context 'indented region'

      context '2950' do
        let(:input) { <<END }
hostname myswitch1
vlan 3
 name MyVlanName
interface FastEthernet0/1
 speed 100
END

        let(:output) { klass.new.call(input) }

        it { expect(output.find('hostname').args[1]).to eq 'myswitch1' }

        it('extracts vlan names') do
          expect(output.find('vlan 3').find('name').args[1])
            .to eq 'MyVlanName'
        end

        it('extracts interface speed') do
          expect(output.find('interface FastEthernet0/1').find('speed').args[1])
            .to eq 100
        end

        it('parses snmp commands') do
          snmp_command = <<-END
snmp-server group my_group v3 auth read my_ro
        END
          result = klass.new.call(snmp_command)
          expect(result[0].name).to eq 'snmp-server'
        end

        it('parses a simple alias') do
          simple_alias = 'alias exec stat sh int | inc [1-9].*ignored|[1-9].*'\
                         "resets|Ethernet0|minute\n"
          result = klass.new.call(simple_alias)
          expect(result[0].name).to eq 'alias'
        end

        it('parses a complex alias') do
          complex_alias = 'alias exec stats sh int | inc Ether.*'\
                          '(con|Loop.*is up|Vlan.*is up|Port-.*is up|'\
                          "input rate [^0]|output rate [^0]\n"
          result = klass.new.call(complex_alias)
          expect(result[0].name).to eq 'alias'
          expect(result[0].args.last).to eq '[^0]'
        end

        it('parses a banner') do
          banner_text = <<-END


Lorem ipsum dolor sit amet, consectetur adipiscing elit,
sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.


END
          banner_command = "banner exec ^C#{banner_text}^C\n"

          result = klass.new.call(banner_command)
          expect(result[0].args[2]).to eq banner_text
        end

        it('parses a crypto trustpoint section') do
          text = <<END
crypto pki trustpoint TP-self-signed-0123456789
 enrollment selfsigned
 subject-name cn=IOS-Self-Signed-Certificate-1234567890
 revocation-check none
 rsakeypair TP-self-signed-2345678901
END
          result = klass.new.call(text)
          expect(result).not_to be_nil
        end

        it('parses a crypto certificate section') do
          sp = ' '
          text = <<END
crypto pki certificate chain TP-self-signed-1234567890
 certificate self-signed 01
  FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF#{sp}
  EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE#{sp}
  DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD#{sp}
  CCCCCCCC CCCCCCCC
  quit

END

          result = klass.new.call(text)
          expect(result).not_to be_nil
        end

        it('parses an MST configuration section') do
          text = <<END
spanning-tree mst configuration
 name MyMSTConfig
 revision 1
 instance 1 vlan 1-59, 4000
 instance 2 vlan 90-99
 instance 3 vlan 100-1500
 instance 4 vlan 2000-3500, 4000
END

          result = klass.new.call(text)
          expect(result).not_to be_nil
        end
      end # context '2950'

      it('finds various ip route formats') do
        text = <<END
ip route 10.0.0.1 255.255.255.255 Null0
ip route 9.9.9.199 255.255.255.255 42.42.42.142 name PONIES
ip route vrf Mgmt-intf 0.0.0.0 0.0.0.0 9.9.9.199
ip route 0.0.0.0/0 11.11.0.111 120
END

        result = klass.new.call(text)

        cmd_ary = [
          { args: ['ip', 'route', '10.0.0.1', '255.255.255.255',
                   'Null0'],
            commands: [], pos: 0 },
          { args: ['ip', 'route', '9.9.9.199', '255.255.255.255',
                   '42.42.42.142', 'name', 'PONIES'],
            commands: [], pos: 40 },
          { args: ['ip', 'route', 'vrf', 'Mgmt-intf', '0.0.0.0',
                   '0.0.0.0', '9.9.9.199'],
            commands: [], pos: 100 },
          { args: ['ip', 'route', '0.0.0.0/0', '11.11.0.111', 120],
            commands: [], pos: 149 }
        ]

        expect(result.find_all('ip route').map(&:to_hash)).to eq(cmd_ary)

        expect(result.find_all('ip route 9.9.9.199').length).to eq 1

        cmd_hash = { args: ['ip', 'route', '9.9.9.199', '255.255.255.255',
                            '42.42.42.142', 'name', 'PONIES'],
                     commands: [], pos: 40 }
        expect(result.find('ip route 9.9.9.199').to_hash).to eq(cmd_hash)
      end # end context '#call'

      describe '#to_s' do
        subject { klass.new.call(input) }
        let(:police2) { <<END }
  police 600000000 1000000 exceed-action policed-dscp-transmit
   set dscp cs2
   command_with_no_args
END

        it('returns the string form of the original command(s)') do
          expect(subject.to_s).to eq input
          expect(subject.find('policy-map').to_s).to eq input
          expect(subject.find('command_with_no_args').to_s)
            .to eq "   command_with_no_args\n"
          expect(subject.find('police 600000000').to_s).to eq police2
        end

        context 'with dedent: true' do
          it('returns the original without extra indentation') do
            expect(subject.find('police 600000000').to_s(dedent: true))
              .to eq police2.lines.map { |l| l[2..-1] }.join
          end
        end
      end # describe '#to_s'

      describe '#each' do
        subject { klass.new.call(input) }
        it 'traverses the AST' do
          actual_paths = subject.map(&:path)
          expected_paths = [
            [],
            ['policy-map mypolicy_in'],
            ['policy-map mypolicy_in',
             'class myservice_service'],
            ['policy-map mypolicy_in',
             'class myservice_service',
             'police 300000000 1000000 exceed-action policed-dscp-transmit'],
            ['policy-map mypolicy_in'],
            ['policy-map mypolicy_in',
             'class other_service'],
            ['policy-map mypolicy_in',
             'class other_service',
             'police 600000000 1000000 exceed-action policed-dscp-transmit'],
            ['policy-map mypolicy_in',
             'class other_service',
             'police 600000000 1000000 exceed-action policed-dscp-transmit']
          ]
          expect(actual_paths).to eq(expected_paths)
        end
      end # describe '#each'
    end # context 'indented region'

    context 'empty source' do
      context 'when input is not a string' do
        it 'raises ArgumentError' do
          expect { klass.new.call [] }.to raise_error ArgumentError
          expect { klass.new.call nil }.to raise_error ArgumentError
          expect { klass.new.call 666 }.to raise_error ArgumentError
        end
      end # context 'when input is not a string' do
    end # context 'empty source' do
  end # end describe IOS
end # end module IOSParser

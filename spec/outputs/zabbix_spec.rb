require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/zabbix"
require "logstash/codecs/plain"
require "logstash/event"
require "zabbix_protocol"
require "socket"
require "timeout"
require "longshoreman"
require_relative "../helpers/zabbix_helper"

RSpec.configure do |c|
  c.include ZabbixHelper
end

NAME = "logstash-output-zabbix-#{rand(999).to_s}"
IMAGE = "untergeek/logstash_output_zabbix_rspec"
TAG = "latest"
ZABBIX_PORT = 10051

describe LogStash::Outputs::Zabbix do
  # Building block "lets"
  let(:port) { ZABBIX_PORT }
  let(:host) { "127.0.0.1" }
  let(:timeout) { 1 }
  let(:timestamp) { "2015-04-15T15:39:42Z" }
  let(:epoch) { 1429112382 } # This is the epoch value of the above timestamp
  let(:zabhost) { "zabbix.example.com" }
  let(:zabkey) { "zabbix.key" }
  let(:message) { "This is a log entry." }

  # Assembled "lets"
  let(:event_hash) {
    {
      "@timestamp" => timestamp,
      "message" => message,
      "zabhost" => zabhost,
      "zabkey"  => zabkey,
    }
  }
  let(:multi_value) {
    {
      "@timestamp" => timestamp,
      "message"    => message,
      "zabhost"    => zabhost,
      "key1"       => "multi1",
      "val1"       => "value1",
      "key2"       => "multi2",
      "val2"       => "value2",
    }
  }
  let(:zabout) {
    {
      "zabbix_server_host" => host,
      "zabbix_server_port" => port,
      "zabbix_host"        => "zabhost",
      "zabbix_key"         => "zabkey",
      "timeout"            => timeout,
    }
  }
  let(:mzabout) {
    {
      "zabbix_server_host" => host,
      "zabbix_server_port" => port,
      "zabbix_host"        => "zabhost",
      "multi_value"        => ["key1", "val1", "key2", "val2"],
      "timeout"            => timeout,
    }
  }

  # Finished object "lets"
  let(:string_event) { LogStash::Event.new(event_hash) }
  let(:output) { LogStash::Outputs::Zabbix.new(zabout) }

  before do
    output.register
  end

  describe "Unit Tests" do

    describe "#field_check" do

      context "when expected field not found" do
        subject { output.field_check(string_event, "not_appearing") }
        it "should return false" do
          expect(subject).to eq(false)
        end
      end

      context "when expected field found" do
        subject { output.field_check(string_event, "zabhost") }
        it "should return true" do
          expect(subject).to eq(true)
        end
      end

    end # "#field_check"

    describe "#format_request (single key/value pair)" do

      context "when it receives an event" do
        # {
        #   "request" => "sender data",
        #   "data" => [{
        #     "host" => "zabbix.example.com",
        #     "key" => "zabbix.key",
        #     "value" => "This is a log entry.",
        #     "clock" => 1429112382
        #   }],
        #   "clock" => 1429112394
        # }
        subject { output.format_request(string_event) }
        it "should return a Zabbix sender data object with the correct host" do
          expect(subject['data'][0]['host']).to eq(zabhost)
        end
        it "should return a Zabbix sender data object with the correct key" do
          expect(subject['data'][0]['key']).to eq(zabkey)
        end
        it "should return a Zabbix sender data object with the correct value" do
          expect(subject['data'][0]['value']).to eq(message)
        end
        it "should return a Zabbix sender data object with the correct clock from @timestamp" do
          expect(subject['data'][0]['clock']).to eq(epoch)
        end
        it "should return a Zabbix sender data object with the correct clock" do
          diff = Time.now.to_i - subject['clock']
          expect(diff).to be < 3 # It should take less than 3 seconds for this.
        end
      end

    end # "#format_request (single key/value pair)"

    describe "#format_request (multiple key/value pairs)" do
      let(:multival_event) { LogStash::Event.new(multi_value) }
      let(:m_output) { LogStash::Outputs::Zabbix.new(mzabout) }

      context "when it receives an event and is configured for multiple values" do
        subject { m_output.format_request(multival_event) }
        it "should return a Zabbix sender data object with a data array" do
          expect(subject['data'].length).to eq(2)
        end
        it "should return a Zabbix sender data object with the correct host [0]" do
          expect(subject['data'][0]['host']).to eq(zabhost)
        end
        it "should return a Zabbix sender data object with the correct key [0]" do
          expect(subject['data'][0]['key']).to eq('multi1')
        end
        it "should return a Zabbix sender data object with the correct value [0]" do
          expect(subject['data'][0]['value']).to eq('value1')
        end
        it "should return a Zabbix sender data object with the correct clock from @timestamp [0]" do
          expect(subject['data'][0]['clock']).to eq(epoch)
        end
        it "should return a Zabbix sender data object with the correct host [1]" do
          expect(subject['data'][1]['host']).to eq(zabhost)
        end
        it "should return a Zabbix sender data object with the correct key [1]" do
          expect(subject['data'][1]['key']).to eq('multi2')
        end
        it "should return a Zabbix sender data object with the correct value [1]" do
          expect(subject['data'][1]['value']).to eq('value2')
        end
        it "should return a Zabbix sender data object with the correct clock from @timestamp [1]" do
          expect(subject['data'][1]['clock']).to eq(epoch)
        end
        it "should return a Zabbix sender data object with the correct clock" do
          diff = Time.now.to_i - subject['clock']
          expect(diff).to be < 3 # It should take less than 3 seconds for this.
        end
      end

    end # "#format_request (multiple key/value pairs)"

    describe "#response_check" do

      context "when it receives a success value" do
        subject { output.response_check(string_event, { "response" => "success" } ) }
        it "should return true" do
          expect(subject).to eq(true)
        end
      end

      context "when it receives a non-success value" do
        subject { output.response_check(string_event, { "response" => "fail" } ) }
        it "should return false" do
          expect(subject).to eq(false)
        end
      end

      context "when it receives a non-hash value" do
        subject { output.response_check(string_event, "foo" ) }
        it "should return false" do
          expect(subject).to eq(false)
        end
      end

    end # "#response_check"

    describe "#info_check" do

      context "when it receives a success value" do
        let(:success_msg) { {"response" => "success", "info" => "processed 1; Failed 0; Total 1; seconds spent: 0.000018"} }
        subject { output.info_check(string_event, success_msg) }
        it "should return true" do
          expect(subject).to eq(true)
        end
      end

      context "when it receives a non-success value" do
        let(:fail_msg) { {"response" => "success", "info" => "processed 0; Failed 1; Total 1; seconds spent: 0.000018"} }
        subject { output.info_check(string_event, fail_msg) }
        it "should return false" do
          expect(subject).to eq(false)
        end
      end

      context "when it receives an atypical value" do
        subject { output.info_check(string_event, "foo") }
        it "should return false" do
          expect(subject).to eq(false)
        end
      end

    end # "#info_check"

  end # "Unit Tests"

  describe "Integration Tests", :integration => true do

    before(:all) do
      @zabbix = Longshoreman.new(
        "#{IMAGE}:#{TAG}",    # Image to use
        NAME,                 # Container name
        {
          "Cmd" => ["run"],
          "Tty" => true,
        }                     # Extra options, if any
      )
      zabbix_server_up?(@zabbix.ip, @zabbix.container.rport(ZABBIX_PORT))
    end

    after(:all) do
      @zabbix.cleanup
    end

    describe "#tcp_send", :integration => true do
      let(:port) { @zabbix.container.rport(ZABBIX_PORT) }
      let(:host) { @zabbix.ip }

      context "when the Zabbix server responds with 'success'" do
        subject { output.tcp_send(string_event) }
        it "should return true" do
          expect(subject).to eq(true)
        end
      end

      context "when the Zabbix server responds that some items were unsuccessful" do
        let(:zabhost) { "something_else.example.com" }
        subject { output.tcp_send(string_event) }
        it "should still return true" do
          expect(subject).to eq(true)
        end
      end

      context "when multiple values are sent" do
        let(:port) { @zabbix.container.rport(ZABBIX_PORT) }
        let(:host) { @zabbix.ip }
        let(:multival_event) { LogStash::Event.new(multi_value) }
        let(:m_output) { LogStash::Outputs::Zabbix.new(mzabout) }

        subject { m_output.tcp_send(multival_event) }
        it "should return true" do
          expect(subject).to eq(true)
        end
      end

    end # "#tcp_send", :integration => true

    describe "#send_to_zabbix", :integration => true do
      let(:port) { @zabbix.container.rport(ZABBIX_PORT) }
      let(:host) { @zabbix.ip }

      context "when an event is sent successfully" do
        subject { output.send_to_zabbix(string_event) }
        it "should return true" do
          expect(subject).to eq(true)
        end
      end

      context "when the Zabbix server cannot connect", :integration => true do
        let(:host) { "172.19.74.123" }
        let(:port) { 12345 }
        subject { output.send_to_zabbix(string_event) }
        it "should timeout and return false" do
          expect(subject).to eq(false)
        end
      end

    end # "#send_to_zabbix", :integration => true

  end # "Integration Tests", :integration => true

end # describe LogStash::Outputs::Zabbix

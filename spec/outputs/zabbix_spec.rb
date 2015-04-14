require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/zabbix"
require "logstash/codecs/plain"
require "logstash/event"
require "socket"
require "timeout"
require "docker"

# This is used to ensure the Docker instance is up and running
def port_open?(ip, port, seconds=1)
  Timeout::timeout(seconds) do
    begin
      TCPSocket.new(ip, port).close
      true
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      false
    end
  end
rescue Timeout::Error
  false
end

describe LogStash::Outputs::Zabbix do
  let(:port) { 10051 }
  let(:host) { "127.0.0.1" }
  let(:zabhost) { "zabbix.example.com" }
  let(:zabkey) { "zabbix.key" }
  let(:message) { "This is a log entry." }
  let(:event_hash) {
    {
      "message" => message,
      "zabhost" => zabhost,
      "zabkey"  => zabkey,
    }
  }
  let(:zabout) {
    {
      "zabbix_server_host" => host,
      "zabbix_server_port" => port,
      "zabbix_host" => "zabhost",
      "zabbix_key" => "zabkey",
      "zabbix_value" => "message",
    }
  }

  let(:string_event) { LogStash::Event.new(event_hash) }
  let(:output) { LogStash::Outputs::Zabbix.new(zabout) }
  let(:server) { Mocks::ZabbixServer.new }
  let(:success_msg) { {"response" => "success", "info" => "processed 1; Failed 0; Total 1; seconds spent: 0.000018"} }
  let(:fail_msg) { {"response" => "success", "info" => "processed 0; Failed 1; Total 1; seconds spent: 0.000018"} }

  before do
    output.register
  end

  describe "Unit Tests" do
    describe "#field_check" do
      context "when expected field not found" do
        subject { output.field_check(:string_event, "not_appearing") }
        it "should return false" do
          expect(subject).to eq(false)
        end
      end
      context "when expected field found" do
        subject { output.field_check(:string_event, "zabhost") }
        it "should return true" do
          expect(subject).to eq(false)
        end
      end
    end

    describe "#format_request" do
      subject { output.format_request(string_event) }
      it "should return a Zabbix sender data object" do
        val = {
          "request" => "sender data",
          "data" => [{
            "host" => "zabbix.example.com",
            "key" => "zabbix.key",
            "value" => "This is a log entry."
          }]
        }
        expect(subject).to eq(val)
      end
    end

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
    end

    describe "#info_check" do
      context "when it receives a success value" do
        subject { output.info_check(string_event, success_msg) }
        it "should return true" do
          expect(subject).to eq(true)
        end
      end

      context "when it receives a non-success value" do
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
    end

  end

  describe "Integration Tests", :integration => true do
    # Let the crazy one-liner definition begin:
    # Docker.url.split(':')[1][2..-1]
    # Docker.url = tcp://192.168.123.205:2375
    #   split(':') = ["tcp", "//192.168.123.205", "2375"]
    #   [1] = "//192.168.123.205"
    #   [2..-1] = "192.168.123.205"
    # This last bit prunes the leading //
    let(:ip) { Docker.url.split(':')[1][2..-1] }
    let(:remote_zabbix) {
      { "zabbix_server_host" => ip,
        "zabbix_host" => "zabhost",
        "zabbix_key" => "zabkey",
        "zabbix_value" => "message",
        "timeout" => 3,
      }
    }

    let(:output) { LogStash::Outputs::Zabbix.new(remote_zabbix) }

    before(:all) do
      zabbix_ip = Docker.url.split(':')[1][2..-1]
      port = 10051
      container = Docker::Container.create(
        "name" => "zabbix_output_test",
        "Cmd" => ["run"],
        "Image" => "untergeek/logstash_output_zabbix_rspec",
        "ExposedPorts" => { "#{port}/tcp" => {} },
        "Tty" => true,
        "HostConfig" => {
          "PortBindings" => {
            "#{port}/tcp" => [
              {
                "HostIp" => "",
                "HostPort" => "#{port}"
              }
            ]
          }
        }
      )
      container.start
      # Wait up to 10 seconds to connect to Zabbix
      running = false
      10.times do
        if port_open?(zabbix_ip, port)
          running = true
        else
          sleep 1
        end
      end
      if !running
        puts "Connection to #{zabbix_ip}:#{port} timed out"
      end
    end

    after(:all) do
      container = Docker::Container.get('zabbix_output_test')
      container.stop
      container.delete(:force => true)
    end

    describe "#tcp_send", :integration => true do
      context "when the Zabbix server responds with 'success'" do
        subject { output.tcp_send(string_event) }
        it "should return true" do
          expect(subject).to eq(true)
        end
      end

      context "when the Zabbix server responds that some items were unsuccessful" do
        let(:string_event) {
          {
            "message" => "This is a log entry.",
            "zabhost" => "something_else.example.com",
            "zabkey" => "zabbix.key",
            "zabvalue" => "value",
          }
        }
        subject { output.tcp_send(string_event) }
        it "should still return true" do
          expect(subject).to eq(true)
        end
      end

    end

    describe "#send_to_zabbix", :integration => true do
      context "when an event is sent successfully" do
        subject { output.send_to_zabbix(string_event) }
        it "should return true" do
          expect(subject).to eq(true)
        end
      end

      context "when the Zabbix server cannot connect", :integration => true do
        let(:output) { LogStash::Outputs::Zabbix.new({
          "zabbix_server_host" => "172.19.74.123", # Arbitrary private IP
          "zabbix_server_port" => 12345, # Arbitrary bad port
          "zabbix_host" => "zabhost",
          "zabbix_key" => "zabkey",
          "zabbix_value" => "message",
        }) }
        subject { output.send_to_zabbix(string_event) }
        it "should timeout and return false" do
          expect(subject).to eq(false)
        end
      end

    end

  end

end

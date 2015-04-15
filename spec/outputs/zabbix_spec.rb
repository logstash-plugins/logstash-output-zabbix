require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/zabbix"
require "logstash/codecs/plain"
require "logstash/event"
require "zabbix_protocol"
require "socket"
require "timeout"
require "docker"


CONTAINER_NAME = "zabbix_container_" + rand(99).to_s

# This is used to ensure the Docker Zabbix port is up and running
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

def get_docker_ip
  # Let the crazy one-liner definition begin:
  # Docker.url.split(':')[1][2..-1]
  # Docker.url = tcp://192.168.123.205:2375
  #   split(':') = ["tcp", "//192.168.123.205", "2375"]
  #   [1] = "//192.168.123.205"
  #   [2..-1] = "192.168.123.205"
  # This last bit prunes the leading //
  url = Docker.url
  ip = "127.0.0.1"
  case url.split(':')[0]
  when 'unix'
    ip = "127.0.0.1"
  when 'tcp'
    ip = url.split(':')[1][2..-1]
  end
  ip
end

def port_responding?(ip, port)
  # Try for up to 10 seconds to get a response
  10.times do
    if port_open?(ip, port)
      return true
    else
      sleep 1
    end
  end
  false
end

def zabbix_server_up?
  zabbix_ip = get_docker_ip
  port = 10051
  test_cfg = { "zabbix_server_host" => zabbix_ip, "zabbix_host" => "zabhost", "zabbix_key" => "zabkey", "zabbix_value" => "message" }
  test_event = LogStash::Event.new({ "message" => "This is a log entry.", "zabhost" => "zabbix.example.com", "zabkey" => "zabbix.key" })
  test_out = LogStash::Outputs::Zabbix.new(test_cfg)
  data = test_out.format_request(test_event)
  if port_responding?(zabbix_ip, port)
    ###
    ### This is a hacky way to guarantee that Zabbix is responsive, because the
    ### port check alone is insufficient.  TCP tests say the port is open, but
    ### it can take another 2 to 5 seconds (depending on the machine) before it
    ### is responding in the way we need for these tests.
    ###
    resp = ""
    # Try for up to 10 seconds to get a response.
    10.times do
      TCPSocket.open(zabbix_ip, port) do |sock|
        sock.print ZabbixProtocol.dump(data)
        resp = sock.read
      end
      if resp.length == 0
        sleep 1
      else
        return true
      end
    end
    if resp.length == 0
      puts "Zabbix server or db is unreachable"
    end
  else
    puts "Unable to reach Zabbix server on #{zabbix_ip}:#{port}"
  end
  false
end

describe LogStash::Outputs::Zabbix do
  # Building block "lets"
  let(:port) { 10051 }
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
  let(:zabout) {
    {
      "zabbix_server_host" => host,
      "zabbix_server_port" => port,
      "zabbix_host" => "zabhost",
      "zabbix_key" => "zabkey",
      "timeout" => timeout
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
    end

    describe "#format_request" do
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
    end

  end

  describe "Integration Tests", :integration => true do
    let(:host) { get_docker_ip }

    # Only open the container once for all tests.
    before(:all) do
      zabbix_ip = get_docker_ip
      port = 10051
      container = Docker::Container.create(
        "name" => CONTAINER_NAME,
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
      zabbix_server_up?
    end

    after(:all) do
      container = Docker::Container.get(CONTAINER_NAME)
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
        let(:zabhost) { "something_else.example.com" }
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
        let(:host) { "172.19.74.123" }
        let(:port) { 12345 }
        subject { output.send_to_zabbix(string_event) }
        it "should timeout and return false" do
          expect(subject).to eq(false)
        end
      end

    end

  end

end

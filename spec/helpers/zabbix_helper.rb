module ZabbixHelper

  # This is used to ensure the (Docker) Zabbix port is up and running
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

  def zabbix_server_up?(zabbix_ip, port)
    data = {
        "request" => "sender data",
        "data" => [{
          "host"  => "zabbix.example.com",
          "key"   => "zabbix.key",
          "value" => "This is a log entry.",
          "clock" => 1429100000,
        }],
        "clock" => Time.now.to_i,
    }
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
  
end

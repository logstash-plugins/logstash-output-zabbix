# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "socket"
require "timeout"
require "zabbix_protocol"

# The Zabbix output is used to send item data (key/value pairs) to a Zabbix
# server.  The event `@timestamp` will automatically be associated with the
# Zabbix item data.
#
# The Zabbix Sender protocol is described at
# https://www.zabbix.org/wiki/Docs/protocols/zabbix_sender/2.0
# Zabbix uses a kind of nested key/value store.
#
# [source,txt]
#     host
#       ├── item1
#       │     └── value1
#       ├── item2
#       │     └── value2
#       ├── ...
#       │     └── ...
#       ├── item_n
#       │     └── value_n
#
# Each "host" is an identifier, and each item is associated with that host.
# Items are typed on the Zabbix side.  You can send numbers as strings and
# Zabbix will Do The Right Thing.
#
# In the Zabbix UI, ensure that your hostname matches the value referenced by
# `zabbix_host`. Create the item with the key as it appears in the field
# referenced by `zabbix_key`.  In the item configuration window, ensure that the
# type dropdown is set to Zabbix Trapper. Also be sure to set the type of
# information that Zabbix should expect for this item.
#
# This plugin does not currently send in batches.  While it is possible to do
# so, this is not supported.  Be careful not to flood your Zabbix server with
# too many events per second.
#
# NOTE: This plugin will log a warning if a necessary field is missing. It will
# not attempt to resend if Zabbix is down, but will log an error message.

class LogStash::Outputs::Zabbix < LogStash::Outputs::Base
  config_name "zabbix"

  # The IP or resolvable hostname where the Zabbix server is running
  config :zabbix_server_host, :validate => :string, :default => "localhost"

  # The port on which the Zabbix server is running
  config :zabbix_server_port, :validate => :number, :default => 10051

  # The field name which holds the Zabbix host name. This can be a sub-field of
  # the @metadata field.
  config :zabbix_host, :validate => :string, :required => true

  # The field name which holds the Zabbix key. This can be a sub-field of
  # the @metadata field.
  config :zabbix_key, :validate => :string, :required => true

  # The field name which holds the value you want to send.
  config :zabbix_value, :validate => :string, :default => "message"

  # The number of seconds to wait before giving up on a connection to the Zabbix
  # server. This number should be very small, otherwise delays in delivery of
  # other outputs could result.
  config :timeout, :validate => :number, :default => 1

  public
  def register
  end # def register

  public
  def field_check(event, fieldname)
    if !event[fieldname]
      @logger.warn("Skipping zabbix output; field referenced by #{fieldname} is missing")
      false
    else
      true
    end
  end

  public
  def format_request(event)
    # The nested `clock` value is the event timestamp
    # The ending `clock` value is "now" so Zabbix knows it's not receiving stale
    # data.
    {
      "request" => "sender data",
      "data" => [{
        "host" => event[@zabbix_host],
        "key" => event[@zabbix_key],
        "value" => event[@zabbix_value].to_s,
        "clock" => event["@timestamp"].to_i
      }],
      "clock" => Time.now.to_i,
    }
  end

  def response_check(event, data)
    # {"response"=>"success", "info"=>"Processed 0; Failed 1; Total 1; seconds spent: 0.000018"}
    unless data["response"] == "success"
      @logger.error("Failed to send event to Zabbix",
        :zabbix_response => data,
        :event => event
      )
      false
    else
      true
    end
  end

  def info_check(event, data)
    # {"response"=>"success", "info"=>"processed 0; Failed 1; Total 1; seconds spent: 0.000018"}
    if !data.is_a?(Hash)
      @logger.error("Zabbix server at #{@zabbix_server_host} responded atypically.",
        :returned_data => data
      )
      return false
    end
    # Prune the semicolons, then turn it into an array
    info = (data["info"].delete! ';').split()
    # ["processed", "0", "Failed", ";", "Total", "1", "seconds", "spent:", "0.000018"]
    failed = info[3].to_i
    total = info[5].to_i
    if failed == total
      @logger.warn("Zabbix server at #{@zabbix_server_host} rejected all items sent.",
        :zabbix_host => event[@zabbix_host],
        :zabbix_key => event[@zabbix_key],
        :zabbix_value => event[@zabbix_value]
      )
      false
    elsif failed > 0
      @logger.warn("Zabbix server at #{@zabbix_server_host} rejected #{info[3]} item(s).",
        :zabbix_host => event[@zabbix_host],
        :zabbix_key => event[@zabbix_key],
        :zabbix_value => event[@zabbix_value]
      )
      false
    elsif failed == 0 && total > 0
      true
    else
      false
    end
  end

  def tcp_send(event)
    begin
      TCPSocket.open(@zabbix_server_host, @zabbix_server_port) do |sock|
        data = format_request(event)
        sock.print ZabbixProtocol.dump(data)
        resp = ZabbixProtocol.load(sock.read)
        @logger.debug? and @logger.debug("Zabbix server response",
                              :response => resp, :data => data)
        # Log whether the key/value pairs accepted
        info_check(event, resp)
        # Did the message get received by Zabbix?
        response_check(event, resp)
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      @logger.error("Connection error.  Unable to connect to Zabbix server",
        :server => @zabbix_server_host,
        :port => @zabbix_server_port.to_s
      )
      false
    end
  end

  def send_to_zabbix(event)
    begin
      Timeout::timeout(@timeout) do
        tcp_send(event)
      end
    rescue Timeout::Error
      @logger.warn("Connection attempt to Zabbix server timed out.",
        :server => @zabbix_server_host,
        :port => @zabbix_server_port.to_s,
        :timeout => @timeout.to_s
      )
      false
    end
  end

  public
  def receive(event)
    return unless output?(event)
    for field in [@zabbix_host, @zabbix_key, @zabbix_value]
      return unless field_check(event, field)
    end
    send_to_zabbix(event)
  end # def event

end # class LogStash::Outputs::Zabbix

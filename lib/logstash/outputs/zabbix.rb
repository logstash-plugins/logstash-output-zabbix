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

  # A single field name which holds the value you intend to use as the Zabbix
  # item key. This can be a sub-field of the @metadata field.
  # This directive will be ignored if using `multi_value`
  config :zabbix_key, :validate => :string

  # The field name which holds the value you want to send.
  # This directive will be ignored if using `multi_value`
  config :zabbix_value, :validate => :string, :default => "message"

  # Use the `multi_value` directive to send multiple key/value pairs.
  # This can be thought of as an array, like:
  #
  # `[ zabbix_key1, zabbix_value1, zabbix_key2, zabbix_value2, ... zabbix_keyN, zabbix_valueN ]`
  #
  # ...where `zabbix_key1` is an instance of `zabbix_key`, and `zabbix_value1`
  # is an instance of `zabbix_value`.  If the field referenced by any
  # `zabbix_key` or `zabbix_value` does not exist, that entry will be ignored.
  #
  # This directive cannot be used in conjunction with the single-value directives
  # `zabbix_key` and `zabbix_value`.
  config :multi_value, :validate => :array

  # The number of seconds to wait before giving up on a connection to the Zabbix
  # server. This number should be very small, otherwise delays in delivery of
  # other outputs could result.
  config :timeout, :validate => :number, :default => 1

  public
  def register
    if !@zabbix_key.nil? && !@multi_value.nil?
      @logger.warn("Cannot use multi_value in conjunction with zabbix_key/zabbix_value.  Ignoring zabbix_key.")
    end

    # We're only going to use @multi_value in the end, so let's build it from
    # @zabbix_key and @zabbix_value if it is empty (single value configuration).
    if @multi_value.nil?
      @multi_value = [ @zabbix_key, @zabbix_value ]
    end
    if @multi_value.length % 2 == 1
      raise LogStash::ConfigurationError, I18n.t("logstash.agent.configuration.invalid_plugin_register",
        :plugin => "output", :type => "zabbix",
        :error => "Invalid zabbix configuration #{@multi_value}. multi_value requires an even number of elements as ['zabbix_key1', 'zabbix_value1', 'zabbix_key2', 'zabbix_value2']")
    end
  end # def register

  public
  def field_check(event, fieldname)
    if !event[fieldname]
      @logger.warn("Field referenced by #{fieldname} is missing")
      false
    else
      true
    end
  end

  public
  def kv_check(event, key_field, value_field)
    errors = 0
    for field in [key_field, value_field]
      errors += 1 unless field_check(event, field)
    end
    errors < 1 ? true : false
  end # kv_check

  public
  def validate_fields(event)
    found = []
    (0..@multi_value.length-1).step(2) do |idx|
      if kv_check(event, @multi_value[idx], @multi_value[idx+1])
        found << @multi_value[idx]
        found << @multi_value[idx+1]
      end
    end
    found
  end # validate_fields

  public
  def format_request(event)
    # The nested `clock` value is the event timestamp
    # The ending `clock` value is "now" so Zabbix knows it's not receiving stale
    # data.
    validated = validate_fields(event)
    data = []
    (0..validated.length-1).step(2) do |idx|
      data << {
        "host"  => event[@zabbix_host],
        "key"   => event[validated[idx]],
        "value" => event[validated[idx+1]],
        "clock" => event["@timestamp"].to_i
      }
    end
    {
      "request" => "sender data",
      "data" => data,
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
    info = data["info"].tr(';', '').split()
    # ["processed", "0", "Failed", "1", "Total", "1", "seconds", "spent:", "0.000018"]
    failed = info[3].to_i
    total = info[5].to_i
    if failed == total
      @logger.warn("Zabbix server at #{@zabbix_server_host} rejected all items sent.",
        :zabbix_host => event[@zabbix_host]
      )
      false
    elsif failed > 0
      @logger.warn("Zabbix server at #{@zabbix_server_host} rejected #{info[3]} item(s).",
        :zabbix_host => event[@zabbix_host]
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
    
    return unless field_check(event, @zabbix_host)
    send_to_zabbix(event)
  end # def event

end # class LogStash::Outputs::Zabbix

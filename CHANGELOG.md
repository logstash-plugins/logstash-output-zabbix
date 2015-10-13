## 2.0.0
 - Plugins were updated to follow the new shutdown semantic, this mainly allows Logstash to instruct input plugins to terminate gracefully,
   instead of using Thread.raise on the plugins' threads. Ref: https://github.com/elastic/logstash/pull/3895
 - Dependency on logstash-core update to 2.0
 - Update to allow semicolons (or not, e.g. Zabbix 2.0). #6 (davmrtl)
 - Update to prevent Logstash from crashing when the Zabbix server becomes unavailable while the plugin is sending data. 
   Ref: https://github.com/logstash-plugins/logstash-output-zabbix/pull/9

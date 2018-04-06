## 3.0.5
  - Docs: Set the default_codec doc attribute.

## 3.0.4
  - Update gemspec summary

## 3.0.3
  - Fix some documentation issues

## 3.0.1
  - Relax constraint on logstash-core-plugin-api to >= 1.60 <= 2.99

# 3.0.0
  - Breaking: Updated plugin to use new Java Event APIs
  - Use zabbix_protocol 0.1.5 or greater (tasty fixes for Zabbix)
  - Make TravisCI use JRuby 1.7.25, and have Travis run the unit & integration tests.
# 2.0.2
  - Depend on logstash-core-plugin-api instead of logstash-core, removing the need to mass update plugins on major releases of logstash
# 2.0.1
  - New dependency requirements for logstash-core for the 5.0 release
## 2.0.0
 - Plugins were updated to follow the new shutdown semantic, this mainly allows Logstash to instruct input plugins to terminate gracefully,
   instead of using Thread.raise on the plugins' threads. Ref: https://github.com/elastic/logstash/pull/3895
 - Dependency on logstash-core update to 2.0
 - Update to allow semicolons (or not, e.g. Zabbix 2.0). #6 (davmrtl)
 - Update to prevent Logstash from crashing when the Zabbix server becomes unavailable while the plugin is sending data. #9 (dkanbier)

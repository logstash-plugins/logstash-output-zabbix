#!/bin/bash

# Start MySQL
/etc/init.d/mysql start

# Build the Zabbix Database
/etc/init.d/mysql start

# Build the Zabbix Database
mysql < /zabbix.sql

# Flush tables and logs
mysqladmin refresh

# Stop it again afterwards
/etc/init.d/mysql stop

### Instructions for building the original db

#echo 'create database zabbix character set utf8 collate utf8_bin' > /create.sql
#mysql < /create.sql

#cd /usr/share/zabbix-server-mysql/
#for file in $(ls *.gz); do gunzip $file; done
#mysql zabbix < schema.sql
#mysql zabbix < images.sql
#mysql zabbix < data.sql

### Run Zabbix, create your items, then mysqldump to zabbix.sql

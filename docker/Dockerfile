FROM ubuntu:14.04

MAINTAINER Aaron Mildenstein <aaron@mildensteins.com>

RUN apt-get -qq update
RUN DEBIAN_FRONTEND=noninteractive apt-get -yqq install mysql-server
#RUN apt-get -yqq install php5-mysql zabbix-frontend-php
RUN apt-get -yqq install zabbix-server-mysql

# Change PHP setup
#RUN sed -i -e 's/^post_max_size =.*/post_max_size = 16M/' -e 's/^max_execution_time.*/max_execution_time = 300/' \
#           -e 's/^max_input_time.*/max_input_time = 300/' -e 's/;date.timezone.*/date.timezone = America\/Denver/' /etc/php5/apache2/php.ini

# Setup Apache
#RUN cp /usr/share/doc/zabbix-frontend-php/examples/apache.conf /etc/apache2/conf-available/zabbix.conf
#RUN ln -s /etc/apache2/conf-available/zabbix.conf /etc/apache2/conf-enabled/zabbix.conf
#COPY zabbix.conf.php /etc/zabbix/zabbix.conf.php

# Set to allow Zabbix to run
RUN sed -i s/START=no/START=yes/g /etc/default/zabbix-server

# Create this dir and change permissions (the package doesn't, for some reason)
RUN mkdir -p /var/run/zabbix
RUN chown zabbix:zabbix /var/run/zabbix

# Configure zabbix_server.conf
RUN sed -i -e 's/^# StartPollers=5/StartPollers=1/' \
	   -e 's/^# StartPollersUnreachable=1/StartPollersUnreachable=0/' \
	   -e 's/^# StartTrappers=5/StartTrappers=1/' \
	   -e 's/^# StartPingers=1/StartPingers=0/' \
	   -e 's/^# StartDiscoverers=1/StartDiscoverers=0/' \
	   -e 's/^# StartHTTPPollers=1/StartHTTPPollers=0/' \
	   -e 's/^# StartDBSyncers=4/StartDBSyncers=2/' \
	   -e 's/^DBUser=zabbix/DBUser=root/' \
	   -e 's/^# DBSocket=\/tmp\/mysql.sock/DBSocket=\/var\/run\/mysqld\/mysqld.sock/' \ 
	   -e 's/^# StartProxyPollers=1/StartProxyPollers=0/' /etc/zabbix/zabbix_server.conf

# Expose the Ports used by
# * Zabbix services
# * Apache with Zabbix UI (Add port 80 below)

EXPOSE 10051

COPY build_db.sh /
COPY run.sh /
COPY zabbix.sql /
RUN ln -s /run.sh /usr/bin/run


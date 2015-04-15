# logstash-output-zabbix

## Testing Information

### Unit Tests

To run the unit tests:

    bundle exec rspec -f d -c

### Integration Tests

This plugin has RSpec integration tests which use a Docker image.

#### Pull the Docker image

If you are using Docker already, you can prime your Docker instance with

    docker pull untergeek/logstash_output_zabbix_rspec:zabbix_v2.2.2

Otherwise, it should pull automatically on the first run (which could take a few minutes, depending on your connection).

See [docker/README.md](https://github.com/logstash-plugins/logstash-output-zabbix/blob/master/docker/README.md) for more information about Docker.

#### Local Docker

To run the integration tests with a local Docker instance (i.e. a local socket):

    bundle exec rspec -f d -c -t integration

#### Remote Docker

To run the integration tests with a remote Docker instance:

    DOCKER_URL=tcp://x.x.x.x:xxxx bundle exec rspec -f d -c -t integration

This will automatically pass the `DOCKER_URL` environment variable to the tests.  This approach works well with MacOS X instances where you need a VM or Linux box to run Docker, and potentially Windows (untested by me).

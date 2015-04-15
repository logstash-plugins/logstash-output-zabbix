# Docker Image For Testing This Plugin

## Docker Hub

The completed image is hosted at https://registry.hub.docker.com/u/untergeek/logstash_output_zabbix_rspec/

You can manually pull it to your Docker installation by running

    docker pull untergeek/logstash_output_zabbix_rspec

Learn more about Docker at http://docs.docker.com

## How the image was created

**Prerequisite: Database SQL file creation**

This image is currently built using a multi-stage process. Because creating
items either requires the API or SQL access, I opted to first build an image
with Apache & PHP so it would have a front-end.  After building a successful
Zabbix installation, I created items and dumped the MySQL of the full db into
`zabbix.sql`.  The vestiges of this remain commented in the `Dockerfile`.

### Building the image

A new Zabbix Server image had to be built based on the database from the previous
step.  The `Dockerfile` is what built this with these steps:

#### 1. Build the initial image:
* `docker build .`
* Get the docker image id from this step and use in the next step

#### 2. Create the database on the initial image:
**Run the image from step 1 in an interactive shell:**

* Run `docker run -i -t IMAGE_ID /bin/bash` from the container host
* Run `/build_db.sh` from the resulting shell.

**Do NOT exit the shellwhen this is done.**

#### 3. Commit the changes to a new image:
From another shell on the container host, commit the changes (the populated
database) from the initial image into a _new_ image:

```
docker commit \
  --author="Aaron Mildenstein <aaron@mildensteins.com>" \
  --message="Populated the database" \
  IMAGE_ID \
  untergeek/logstash_output_zabbix_rspec:zabbix_v2.2.2
```

#### 4. Push the image to Docker Hub:

The image is then pushed to the Docker Hub:

    docker push untergeek/logstash_output_zabbix_rspec:zabbix_v2.2.2

### Running the image

While the RSpec test handles creating a container from this image, and then
deleting when done, you can manually run the image, if needed:

    docker run -i --name="logstash_zabbix_rspec" -d -p 10051:10051 untergeek/logstash_output_zabbix_rspec run

This command ensures that port 10051 is forwarded from the container to the
container host.  The `run` command at the end runs `run.sh` as in this directory.

#### Manual/interactive container use

You can also run Zabbix interactively, as though you were on the server:

    docker run -i -t -p 10051:10051 untergeek/logstash_output_zabbix_rspec /bin/bash

At this point, you'd need to run `service mysql start` and `service zabbix-server start`
to fully initialize the server, but you have the ability to see the logs, or
query the MySQL directly.  Exiting the shell will close and delete the container.

### Stopping the image

If you ran a container in detached (`-d`) mode, you can stop the running image
by running:

    docker stop logstash_zabbix_rspec

This will only work if you included `--name="logstash_zabbix_rspec"` in your
`docker run` command-line.  You will otherwise have to run `docker ps` and find
the container id.

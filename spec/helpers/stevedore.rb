# Helper methods for Docker testing

module Stevedore
  require 'docker'

  # Figure out which IP address the Docker host is at
  def get_host_ip
    # Let the crazy one-liner definition begin:
    # Docker.url.split(':')[1][2..-1]
    # Docker.url = tcp://192.168.123.205:2375
    #   split(':') = ["tcp", "//192.168.123.205", "2375"]
    #   [1] = "//192.168.123.205"
    #   [2..-1] = "192.168.123.205"
    # This last bit prunes the leading //
    url = Docker.url
    case url.split(':')[0]
    when 'unix'
      ip = "127.0.0.1"
    when 'tcp'
      ip = url.split(':')[1][2..-1]
    end
    ip
  end

  # Build an image from a Dockerfile
  def build_image(dockerfile_path)
    dockerfile = IO.read(dockerfile_path)
    Docker::Image.build(dockerfile)
  end

  def delete_image(image)
    if image_exists?(image.id)
      image.remove(:force => true)
    end
  end

  # Return the image object identified by repository:tag
  def get_image(repository, tag)
    images = Docker::Image.all.select { |i|
      i.info["RepoTags"].include? "#{repository}:#{tag}"
    }
    # I don't think it's possible to have multiple images from the same
    # repository with the same tag, so this shouldn't be an issue.
    images[0]
  end

  def image_exists?(id)
    begin
      Docker::Image.get(id)
      true
    rescue Docker::Error::NotFoundError
      false
    end
  end

  # Return the randomized port number associated with the exposed port.
  def get_randomized_port(container, exposed_port, protocol="tcp")
    # Get all mapped ports
    ports = container.json["NetworkSettings"]["Ports"]
    # We're going to expect 1:1 mapping here
    ports["#{exposed_port.to_s}/#{protocol}"][0]["HostPort"].to_i
  end

  # Create a docker container from an image (or repository:tag string), name,
  # and optional extra args.
  def create_container(image, name, extra_args={})
    # If this ends up getting integrated, we'll use @logger.error here
    case image.class.to_s
    when "Docker::Image"
      i = image.id
    when "String"
      if image.include? ':' # repository:tag format
        i = image
      else
        puts "Image string must be in 'repository:tag' format."
        return
      end
    else
      puts "image must be Docker::Image or in 'repository:tag' format"
      return
    end
    Docker.options = { :write_timeout => 300, :read_timeout => 300 }
    Docker.validate_version!
    # Don't change the non-capitalized 'name' here.  The Docker API gem extracts
    # this key and uses it to name the container on create.
    main_args = {
      'name' => name,
      'Hostname' => name,
      'Image' => i,
      'PublishAllPorts' => true,
    }
    Docker::Container.create(main_args.merge(extra_args))
  end

  # Wrapper to clean up container in a single call
  # name can be a name or id
  def cleanup_container(name)
    container = Docker::Container.get(name)
    if container
      container.stop
      container.delete(:force => true)
    end
  end

  # This is useful if you're building from Dockerfiles each run
  def cleanup_image(image)
    if image_exists?(image.id)
      image.remove(:force => true)
    end
  end

end

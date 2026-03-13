#!/usr/bin/env ruby
# frozen_string_literal: true

require './lib/legion/version'
puts "Building docker image for Legion v#{Legion::VERSION}"
system("docker build --tag legionio/legion:v#{Legion::VERSION} .")
puts 'Pushing to hub.docker.com'
system("docker push legionio/legion:v#{Legion::VERSION}")
system("docker tag legionio/legion:v#{Legion::VERSION} legionio/legion:lastest")
system("docker push legionio/legion:v#{Legion::VERSION}")
puts 'completed'

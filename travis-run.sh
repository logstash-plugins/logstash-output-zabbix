#!/bin/bash
set -ex

if [[ "$INTEGRATION" != "true" ]]; then
  bundle exec rspec -fd spec
elif [[ "$INTEGRATION" == "true" ]]; then
  bundle exec rspec -fd spec -t integration
fi

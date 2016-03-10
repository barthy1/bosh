#!/usr/bin/env bash

set -e

source bosh-src/ci/tasks/utils.sh
check_param RUBY_VERSION

source /etc/profile.d/chruby.sh
chruby $RUBY_VERSION

cd bosh-src
print_git_state

export PATH=/usr/local/ruby/bin:/usr/local/go/bin:$PATH
export GOPATH=$(pwd)/go
export GOROOT=/usr/local/go
export TRAVIS=true
gem install nokogiri -v 1.6.6.2 -- --use-system-libraries --with-xml2-include=/usr/include/libxml2
bundle install --local
bundle exec rake --trace spec:unit

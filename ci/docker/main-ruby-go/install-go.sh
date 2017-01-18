#!/usr/bin/env bash

set -eux

GOPATH=/home/vagrant/go
GO_ARCHIVE_URL=https://storage.googleapis.com/golang/go1.7.3.linux-amd64.tar.gz
GO_ARCHIVE_SHA256=508028aac0654e993564b6e2014bf2d4a9751e3b286661b0b0040046cf18028e
GO_ARCHIVE=/tmp/$(basename $GO_ARCHIVE_URL)

if [ `uname -m` == "ppc64le" ]; then
   GO_ARCHIVE_URL=http://ftp.unicamp.br/pub/ppc64el/ubuntu/14_04/cloud-foundry/go-1.7.3-ppc64le.tar.gz
   GO_ARCHIVE_SHA256=b17ca1dcf9c3e3fe219e9adb159530170e7c28e29611809754ded82d2fa9efc4
fi

echo "Downloading go..."
mkdir -p $(dirname $GOROOT)
wget -q $GO_ARCHIVE_URL -O $GO_ARCHIVE
echo "${GO_ARCHIVE_SHA256} ${GO_ARCHIVE}" | sha256sum -c -
tar xf $GO_ARCHIVE -C $(dirname $GOROOT)

rm -f $GO_ARCHIVE

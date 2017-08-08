#!/bin/sh -e
exec nice env -i \
 DEB_BUILD_OPTIONS="parallel=4 nocheck" \
 HOME="/home/buildd" \
 LC_ALL="POSIX" \
 sbuild \
 -d unstable \
 --no-apt-update \
 --no-apt-upgrade \
 --no-apt-distupgrade \
 --pre-build-commands='sort -u < repro-build-env.list | %e tee /etc/apt/sources.list.d/repro-build-env.list' \
 --pre-build-commands='cat script.sh | %e /bin/sh' \
 --verbose \
 $*

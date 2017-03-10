#!/usr/bin/env bash

## auto-generated debian install file written by halyard

set -e
set -o pipefail

INSTALL_REDIS="{%install-redis%}"
INSTALL_SPINNAKER="{%install-spinnaker%}"
SPINNAKER_ARTIFACTS=({%spinnaker-artifacts%})
CONFIG_DIR="{%config-dir%}"

REPOSITORY_URL="{%debian-repo%}"

## check that the user is root
if [[ `/usr/bin/id -u` -ne 0 ]]; then
  echo "$0 must be executed with root permissions; exiting"
  exit 1
fi

if [[ -f /etc/lsb-release ]]; then
  . /etc/lsb-release
  DISTRO=$DISTRIB_ID
elif [[ -f /etc/debian_version ]]; then
  DISTRO=Debian
  # XXX or Ubuntu
elif [[ -f /etc/redhat-release ]]; then
  if grep -iq cent /etc/redhat-release; then
    DISTRO="CentOS"
  elif grep -iq red /etc/redhat-release; then
    DISTRO="RedHat"
  fi
else
  DISTRO=$(uname -s)
fi

# If not Ubuntu 14.xx.x or higher

if [ "$DISTRO" = "Ubuntu" ]; then
  if [ "${DISTRIB_RELEASE%%.*}" -lt "14" ]; then
    echo "Not a supported version of Ubuntu"
    echo "Version is $DISTRIB_RELEASE we require 14.04 or higher"
    exit 1
  fi
else
  echo "Not a supported operating system: " $DISTRO
  echo "It's recommended you use Ubuntu 14.04 or higher."
  echo ""
  echo "Please file an issue against https://github.com/spinnaker/spinnaker/issues"
  echo "if you'd like to see support for your OS and version"
  exit 1
fi

function contains() {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

function add_redis_apt_repository() {
  add-apt-repository -y ppa:chris-lea/redis-server
}

function add_spinnaker_apt_repository() {
  REPOSITORY_HOST=$(echo $REPOSITORY_URL | cut -d/ -f3)
  if [[ "$REPOSITORY_HOST" == "dl.bintray.com" ]]; then
    REPOSITORY_ORG=$(echo $REPOSITORY_URL | cut -d/ -f4)
    # Personal repositories might not be signed, so conditionally check.
    gpg=""
    gpg=$(curl -s -f "https://bintray.com/user/downloadSubjectPublicKey?username=$REPOSITORY_ORG") || true
    if [[ ! -z "$gpg" ]]; then
      echo "$gpg" | apt-key add -
    fi
  fi
  echo "deb $REPOSITORY_URL $DISTRIB_CODENAME spinnaker" | tee /etc/apt/sources.list.d/spinnaker.list > /dev/null
}

function add_java_apt_repository() {
  add-apt-repository -y ppa:openjdk-r/ppa
}

function install_java() {
  apt-get install -y --force-yes unzip
  apt-get install -y --force-yes openjdk-8-jdk

  # https://bugs.launchpad.net/ubuntu/+source/ca-certificates-java/+bug/983302
  # It seems a circular dependency was introduced on 2016-04-22 with an openjdk-8 release, where
  # the JRE relies on the ca-certificates-java package, which itself relies on the JRE.
  # This causes the /etc/ssl/certs/java/cacerts file to never be generated, causing a startup
  # failure in Clouddriver.
  dpkg --purge --force-depends ca-certificates-java
  apt-get install ca-certificates-java
}

function install_redis_server() {
  apt-get -q -y --force-yes install redis-server
  if [[ $? -eq 0 ]]; then
    return
  else
    echo "Error installing redis-server."
    echo "Cannot continue installation; exiting."
    exit 1
  fi
}

function install_apache2() {
  if ! $(dpkg -s apache2 2>/dev/null >/dev/null) ; then
    local apt_status=`apt-get -s -y --force-yes install apache2 > /dev/null 2>&1 ; echo $?`
    if [[ $apt_status -eq 0 ]]; then
      echo "apt sources contain apache2; installing using apt-get"
      apt-get -q -y --force-yes install apache2
    else
      echo "Unknown error ($apt_status) occurred while attempting to install Apache2."
      echo "Cannot continue installation; exiting."
      exit 1
    fi
  fi

  service apache2 stop
  mkdir -p /etc/apache2/sites-available
  mv ${CONFIG_DIR}/apache2/spinnaker.conf /etc/apache2/sites-available
  mv ${CONFIG_DIR}/apache2/ports.conf /etc/apache2
  mv ${CONFIG_DIR}/settings.js /opt/deck/html/settings.js

  a2ensite spinnaker
  service apache2 start
}

echo "Updating apt package lists..."

if [ -n "$INSTALL_REDIS" ]; then
  add_redis_apt_repository
fi

if [ -n "$INSTALL_SPINNAKER" ]; then
  add_java_apt_repository
  add_spinnaker_apt_repository
fi

apt-get update ||:

echo "Installing desired components..."

if [ -n "$INSTALL_REDIS" ]; then
  install_redis_server
fi

if [ -n "$INSTALL_SPINNAKER" ]; then
  install_java

  rm -f /etc/apt/preferences.d/pin-spin-*
  {%pin-files%}

  {%etc-init%}

  for package in ${SPINNAKER_ARTIFACTS[@]}; do
    apt-get install -y --force-yes --allow-unauthenticated spinnaker-${package}
  done

  if contains "deck" "${SPINNAKER_ARTIFACTS[@]}"; then
    install_apache2
  fi

  mkdir -p /opt/spinnaker/config/
  chown spinnaker /opt/spinnaker/config/
  cp ${CONFIG_DIR}/*.yml /opt/spinnaker/config/
fi

# so this script can be used for updates
service spinnaker restart

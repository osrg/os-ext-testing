#! /usr/bin/env bash

# Sets up a slave Jenkins server intended to run devstack-based Jenkins jobs

set -e

THIS_DIR=`pwd`

DEVSTACK_GATE_3PPRJ_BASE=${DEVSTACK_GATE_3PPRJ_BASE:-osrg}
DEVSTACK_GATE_3PBRANCH=${DEVSTACK_GATE_3PBRANCH:-ofaci}
DATA_REPO_INFO_FILE=$THIS_DIR/.data_repo_info
DATA_PATH=$THIS_DIR/data
OSEXT_PATH=$THIS_DIR/os-ext-testing
OSEXT_REPO=${OSEXT_REPO:-https://github.com/jaypipes/os-ext-testing}
CONFIG_REPO=${CONFIG_REPO:-https://review.openstack.org/p/openstack-infra/system-config.git}
CONFIG_REPO_DIR=/root/system-config
PROJECT_CONF_REPO=${PROJECT_CONF_REPO:-https://git.openstack.org/openstack-infra/project-config}
DEVSTACK_GATE_REPO=${DEVSTACK_GATE_REPO:-git://git.openstack.org/openstack-infra/devstack-gate}
DEVSTACK_GATE_3PPRJ_BASE=${DEVSTACK_GATE_3PPRJ_BASE:-osrg}
PUPPET_MODULE_PATH="--modulepath=$OSEXT_PATH/puppet/modules:$CONFIG_REPO_DIR/modules:/etc/puppet/modules"
INST_PUPPET_SH=${INST_PUPPET_SH:-https://git.openstack.org/cgit/openstack-infra/system-config/plain/install_puppet.sh}

# Install Puppet and the OpenStack Infra Config source tree
if [[ ! -e install_puppet.sh ]]; then
  wget $INST_PUPPET_SH
  sudo bash -xe install_puppet.sh
  sudo git clone $CONFIG_REPO $CONFIG_REPO_DIR
  sudo /bin/bash $CONFIG_REPO_DIR/install_modules.sh
fi

# Clone or pull the the os-ext-testing repository
if [[ ! -d $OSEXT_PATH ]]; then
    echo "Cloning os-ext-testing repo..."
    git clone $OSEXT_REPO $OSEXT_PATH
fi

if [[ "$PULL_LATEST_OSEXT_REPO" == "1" ]]; then
    echo "Pulling latest os-ext-testing repo master..."
    cd $OSEXT_PATH; git checkout master && sudo git pull; cd $THIS_DIR
fi

if [[ ! -e $DATA_PATH ]]; then
    echo "Enter the URI for the location of your config data repository. Example: https://github.com/jaypipes/os-ext-testing-data"
    read data_repo_uri
    if [[ "$data_repo_uri" == "" ]]; then
        echo "Data repository is required to proceed. Exiting."
        exit 1
    fi
    git clone $data_repo_uri $DATA_PATH
fi

if [[ "$PULL_LATEST_DATA_REPO" == "1" ]]; then
    echo "Pulling latest data repo master."
    cd $DATA_PATH; git checkout master && git pull; cd $THIS_DIR;
fi

# Pulling in variables from data repository
. $DATA_PATH/vars.sh

# Validate that the upstream gerrit user and key are present in the data
# repository
if [[ -z $UPSTREAM_GERRIT_USER ]]; then
    echo "Expected to find UPSTREAM_GERRIT_USER in $DATA_PATH/vars.sh. Please correct. Exiting."
    exit 1
else
    echo "Using upstream Gerrit user: $UPSTREAM_GERRIT_USER"
fi

if [[ ! -e "$DATA_PATH/$UPSTREAM_GERRIT_SSH_KEY_PATH" ]]; then
    echo "Expected to find $UPSTREAM_GERRIT_SSH_KEY_PATH in $DATA_PATH. Please correct. Exiting."
    exit 1
fi
export UPSTREAM_GERRIT_SSH_PRIVATE_KEY_CONTENTS=`cat "$DATA_PATH/$UPSTREAM_GERRIT_SSH_KEY_PATH"`

# Validate there is a Jenkins SSH key pair in the data repository
if [[ -z $JENKINS_SSH_KEY_PATH ]]; then
    echo "Expected to find JENKINS_SSH_KEY_PATH in $DATA_PATH/vars.sh. Please correct. Exiting."
    exit 1
elif [[ ! -e "$DATA_PATH/$JENKINS_SSH_KEY_PATH" ]]; then
    echo "Expected to find Jenkins SSH key pair at $DATA_PATH/$JENKINS_SSH_KEY_PATH, but wasn't found. Please correct. Exiting."
    exit 1
else
    echo "Using Jenkins SSH key path: $DATA_PATH/$JENKINS_SSH_KEY_PATH"
    JENKINS_SSH_PRIVATE_KEY_CONTENTS=`sudo cat $DATA_PATH/$JENKINS_SSH_KEY_PATH`
    JENKINS_SSH_PUBLIC_KEY_CONTENTS=`sudo cat $DATA_PATH/$JENKINS_SSH_KEY_PATH.pub | cut -d' ' -f2`
fi

CLASS_ARGS="ssh_key => '$JENKINS_SSH_PUBLIC_KEY_CONTENTS', "
CLASS_ARGS="$CLASS_ARGS jenkins_url => '$JENKINS_URL', "
CLASS_ARGS="$CLASS_ARGS data_repo_dir => '$DATA_PATH', "
CLASS_ARGS="$CLASS_ARGS project_config_repo => '$PROJECT_CONF_REPO', "
CLASS_ARGS="$CLASS_ARGS devstack_gate_3pprj_base => '$DEVSTACK_GATE_3PPRJ_BASE', "
CLASS_ARGS="$CLASS_ARGS devstack_gate_3pbranch => '$DEVSTACK_GATE_3PBRANCH', "

sudo puppet apply --verbose $PUPPET_MODULE_PATH -e "class {'os_ext_testing::devstack_slave': $CLASS_ARGS }"

if [[ ! -e /opt/git ]]; then
    sudo mkdir -p /opt/git
    sudo -i python /opt/nodepool-scripts/cache_git_repos.py
    sudo mkdir -p /opt/git/${DEVSTACK_GATE_3PPRJ_BASE}
    sudo git clone https://github.com/${DEVSTACK_GATE_3PPRJ_BASE}/ryu /opt/git/${DEVSTACK_GATE_3PPRJ_BASE}/ryu
    sudo git clone $DEVSTACK_GATE_REPO /opt/git/${DEVSTACK_GATE_3PPRJ_BASE}/devstack-gate
    sudo -u jenkins -i /opt/nodepool-scripts/prepare_devstack.sh
fi

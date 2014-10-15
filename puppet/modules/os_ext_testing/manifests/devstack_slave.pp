# A Jenkins slave that will execute jobs that use devstack
# to set up a full OpenStack environment for test runs.

class os_ext_testing::devstack_slave (
  $thin = false,
  $certname = $::fqdn,
  $ssh_key = '',
  $sysadmins = [],
  $python3 = false,
  $include_pypy = false,
  $jenkins_url = '',
  $project_config_repo = '',
  $devstack_gate_3pprj_base = '',
  $devstack_gate_3pbranch = '',
) {
  include openstack_project::tmpcleanup

  class { 'openstack_project::server':
    iptables_public_tcp_ports => [],
    certname                  => $certname,
    sysadmins                 => $sysadmins,
  }

  class { 'jenkins::slave':
    ssh_key      => $ssh_key,
    python3      => $python3,
  }

  class { 'openstack_project::slave_common':
    include_pypy        => $include_pypy,
    sudo                => true,
    project_config_repo => $project_config_repo,
  }

  if (! $thin) {
    include openstack_project::thick_slave
  }

  # Although we don't use Nodepool itself, we DO make use of some
  # of the scripts that are housed in the nodepool openstack-infra/config
  # files directory.
  file { '/opt/nodepool-scripts':
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    recurse => true,
    purge   => true,
    force   => true,
    source  => $::project_config::nodepool_scripts_dir,
    require => $::project_config::config_dir,
  }

  file { '/usr/local/jenkins/jenkins-cli.jar':
    ensure  => present,
    source  => 'puppet:///modules/jenkins_3p/jenkins-slave/jenkins-cli.jar',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File['/usr/local/jenkins'],
  }

  file { '/usr/local/bin/rebuild-node.sh':
    ensure => present,
    source => 'puppet:///modules/jenkins_3p/rebuild-node.sh',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  if ($::osfamily == 'Debian') {

    file { '/etc/init.d/jenkins-slave':
      ensure => present,
      source => 'puppet:///modules/jenkins_3p/jenkins-slave/init',
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      require => File ['/usr/local/jenkins/jenkins-cli.jar']
    }
    file { '/etc/default/jenkins-slave':
      ensure => present,
      content => template('jenkins_3p/jenkins-slave/default.erb'),
      owner  => 'root',
      group  => 'root',
      mode   => '0644',
      require => File ['/etc/init.d/jenkins-slave']
    }
    exec { 'update-rc':
      command => '/usr/sbin/update-rc.d jenkins-slave defaults 99 01',
      path    => ['/sbin', '/bin', '/usr/sbin', '/usr/bin'],
      require => File ['/etc/init.d/jenkins-slave']
    }
  }

}

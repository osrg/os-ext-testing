# Puppet module that installs Jenkins, Zuul, Jenkins Job Builder,
# and installs JJB and Zuul configuration files from a repository
# called the "data repository".

class os_ext_testing::master (
  $vhost_name = $::fqdn,
  $data_repo_dir = '',
  $manage_jenkins_jobs = true,
  $ssl_cert_file_contents = '',
  $ssl_key_file_contents = '',
  $ssl_chain_file_contents = '',
  $jenkins_ssh_private_key = '',
  $jenkins_ssh_public_key = '',
  $gearman_workers = ['master'],
  $project_config_repo = 'https://git.openstack.org/openstack-infra/project-config',
  $publish_host = 'localhost',
  $url_pattern = 'http://localhost/{change.number}/{change.patchset}/{pipeline.name}/{job.name}/{build.number}',
  $log_root_url= "$publish_host/logs",
  $static_root_url= "$publish_host/static",
  $upstream_gerrit_server = 'review.openstack.org',
  $gearman_server = '127.0.0.1',
  $upstream_gerrit_user = '',
  $upstream_gerrit_ssh_private_key = '',
  $upstream_gerrit_host_pub_key = '',
  $git_email = 'testing@myvendor.com',
  $git_name = 'MyVendor Jenkins',
  $jenkins_url = 'http://localhost:8080/',
  $zuul_url = '',
  $scp_name = '',
  $scp_host = '',
  $scp_port = '',
  $scp_user = '',
  $scp_password = '',
  $scp_keyfile = '',
  $scp_destpath = '',
  $devstack_gate_3pprj_base = '',
  $devstack_gate_3pbranch = '',
) {
  include apache

  class { 'project_config':
    url  => $project_config_repo,
  }

  if $ssl_chain_file_contents != '' {
    $ssl_chain_file = '/etc/ssl/certs/intermediate.pem'
  } else {
    $ssl_chain_file = ''
  }

  class { 'openstack_project::jenkins':
    vhost_name              => 'jenkins',
    jenkins_jobs_password   => '',
    jenkins_jobs_username   => 'jenkins',
    manage_jenkins_jobs     => false,
    ssl_cert_file           => "/etc/ssl/certs/jenkins.pem",
    ssl_key_file            => "/etc/ssl/private/jenkins.key",
    ssl_chain_file          => $ssl_chain_file,
    ssl_cert_file_contents  => $ssl_cert_file_contents,
    ssl_key_file_contents   => $ssl_key_file_contents,
    ssl_chain_file_contents => $ssl_chain_file_contents,
    jenkins_ssh_private_key => $jenkins_ssh_private_key,
    zmq_event_receivers     => $gearman_workers,
    project_config_repo     => $project_config_repo,
  }

  jenkins::plugin { 'htmlpublisher':
    version => '1.0',
  }
  jenkins::plugin { 'postbuild-task':
    version => '1.8',
  }
  jenkins::plugin { 'violations':
    version => '0.7.11',
  }
  jenkins::plugin { 'rebuild':
    version => '1.14',
  }

  file { '/var/lib/jenkins/plugins/scp.hpi':
    ensure  => present,
    owner   => 'jenkins',
    group   => 'jenkins',
    mode    => 0644,
    source  => 'puppet:///modules/jenkins_3p/scp.hpi',
    require => File['/var/lib/jenkins/plugins'],
  }

  file { '/var/lib/jenkins/be.certipost.hudson.plugin.SCPRepositoryPublisher.xml':
    content => template('jenkins_3p/jenkins.scp.erb'),
    owner   => 'jenkins',
    group   => 'jenkins',
    mode    => '0644',
    require => File['/var/lib/jenkins'],
  }

  file { '/var/lib/jenkins/credentials.xml':
    source  => 'puppet:///modules/jenkins_3p/credentials.xml',
    owner   => 'jenkins',
    group   => 'jenkins',
    mode    => '0644',
    require => File['/var/lib/jenkins/.ssh/id_rsa'],
  }

  exec { 'put_jenkins_pub_key':
    command => "echo ${jenkins_ssh_public_key} > /var/lib/jenkins/.ssh/id_rsa.pub",
    path    => ['/sbin', '/bin', '/usr/sbin', '/usr/bin'],
    require => File['/var/lib/jenkins/.ssh/id_rsa.pub'],
  }

  file { '/var/lib/jenkins/.ssh/config':
    ensure  => present,
    owner   => 'jenkins',
    group   => 'jenkins',
    mode    => '0640',
    require => File['/var/lib/jenkins/.ssh'],
    source  => 'puppet:///modules/jenkins/ssh_config',
  }

  exec { 'invalidate_fw':
    command => "cp ${data_repo_dir}/etc/iptables/rules.* ${::iptables::params::rules_dir}/",
    path    => ['/sbin', '/bin', '/usr/sbin', '/usr/bin'],
    require => File[$::iptables::params::rules_dir],
    notify  => $::iptables::notify_iptables,
  }

  #exec { 'restart_iptables':
  #  command => "service ${::iptables::params::service_name} restart",
  #  path    => ['/sbin', '/bin', '/usr/sbin', '/usr/bin'],
  #  require => Exec['invalidate_fw'],
  #}

  exec { 'restart_jenkins':
    command => 'service jenkins restart',
    path    => ['/sbin', '/bin', '/usr/sbin', '/usr/bin'],
    require => Class['jenkins::master'],
  }

  if $manage_jenkins_jobs == true {

    class { '::jenkins_3p::job_builder':
      url          => "http://${vhost_name}:8080/",
      username     => 'jenkins',
      password     => '',
      config_dir   => 'puppet:///modules/os_ext_testing/jenkins_job_builder/config',
      require      => $::project_config::config_dir,
    }

    exec { 'copy_my_project':
      command => "cp ${data_repo_dir}/etc/jenkins_jobs/config/* /etc/jenkins_jobs/config/",
      path    => ['/sbin', '/bin', '/usr/sbin', '/usr/bin'],
      require => File['/etc/jenkins_jobs/config'],
    }

    file { '/etc/jenkins_jobs/config/macros.yaml':
      ensure => present,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      content => template('os_ext_testing/jenkins_job_builder/config/macros.yaml.erb'),
      require => [File['/etc/jenkins_jobs/config'],
                  Exec['restart_jenkins']],
    }

    file { '/etc/jenkins_jobs/config/check-tempest-dsvm-ofa.yaml':
      ensure => present,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      content => template('os_ext_testing/jenkins_job_builder/config/check-tempest-dsvm-ofa.yaml.erb'),
      notify  => Exec['jenkins_jobs_update'],
      require => [File['/etc/jenkins_jobs/config/macros.yaml'],
                  Exec['restart_jenkins']],
    }

    file { '/etc/default/jenkins':
      ensure => present,
      owner  => 'root',
      group  => 'root',
      mode   => '0644',
      source => 'puppet:///modules/openstack_project/jenkins/jenkins.default',
    }
  }

  class { '::zuul':
    vhost_name           => "zuul",
    gearman_server       => $gearman_server,
    gerrit_server        => $upstream_gerrit_server,
    gerrit_user          => $upstream_gerrit_user,
    zuul_ssh_private_key => $upstream_gerrit_ssh_private_key,
    url_pattern          => $url_pattern,
    zuul_url             => $zuul_url,
    job_name_in_report   => true,
    status_url           => "http://$publish_host/zuul/status",
    statsd_host          => $statsd_host,
    git_email            => $git_email,
    git_name             => $git_name
  }

  class { '::zuul::server':
    layout_dir => $::project_config::zuul_layout_dir,
    require    => $::project_config::config_dir,
  }
  class { '::zuul::merger': }

  if $upstream_gerrit_host_pub_key != '' {
    file { '/home/zuul/.ssh':
      ensure  => directory,
      owner   => 'zuul',
      group   => 'zuul',
      mode    => '0700',
      require => User['zuul'],
    }
    file { '/home/zuul/.ssh/known_hosts':
      ensure  => present,
      owner   => 'zuul',
      group   => 'zuul',
      mode    => '0600',
      content => "review.openstack.org,23.253.232.87,2001:4800:7815:104:3bc3:d7f6:ff03:bf5d ${upstream_gerrit_host_pub_key}",
      replace => true,
      require => File['/home/zuul/.ssh'],
    }
    file { '/home/zuul/.ssh/config':
      ensure  => present,
      owner   => 'zuul',
      group   => 'zuul',
      mode    => '0700',
      require => File['/home/zuul/.ssh'],
      source  => 'puppet:///modules/jenkins/ssh_config',
    }
  }

  file { '/etc/zuul/layout/layout.yaml':
    ensure => present,
    require => File['/etc/zuul/layout'],
    source  => "${data_repo_dir}/etc/zuul/layout.yaml",
    notify => Exec['zuul-reload'],
  }

  file { '/etc/zuul/logging.conf':
    ensure => present,
    source => 'puppet:///modules/openstack_project/zuul/logging.conf',
    notify => Exec['zuul-reload'],
  }

  file { '/etc/zuul/gearman-logging.conf':
    ensure => present,
    source => 'puppet:///modules/openstack_project/zuul/gearman-logging.conf',
    notify => Exec['zuul-reload'],
  }

  file { '/etc/zuul/merger-logging.conf':
    ensure => present,
    source => 'puppet:///modules/openstack_project/zuul/merger-logging.conf',
  }

  class { '::recheckwatch':
    gerrit_server                => $upstream_gerrit_server,
    gerrit_user                  => $upstream_gerrit_user,
    recheckwatch_ssh_private_key => $upstream_gerrit_ssh_private_key,
    require                      => Package['httpd'],
  }

  file { '/var/lib/recheckwatch/scoreboard.html':
    ensure  => present,
    source  => 'puppet:///modules/openstack_project/zuul/scoreboard.html',
    require => File['/var/lib/recheckwatch'],
  }
}

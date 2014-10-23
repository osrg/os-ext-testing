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

  # Turn a list of hostnames into a list of iptables rules
  $iptables_rules = regsubst ($gearman_workers, '^(.*)$', '-m state --state NEW -m tcp -p tcp --dport 4730,8888 -s \1 -j ACCEPT')

  class { 'openstack_project::server':
    iptables_public_tcp_ports => [80, 443, 8080, 9000],
    iptables_rules6           => $iptables_rules,
    iptables_rules4           => $iptables_rules,
    sysadmins                 => $sysadmins,
  }

  # Note that we need to do this here, once instead of in the jenkins::master
  # module because zuul also defines these resource blocks and Puppet barfs.
  # Upstream probably never noticed this because they do not deploy Zuul and
  # Jenkins on the same node...
  a2mod { 'rewrite':
    ensure => present,
  }
  a2mod { 'proxy':
    ensure => present,
  }
  a2mod { 'proxy_http':
    ensure => present,
  }

  if $ssl_chain_file_contents != '' {
    $ssl_chain_file = '/etc/ssl/certs/intermediate.pem'
  } else {
    $ssl_chain_file = ''
  }

  class { '::jenkins::master':
    vhost_name              => "jenkins",
    logo                    => 'openstack.png',
    ssl_cert_file           => "/etc/ssl/certs/jenkins.pem",
    ssl_key_file            => "/etc/ssl/private/jenkins.key",
    ssl_chain_file          => $ssl_chain_file,
    ssl_cert_file_contents  => $ssl_cert_file_contents,
    ssl_key_file_contents   => $ssl_key_file_contents,
    ssl_chain_file_contents => $ssl_chain_file_contents,
    jenkins_ssh_private_key => $jenkins_ssh_private_key,
    jenkins_ssh_public_key  => $jenkins_ssh_public_key,
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

  jenkins::plugin { 'ansicolor':
    version => '0.4.0',
  }
  jenkins::plugin { 'build-timeout':
    version => '1.14',
  }
  jenkins::plugin { 'copyartifact':
    version => '1.22',
  }
  jenkins::plugin { 'dashboard-view':
    version => '2.3',
  }
  jenkins::plugin { 'envinject':
    version => '1.70',
  }
  jenkins::plugin { 'gearman-plugin':
    version => '0.0.7',
  }
  jenkins::plugin { 'git':
    version => '1.1.23',
  }
  jenkins::plugin { 'github-api':
    version => '1.33',
  }
  jenkins::plugin { 'github':
    version => '1.4',
  }
  jenkins::plugin { 'greenballs':
    version => '1.12',
  }
  jenkins::plugin { 'htmlpublisher':
    version => '1.0',
  }
  jenkins::plugin { 'extended-read-permission':
    version => '1.0',
  }
  jenkins::plugin { 'zmq-event-publisher':
    version => '0.0.3',
  }
#  TODO(jeblair): release
#  jenkins::plugin { 'scp':
#    version => '1.9',
#  }
  jenkins::plugin { 'postbuild-task':
    version => '1.8',
  }
  jenkins::plugin { 'violations':
    version => '0.7.11',
  }
  jenkins::plugin { 'jobConfigHistory':
    version => '1.13',
  }
  jenkins::plugin { 'monitoring':
    version => '1.40.0',
  }
  jenkins::plugin { 'nodelabelparameter':
    version => '1.2.1',
  }
  jenkins::plugin { 'notification':
    version => '1.4',
  }
  jenkins::plugin { 'openid':
    version => '1.5',
  }
  jenkins::plugin { 'parameterized-trigger':
    version => '2.15',
  }
  jenkins::plugin { 'publish-over-ftp':
    version => '1.7',
  }
  jenkins::plugin { 'rebuild':
    version => '1.14',
  }
  jenkins::plugin { 'simple-theme-plugin':
    version => '0.2',
  }
  jenkins::plugin { 'timestamper':
    version => '1.3.1',
  }
  jenkins::plugin { 'token-macro':
    version => '1.5.1',
  }
  jenkins::plugin { 'url-change-trigger':
    version => '1.2',
  }
  jenkins::plugin { 'urltrigger':
    version => '0.24',
  }

  file { '/var/lib/jenkins/.ssh/config':
    ensure  => present,
    owner   => 'jenkins',
    group   => 'jenkins',
    mode    => '0640',
    require => File['/var/lib/jenkins/.ssh'],
    source  => 'puppet:///modules/jenkins/ssh_config',
  }

  exec { 'restart_jenkins':
    command => 'service jenkins restart',
    path    => ['/sbin', '/bin', '/usr/sbin', '/usr/bin'],
    require => Class['jenkins::master'],
  }

  class { 'project_config':
    url  => $project_config_repo,
  }

  if $manage_jenkins_jobs == true {

    class { '::jenkins::job_builder':
      url          => "http://${vhost_name}:8080/",
      username     => $jenkins_jobs_username,
      password     => $jenkins_jobs_password,
      git_revision => $jenkins_git_revision,
      git_url      => $jenkins_git_url,
      config_dir   => 'puppet:///modules/os_ext_testing/jenkins_job_builder/config',
      require      => [$::project_config::config_dir,
                       Exec['restart_jenkins']],
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

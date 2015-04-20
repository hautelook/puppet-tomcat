#
# Core Tomcat defined type for install and config
#
define tomcat::tomcat_application (
  $tomcat_base,
  $application_name,
  $application_root,
  $tomcat_user,
  $tomcat_port,
  $tomcat_shutdown_port,
  $jvm_envs,
  $classpath_append      = undef,
  $tomcat_pidfile        = "/var/tmp/${application_name}.pid",
  $tomcat_admin_user     = 'tomcat',
  $tomcat_admin_password = 's3cr3t',
  $jmxRegistryPort       = 10052,
  $jmxServerPort         = 10051) {
  include tomcat
  include tomcat::params


# We handle the special Jenkins user elsewhere. Don't create it in the tomcat module
  if $tomcat_user != 'jenkins' {
    group { $tomcat_user:
      ensure => present
    }

    user { $tomcat_user:
      ensure     => present,
      managehome => true,
      gid        => $tomcat_user,
      require    => Group[ $tomcat_user ],
      comment    => 'Tomcat Application Server'
    }
  }

  $application_dir = "${application_root}/${application_name}"
  $tomcat_log = "${application_dir}/logs/catalina.out"

  if $tomcat_base == '7' {
    $tomcat_version = $tomcat::params::tomcat_7
  }
  else {
    notify { 'tomcat-base-is-6': message => 'Tomcat base is 6' }
    $tomcat_version = $tomcat::params::tomcat_6
  }

    # download latest version of tomcat tar file
    file { "/var/lib/puppet/clientbucket/apache-tomcat-${tomcat_version}.tar.gz":
      ensure => present,
      owner  => root,
      group  => root,
      mode   => '0740',
      source => "puppet:///modules/tomcat/apache-tomcat-${tomcat_version}.tar.gz",
    }

exec { "extract_tomcat_archive_${application_name}":
      command   =>
      "/bin/tar -xz -f /var/lib/puppet/clientbucket/apache-tomcat-${tomcat_version}.tar.gz -C ${application_dir} && /bin/chown -R ${tomcat_user}:${tomcat_user} ${application_dir}",
      cwd       => $application_root,
      unless    => "/usr/bin/test -d ${application_dir}/bin",
      require   => [
          File["/var/lib/puppet/clientbucket/apache-tomcat-${tomcat_version}.tar.gz"],
          File[ $application_dir ],
      ],
      logoutput => true,
    }


    # move all files to app directory
    exec { "${application_dir}-mv-${tomcat_version}":
      command   => "/bin/mv ${application_dir}/apache-tomcat-${tomcat_version}/* ${application_dir}",
      onlyif    => "/usr/bin/test -d ${application_dir}/apache-tomcat-${tomcat_version}",
      require   => Exec["extract_tomcat_archive_${application_name}"],
      logoutput => true,
    }

    # remove empty tomcat app directory
    exec { "${application_dir}-rmdir-tomcat":
      command   => "/bin/rmdir ${application_dir}/apache-tomcat-${tomcat_version}",
      onlyif    => "/usr/bin/test -d ${application_dir}/apache-tomcat-${tomcat_version}",
      require   => Exec["${application_dir}-mv-${tomcat_version}"],
      logoutput => true,
    }

  # change application directory permissions to own tomcat
  file { $application_dir :
    ensure       => 'directory',
    mode         => '0755',
    owner        => $tomcat_user,
    group        => $tomcat_user,
#    recurse      => true,
    #    require => Exec["${application_dir}-rmdir-tomcat"],
  }

# Have Puppet manage tomcat service
  service { $application_name :
    ensure => running,
    enable => true,
  }

# Init script
  file { "/etc/init.d/${application_name}":
    content => template('tomcat/init.sh.erb'),
    owner   => $tomcat_user,
    group   => $tomcat_user,
    mode    => '0740',
    require => Exec["${application_dir}-mv-${tomcat_version}"],
    notify  => Service[ $application_name ],
  }

  file { "${application_dir}/bin/setenv.sh":
    content => template('tomcat/setenv.erb'),
    require => Exec["${application_dir}-mv-${tomcat_version}"],
    notify  => Service[ $application_name ],
  }

  file { "${application_dir}/conf/server.xml":
    content => template('tomcat/server.xml.erb'),
    require => Exec["${application_dir}-mv-${tomcat_version}"],
    notify  => Service[ $application_name ],
  }

  file { "${application_dir}/conf/catalina.properties":
    content => template('tomcat/catalina.properties.erb'),
    require => Exec["${application_dir}-mv-${tomcat_version}"],
    notify  => Service[ $application_name ],
  }

  file { "/etc/logrotate.d/${application_name}":
    content => template('tomcat/logrotate.erb'),
    require => Exec["${application_dir}-mv-${tomcat_version}"]
  }


  file { "${application_dir}/conf/tomcat-users.xml":
    content => template('tomcat/tomcat-users.xml.erb'),
    require => Exec["${application_dir}-mv-${tomcat_version}"],
    notify  => Service[ $application_name ],
  }

  file { "${application_dir}/bin/deploy_with_tomcat_manager.sh":
    content => template('tomcat/deploy_with_tomcat_manager.sh.erb'),
    owner   => $tomcat_user,
    group   => $tomcat_user,
    mode    => '0740',
    require => Exec["${application_dir}-mv-${tomcat_version}"]
  }

  file { "${application_dir}/bin/check_memory_leaks.sh":
    content => template('tomcat/check_memory_leaks.sh.erb'),
    owner   => $tomcat_user,
    group   => $tomcat_user,
    mode    => '0740',
    require => Exec["${application_dir}-mv-${tomcat_version}"]
  }

  file { "${application_dir}/bin/list-applications.sh":
    content => template('tomcat/list-applications.sh.erb'),
    owner   => $tomcat_user,
    group   => $tomcat_user,
    mode    => '0740',
    require => Exec["${application_dir}-mv-${tomcat_version}"]
  }

  file { "${application_dir}/bin/undeploy_with_tomcat_manager.sh":
    content => template('tomcat/undeploy_with_tomcat_manager.sh.erb'),
    owner   => $tomcat_user,
    group   => $tomcat_user,
    mode    => '0740',
    require => Exec["${application_dir}-mv-${tomcat_version}"]
  }

  # # jmx-remote jar
  file { "${application_dir}/lib/catalina-jmx-remote.jar":
    source  => 'puppet:///modules/tomcat/utility/catalina-jmx-remote.jar',
    owner   => $tomcat_user,
    group   => $tomcat_user,
    mode    => '0740',
    require => Exec["${application_dir}-mv-${tomcat_version}"]
  }

  # # commons-logging jar
  file { "${application_dir}/lib/commons-logging-api.jar":
    source  => 'puppet:///modules/tomcat/utility/commons-logging-api.jar',
    owner   => $tomcat_user,
    group   => $tomcat_user,
    mode    => '0740',
    require => Exec["${application_dir}-mv-${tomcat_version}"]
  }

  # # mail jar
  file { "${application_dir}/lib/mail.jar":
    source  => 'puppet:///modules/tomcat/utility/mail.jar',
    owner   => $tomcat_user,
    group   => $tomcat_user,
    mode    => '0740',
    require => Exec["${application_dir}-mv-${tomcat_version}"]
  }

  # # tomcat logback
  file { "${application_dir}/conf/tomcat-logback.xml":
    source  => 'puppet:///modules/tomcat/tomcat-logback.xml',
    owner   => $tomcat_user,
    group   => $tomcat_user,
    mode    => '0740',
    require => Exec["${application_dir}-mv-${tomcat_version}"],
    notify  => Service[ $application_name ],
  }


  ## jmx remote password and access files
  file { "${application_dir}/conf/jmxremote.access":
    source  => 'puppet:///modules/tomcat/jmxremote.access',
    owner   => $tomcat_user,
    group   => $tomcat_user,
    mode    => '0740',
    require => Exec["${application_dir}-mv-${tomcat_version}"],
    notify  => Service[ $application_name ],
  }

  file { "${application_dir}/conf/jmxremote.password":
    source  => 'puppet:///modules/tomcat/jmxremote.password',
    owner   => $tomcat_user,
    group   => $tomcat_user,
    mode    => '0740',
    require => Exec["${application_dir}-mv-${tomcat_version}"],
    notify  => Service[ $application_name ],
  }
}

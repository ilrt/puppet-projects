# == Resource type: project
#
# A top level project type.
define projects::project (
  $apache = {},
  $tomcat = {},
  $mysql = {},
  $apache_common = {},
  $default_vhost = true,
  $uid = undef,
  $gid = undef,
  $users = [],
  $ensure = undef,
  $description = ""
) {

  # If least one project definition exists for this host, creaste the base structure
  if ($apache != {} or
      $mysql != {} or
      $tomcat !={} or
      $ensure == 'present') {
    user { $title:
      comment => $description,
      uid     => $uid,
      gid     => $gid,
      home    => "$::projects::basedir/$title"
    }

    group { $title:
      gid     => $gid,
      members => $users,
    }

    project_user { $users:
      group => $title
    }

    file { [
           "$::projects::basedir/$title",
           ] :
      ensure => directory,
      owner  => $uid,
      group  => $gid,
      mode   => '0755',
    }

    file { "$::projects::basedir/$title/.ssh":
      ensure   => 'directory',
      owner  => $uid,
      group  => $gid,
      mode     => '700',
      seltype  => 'ssh_home_t',
    }

    file { "$::projects::basedir/$title/.settings":
      ensure   => 'directory',
      owner  => $uid,
      group  => $gid,
      mode     => '775',
      seltype  => 'httpd_sys_content_t',
    }

    file { [
           "$::projects::basedir/$title/etc",
           ] :
      ensure => directory,
      owner  => $uid,
      group  => $gid,
      mode   => '0775',
    }

    file { [
           "$::projects::basedir/$title/var",
           ] :
      ensure => directory,
      owner  => $uid,
      group  => $gid,
      seltype => 'httpd_sys_rw_content_t',
      mode   => '0775',
    }

    file { [
           "$::projects::basedir/$title/lib",
           ] :
      ensure => directory,
      owner  => $uid,
      group  => $gid,
      mode   => '0775',
      seltype => 'httpd_sys_content_t',
    }

    file { "$::projects::basedir/$title/var/log":
      ensure  => directory,
      owner   => $uid,
      group   => $gid,
      mode    => '0755',
      seltype => 'httpd_log_t',
    }

    concat { "${::projects::basedir}/${title}/README":
      owner => $title,
      group => $title,
      mode  => '0640',
    }

    concat::fragment { "${title} header":
      target  => "${::projects::basedir}/${title}/README",
      content => "Project: ${title}\n\n",
      order   => '01'
    }

  }

  # Create apache vhosts
  if ($apache != {}) {
    projects::project::apache { $title:
      vhosts        => $apache,
      apache_common => $apache_common,
      default_vhost => $default_vhost,
    }
  }

  # Create Tomcat services
  if ($tomcat != {}) {
    projects::project::tomcat { $title:
      ajp_port      => pick($tomcat[ajp_port],'8009')
    }
  }

  # Create MySQL server
  if ($mysql != {}) {
    projects::project::mysql { $title:
      user     => $title,
      password => pick($mysql[password],'changeme'),
      host     => pick($mysql[host],'localhost'),
      grant    => pick($mysql[grant],['ALL']),
    }
  }

  sudo::conf { "${title}-reset-perms":
    priority => 25,
    content  => "%${title} ALL=(ALL) NOPASSWD: /usr/local/bin/reset-perms"
  }
}

define project_user (
  $group = undef
) {
  create_resources('@user', { $title => {} })
  User <| title == $title |> {
    groups +> $group,
  }
}

# == Class: projects
#
# A puppet module to manage top level projects.
#
# === Examples
#
# === Authors
#
# Dan Foster <dan@zem.org.uk>
#
# === Copyright
#
# Copyright 2015 Dan Foster, unless otherwise noted.
#
class projects (
  $basedir = '/srv/projects',
  $symlink = [],
  $projects,
) inherits ::projects::params {

  file { $basedir:
    ensure => directory,
    mode   => '0775',
    owner  => root,
    group  => root,
  }

  file { $symlink:
    ensure => symlink,
    target => $basedir,
  }

  file { '/usr/local/bin/reset-perms':
    source  => "puppet:///modules/projects/bin/reset-perms",
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
  }

  create_resources('projects::project', $projects)
}

# -- Resource type: project::apache
#
# Defines an apache project
define projects::project::apache (
  $vhosts           = {},
  $apache_user      = 'apache',
  $apache_common    = {},
  $default_vhost    = true,
) {
  if !defined(Class['::apache']) {
    ensure_resource('class', '::apache', {
      default_vhost         => $default_vhost,
      use_optional_includes => true,
      mpm_module            => false,
      service_ensure        => running,
      service_enable        => true,
      server_signature      => 'Off',
      server_tokens         => 'Prod',
      keepalive_timeout     => '3',
    })
    include ::apache::mod::proxy
    include ::apache::mod::alias
    include ::apache::mod::proxy_http
    include ::apache::mod::proxy_ajp
    include ::apache::mod::headers

    unless $apache_common['no_ldap'] {
      class {'::apache::mod::authnz_ldap':
        verify_server_cert => false
      }
    }

    include ::apache::mod::status

    if defined(Class['::selinux']) {
      ensure_resource('selinux::boolean', 'httpd_can_connect_ldap', {'ensure' =>  'on'})
      ensure_resource('selinux::boolean', 'httpd_can_network_connect_db', {'ensure' =>  'on'})
      ensure_resource('selinux::boolean', 'httpd_can_network_connect', {'ensure' =>  'on'})
      ensure_resource('selinux::boolean', 'httpd_can_sendmail', {'ensure' =>  'on'})
      ensure_resource('selinux::boolean', 'httpd_can_network_memcache', {'ensure' =>  'on'})
    }


    # installing apache doesn't appear to pull in these deps.
    # Problem with the RPM or the puppetlabs/apache module?
    package { ['apr', 'apr-util']:
      ensure => present
    }
  }

  if $apache_common['php'] {
    include '::apache::mod::php'
    ensure_packages(['php-pdo', 'php-mysql', 'php-mbstring', 'php-snmp'])
  }

  if $apache_common['mpm'] == 'event' {
    include ::apache::mod::event
  } elsif $apache_common['mpm'] == 'worker' {
    include ::apache::mod::worker
  } else {
    include ::apache::mod::prefork
  }

  if $apache_common['use_python3_wsgi'] {
    package { 'mod-wsgi':
      ensure   => '4.5.14',
      provider => 'pip3',
      require  => Package['httpd', 'httpd-devel'],
      notify   => Service['httpd'],
    }
    if $apache_common['mod_wsgi_so'] {
      $mod_wsgi_so = $apache_common['mod_wsgi_so']
    } else {
      $mod_wsgi_so = "/usr/lib64/python3.4/site-packages/mod_wsgi/server/mod_wsgi-py34.cpython-34m.so"
    }
    file { '/etc/httpd/conf.modules.d/wsgi3.load':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => epp('projects/apache/wsgi3.conf.epp', { mod_wsgi_so => $mod_wsgi_so }),
      require => Package['httpd'],
      notify  => Service['httpd'],
    }
  } else {
    include ::apache::mod::wsgi
  }

  file { "${::projects::basedir}/${title}/var/log/httpd":
    ensure  => directory,
    owner   => $apache_user,
    group   => $title,
    mode    => '0750',
    seltype => 'httpd_log_t',
    require => File["${::projects::basedir}/${title}/var/log"],
  }

  file { "${::projects::basedir}/${title}/etc/apache":
    ensure  => directory,
    owner   => $title,
    group   => $title,
    seltype => 'httpd_config_t',
    require => File["${::projects::basedir}/${title}/etc"],
  }

  file { "${::projects::basedir}/${title}/etc/apache/conf.d":
    ensure  => directory,
    owner   => $apache_user,
    group   => $title,
    mode    => '2770',
    seltype => 'httpd_config_t',
    require => File["${::projects::basedir}/${title}/etc/apache"],
  }

  file { "${::projects::basedir}/${title}/etc/ssl":
    ensure  => directory,
    owner   => $title,
    group   => $title,
    seltype => 'cert_t',
    require => File["${::projects::basedir}/${title}/etc"],
  }

  file { [ "${::projects::basedir}/${title}/etc/ssl/private",
    "${::projects::basedir}/${title}/etc/ssl/certs",
    "${::projects::basedir}/${title}/etc/ssl/csrs",
    "${::projects::basedir}/${title}/etc/ssl/conf"] :
    ensure  => directory,
    owner   => $title,
    group   => $title,
    require => File["${::projects::basedir}/${title}/etc/ssl"],
  }

  sudo::conf { "${title}-apache":
    priority => 25,
    content  => "%${title} ALL= (ALL) NOPASSWD: /sbin/apachectl"
  }

  create_resources('::projects::project::apache::vhost', $vhosts, {
    'projectname' => $title,
    'apache_user' => $apache_user
  })
}

# -- Resource type: project::apache::vhost
#
# Configures and project apache vhost.
#
# "forwarded_custom_log" decides whether to include custom log config
# fragments to handle forwarded (with X-Forwarded-For header)
# connections.  This is a legacy option and the use of "mod_remoteip"
# should be used in preference to this.
#   Enabled by default at present but a future release will disable this.
#
define projects::project::apache::vhost (
  $projectname = undef,
  $docroot = 'www',
  $options = ['Indexes','FollowSymLinks','MultiViews'],
  $allow_override = ['None'],
  $port = 80,
  $vhost_name = $title,
  $ssl = false,
  $php = false,
  $apache_user = 'apache',
  $altnames = [],
  $ip = undef,
  $cert_name = $vhost_name,
  $redirect = undef,
  $redirect_to_https = false,
  $php_values = {},
  $forwarded_custom_log = true,
) {

  if ($ip) {
    $ip_based = true
  } else {
    $ip_based = false
  }

  concat::fragment { "${projectname} apache ${title} vhost":
    target  => "${::projects::basedir}/${projectname}/README",
    content => "Apache Virtualhost: ${vhost_name}
  hostname: ${vhost_name}
  port: ${port}
  SSL: ${ssl}
  PHP support: ${php}
  altnames: ${altnames}\n",
    order   => '10'
  }

  file { "${::projects::basedir}/${projectname}/etc/apache/conf.d/${title}":
    ensure  => directory,
    owner   => $apache_user,
    group   => $projectname,
    mode     => '2775',
    seltype => 'httpd_config_t',
    require => File["${::projects::basedir}/${projectname}/etc/apache/conf.d"],
  }

  if $docroot !~ /^\// {
    $full_docroot = "${::projects::basedir}/${projectname}/var/${docroot}"
  }
  else {
    $full_docroot = $docroot
  }

  $directories = [
    { path => $full_docroot, options => $options, allow_override => $allow_override },
  ]

  if $forwarded_custom_log {
    $custom_log_entries = {
      access_log_env_var    => "!forwarded",
      custom_fragment       => "LogFormat \"%{X-Forwarded-For}i %l %u %t \\\"%r\\\" %s %b \\\"%{Referer}i\\\" \\\"%{User-Agent}i\\\"\" proxy
      SetEnvIf X-Forwarded-For \"^.*\\..*\\..*\\..*\" forwarded
      CustomLog \"${::projects::basedir}/${projectname}/var/log/httpd/${title}_access.log\" proxy env=forwarded",
    }
  } else {
    $custom_log_entries = {}
  }

  if $redirect {
    ::apache::vhost { $title:
      servername            => $vhost_name,
      port                  => $port,
      ssl                   => $ssl,
      docroot               => $full_docroot,
      redirect_status       => 'permanent',
      redirect_dest         => $redirect,
      logroot               => "${::projects::basedir}/${projectname}/var/log/httpd",
      use_optional_includes => "true",
      additional_includes   => 
      ["${::projects::basedir}/${projectname}/etc/apache/conf.d/*.conf",
      "${::projects::basedir}/${projectname}/etc/apache/conf.d/${title}/*.conf"],
      ssl_cert              => 
      "${::projects::basedir}/${projectname}/etc/ssl/certs/${cert_name}.crt",
      ssl_chain             => 
      "${::projects::basedir}/${projectname}/etc/ssl/certs/${cert_name}.crt",
      ssl_key               => 
      "${::projects::basedir}/${projectname}/etc/ssl/private/${cert_name}.key",
      serveraliases         => $altnames,
      ip                    => $ip,
      ip_based              => $ip_based,
      add_listen            => false,
      headers               => 'Set Strict-Transport-Security "max-age=63072000; includeSubdomains;"',
      *                     => $custom_log_entries,
    }
  }
  elsif $redirect_to_https {
    ::apache::vhost { $title:
      servername            => $vhost_name,
      port                  => $port,
      docroot               => $full_docroot,
      redirect_status       => 'permanent',
      redirect_dest         => "https://${title}/",
      logroot               => "${::projects::basedir}/${projectname}/var/log/httpd",
      use_optional_includes => "true",
      additional_includes   => 
      ["${::projects::basedir}/${projectname}/etc/apache/conf.d/*.conf",
      "${::projects::basedir}/${projectname}/etc/apache/conf.d/${title}/*.conf"],
      ip                    => $ip,
      ip_based              => $ip_based,
      add_listen            => false,
      headers               => 'Set Strict-Transport-Security "max-age=63072000; includeSubdomains;"',
      *                     => $custom_log_entries,
    }
  }
  else {
    ::apache::vhost { $title:
      servername            => $vhost_name,
      port                  => $port,
      ssl                   => $ssl,
      docroot               => $full_docroot,
      directories           => $directories,
      logroot               => "${::projects::basedir}/${projectname}/var/log/httpd",
      use_optional_includes => "true",
      additional_includes   => 
      ["${::projects::basedir}/${projectname}/etc/apache/conf.d/*.conf",
      "${::projects::basedir}/${projectname}/etc/apache/conf.d/${title}/*.conf"],
      ssl_cert              => 
      "${::projects::basedir}/${projectname}/etc/ssl/certs/${cert_name}.crt",
      ssl_chain             => 
      "${::projects::basedir}/${projectname}/etc/ssl/certs/${cert_name}.crt",
      ssl_key               => 
      "${::projects::basedir}/${projectname}/etc/ssl/private/${cert_name}.key",
      serveraliases         => $altnames,
      ip                    => $ip,
      ip_based              => $ip_based,
      add_listen            => false,
      headers               => 'Set Strict-Transport-Security "max-age=63072000; includeSubdomains;"',
      php_values            => $php_values,
      *                     => $custom_log_entries,
    }
  }

  if !defined(Apache::Listen["$port"]) {
    ::apache::listen { "$port":}
  }

  if !defined(File[$full_docroot]) {
    file { $full_docroot:
      ensure  => directory,
      owner   => $apache_user,
      group   => $projectname,
      mode    => '0770',
      seltype => 'httpd_sys_content_t',
    }
  }

  ensure_resource('file', [
	"${::projects::basedir}/${projectname}/etc/ssl/certs/${cert_name}.crt",
	"${::projects::basedir}/${projectname}/etc/ssl/private/${cert_name}.key"
    ],
    { seltype => 'cert_t' }
  )

  if !defined(Firewall["050 accept Apache ${port}"]) {
    firewall { "050 accept Apache ${port}":
      dport  => $port,
      proto  => tcp,
      action => accept,
    }
  }

}

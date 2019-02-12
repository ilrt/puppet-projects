# Puppet Projects

This documentation is targetted to users of projects deployed by this module.

A project is a standard structured area where non-privilidged users can
configure and deploy pre-defined services.  The default base location for
projects is `/srv/projects/<projectname>`, the rest of this documentation refers to paths relative to this base location.

# Apache

If your project has an apache component, it will have deployed one of more virtualhosts.
Extra apache config snippets can be added to `etc/apache/conf.d/` and `etc/apache/conf.d/$vhost_key`.
If SSL is enabled, A SSL private key, CSR and self-signed certificate will be generated under `etc/ssl`. If a private key or certificate have manually be put in place, it should not be overwritten.

You should be able to control apache by running `/sbin/apachectl` as root via sudo.
Apache logs are written to `var/log/httpd/`

# Tomcat

If your project has a tomcat component, it will have deployed a tomcat instance. Webapps can be deployed under `var/webapps`.

`etc/tomcat-env` is symlinked to the tomcats `setenv.sh`, use this to set any environment variables you require.

It is possible to start and stop the tomcat instance via sudo as the tomcat user. e.g.: `sudo -u tomcat lib/tomcat/bin/shutdown.sh`. Note that tomcat will start up the tomcat instance on its next run.

# MySQL

If your project has a MySQL component, a database and user will have been created.

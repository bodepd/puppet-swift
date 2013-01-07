$keystone_db_password = 'keystone_db_password'
$keystone_admin_token = 'keystone_token'
$admin_email          = 'dan@example_company.com'
$admin_password       = 'admin_password'
$verbose              = true
$swift_user_password  = 'swift_user'
$swift_proxy_address  = '192.168.101.17'
# This node can be used to deploy a keystone service.
# This service only contains the credentials for authenticating
# swift
node keystone {
  # set up mysql server
  class { 'mysql::server':
    config_hash => {
      # the priv grant fails on precise if I set a root password
      # TODO I should make sure that this works
      # 'root_password' => $mysql_root_password,
      'bind_address'  => '0.0.0.0'
    }
  }
  # set up all openstack databases, users, grants
  class { 'keystone::db::mysql':
    password => $keystone_db_password,
  }

  # in stall and configure the keystone service
  class { 'keystone':
    admin_token  => $keystone_admin_token,
    # we are binding keystone on all interfaces
    # the end user may want to be more restrictive
    bind_host    => '0.0.0.0',
    log_verbose  => $verbose,
    log_debug    => $verbose,
    catalog_type => 'sql',
  }

  # set up keystone database
  # set up the keystone config for mysql
  class { 'keystone::config::mysql':
    password => $keystone_db_password,
  }
  # set up keystone admin users
  class { 'keystone::roles::admin':
    email    => $admin_email,
    password => $admin_password,
  }
  # configure the keystone service user and endpoint
  class { 'swift::keystone::auth':
    password => $swift_user_password,
    address  => $swift_proxy_address,
  }
}

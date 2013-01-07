#
# Example file for building out a multi-node environment
#
# This example creates nodes of the following roles:
#   swift_storage - nodes that host storage servers
#   swift_proxy - nodes that serve as a swift proxy
#   swift_ringbuilder - nodes that are responsible for
#     rebalancing the rings
#
# This example assumes a few things:
#   * the multi-node scenario requires a puppetmaster
#   * it assumes that networking is correctly configured
#
# These nodes need to be brought up in a certain order
#
# 1. storage nodes
# 2. ringbuilder
# 3. run the storage nodes again (to synchronize the ring db)
# 4. run the proxy
# 5. test that everything works!!
# this site manifest serves as an example of how to
# deploy various swift environments


#$swift_admin_password = 'admin_password'
$swift_admin_password = hiera('admin_password', 'admin_password')

 # swift specific configurations
#$swift_shared_secret = 'changeme'
$swift_shared_secret = hiera('swift_shared_secret', 'changeme')


#$swift_local_net_ip   = $ipaddress_eth0
$swift_local_net_ip = hiera('swift_local_net_ip', $ipaddress_eth0)

#$controller_node_public = '192.168.101.17'
$controller_node_public = hiera('openstack_controller', '192.168.101.17')

$swift_zone = hiera('swift_zone', 1)
# configurations that need to be applied to all swift nodes
node swift_base  {

  class { 'ssh::server::install': }

  class { 'swift':
    # not sure how I want to deal with this shared secret
    swift_hash_suffix => $swift_shared_secret,
    package_ensure    => latest,
  }

}

#
# The example below is used to model swift storage nodes that
# manage 2 endpoints.
#
# The endpoints are actually just loopback devices. For real deployments
# they would need to be replaced with something that create and mounts xfs
# partitions
#
node /swift-storage/ inherits swift_base {

  # create xfs partitions on a loopback device and mount them
  swift::storage::loopback { ['1', '2']:
    base_dir     => '/srv/loopback-device',
    mnt_base_dir => '/srv/node',
    require      => Class['swift'],
  }

  # install all swift storage servers together
  class { 'swift::storage::all':
    storage_local_net_ip => $swift_local_net_ip,
  }

  # specify endpoints per device to be added to the ring specification
  @@ring_object_device { "${swift_local_net_ip}:6000/1":
    zone        => $swift_zone,
    weight      => 1,
  }

  @@ring_object_device { "${swift_local_net_ip}:6000/2":
    zone        => $swift_zone,
    weight      => 1,
  }

  @@ring_container_device { "${swift_local_net_ip}:6001/1":
    zone        => $swift_zone,
    weight      => 1,
  }

  @@ring_container_device { "${swift_local_net_ip}:6001/2":
    zone        => $swift_zone,
    weight      => 1,
  }
  # TODO should device be changed to volume
  @@ring_account_device { "${swift_local_net_ip}:6002/1":
    zone        => $swift_zone,
    weight      => 1,
  }

  @@ring_account_device { "${swift_local_net_ip}:6002/2":
    zone        => $swift_zone,
    weight      => 1,
  }

  # collect resources for synchronizing the ring databases
  Swift::Ringsync<<||>>

}


node /swift-proxy/ inherits swift_base {


  # curl is only required so that I can run tests
  package { 'curl': ensure => present }

  class { 'memcached':
    listen_ip => '127.0.0.1',
  }

  # specify swift proxy and all of its middlewares
  class { 'swift::proxy':
    proxy_local_net_ip => $swift_local_net_ip,
    pipeline           => [
      'catch_errors',
      'healthcheck',
      'cache',
      'ratelimit',
      'swift3',
      's3token',
      'authtoken',
      'keystone',
      'proxy-server'
    ],
    account_autocreate => true,
    # TODO where is the  ringbuilder class?
    require            => Class['swift::ringbuilder'],
  }

  # configure all of the middlewares
  class { [
    'swift::proxy::catch_errors',
    'swift::proxy::healthcheck',
    'swift::proxy::cache',
    'swift::proxy::swift3',
  ]: }
  class { 'swift::proxy::ratelimit':
    clock_accuracy         => 1000,
    max_sleep_time_seconds => 60,
    log_sleep_time_seconds => 0,
    rate_buffer_seconds    => 5,
    account_ratelimit      => 0
  }
  class { 'swift::proxy::s3token':
    # assume that the controller host is the swift api server
    auth_host     => $controller_node_public,
    auth_port     => '35357',
  }
  class { 'swift::proxy::keystone':
    operator_roles => ['admin', 'SwiftOperator'],
  }
  class { 'swift::proxy::authtoken':
    admin_user        => 'swift',
    admin_tenant_name => 'services',
    admin_password    => $swift_admin_password,
    # assume that the controller host is the swift api server
    auth_host         => $controller_node_public,
  }

  # collect all of the resources that are needed
  # to balance the ring
  Ring_object_device <<| |>>
  Ring_container_device <<| |>>
  Ring_account_device <<| |>>

  # create the ring
  class { 'swift::ringbuilder':
    # the part power should be determined by assuming 100 partitions per drive
    part_power     => '18',
    replicas       => '3',
    min_part_hours => 1,
    require        => Class['swift'],
  }

  # sets up an rsync db that can be used to sync the ring DB
  class { 'swift::ringserver':
    local_net_ip => $swift_local_net_ip,
  }

  # exports rsync gets that can be used to sync the ring files
  @@swift::ringsync { ['account', 'object', 'container']:
   ring_server => $swift_local_net_ip
 }

  # deploy a script that can be used for testing
  file { '/tmp/swift_keystone_test.rb':
    source => 'puppet:///modules/swift/swift_keystone_test.rb'
  }
}


require File.join(File.dirname(__FILE__), '..', 'swift_ring_builder')
Puppet::Type.type(:ring_object_device).provide(
  :swift_ring_builder,
  :parent => Puppet::Provider::SwiftRingBuilder
) do

  optional_commands :swift_ring_builder => 'swift-ring-builder'

  # TODO maybe this should be a parameter eventually so that
  # it can be configurable
  def self.builder_file_path
    '/etc/swift/object.builder'
  end

end

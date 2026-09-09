# frozen_string_literal: true

# This file constructs only the base VM. The host-side deployer transfers an
# exact Git bundle, then runs the same H0 and H1 roles used on bare metal.
TRUSTED_BASE_BOX = "kin/sanitized-ubuntu-26.04"
TRUSTED_BASE_BOX_VERSION = "20260823.0"
BASE_BOX = ENV.fetch("KIN_NODE_BOX", TRUSTED_BASE_BOX)
BASE_BOX_VERSION = ENV.fetch("KIN_NODE_BOX_VERSION", TRUSTED_BASE_BOX_VERSION)

unless BASE_BOX == TRUSTED_BASE_BOX && BASE_BOX_VERSION == TRUSTED_BASE_BOX_VERSION
  raise "only the admitted Canonical-derived Kin Ubuntu 26.04 base is permitted; no fallback is configured"
end

Vagrant.configure("2") do |config|
  config.vm.box = BASE_BOX
  config.vm.box_version = BASE_BOX_VERSION
  config.vm.box_check_update = false
  config.vm.hostname = "kin-node"

  # Avoid VirtualBox shared-folder and Guest Additions coupling. The node gets
  # its configuration from Git, not an implicit mount of the host checkout.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # Repository content crosses the boundary as a Git bundle. No host GitHub
  # credential or agent socket is exposed to the guest.
  config.ssh.forward_agent = false

  config.vm.provider "virtualbox" do |virtualbox|
    virtualbox.name = ENV.fetch("KIN_NODE_VM_NAME", "kin-node")
    virtualbox.memory = Integer(ENV.fetch("KIN_NODE_VM_MEMORY_MB", "2048"))
    virtualbox.cpus = Integer(ENV.fetch("KIN_NODE_VM_CPUS", "2"))
    virtualbox.gui = false
    virtualbox.customize ["modifyvm", :id, "--vrde", "off"]
  end

  config.vm.provision "shell",
                      name: "Base execution bootstrap",
                      privileged: true,
                      path: "scripts/base-bootstrap.sh"
end

# frozen_string_literal: true

# This file constructs only the base VM. The host-side deployer transfers an
# exact Git bundle, then runs the same H0 and H1 roles used on bare metal.
Vagrant.configure("2") do |config|
  config.vm.box = ENV.fetch("KIN_NODE_BOX", "bento/ubuntu-26.04")
  config.vm.box_version = ENV.fetch("KIN_NODE_BOX_VERSION", "202606.01.0")
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

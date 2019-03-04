resource "digitalocean_droplet" "cassandra_node" {
  image              = "centos-7-x64"
  name               = "cassandra-node-${count.index}"
  region             = "fra1"
  private_networking = true
  size               = "s-6vcpu-16gb"
  ssh_keys           = ["${data.digitalocean_ssh_key.default.id}"]
  tags               = ["${digitalocean_tag.otr.id}"]
  count              = "${var.node_count}"
}

resource "null_resource" "cassandra_cluster" {
  connection {
    host        = "${element(digitalocean_droplet.cassandra_node.*.ipv4_address, count.index)}"
    agent       = false
    private_key = "${file("~/.ssh/id_ed25519")}"
  }

  provisioner "file" {
    source      = "conf/cassandra.repo"
    destination = "/etc/yum.repos.d/cassandra.repo"
  }

  provisioner "file" {
    source      = "conf/disable-transparent-hugepages"
    destination = "/etc/init.d/disable-transparent-hugepages"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir /etc/tuned/no-thp",
    ]
  }

  provisioner "file" {
    source      = "conf/tuned.conf"
    destination = "/etc/tuned/no-thp/tuned.conf"
  }

  provisioner "file" {
    source      = "conf/99-cassandra-limits.conf"
    destination = "/etc/security/limits.d/99-cassandra-limits.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "yum -y update",
      "yum -y install java-1.8.0-openjdk",
      "yum -y install cassandra",
      "chkconfig cassandra on",
      "chmod 755 /etc/init.d/disable-transparent-hugepages",
      "chkconfig --add disable-transparent-hugepages",
      "tuned-adm profile no-thp",
      "sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config",
      "sed -i 's/^listen_address:.*/listen_address: ${element(digitalocean_droplet.cassandra_node.*.ipv4_address_private, count.index)}/g' /etc/cassandra/conf/cassandra.yaml",
      "sed -i 's/^rpc_address:.*/rpc_address: ${element(digitalocean_droplet.cassandra_node.*.ipv4_address_private, count.index)}/g' /etc/cassandra/conf/cassandra.yaml",
      "sed -i 's/^endpoint_snitch:.*/endpoint_snitch: GossipingPropertyFileSnitch/g' /etc/cassandra/conf/cassandra.yaml",
      "sed -i 's/- seeds:.*/- seeds: \"${element(digitalocean_droplet.cassandra_node.*.ipv4_address_private, 0)}\"/g' /etc/cassandra/conf/cassandra.yaml",
      "echo >> /etc/cassandra/conf/cassandra.yaml",
      "echo 'auto_bootstrap: false' >> /etc/cassandra/conf/cassandra.yaml",
      "echo >> /etc/cassandra/conf/cassandra.yaml",
      "shutdown -r +0",
    ]
  }

  count = "${var.node_count}"
}

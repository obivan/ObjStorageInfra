provider "digitalocean" {
  token = ""
}

data "digitalocean_ssh_key" "default" {
  name = "Personal"
}

resource "digitalocean_tag" "otr" {
  name = "otr"
}

variable "node_count" {
  default = 3
}

resource "digitalocean_droplet" "benchmark_node" {
  image              = "centos-7-x64"
  name               = "benchmark-node"
  region             = "fra1"
  private_networking = true
  size               = "s-1vcpu-1gb"
  ssh_keys           = ["${data.digitalocean_ssh_key.default.id}"]
  tags               = ["${digitalocean_tag.otr.id}"]

  connection {
    agent       = false
    private_key = "${file("~/.ssh/id_ed25519")}"
  }

  provisioner "remote-exec" {
    inline = [
      "yum -y update",
      "yum -y install java-1.8.0-openjdk",
      "curl -O --location https://github.com/brianfrankcooper/YCSB/releases/download/0.15.0/ycsb-0.15.0.tar.gz",
      "tar xfvz ycsb-0.15.0.tar.gz",
      "rm -f ycsb-0.15.0.tar.gz",
    ]
  }
}

resource "digitalocean_droplet" "cassandra_node" {
  image              = "centos-7-x64"
  name               = "cassandra-node-${count.index}"
  region             = "fra1"
  private_networking = true
  size               = "s-1vcpu-1gb"
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

  provisioner "remote-exec" {
    inline = [
      "yum -y update",
      "yum -y install java-1.8.0-openjdk",
      "yum -y install cassandra",
      "chkconfig cassandra on",
      "sed -i 's/^listen_address:.*/listen_address: ${element(digitalocean_droplet.cassandra_node.*.ipv4_address_private, count.index)}/g' /etc/cassandra/conf/cassandra.yaml",
      "sed -i 's/^rpc_address:.*/rpc_address: ${element(digitalocean_droplet.cassandra_node.*.ipv4_address_private, count.index)}/g' /etc/cassandra/conf/cassandra.yaml",
      "sed -i 's/^endpoint_snitch:.*/endpoint_snitch: GossipingPropertyFileSnitch/g' /etc/cassandra/conf/cassandra.yaml",

      # only one seed node
      "sed -i 's/- seeds:.*/- seeds: \"${element(digitalocean_droplet.cassandra_node.*.ipv4_address_private, 0)}\"/g' /etc/cassandra/conf/cassandra.yaml",

      # initialize empty cluster
      "echo >> /etc/cassandra/conf/cassandra.yaml",
      "echo 'auto_bootstrap: false' >> /etc/cassandra/conf/cassandra.yaml",
      "echo >> /etc/cassandra/conf/cassandra.yaml",
    ]
  }

  count = "${var.node_count}"
}

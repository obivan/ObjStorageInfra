resource "digitalocean_droplet" "mongodb_node" {
  image              = "centos-7-x64"
  name               = "mongodb-node-${count.index}"
  region             = "fra1"
  private_networking = true
  size               = "s-1vcpu-1gb"                               # todo: s-6vcpu-16gb
  ssh_keys           = ["${data.digitalocean_ssh_key.default.id}"]
  tags               = ["${digitalocean_tag.otr.id}"]
  count              = "${var.node_count}"
}

resource "null_resource" "mongodb_replicaset" {
  connection {
    host        = "${element(digitalocean_droplet.mongodb_node.*.ipv4_address, count.index)}"
    agent       = false
    private_key = "${file("~/.ssh/id_ed25519")}"
  }

  provisioner "file" {
    source      = "conf/mongodb.repo"
    destination = "/etc/yum.repos.d/mongodb.repo"
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
    source      = "conf/99-mongo-limits.conf"
    destination = "/etc/security/limits.d/99-mongo-limits.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "yum -y update",
      "yum -y install mongodb-org",
      "systemctl enable mongod",
      "chmod 755 /etc/init.d/disable-transparent-hugepages",
      "chkconfig --add disable-transparent-hugepages",
      "tuned-adm profile no-thp",
      "sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config",
      "sed -i 's/^  bindIp:.*/  bindIp: 127.0.0.1,${element(digitalocean_droplet.mongodb_node.*.ipv4_address_private, count.index)}/g' /etc/mongod.conf",
      "echo >> /etc/mongod.conf",
      "echo 'replication:' >> /etc/mongod.conf",
      "echo '  replSetName: \"rs0\"' >> /etc/mongod.conf",
      "echo >> /etc/mongod.conf",
      "shutdown -r +0",
    ]
  }

  count = "${var.node_count}"
}

resource "null_resource" "mongodb_replicaset_initialize" {
  depends_on = ["null_resource.mongodb_replicaset"]

  connection {
    host        = "${digitalocean_droplet.mongodb_node.0.ipv4_address}"
    agent       = false
    private_key = "${file("~/.ssh/id_ed25519")}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'rs.initiate( {_id : \"rs0\", members: [' >> /root/init_rs0.txt",
      "echo '${join(",\n", formatlist("{ _id: @, host: \"%s\" }", digitalocean_droplet.mongodb_node.*.ipv4_address_private))}' >> /root/init_rs0.txt",
      "echo ']})' >> /root/init_rs0.txt",
      "sleep 10",
      "cat /root/init_rs0.txt | awk '{gsub(/@/, NR-2); print }' | mongo",
    ]
  }
}

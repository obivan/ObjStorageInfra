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
  size               = "s-4vcpu-8gb"
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
      "curl -O -L https://github.com/brianfrankcooper/YCSB/releases/download/0.15.0/ycsb-0.15.0.tar.gz",
      "tar xfvz ycsb-0.15.0.tar.gz",
      "rm -f ycsb-0.15.0.tar.gz",
      "rm -f ycsb-0.15.0/s3-binding/lib/aws-java-sdk-core-1.10.20.jar",
      "rm -f ycsb-0.15.0/s3-binding/lib/aws-java-sdk-kms-1.10.20.jar",
      "rm -f ycsb-0.15.0/s3-binding/lib/aws-java-sdk-s3-1.10.20.jar",
      "(cd ycsb-0.15.0/s3-binding/lib && curl -O -L http://central.maven.org/maven2/com/amazonaws/aws-java-sdk-core/1.10.77/aws-java-sdk-core-1.10.77.jar)",
      "(cd ycsb-0.15.0/s3-binding/lib && curl -O -L http://central.maven.org/maven2/com/amazonaws/aws-java-sdk-kms/1.10.77/aws-java-sdk-kms-1.10.77.jar)",
      "(cd ycsb-0.15.0/s3-binding/lib && curl -O -L http://central.maven.org/maven2/com/amazonaws/aws-java-sdk-s3/1.10.77/aws-java-sdk-s3-1.10.77.jar)",
    ]
  }
}

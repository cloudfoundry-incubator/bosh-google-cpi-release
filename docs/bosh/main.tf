resource "google_compute_network" "cf" {
  name       = "cf"
}

// Subnet for the BOSH director
resource "google_compute_subnetwork" "bosh-us-east1" {
  name          = "bosh-us-east1"
  ip_cidr_range = "10.0.0.0/24"
  network       = "${google_compute_network.cf.self_link}"
}

// Allow SSH to BOSH bastion
resource "google_compute_firewall" "bosh-bastion" {
  name    = "bosh-bastion"
  network = "${google_compute_network.cf.name}"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = ["bosh-bastion"]
}

// Allow open access between internal MVs
resource "google_compute_firewall" "bosh-internal" {
  name    = "bosh-internal"
  network = "${google_compute_network.cf.name}"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }
  target_tags = ["bosh-internal"]
  source_tags = ["bosh-internal"]
}

// BOSH bastion host
resource "google_compute_instance" "bosh-bastion" {
  name         = "bosh-bastion"
  machine_type = "n1-standard-1"
  zone         = "us-east1-b"

  tags = ["bosh-bastion", "bosh-internal"]

  disk {
    image = "ubuntu-1404-trusty-v20160610"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.bosh-us-east1.name}"
    access_config {
      // Ephemeral IP
    }
  }

  metadata_startup_script = <<EOT
#!/bin/bash
apt-get update -y
apt-get upgrade -y
apt-get install -y build-essential zlibc zlib1g-dev ruby ruby-dev openssl libxslt-dev libxml2-dev libssl-dev libreadline6 libreadline6-dev libyaml-dev libsqlite3-dev sqlite3
gem install bosh_cli 
curl -o /tmp/cf.tgz https://s3.amazonaws.com/go-cli/releases/v6.19.0/cf-cli_6.19.0_linux_x86-64.tgz
tar -zxvf /tmp/cf.tgz && mv cf /usr/bin/cf && chmod +x /usr/bin/cf
curl -o /usr/bin/bosh-init https://s3.amazonaws.com/bosh-init-artifacts/bosh-init-0.0.94-linux-amd64
chmod +x /usr/bin/bosh-init
EOT

  service_account {
    scopes = ["cloud-platform"]
  }
}

locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  project_id = var.project_create ? digitalocean_project.this[0].id : data.digitalocean_project.existing[0].id

  ssh_key_fingerprint = (var.existing_ssh_key_name != null
    ? data.digitalocean_ssh_key.existing[0].fingerprint
  : digitalocean_ssh_key.this[0].fingerprint)

  docker_config = jsonencode({
    auths = {
      "https://index.docker.io/v1/" = {
        auth = base64encode("${var.registry_username}:${var.registry_token}")
      }
    }
  })
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "digitalocean_project" "this" {
  count       = var.project_create ? 1 : 0
  name        = var.project_name
  purpose     = "Web Application"
  environment = "Production"
}

data "digitalocean_project" "existing" {
  count = var.project_create ? 0 : 1
  name  = var.project_name
}

resource "digitalocean_project_resources" "this" {
  project   = local.project_id
  resources = [digitalocean_droplet.this.urn]
}

data "digitalocean_ssh_key" "existing" {
  count = var.existing_ssh_key_name != null ? 1 : 0
  name  = var.existing_ssh_key_name
}

resource "digitalocean_ssh_key" "this" {
  count      = var.existing_ssh_key_name != null ? 0 : 1
  name       = "${var.name}-key"
  public_key = local.ssh_public_key
}

resource "digitalocean_droplet" "this" {
  name       = var.name
  region     = var.region
  size       = var.size
  image      = "ubuntu-24-04-x64"
  ssh_keys   = [local.ssh_key_fingerprint]
  monitoring = true
  ipv6       = true

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    ssh_public_key    = local.ssh_public_key
    compose           = file("${path.module}/../docker-compose.yml")
    wiki_domain       = var.wiki_domain
    letsencrypt_email = var.letsencrypt_email
    db_password       = random_password.db.result
    docker_config     = local.docker_config
  })
}

resource "digitalocean_record" "wiki" {
  count  = var.dns_zone != null ? 1 : 0
  domain = var.dns_zone
  type   = "A"
  name   = var.wiki_domain == var.dns_zone ? "@" : trimsuffix(var.wiki_domain, ".${var.dns_zone}")
  value  = digitalocean_droplet.this.ipv4_address
  ttl    = 300
}

resource "digitalocean_firewall" "this" {
  name        = "${var.name}-fw"
  droplet_ids = [digitalocean_droplet.this.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_cidrs
  }

  dynamic "inbound_rule" {
    for_each = ["80", "443"]
    content {
      protocol         = "tcp"
      port_range       = inbound_rule.value
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  dynamic "outbound_rule" {
    for_each = ["tcp", "udp"]
    content {
      protocol              = outbound_rule.value
      port_range            = "1-65535"
      destination_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  # Projet créé par Terraform ou existant
  project_id = var.project_create ? digitalocean_project.this[0].id : data.digitalocean_project.existing[0].id

  # Clé SSH existante (data source) ou nouvelle clé (resource)
  use_existing_key = var.existing_ssh_key_name != null
  ssh_key_fingerprint = (local.use_existing_key
    ? data.digitalocean_ssh_key.existing[0].fingerprint
  : digitalocean_ssh_key.this[0].fingerprint)

  # Contenu du docker-compose.yml ("" si pas de compose)
  compose_content = var.compose_file_path != null ? trimspace(file(var.compose_file_path)) : ""

  # Secrets compose : générés par Terraform + fournis à la main
  compose_secrets = merge(
    { for k, r in random_password.secret : k => r.result },
    var.compose_secrets
  )
  # Auth registry privé -> /root/.docker/config.json ("" si pas d'auth)
  docker_config = (var.registry_username != null && var.registry_token != null
    ? jsonencode({
      auths = {
        (var.registry_server) = {
          auth = base64encode("${var.registry_username}:${var.registry_token}")
        }
      }
    })
  : "")
  # Ports à ouvrir dans les firewalls (Cloud + UFW)
  run_single     = var.docker_image != ""
  open_app_ports = distinct(concat(local.run_single ? [var.host_port] : [], var.extra_open_ports))
}

# ---------- Secrets générés ----------
resource "random_password" "secret" {
  for_each = toset(var.generated_secrets)
  length   = 32
  special  = false # évite les soucis d'échappement shell/URL
}

# ---------- Projet ----------
# Soit Terraform crée le projet...
resource "digitalocean_project" "this" {
  count       = var.project_create ? 1 : 0
  name        = var.project_name
  description = var.project_description
  purpose     = var.project_purpose
  environment = var.project_environment
}

# ...soit on récupère un projet existant par son nom
data "digitalocean_project" "existing" {
  count = var.project_create ? 0 : 1
  name  = var.project_name
}

# Rattachement du droplet au projet
# (les firewalls et clés SSH ne sont pas des ressources "projet" chez DO)
resource "digitalocean_project_resources" "this" {
  project   = local.project_id
  resources = [digitalocean_droplet.this.urn]
}

# ---------- Clé SSH ----------
# Clé déjà présente dans le compte DO : on la lit, Terraform ne la gère pas
# (donc pas supprimée au destroy)
data "digitalocean_ssh_key" "existing" {
  count = local.use_existing_key ? 1 : 0
  name  = var.existing_ssh_key_name
}

# Sinon, Terraform l'enregistre
resource "digitalocean_ssh_key" "this" {
  count      = local.use_existing_key ? 0 : 1
  name       = "${var.name}-key"
  public_key = local.ssh_public_key
}

# ---------- Droplet ----------
resource "digitalocean_droplet" "this" {
  name       = var.name
  region     = var.region
  size       = var.size
  image      = var.image
  ssh_keys   = [local.ssh_key_fingerprint]
  monitoring = true
  ipv6       = true
  tags       = var.tags

  # cloud-init : installe Docker puis lance le conteneur et/ou le compose au premier boot
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    admin_user      = var.admin_user
    ssh_public_key  = local.ssh_public_key
    run_single      = local.run_single
    docker_image    = var.docker_image
    container_name  = var.container_name
    container_port  = var.container_port
    host_port       = var.host_port
    container_env   = var.container_env
    compose_content = local.compose_content
    compose_env     = var.compose_env
    docker_config   = local.docker_config 
    secrets         = local.compose_secrets
    open_app_ports  = local.open_app_ports
  })

  # Toute modif du user_data (image, compose...) recrée le droplet : infra immuable.
  # Pour mettre à jour sans recréer, décommente :
  # lifecycle {
  #   ignore_changes = [user_data]
  # }
}

# ---------- DNS (optionnel) ----------
# Le domaine doit déjà exister dans DO > Networking > Domains,
# avec les NS du registrar pointant vers ns1/ns2/ns3.digitalocean.com
resource "digitalocean_record" "a" {
  for_each = var.dns_zone != null ? toset(var.dns_records) : toset([])
  domain   = var.dns_zone
  type     = "A"
  name     = each.value
  value    = digitalocean_droplet.this.ipv4_address
  ttl      = 300
}

# ---------- Firewall Cloud ----------
resource "digitalocean_firewall" "this" {
  name        = "${var.name}-fw"
  droplet_ids = [digitalocean_droplet.this.id]

  # SSH restreint
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_cidrs
  }

  # Ports applicatifs (conteneur seul + compose) ouverts au monde
  dynamic "inbound_rule" {
    for_each = local.open_app_ports
    content {
      protocol         = "tcp"
      port_range       = tostring(inbound_rule.value)
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  # Ping
  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Sortant : tout autorisé (apt, pull d'images Docker, DNS...)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

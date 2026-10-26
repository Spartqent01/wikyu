output "project" {
  description = "Projet DigitalOcean contenant le droplet"
  value = {
    id   = local.project_id
    name = var.project_name
  }
}

output "droplet_id" {
  description = "ID du droplet"
  value       = digitalocean_droplet.this.id
}

output "ipv4" {
  description = "IP publique IPv4"
  value       = digitalocean_droplet.this.ipv4_address
}

output "ipv6" {
  description = "IP publique IPv6"
  value       = digitalocean_droplet.this.ipv6_address
}

output "app_urls" {
  description = "URLs des ports applicatifs ouverts (conteneur seul + compose)"
  value       = [for p in local.open_app_ports : "http://${digitalocean_droplet.this.ipv4_address}:${p}"]
}

output "dns_fqdns" {
  description = "Noms DNS créés pointant vers le droplet"
  value       = [for r in digitalocean_record.a : r.fqdn]
}

output "generated_secrets" {
  description = "Secrets générés (terraform output -json generated_secrets)"
  value       = { for k, r in random_password.secret : k => r.result }
  sensitive   = true
}

output "ssh_command" {
  description = "Commande SSH"
  value       = "ssh ${var.admin_user}@${digitalocean_droplet.this.ipv4_address}"
}

output "wait_cloud_init" {
  description = "Attendre la fin du provisioning"
  value       = "ssh ${var.admin_user}@${digitalocean_droplet.this.ipv4_address} 'cloud-init status --wait && docker ps'"
}

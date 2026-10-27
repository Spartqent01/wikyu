output "ipv4" {
  description = "IP publique du droplet"
  value       = digitalocean_droplet.this.ipv4_address
}

output "url" {
  description = "Adresse du wiki"
  value       = "https://${var.wiki_domain}"
}

output "ssh_command" {
  description = "Connexion SSH"
  value       = "ssh ops@${digitalocean_droplet.this.ipv4_address}"
}

output "db_password" {
  description = "Mot de passe PostgreSQL (terraform output -raw db_password)"
  value       = random_password.db.result
  sensitive   = true
}

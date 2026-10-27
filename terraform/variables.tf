# ---------- Projet DigitalOcean ----------
variable "project_name" {
  description = "Nom du projet DigitalOcean"
  type        = string
  default     = "wikyu"
}

variable "project_create" {
  description = "true = Terraform crée le projet ; false = réutilise un projet existant de ce nom"
  type        = bool
  default     = true
}

# ---------- Droplet ----------
variable "name" {
  description = "Nom du droplet (préfixe des autres ressources)"
  type        = string
  default     = "wikyu"
}

variable "region" {
  description = "Région DigitalOcean"
  type        = string
  default     = "fra1"
}

variable "size" {
  description = "Gabarit du droplet (doit exister dans la région)"
  type        = string
  default     = "s-1vcpu-1gb-amd"
}

# ---------- SSH ----------
variable "ssh_public_key_path" {
  description = "Clé publique SSH de l'utilisateur ops"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "existing_ssh_key_name" {
  description = "Nom d'une clé déjà enregistrée chez DO. null = Terraform la crée."
  type        = string
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = "IP autorisées en SSH (ton IP en /32)"
  type        = list(string)
}

# ---------- Wiki ----------
variable "wiki_domain" {
  description = "Domaine du wiki (ex : wiki.example.com)"
  type        = string
}

variable "letsencrypt_email" {
  description = "E-mail du compte Let's Encrypt"
  type        = string
}

variable "registry_username" {
  description = "Compte Docker Hub qui héberge l'image privée"
  type        = string
}

variable "registry_token" {
  description = "Token Docker Hub en lecture seule (export TF_VAR_registry_token=...)"
  type        = string
  sensitive   = true
}

# ---------- DNS (optionnel) ----------
variable "dns_zone" {
  description = "Zone gérée chez DO (ex : example.com) pour créer l'enregistrement A. null = DNS fait à la main."
  type        = string
  default     = null
}

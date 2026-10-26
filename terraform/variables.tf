# ---------- Projet DigitalOcean ----------
variable "project_name" {
  description = "Nom du projet DigitalOcean dans lequel ranger le droplet"
  type        = string
}

variable "project_create" {
  description = "true = Terraform crée le projet ; false = utilise un projet existant portant ce nom"
  type        = bool
  default     = true
}

variable "project_description" {
  description = "Description du projet (si créé par Terraform)"
  type        = string
  default     = "VM Docker déployée par Terraform"
}

variable "project_purpose" {
  description = "Usage du projet (si créé par Terraform)"
  type        = string
  default     = "Web Application"
}

variable "project_environment" {
  description = "Environnement du projet (si créé par Terraform)"
  type        = string
  default     = "Development"

  validation {
    condition     = contains(["Development", "Staging", "Production"], var.project_environment)
    error_message = "project_environment doit valoir Development, Staging ou Production."
  }
}

# ---------- Droplet ----------
variable "name" {
  description = "Nom du droplet (sert aussi de préfixe aux autres ressources)"
  type        = string
  default     = "docker-vm"
}

variable "region" {
  description = "Région DigitalOcean (fra1 = Francfort, ams3 = Amsterdam, lon1 = Londres)"
  type        = string
  default     = "fra1"
}

variable "size" {
  description = "Gabarit du droplet (doit être disponible dans la région choisie)"
  type        = string
  default     = "s-1vcpu-1gb-amd"
}

variable "image" {
  description = "Image OS du droplet"
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "tags" {
  description = "Tags appliqués au droplet"
  type        = list(string)
  default     = ["terraform", "docker"]
}

# ---------- Accès SSH ----------
variable "admin_user" {
  description = "Utilisateur non-root créé par cloud-init (sudo + groupe docker)"
  type        = string
  default     = "ops"
}

variable "ssh_public_key_path" {
  description = "Chemin vers ta clé publique SSH (sert aussi pour l'utilisateur admin_user)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "existing_ssh_key_name" {
  description = "Nom d'une clé SSH déjà enregistrée dans le compte DO (Settings > Security). null = Terraform en crée une."
  type        = string
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = "Plages IP autorisées en SSH (mets ton IP publique en /32 !)"
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

# ---------- Conteneur seul ----------
variable "docker_image" {
  description = "Image Docker à lancer seule dans la VM. \"\" = pas de conteneur seul."
  type        = string
  default     = "nginx:stable-alpine"
}

variable "container_name" {
  description = "Nom du conteneur seul"
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "Port exposé par le conteneur seul"
  type        = number
  default     = 80
}

variable "host_port" {
  description = "Port publié sur la VM pour le conteneur seul (ouvert dans les firewalls)"
  type        = number
  default     = 80
}

variable "container_env" {
  description = "Variables d'environnement passées au conteneur seul"
  type        = map(string)
  default     = {}
}

# ---------- Docker Compose ----------
variable "compose_file_path" {
  description = "Chemin local vers un docker-compose.yml à déployer. null = pas de compose."
  type        = string
  default     = null
}

variable "extra_open_ports" {
  description = "Ports TCP supplémentaires à ouvrir (ceux publiés par le compose)"
  type        = list(number)
  default     = []
}

variable "compose_env" {
  description = "Variables écrites dans /opt/deploy/.env (interpolées par compose : $${VAR})"
  type        = map(string)
  default     = {}
}

variable "generated_secrets" {
  description = "Noms de secrets compose générés aléatoirement par Terraform -> /opt/deploy/secrets/<nom>.txt"
  type        = list(string)
  default     = []
}

variable "compose_secrets" {
  description = "Secrets compose fournis à la main (nom => valeur) -> /opt/deploy/secrets/<nom>.txt"
  type        = map(string)
  default     = {}
  sensitive   = true
}
# ---------- Registry privé (optionnel) ----------
variable "registry_server" {
  description = "Registry des images privées (Docker Hub par défaut)"
  type        = string
  default     = "https://index.docker.io/v1/"
}

variable "registry_username" {
  description = "Utilisateur du registry. null = pas d'authentification."
  type        = string
  default     = null
}

variable "registry_token" {
  description = "Token d'accès du registry (Docker Hub : Personal Access Token en lecture seule)"
  type        = string
  default     = null
  sensitive   = true
}
# ---------- DNS (optionnel, domaine géré chez DigitalOcean) ----------
variable "dns_zone" {
  description = "Domaine déjà déclaré dans DO > Networking > Domains (ex: example.com). null = pas de DNS."
  type        = string
  default     = null
}

variable "dns_records" {
  description = "Sous-domaines à pointer vers le droplet (enregistrements A), ex: [\"wiki\"]"
  type        = list(string)
  default     = []
}

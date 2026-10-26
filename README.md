# Wikyu

Wiki.js v3 conteneurisé, déployé en HTTPS sur DigitalOcean avec Terraform.

```
   Poste de dev               Docker Hub (privé)              DigitalOcean
┌──────────────┐   push   ┌────────────────────┐   pull   ┌─────────────────────────────┐
│ Dockerfile   │ ───────► │ headwind565/       │ ───────► │ Droplet Ubuntu 24.04        │
│ ./wiki       │          │ dumbsumb:1         │          │  ├─ nginx-proxy     80/443  │
└──────────────┘          └────────────────────┘          │  ├─ acme-companion  HTTPS   │
       │                                                  │  ├─ wiki            :3000   │
       │ terraform apply                                  │  └─ db              Postgres│
       └─────────────────────────────────────────────────►└─────────────────────────────┘
```

## 1. L'image Docker

Le `Dockerfile` est en deux étapes :

| Étape | Image | Rôle |
|---|---|---|
| build | `node:26` | Compile `frontend` et `blocks`, installe les dépendances de prod de `backend` |
| run | `node:26` | Ne garde que le résultat du build. Tourne avec l'utilisateur `node` (non-root), port 3000 |

L'image finale est légère et ne contient ni les sources du front ni les outils de build.

### Construire et publier

Le code de Wiki.js n'est pas versionné ici. Il sert de contexte de build :

```bash
git clone https://github.com/requarks/wiki.git wiki
docker build -f Dockerfile -t headwind565/dumbsumb:1 ./wiki
docker login -u headwind565          # token Docker Hub "Read & Write"
docker push headwind565/dumbsumb:1
```

Le build du front consomme beaucoup de mémoire. S'il s'arrête sans erreur claire, augmente la RAM allouée à Docker.

## 2. La stack Docker Compose

| Service | Image | Rôle |
|---|---|---|
| `nginx-proxy` | `nginxproxy/nginx-proxy` | Reverse proxy sur 80/443. Route vers le wiki grâce à `VIRTUAL_HOST` |
| `acme-companion` | `nginxproxy/acme-companion` | Obtient et renouvelle le certificat Let's Encrypt grâce à `LETSENCRYPT_HOST` |
| `wiki` | `headwind565/dumbsumb:1` | Wiki.js. Démarre uniquement quand la base est `healthy` |
| `db` | `postgres:18` | Base de données, avec un healthcheck `pg_isready` |

**Réseaux**

- `pub` : relie le proxy et le wiki ;
- `db` : relie le wiki et la base. Il est `internal`, donc PostgreSQL n'a aucun accès Internet.

Le wiki n'expose aucun port : il n'est joignable qu'en HTTPS, via le proxy.

**Configuration**

- `.env` : `WIKI_DOMAIN` (le domaine du wiki) et `LETSENCRYPT_EMAIL` ;
- `secrets/db_password.txt` : mot de passe de la base, monté dans les conteneurs sous `/run/secrets/db_password`. Il n'apparaît jamais dans le compose ni dans les variables d'environnement visibles.

En production, ces deux fichiers sont générés par Terraform.

## 3. Le déploiement Terraform

### Ce qui est créé

- un **projet DigitalOcean** (créé, ou réutilisé s'il existe) ;
- un **droplet** Ubuntu 24.04, accessible en SSH par clé avec l'utilisateur `ops` (root désactivé) ;
- un **firewall Cloud** (SSH restreint à tes IP, 80/443 ouverts), doublé de **UFW** dans la VM ;
- un **mot de passe PostgreSQL aléatoire** ;
- en option, un **enregistrement DNS A** si le domaine est géré chez DigitalOcean.

### Ce que fait cloud-init au premier démarrage

1. Crée l'utilisateur `ops` et désactive l'accès root et par mot de passe.
2. Dépose dans `/opt/deploy/` le compose, le `.env`, le secret de la base, et les identifiants Docker Hub dans `/root/.docker/config.json`.
3. Installe Docker et active UFW.
4. Lance `docker compose up -d`.

### Variables principales (`terraform.tfvars`)

| Variable | Exemple | Rôle |
|---|---|---|
| `project_name` | `"wikyu"` | Projet DigitalOcean |
| `region` / `size` | `"fra1"` / `"s-1vcpu-1gb-amd"` | Emplacement et taille de la VM |
| `existing_ssh_key_name` | `"ma-cle"` | Clé déjà enregistrée chez DO (sinon, elle est créée) |
| `ssh_allowed_cidrs` | `["1.2.3.4/32"]` | IP autorisées en SSH |
| `docker_image` | `""` | Vide : on utilise uniquement le compose |
| `compose_file_path` | `"../docker-compose.yml"` | Compose à déployer |
| `extra_open_ports` | `[80, 443]` | Ports ouverts dans les firewalls |
| `compose_env` | `{ WIKI_DOMAIN = "wiki.noyye.fr", ... }` | Contenu du `.env` |
| `generated_secrets` | `["db_password"]` | Secrets générés aléatoirement |
| `registry_username` | `"headwind565"` | Compte Docker Hub (image privée) |

### Déployer

Prérequis : Terraform ≥ 1.5, un token DigitalOcean, une clé SSH, un token Docker Hub **en lecture seule**, et un domaine.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # puis adapter
export DIGITALOCEAN_TOKEN="dop_v1_..."
export TF_VAR_registry_token="dckr_pat_..."
terraform init
terraform apply
```

Ensuite, crée l'enregistrement **A** du domaine vers l'IP affichée (`terraform output ipv4`), sauf si `dns_zone` s'en charge. Le wiki est disponible sur `https://<domaine>` quelques minutes plus tard.

## Exploitation

```bash
ssh ops@$(terraform output -raw ipv4)

sudo cloud-init status --wait                       # attendre la fin de l'installation
sudo tail -f /var/log/cloud-init-output.log         # suivre l'installation
cd /opt/deploy && sudo docker compose ps            # état des services
sudo docker compose logs -f wiki                    # logs du wiki
sudo docker logs -f acme-companion                  # suivi du certificat
sudo docker exec acme-companion /app/force_renew    # relancer l'émission du certificat
```

Depuis le poste de dev :

```bash
terraform output -json generated_secrets   # mot de passe PostgreSQL
terraform destroy                          # tout supprimer (VM facturée à l'heure)
```

Toute modification du compose ou des variables passées à cloud-init **recrée la VM**, et les données sont alors perdues. Pour l'éviter, voir le bloc `lifecycle` commenté dans `main.tf`.

## Dépannage

| Symptôme | Cause / solution |
|---|---|
| `Size is not available in this region` | Changer `size` ou `region` |
| `SSH Key is already in use` | Renseigner `existing_ssh_key_name` |
| `docker: command not found` juste après l'apply | cloud-init n'a pas fini : `sudo cloud-init status --wait` |
| `pull access denied` sur l'image du wiki | Vérifier `registry_username` et `TF_VAR_registry_token` |
| Site en HTTP, `NXDOMAIN` dans les logs d'acme-companion | Le DNS ne pointait pas encore vers la VM. Vérifier avec `dig +short <domaine> @1.1.1.1`, puis `force_renew` |
| Liens en `http://` dans Wiki.js | Régler l'URL du site en `https://` dans l'administration de Wiki.js |

## Sécurité

- `secrets/`, `.env`, `*.tfvars` et `*.tfstate` sont exclus du dépôt par le `.gitignore`.
- Le state Terraform contient le mot de passe de la base et le token Docker Hub en clair : garde-le en lieu sûr, ou utilise un backend distant.
- Le token Docker Hub utilisé pour le déploiement doit être en lecture seule.

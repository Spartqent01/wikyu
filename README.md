# Wikyu : Wiki.js conteneurisé et déployé sur DigitalOcean

Ce projet conteneurise [Wiki.js v3](https://github.com/requarks/wiki), puis le déploie en HTTPS sur une VM DigitalOcean avec Terraform.

Il comporte deux parties :

1. **Conteneurisation** : un Dockerfile multi-stage qui construit l'image Wiki.js, et un compose pour la faire tourner en local avec PostgreSQL.
2. **Déploiement** (`terraform/`) : Terraform crée la VM, cloud-init installe Docker, et la stack démarre derrière un reverse proxy HTTPS (Let's Encrypt).

```
   Poste de dev                         Docker Hub                 DigitalOcean
┌─────────────────┐  docker push   ┌──────────────────┐  pull   ┌──────────────────────────┐
│ Dockerfile      │ ─────────────► │ headwind565/     │ ──────► │ Droplet Ubuntu 24.04     │
│ docker-compose  │                │ dumbsumb:1       │         │  ├─ nginx-proxy (80/443) │
└─────────────────┘                │ (privé)          │         │  ├─ acme-companion       │
        │                          └──────────────────┘         │  ├─ wiki (Wiki.js)       │
        │ terraform apply                                       │  └─ db (PostgreSQL 18)   │
        └──────────────────────────────────────────────────────►└──────────────────────────┘
```

## Structure du dépôt

```
.
├── Dockerfile               # build multi-stage de l'image Wiki.js
├── docker-compose.yml       # stack locale : Wiki.js + PostgreSQL
├── .gitignore
└── terraform/               # déploiement sur DigitalOcean
    ├── versions.tf          # providers (digitalocean, random)
    ├── variables.tf         # paramètres
    ├── main.tf              # projet, clé SSH, droplet, firewall, DNS, secrets
    ├── outputs.tf           # IP, URLs, commande SSH
    ├── cloud-init.yaml.tftpl  # script de premier démarrage de la VM
    ├── docker-compose.yml   # stack de production (avec reverse proxy HTTPS)
    ├── terraform.tfvars.example
    └── README.md            # documentation détaillée du module
```

Les branches :

- `master` : la partie conteneurisation ;
- `deploy` : conteneurisation + déploiement Terraform.

Les éléments suivants ne sont **pas versionnés** :

- `wiki/` : code source de Wiki.js, utilisé comme contexte de build. Il est à cloner à part, voir ci-dessous ;
- `secrets/` : mot de passe de la base ;
- les fichiers Terraform locaux (`*.tfvars`, `*.tfstate`, `.terraform/`).

## 1. L'image Docker

Le `Dockerfile` est découpé en deux étapes :

| Étape | Image | Rôle |
|---|---|---|
| `build` | `node:26` | Compile le front (`frontend`) et les blocks (`blocks`), installe les dépendances de prod du back (`backend`) |
| run | `node:alpine` | Ne récupère que le résultat du build. Le serveur tourne avec l'utilisateur `node`, pas en root, sur le port 3000 |

### Construire et publier

Le code source de Wiki.js doit être présent dans `./wiki` :

```bash
git clone https://github.com/requarks/wiki.git wiki
docker compose build wiki
docker login -u headwind565          # token Docker Hub "Read & Write"
docker compose push wiki
```

Le build du front est gourmand en mémoire. S'il échoue sans erreur claire (processus tué), augmente la RAM allouée à Docker.

## 2. Lancer en local

```bash
mkdir -p secrets
echo -n "MonMotDePasse" > secrets/db_password.txt
docker network create pub            # réseau déclaré "external" dans le compose local
docker compose up -d
docker compose ps                    # attendre que tout soit "healthy"
```

Puis ouvrir http://localhost:3000.

**Fonctionnement :**

- **Secret** : le mot de passe n'est jamais écrit dans le compose. Il est lu depuis `secrets/db_password.txt` et monté dans les conteneurs sous `/run/secrets/db_password`.
- **db** : PostgreSQL 18, avec un healthcheck `pg_isready`. Wiki.js ne démarre que lorsque la base est `healthy`.
- **wiki** : son healthcheck interroge `http://localhost:3000/healthz`.

## 3. Déployer sur DigitalOcean

Le dossier `terraform/` déploie la stack en production.

### Ce qui est créé

- un **projet DigitalOcean** pour ranger les ressources ;
- un **droplet** Ubuntu 24.04, accessible en SSH par clé avec l'utilisateur `ops` (root désactivé) ;
- un **firewall Cloud** (SSH restreint, 80/443 ouverts) et le firewall local **UFW** ;
- un **mot de passe PostgreSQL aléatoire** généré par Terraform ;
- en option, un **enregistrement DNS A** vers la VM.

Au premier démarrage, **cloud-init** dépose dans `/opt/deploy/` le compose, le `.env`, le secret de la base et les identifiants Docker Hub. Il installe ensuite Docker, puis lance `docker compose up -d`.

### La stack de production (`terraform/docker-compose.yml`)

| Service | Rôle |
|---|---|
| `nginx-proxy` | Reverse proxy sur 80/443. Route vers le wiki grâce à `VIRTUAL_HOST` |
| `acme-companion` | Obtient et renouvelle automatiquement le certificat Let's Encrypt (`LETSENCRYPT_HOST`) |
| `wiki` | Wiki.js. Pas de port exposé, joignable uniquement via le proxy |
| `db` | PostgreSQL 18, sur un réseau `internal` sans accès Internet |

Différences avec le compose local : pas de `build:`, car l'image est tirée de Docker Hub. Les réseaux sont aussi créés par compose et ne sont plus `external`.

### Déployer

Prérequis :

- un token API DigitalOcean ;
- une clé SSH ;
- un nom de domaine pointant vers la VM ;
- un token Docker Hub **en lecture seule**.

```bash
cd terraform
export DIGITALOCEAN_TOKEN="dop_v1_..."
export TF_VAR_registry_token="dckr_pat_..."
cp terraform.tfvars.example terraform.tfvars    # adapter : projet, domaine, email, IP SSH...
terraform init
terraform apply
```

Après environ 3 minutes de provisioning, le wiki est disponible sur `https://<WIKI_DOMAIN>`. Le détail des variables et le dépannage sont dans [`terraform/README.md`](terraform/README.md).

### Commandes utiles

```bash
ssh ops@$(terraform output -raw ipv4)              # se connecter à la VM
sudo cloud-init status --wait                      # attendre la fin du provisioning
cd /opt/deploy && sudo docker compose ps           # état des services
sudo docker logs -f acme-companion                 # suivi du certificat HTTPS
terraform output -json generated_secrets           # mot de passe PostgreSQL (depuis le poste)
terraform destroy                                  # tout supprimer
```

## Sécurité

- **Secrets** : le mot de passe de la base n'apparaît ni dans le code ni dans le compose. En prod, il est généré par Terraform.
- **Accès** : SSH par clé uniquement, root désactivé, SSH filtré par IP sur le firewall Cloud.
- **Moindre privilège** : Wiki.js tourne en utilisateur `node`, PostgreSQL n'a pas d'accès Internet, le token Docker Hub de la VM est en lecture seule.
- **À ne jamais commiter** : `*.tfvars`, `*.tfstate*`, `.env`, `secrets/`. Le state Terraform contient les secrets en clair.

# Droplet DigitalOcean + Docker avec Terraform

Ce module crée un droplet Ubuntu 24.04, rangé dans un projet DigitalOcean dont tu choisis le nom. Il est protégé par un firewall Cloud et par UFW. Docker est installé par cloud-init, qui lance ensuite :

- un **conteneur seul** (`docker_image`, Nginx par défaut) ;
- et/ou une **stack docker compose** (`compose_file_path`).

## Arborescence

```
versions.tf               provider + version Terraform
variables.tf              toutes les variables
main.tf                   projet, clé SSH, droplet, firewall
cloud-init.yaml.tftpl     provisioning (user, Docker, UFW, conteneur, compose)
docker-compose.yml        exemple de stack (whoami + uptime-kuma)
outputs.tf                projet, IP, URL, commande SSH
terraform.tfvars.example  exemple de valeurs
```

## Prérequis

- Terraform >= 1.5
- Un token API DigitalOcean (Control Panel > API > Generate New Token, scope write)
- Une paire de clés SSH (`ssh-keygen -t ed25519`), avec les bons droits :
  `chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519 && chmod 644 ~/.ssh/id_ed25519.pub`

## Déploiement

```bash
export DIGITALOCEAN_TOKEN="dop_v1_xxxxxxxx"
cp terraform.tfvars.example terraform.tfvars   # puis édite
terraform init
terraform validate
terraform plan
terraform apply
```

Le provisioning cloud-init prend 1 à 3 minutes après l'`apply`. Pour suivre :

```bash
$(terraform output -raw wait_cloud_init)
terraform output app_urls
```

## Projet DigitalOcean

- `project_name` (obligatoire) : nom du projet.
- `project_create = true` : Terraform crée le projet, et `destroy` le supprime aussi.
- `project_create = false` : le droplet est rattaché à un projet existant, qui n'est jamais supprimé.

## Clé SSH

- Par défaut, Terraform enregistre ta clé publique chez DigitalOcean.
- Si elle y est déjà (erreur `422 SSH Key is already in use`), renseigne `existing_ssh_key_name` avec son nom dans Settings > Security. Terraform la lit alors sans la gérer.

## Conteneur seul / Docker compose

| Usage | tfvars |
|---|---|
| Conteneur seul | `docker_image = "nginx:stable-alpine"`, `compose_file_path` commenté |
| Compose seul | `docker_image = ""`, `compose_file_path = "docker-compose.yml"` |
| Les deux | les deux renseignés |

Pense à lister dans `extra_open_ports` les ports publiés par le compose. Ils sont alors ouverts dans le firewall Cloud et dans UFW.

Dans la VM, les fichiers sont dans `/opt/deploy/` :

```bash
docker compose -f /opt/deploy/docker-compose.yml ps
sudo /opt/deploy/run-container.sh     # relance le conteneur seul
```

## Stack fournie : wiki + Postgres + nginx-proxy + Let's Encrypt

Le `docker-compose.yml` déploie :

- **nginx-proxy** (ports 80/443). Il route vers les conteneurs qui ont `VIRTUAL_HOST`.
- **acme-companion**. Il obtient et renouvelle les certificats pour les conteneurs qui ont `LETSENCRYPT_HOST`.
- **db** (Postgres 18) sur un réseau interne sans accès Internet.
- **wiki**, joignable uniquement via le proxy en HTTPS.

Terraform fournit au compose :

- `/opt/deploy/.env` à partir de `compose_env` (`WIKI_DOMAIN`, `LETSENCRYPT_EMAIL`) ;
- `/opt/deploy/secrets/db_password.txt`, généré aléatoirement via `generated_secrets`. Pour le relire : `terraform output -json generated_secrets`.

**Avant l'`apply`, le domaine doit pointer vers le droplet** (enregistrement A). Sinon Let's Encrypt échoue. acme-companion réessaie ensuite automatiquement, mais lentement. Si ton domaine est géré chez DigitalOcean, `dns_zone` + `dns_records` créent l'enregistrement tout seul. Pour tes premiers essais, active `ACME_CA_URI` (staging) dans le compose afin d'éviter le rate limit de Let's Encrypt.

Suivre l'émission du certificat : `docker logs -f acme-companion`.

Les secrets transitent par le `user_data`. Ils sont donc lisibles dans le state Terraform et via le service de métadonnées du droplet. C'est acceptable pour un lab. En prod, utilise un gestionnaire de secrets (Vault, SOPS…).

## Mises à jour

Toute modif de l'image ou du compose change le `user_data`, ce qui **recrée le droplet**. Les données des volumes sont alors perdues. Pour mettre à jour sans recréer, décommente le bloc `lifecycle { ignore_changes = [user_data] }` dans `main.tf`. Pousse ensuite les changements à la main (`scp` + `docker compose up -d`) ou avec Ansible.

Le `user_data` est limité à 64 Ko chez DigitalOcean.

## Erreurs courantes

- **`Size is not available in this region`** : liste les gabarits disponibles :
  ```bash
  curl -s -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
    "https://api.digitalocean.com/v2/sizes?per_page=200" \
  | jq -r '.sizes[] | select(.available and (.regions | index("fra1"))) | .slug'
  ```
- **`permission denied` sur la clé** : revoir les droits de `~/.ssh` (voir Prérequis).

## Détruire

```bash
terraform destroy
```

Le droplet est facturé à l'heure. Pense à le détruire après les tests.

## Pistes d'amélioration

- State distant dans un Space DigitalOcean (backend `s3`)
- Reserved IP (`digitalocean_reserved_ip`) pour garder une IP fixe
- Enregistrement DNS (`digitalocean_record`) + reverse proxy TLS (Caddy/Traefik)
- Pipeline CI (GitHub Actions) pour `plan`/`apply`

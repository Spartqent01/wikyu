# Rebuild Wiki.js

Conteneurisation de [Wiki.js](https://github.com/requarks/wiki) (v3) avec un Dockerfile multi-stage et Docker Compose.

## Contenu du projet

```
.
├── Dockerfile            # build multi-stage de Wiki.js
├── docker-compose.yml    # Wiki.js + PostgreSQL
├── .dockerignore         # fichiers exclus du build
├── secrets/
│   └── db_password.txt   # mot de passe de la base (non versionné)
├── frontend/             # code source Wiki.js (front Vue/Vite)
├── backend/              # code source Wiki.js (serveur Node)
└── blocks/               # code source Wiki.js (composants des pages)
```

## Prérequis

- Docker et Docker Compose
- Environ 8 Go de RAM disponibles pour Docker (le build du front est gourmand)

## Le Dockerfile

Il est découpé en deux étapes :

1. **build** (`node:26`) : compile le front et les blocks, installe les dépendances de prod du back.
2. **run** (`node:26-slim`) : ne récupère que le résultat du build pour obtenir une image plus légère. Le serveur tourne avec l'utilisateur `node` (pas en root).

## Lancer le projet

1. Créer le fichier secret avec le mot de passe de la base :

   ```bash
   mkdir -p secrets
   echo -n "MonMotDePasse" > secrets/db_password.txt
   ```

2. Construire et démarrer :

   ```bash
   docker compose up -d --build
   ```

3. Vérifier que tout est `healthy` :

   ```bash
   docker compose ps
   ```

4. Ouvrir http://localhost:3000

## Secret et healthchecks

- Le mot de passe de la base n'est pas écrit dans le compose : il est lu depuis `secrets/db_password.txt`, monté dans les conteneurs sous `/run/secrets/db_password`.
- **db** : `pg_isready` vérifie que PostgreSQL accepte les connexions. Wiki.js attend que la base soit `healthy` avant de démarrer.
- **wiki** : une requête sur la page d'accueil vérifie que le serveur répond.

## Commandes utiles

```bash
docker compose logs -f wiki    # suivre les logs de Wiki.js
docker compose down            # arrêter (les données sont conservées)
docker compose down -v         # arrêter et supprimer la base
```

## Publier l'image sur Docker Hub

Se connecter avec un token ayant les droits **Read & Write**, puis :

```bash
docker login -u headwind565
docker compose push wiki
```

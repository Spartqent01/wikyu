terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Le token est lu depuis la variable d'environnement DIGITALOCEAN_TOKEN
# (export DIGITALOCEAN_TOKEN="dop_v1_...") -> jamais de secret dans le code.
provider "digitalocean" {}

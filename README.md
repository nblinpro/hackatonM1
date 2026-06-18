# 🛡️ Mini SOC M1Tech - Hackathon 2026

Ce dépôt contient l'infrastructure, les scripts d'automatisation et les playbooks de configuration pour le déploiement du mini SOC de la PME **M1Tech Solutions**.

Cette solution permet d'héberger les services critiques, de monitorer leur disponibilité et de centraliser la détection d'incidents de sécurité.

---

# 🚀 Procédure de déploiement de l'infrastructure

Pour reproduire fidèlement l'environnement de sécurité et de supervision, vous devez exécuter les composants dans l'ordre strict décrit ci-dessous.

## 📋 Prérequis

* Un système hôte **Ubuntu Server 24.04 LTS** propre.
* **Ansible** et **Docker / Docker Compose** installés sur la machine.
* Les privilèges `sudo` sur l'utilisateur exécutant les scripts.

---

## 🛠️ Étape 1 : Durcissement du système hôte (Hardening)

Avant de déployer la moindre brique applicative, le système d'hébergement doit être sécurisé (fermeture des ports inutiles, restriction SSH, configuration des politiques par défaut).

Exécutez le playbook Ansible dédié au durcissement :

```bash
ansible-playbook hardening.yml
```

### Ce que fait ce playbook

* Configure `sshd_config` :

  * Désactivation du login root.
  * Limitation des tentatives de connexion à 3.
  * Restriction de l'accès SSH à l'utilisateur `nicolas`.

* Active le pare-feu **UFW** et autorise uniquement les flux légitimes :

  * `22/tcp` (SSH)
  * `80/tcp` (HTTP)
  * `443/tcp` (HTTPS)
  * `3001/tcp` (Uptime Kuma)

* Installe et initialise **Fail2Ban** pour surveiller et bannir automatiquement les attaques par brute force sur le service SSH.

---

## 🐳 Étape 2 : Déploiement automatisé de la stack SOC & Web

Une fois l'hôte sécurisé, lancez le script d'automatisation principal qui gère la préparation du système, la cryptographie interne et l'orchestration des conteneurs.

Exécutez le script Bash de déploiement :

```bash
./deploy_wazuh.sh
```

### Ce que fait ce script

* Règle les variables mémoire du noyau (`vm.max_map_count`) requises par l'indexeur.

* Clone le dépôt officiel **Wazuh v4.11.0**.

* Génère de manière isolée les certificats **SSL/TLS** requis pour le chiffrement des flux internes :

  * Wazuh Manager
  * Wazuh Indexer
  * Wazuh Dashboard

* Corrige les propriétés et permissions des dossiers de configuration.

* Lance l'orchestration Docker Compose unifiant les six conteneurs :

  * Nginx
  * MariaDB
  * Uptime Kuma
  * Wazuh Manager
  * Wazuh Indexer
  * Wazuh Dashboard

---

## 👁️ Étape 3 : Déploiement et raccordement de l'Agent Wazuh

La dernière étape consiste à installer l'agent de collecte local sur l'hôte afin qu'il puisse transmettre ses logs système et applicatifs au SOC en temps réel.

Exécutez le playbook Ansible de l'agent :

```bash
ansible-playbook wazuh_agent.yml
```

### Ce que fait ce playbook

* Installe l'agent Wazuh natif sur le système d'exploitation de la machine.

* Enregistre l'agent auprès du Wazuh Manager via l'API locale.

* Configure la surveillance active des fichiers de logs :

  * `journald`
  * `auth.log`
  * Logs d'accès Nginx

* Active le module **FIM (File Integrity Monitoring)** en temps réel sur les répertoires sensibles.

## 🔍 Étape 4 : Activation du module de détection des vulnérabilités

Afin de permettre au SOC de détecter automatiquement les vulnérabilités connues (CVE) affectant le système Ubuntu surveillé, activez le module **Vulnerability Detector** de Wazuh.

### Modification de la configuration du Manager

Ouvrez le fichier de configuration du Manager :

```bash
nano ~/hackatonM1/wazuh-docker/single-node/config/wazuh_cluster/wazuh_manager.conf
```

Descendez jusqu'à la fin du fichier et repérez la balise de fermeture :

```xml
</ossec_config>
```

Ajoutez le bloc suivant **juste avant cette balise** :

```xml
<vulnerability-detector>
  <enabled>yes</enabled>
  <interval>5m</interval>
  <min_full_scan_interval>6h</min_full_scan_interval>
  <run_on_start>yes</run_on_start>

  <provider name="canonical">
    <enabled>yes</enabled>
    <os>noble</os>
    <update_interval>1h</update_interval>
  </provider>
</vulnerability-detector>
```

Le bas du fichier doit alors ressembler à ceci :

```xml
<vulnerability-detector>
  <enabled>yes</enabled>
  <interval>5m</interval>
  <min_full_scan_interval>6h</min_full_scan_interval>
  <run_on_start>yes</run_on_start>

  <provider name="canonical">
    <enabled>yes</enabled>
    <os>noble</os>
    <update_interval>1h</update_interval>
  </provider>
</vulnerability-detector>

</ossec_config>
```

Enregistrez puis quittez l'éditeur :

* `Ctrl + O`
* `Entrée`
* `Ctrl + X`

### Application de la configuration

Redémarrez ensuite le conteneur Wazuh Manager afin qu'il recharge sa configuration :

```bash
cd ~/hackatonM1/wazuh-docker/single-node/
sudo docker compose restart wazuh.manager
```

### Vérification

Quelques minutes après le redémarrage, les premières données de vulnérabilités devraient être visibles dans l'interface Wazuh :

```text
Security Events → Vulnerabilities
```

Le moteur analysera les paquets installés sur les agents et les comparera aux bases de vulnérabilités Canonical pour Ubuntu 24.04 LTS (Noble Numbat).


---

# 📊 Cartographie des accès de l'infrastructure

Une fois le déploiement terminé, les interfaces d'exploitation sont accessibles aux adresses suivantes :

| Service                 | URL                        |
| ----------------------- | -------------------------- |
| Site Web Institutionnel | `http://<IP_SERVEUR>:80`   |
| Supervision Uptime Kuma | `http://<IP_SERVEUR>:3001` |
| Console SOC Wazuh       | `https://<IP_SERVEUR>:443` |

### Identifiants par défaut Wazuh

```text
Utilisateur : admin
Mot de passe : SecretPassword
```

> ⚠️ Pensez à modifier immédiatement les identifiants par défaut après le premier déploiement.

---

## 🔒 Isolation réseau

La base de données **MariaDB** est entièrement isolée au sein du réseau virtuel **Docker Bridge** interne et n'expose aucun port directement sur l'hôte.

Cette architecture réduit la surface d'attaque et limite l'accès à la base de données aux seuls services autorisés.

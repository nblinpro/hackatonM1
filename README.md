# 🛡️ Mini SOC M1Tech - Hackathon 2026

Ce dépôt contient l'infrastructure, les scripts d'automatisation et les playbooks de configuration pour le déploiement du mini SOC de la PME **M1Tech Solutions**.

Cette solution permet d'héberger les services critiques, de superviser leur **disponibilité** et leurs **métriques**, et de centraliser la **détection d'incidents de sécurité**.

---

# 🚀 Procédure de déploiement de l'infrastructure

Pour reproduire fidèlement l'environnement de sécurité et de supervision, exécutez les composants dans l'ordre strict décrit ci-dessous.

## 📋 Prérequis

* Un système hôte **Ubuntu Server 24.04 LTS** propre.
* **Ansible** et **Docker / Docker Compose** installés sur la machine.
* Les privilèges `sudo` sur l'utilisateur exécutant les scripts.
* Le dépôt cloné, contenant à la racine : `docker-compose.yml`, `deploy.sh`, les playbooks Ansible, le dossier **`monitoring/`** (config Prometheus + provisioning Grafana) et un fichier **`.env`** (créé à partir de `.env.example`).

---

## 🛠️ Étape 1 : Durcissement du système hôte (Hardening)

Avant de déployer la moindre brique applicative, le système d'hébergement doit être sécurisé (fermeture des ports inutiles, restriction SSH, politiques par défaut).

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
  * `80/tcp` (HTTP - site web)
  * `443/tcp` (HTTPS - console Wazuh)
  * `3001/tcp` (Uptime Kuma)
  * `3000/tcp` (Grafana)
  * `9090/tcp` (Prometheus)

* Installe et initialise **Fail2Ban** pour surveiller et bannir automatiquement les attaques par force brute sur le service SSH.

---

## 🐳 Étape 2 : Déploiement automatisé de la stack SOC, Web & Supervision

Une fois l'hôte sécurisé, créez le fichier `.env` (à partir de `.env.example`), puis lancez le script d'automatisation principal qui gère la préparation du système, la cryptographie interne et l'orchestration des conteneurs.

```bash
cp .env.example .env    # puis renseigner des mots de passe robustes
./deploy.sh
```

### Ce que fait ce script

* Règle les variables mémoire du noyau (`vm.max_map_count`) requises par l'indexeur.
* Clone le dépôt officiel **Wazuh v4.11.0**.
* Génère de manière isolée les certificats **SSL/TLS** des composants Wazuh (Manager, Indexer, Dashboard).
* Corrige les propriétés et permissions des dossiers de configuration.
* Initialise l'index de sécurité de l'indexeur (`securityadmin`) si nécessaire.
* Lance l'orchestration **Docker Compose** unifiant les **dix conteneurs** :

| Catégorie | Conteneurs |
| --------- | ---------- |
| Services métiers | `nginx-web`, `mariadb-db` |
| Supervision (disponibilité) | `uptime-kuma` |
| Détection / SIEM | `wazuh.manager`, `wazuh.indexer`, `wazuh.dashboard` |
| Métriques (observabilité) | `prometheus`, `grafana`, `node-exporter`, `cadvisor` |

> ℹ️ Le dossier `monitoring/` doit être présent à la racine (il contient `prometheus.yml` et le provisioning Grafana), sinon Prometheus et Grafana ne démarreront pas.

---

## 👁️ Étape 3 : Déploiement et raccordement de l'Agent Wazuh

Installez l'agent de collecte local sur l'hôte afin qu'il transmette ses logs système et applicatifs au SOC en temps réel.

```bash
ansible-playbook wazuh_agent.yml
```

### Ce que fait ce playbook

* Installe l'agent Wazuh natif sur le système d'exploitation de la machine.
* Enregistre l'agent auprès du Wazuh Manager.
* Configure la surveillance des journaux : `journald`, `auth.log`, logs d'accès Nginx.
* Active le module **FIM (File Integrity Monitoring)** en temps réel sur les répertoires sensibles (`/etc/m1tech`).

---

## 🔍 Étape 4 : Activation du module de détection des vulnérabilités

Afin de permettre au SOC de détecter automatiquement les vulnérabilités connues (CVE) affectant le système Ubuntu surveillé, activez le module **Vulnerability Detector** de Wazuh.

### Modification de la configuration du Manager

```bash
nano ~/hackatonM1/wazuh-docker/single-node/config/wazuh_cluster/wazuh_manager.conf
```

Ajoutez le bloc suivant **juste avant** la balise de fermeture `</ossec_config>` :

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

Enregistrez (`Ctrl+O`, `Entrée`, `Ctrl+X`), puis rechargez le Manager :

```bash
cd ~/hackatonM1
sudo docker compose restart wazuh.manager
```

### Vérification

Quelques minutes après le redémarrage, les vulnérabilités apparaissent dans l'interface Wazuh :

```text
Endpoint Security → Vulnerability Detection
```

Le moteur compare les paquets installés aux bases de vulnérabilités Canonical pour Ubuntu 24.04 LTS (Noble Numbat).

---

## 📈 Étape 5 : Tableaux de bord de métriques (Grafana)

La couche d'observabilité (Prometheus + node-exporter + cAdvisor) collecte automatiquement les métriques. Pour les visualiser, connectez-vous à Grafana et importez les tableaux de bord.

1. Connexion : `http://<IP_SERVEUR>:3000` (la datasource **Prometheus** est provisionnée automatiquement).
2. **Dashboards → New → Import**, puis saisissez l'ID et sélectionnez la datasource **Prometheus** :

| ID | Tableau de bord | Contenu |
| -- | --------------- | ------- |
| `1860` | Node Exporter Full | CPU / RAM / disque / réseau de l'hôte |
| `11074` | Node Exporter Dashboard | Vue système synthétique |

> Vérifiez que les cibles de collecte sont actives : `http://<IP_SERVEUR>:9090/targets`.

---

# 📊 Cartographie des accès de l'infrastructure

| Service                 | URL                          | Identifiants par défaut |
| ----------------------- | ---------------------------- | ----------------------- |
| Site Web Institutionnel | `http://<IP_SERVEUR>:80`     | —                       |
| Supervision Uptime Kuma | `http://<IP_SERVEUR>:3001`   | `hackaton` / `infram1`  |
| Console SOC Wazuh       | `https://<IP_SERVEUR>:443`   | `admin` / `SecretPassword` |
| Métriques Grafana       | `http://<IP_SERVEUR>:3000`   | `admin` / `Grafana2026!` |
| Prometheus              | `http://<IP_SERVEUR>:9090`   | —                       |

> ⚠️ Pensez à modifier immédiatement les identifiants par défaut après le premier déploiement. Les mots de passe applicatifs (MariaDB, Grafana) sont externalisés dans un fichier `.env` exclu du dépôt (`.gitignore`).

---

## 🔒 Segmentation réseau (frontend / backend)

La stack est répartie sur **deux réseaux Docker distincts** afin de cloisonner les services et de réduire la surface d'attaque :

* **frontend** (services exposés) : `nginx-web`, `wazuh.dashboard`, `uptime-kuma`, `grafana`
* **backend** (services internes / sensibles) : `mariadb-db`, `wazuh.manager`, `wazuh.indexer`, `prometheus`, `node-exporter`, `cadvisor`

Seuls `uptime-kuma`, `wazuh.dashboard` et `grafana` sont raccordés aux **deux** réseaux, pour leurs besoins légitimes (sondes, lecture des alertes, lecture des métriques). En conséquence, le service web exposé (`nginx-web`) ne partage **aucun** réseau avec la base de données : il ne peut atteindre ni `mariadb-db` ni le cœur du SOC. La base de données n'expose en outre aucun port sur l'hôte.

### Vérification

```bash
sudo docker network ls | grep hackatonm1
sudo docker inspect nginx-web  --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'   # frontend
sudo docker inspect mariadb-db --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'   # backend
sudo docker network inspect hackatonm1_backend  --format '{{range .Containers}}{{.Name}} {{end}}'
sudo docker network inspect hackatonm1_frontend --format '{{range .Containers}}{{.Name}} {{end}}'
```

---

## 🗂️ Contenu du dépôt

| Élément | Description |
| ------- | ----------- |
| `docker-compose.yml` | Orchestration complète des 10 conteneurs (réseaux frontend / backend) |
| `deploy.sh` | Déploiement automatisé de la stack |
| `hardening.yml` | Playbook Ansible de durcissement (SSH, UFW, Fail2Ban) |
| `wazuh_agent.yml` | Playbook Ansible d'installation/configuration de l'agent |
| `monitoring/` | Configuration Prometheus + provisioning Grafana |
| `nginx/` | Contenu et logs du site web |
| `.env.example` | Modèle de variables d'environnement (secrets) |

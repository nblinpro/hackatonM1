#!/bin/bash
# Deploiement du mini SOC M1Tech (Wazuh 4.11 + site web + BDD + supervision)
# A placer A LA RACINE du projet (hackatonM1/), a cote du docker-compose.yml
set -euo pipefail
cd "$(dirname "$0")"

WAZUH_VERSION="4.11.0"
CERTS_DIR="wazuh-docker/single-node/config/wazuh_indexer_ssl_certs"

echo "==> 1. Prerequis systeme (vm.max_map_count, requis par l'indexer)"
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf >/dev/null
sudo sysctl -p /etc/sysctl.d/99-wazuh.conf

echo "==> 2. Clonage du depot Wazuh v${WAZUH_VERSION} (uniquement si absent)"
if [ ! -d wazuh-docker ]; then
  git clone https://github.com/wazuh/wazuh-docker.git -b "v${WAZUH_VERSION}"
else
  echo "    wazuh-docker deja present, clonage ignore."
fi

echo "==> 3. Generation des certificats TLS (uniquement si absents)"
if [ ! -f "${CERTS_DIR}/wazuh.indexer.pem" ]; then
  ( cd wazuh-docker/single-node && sudo docker compose -f generate-indexer-certs.yml run --rm generator )
else
  echo "    Certificats deja presents, generation ignoree."
fi

echo "==> 4. Correction des droits des certificats (uid des conteneurs = 1000)"
sudo chown -R 1000:1000 \
  wazuh-docker/single-node/config/wazuh_indexer_ssl_certs \
  wazuh-docker/single-node/config/wazuh_indexer

echo "==> 5. Demarrage de la stack complete"
sudo docker compose up -d

echo "==> 6. Attente de l'indexer puis init securite si necessaire (max ~3 min)"
for _ in $(seq 1 36); do
  code=$(curl -k -s -o /dev/null -w "%{http_code}" -u admin:SecretPassword \
         https://localhost:9200/_cluster/health || true)
  if [ "$code" = "200" ]; then
    echo "    Indexer operationnel, securite deja initialisee."
    break
  fi
  if [ "$code" = "401" ]; then
    echo "    Index de securite vide -> execution de securityadmin..."
    sudo docker compose exec -T wazuh.indexer bash -c '
      export JAVA_HOME=/usr/share/wazuh-indexer/jdk
      bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
        -cd /usr/share/wazuh-indexer/opensearch-security/ -nhnv \
        -cacert /usr/share/wazuh-indexer/certs/root-ca.pem \
        -cert /usr/share/wazuh-indexer/certs/admin.pem \
        -key /usr/share/wazuh-indexer/certs/admin-key.pem -p 9200 -icl'
    break
  fi
  sleep 5
done

echo ""
echo "==> Termine. Etat des conteneurs :"
sudo docker compose ps
echo ""
echo "Dashboard Wazuh : https://<IP_VM>:443   (admin / SecretPassword)"
echo "Site web        : http://<IP_VM>"
echo "Uptime Kuma     : http://<IP_VM>:3001"

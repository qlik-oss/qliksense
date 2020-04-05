#!/bin/bash
# You need:
# - kubectl w/ qliksense plugin installed
# - gcloud set to your project: gcloud config set project my-project
# - you may wish to change the zone/region closer to 

echo "What version of QLik Sense?"
read QLIKSENSE_VERSION
echo "What is the DNS domain name of Qlik Sense?"
read DOMAIN
echo "What is the instance/host name of Qlik Sense?"
read QLIKSENSE_HOST
echo "What is the realm/host name of Keycloak?"
read KEYCLOAK_HOST
echo "What is the Keycloak client secret?"
read KEYCLOAK_SECRET
echo "What is the Default Password for Demo Users?"
read DEFAULT_USER_PASSWORD
echo "What will be the Keycloak admin password?"
read KEYCLOAK_ADMIN_PASSWORD

# Create Cluster
gcloud container clusters create $QLIKSENSE_HOST --zone "northamerica-northeast1-a" --no-enable-basic-auth --cluster-version "1.15.9-gke.22" --machine-type "n1-standard-16" --image-type "UBUNTU" --disk-type "pd-standard" --disk-size "100" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --num-nodes "4" --enable-stackdriver-kubernetes --enable-ip-alias --network "projects/dev-elastic-charts/global/networks/default" --subnetwork "projects/dev-elastic-charts/regions/northamerica-northeast1/subnetworks/default" --default-max-pods-per-node "110" --no-enable-master-authorized-networks --addons HorizontalPodAutoscaling,HttpLoadBalancing --enable-autoupgrade --enable-autorepair
echo "Cluster"
echo "--"
echo "Cluster: $QLIKSENSE_HOST"

# Create Address
gcloud compute addresses create $QLIKSENSE_HOST-ip --region=northamerica-northeast1
gcloud compute addresses create $KEYCLOAK_HOST-ip --global

# IPs
QLIKSENSE_IP=$(gcloud compute addresses describe $QLIKSENSE_HOST-ip --region=northamerica-northeast1 --format='value(address)')
KEYCLOAK_IP=$(gcloud compute addresses describe $KEYCLOAK_HOST-ip --global --format='value(address)')

echo "Addresses"
echo "--"
echo "Qliksense Host: $QLIKSENSE_HOST"
echo "Qliksense IP: $QLIKSENSE_IP"
echo "Keycloak Host: $KEYCLOAK_HOST"
echo "Keycloak IP: $KEYCLOAK_IP"

# DNS
gcloud dns record-sets transaction start --zone=qseok
gcloud dns record-sets transaction add $KEYCLOAK_IP --name=$KEYCLOAK_HOST.$DOMAIN. --ttl=300 --type=A --zone=qseok
gcloud dns record-sets transaction add $QLIKSENSE_IP --name=$QLIKSENSE_HOST.$DOMAIN. --ttl=300 --type=A --zone=qseok
gcloud dns record-sets transaction execute --zone=qseok

echo "DNS"
echo "--"
echo "Qliksense Name: $QLIKSENSE_HOST.$DOMAIN."
echo "Qliksense IP: $QLIKSENSE_IP"
echo "Keycloak Name: $KEYCLOAK_HOST.$DOMAIN."
echo "Keycloak IP: $KEYCLOAK_IP"

gcloud filestore instances create $QLIKSENSE_HOST --file-share=name="qliksense",capacity=1T --network=name="default" --zone northamerica-northeast1-a
NFS_IP=$(gcloud filestore instances describe $QLIKSENSE_HOST --zone northamerica-northeast1-a --format='value(networks[0].ipAddresses[0])')
echo "Filestore"
echo "--"
echo "nfsShare: /qliksense"
echo "nfsServer: $NFS_IP"

gcloud container clusters get-credentials $QLIKSENSE_HOST --zone northamerica-northeast1-a

kubectl qliksense config set-context $QLIKSENSE_HOST 
kubectl qliksense config set storageClassName=$QLIKSENSE_HOST-nfs-client
kubectl qliksense config set rotateKeys="no" 
kubectl qliksense config set-configs qliksense.acceptEULA="yes"
kubectl qliksense config set-secrets qliksense.mongoDbUri="mongodb://$QLIKSENSE_HOST-mongodb:27017/qsefe?ssl=false"
kubectl qliksense config set-configs gke.idpHostName=$KEYCLOAK_HOST.$DOMAIN
kubectl qliksense config set-configs gke.realmName=$QLIKSENSE_HOST
kubectl qliksense config set-configs gke.qlikSenseDomain=$DOMAIN
kubectl qliksense config set-secrets gke.clientSecret=$KEYCLOAK_SECRET
kubectl qliksense config set-configs keycloak.staticIpName=$KEYCLOAK_HOST-ip
kubectl qliksense config set-secrets keycloak.defaultUserPassword=$DEFAULT_USER_PASSWORD
kubectl qliksense config set-secrets keycloak.password=$KEYCLOAK_ADMIN_PASSWORD
kubectl qliksense config set-configs certificate.adminEmailAddress=admin@$DOMAIN
kubectl qliksense config set-configs nfs-client-provisioner.nfsServer=$NFS_IP
kubectl qliksense config set-configs nfs-client-provisioner.nfsPath="/qliksense"

kubectl qliksense fetch $QLIKSENSE_VERSION

#Install CRDS
kubectl qliksense install crds --all

# Install Cert-manager, need to be done seperatly due to timing issue
kubectl qliksense config set profile=gke/manifests/cert-manager
kubectl qliskense install

# Could wait for kubectl --wait.. nah, should be enough time
# Install gke profile
kubectl qliksense config set profile=gke
kubectl qliksense config set rotateKeys="yes"
kubectl qliskense install

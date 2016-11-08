#!/usr/bin/env bash

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# This script downloads and installs the Kubernetes control binary,
# It is intended to be called after a successful deployement of the cluster.
#
# You have to choose the correct Kubernetes control binary to download.
#
# Options:
#  Set KUBERNETES_RELEASE to choose the version (Kubernetes cluster)
#  architecture to download:
#    * amd64 [default]
#    * 386
#
#  Set MASTER_HOST to identify the Kubernetes server hostname eventually with the port number in use.

set -o errexit
set -o nounset
set -o pipefail

# K8S Configuration 
KUBERNETES_RELEASE_URL="https://storage.googleapis.com/kubernetes-release/release"
KUBERNETES_RELEASE=v1.4.3
DOWNLOAD_URL_PREFIX="${KUBERNETES_RELEASE_URL}/${KUBERNETES_RELEASE}"
# Cluster configuration
MASTER_HOST=localhost:443
CA_CERT=~/.kube/ca.crt 
ADMIN_CERT=~/.kube/kubecfg.crt 
ADMIN_KEY=~/.kube/kubecfg.key

function detect_client_info() {
  local kernel=$(uname -s)
  case "${kernel}" in
    Darwin)
      CLIENT_PLATFORM="darwin"
      ;;
    Linux)
      CLIENT_PLATFORM="linux"
      ;;
    *)
      echo "Unknown, unsupported platform: ${kernel}." >&2
      echo "Supported platforms: Linux, Darwin." >&2
      exit 1
  esac

  local machine=$(uname -m)
  case "${machine}" in
    x86_64*|i?86_64*|amd64*)
      CLIENT_ARCH="amd64"
      ;;
    i?86*)
      CLIENT_ARCH="386"
      ;;
    *)
      echo "Unknown, unsupported architecture (${machine})." >&2
      echo "Supported architectures x86_64, i686." >&2
      exit 2
      ;;
  esac
}

function download_kubectl()
{
    local -r url="${DOWNLOAD_URL_PREFIX}/${KUBERNETES_RELEASE}/bin/${CLIENT_PLATFORM}/${CLIENT_ARCH}/kubectl"
    echo "Will download kubectl from ${url}"
    echo 
    if [[ $(which curl) ]]; then
        curl -L "${url}" -o "kubectl"
    elif [[ $(which wget) ]]; then
        wget "${url}" -O "kubectl" && chmod +x kubectl && mv kubectl /usr/local/bin/kubectl && \
         echo "Add '/usr/local/bin/' to your PATH to use the installed binary."
        /usr/local/bin/kubectl config set preferences.colors true;
        echo "Show kubectl current configuration"
        /usr/local/bin/kubectl config view;
        echo
    else
    echo "Couldn't find curl or wget." >&2
    exit 3
    fi
}

function copy_certificates()
{
    local -r hostname=`echo ${MASTER_HOST} | awk 'BEGIN { FS=":" } /1/ { print $1 }'`
    echo "Will copy certificates from ${hostname}"
    echo 
    if [[ $(which scp) ]]; then
        echo "Copying Kubernetes certificate from Kube Master"
        scp -rp root@"${hostname}":/etc/kubernetes/certs/ ~/.kube 
    else
        echo "Couldn't find scp." >&2
        exit 4
    fi
    # Generate certificate to be feeded in the browser, (ie: Keychain on MacOS) 
    # sudo openssl pkcs12 -export -clcerts -inkey certs/kubecfg.key -in certs/kubecfg.crt -out kubecfg.p12 -name "kubecfg"
    # open kubecfg.p12
}

function configure_kubectl()
{
    echo "API access to Kubernetes master: ${MASTER_HOST}"
    /usr/local/bin/kubectl config set-cluster default-cluster --server=https://${MASTER_HOST} --certificate-authority=${CA_CERT} --embed-certs=true && \
    /usr/local/bin/kubectl config set-credentials default-admin --certificate-authority=${CA_CERT} --client-key=${ADMIN_KEY} --client-certificate=${ADMIN_CERT} && \
    # /usr/local/bin/kubectl config set-credentials default-admin-basic-auth --username=admin --password=webinage && \
    /usr/local/bin/kubectl config set-context default-system --cluster=default-cluster --user=default-admin && \
    # /usr/local/bin/kubectl config set-context default-system-basic-auth --cluster=default-cluster --user=default-admin-basic-auth && \
    /usr/local/bin/kubectl config use-context default-system && \
    # /usr/local/bin/kubectl config use-context default-system-basic-auth && \
    
    echo "Backup the configuration file" && \
    cp ~/.kube/config ~/.kube/config.`date "+%Y%m%d"`.bak

    echo "Check kubectl configuration and connection"
    /usr/local/bin/kubectl get nodes
}

echo "Detect client machine information..."
detect_client_info
echo "Kubernetes Control over: ${CLIENT_PLATFORM}/${CLIENT_ARCH}"
echo
echo "Download kubectl binary..."
download_kubectl
echo
echo "Copy Kubernetes certificate..."
copy_certificates
echo
echo "Configure kubectl to access the cluster..."
configure_kubectl

# Error launching Kube UI 
# Workaround for Kube UI, we have to add a route as instance: 
# route add -net $IP netmask 255.255.255.255 gw $GATEWAY
#
# Accesing the API
#
# Via Python Script
# >>> import requests
# >>> url = 'https://...'
# >>> headers = {'Authorization': 'Bearer TOKEN'}
# >>> requests.get(url, headers=headers, verify=False)
# <Response [200]>
#
# Via Shell Script
# export TOKEN=$(kubectl describe secret $(kubectl get secrets | grep default | cut -f1 -d ' ') | grep -E '^token' | cut -f2 -d':' | tr -d '\t')
# export APISERVER=https://...:443
# curl -X GET -H "Authorization: Bearer <token>" https://... --insecure
#
# Example:
# curl $APISERVER/api --header "Authorization: Bearer $TOKEN" --insecure
# {
#   "kind": "APIVersions",
#   "versions": [
#     "v1"
#   ],
#   "serverAddressByClientCIDRs": [
#     {
#       "clientCIDR": "0.0.0.0/0",
#       "serverAddress": "...:443"
#     }
#   ]
# }
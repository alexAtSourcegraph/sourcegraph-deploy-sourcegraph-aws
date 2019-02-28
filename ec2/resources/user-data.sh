#!/usr/bin/env bash

# Set $HOME as it does not exist for the running of this script
export HOME=/root
export SOURCEGRAPH_VERSION=3.1.1

# For convenience as binarties installed to /usr/local/bin are used
export PATH=$PATH:/usr/local/bin

# Update system
yum clean all
yum update -y
yum upgrade -y

# Add docker to packages list
amazon-linux-extras install docker

yum install -y \
    docker \
    git \
    make \
    nano \
    python3 \

# Install Docker Compose
pip3 install pip setuptools --upgrade
pip3 install docker-compose

# Start docker service now and on boot
systemctl enable --now --no-block docker

## Generate certs and replace existing nginx

# Create the ~/.sourcegraph/config directory to hold the certificates
mkdir -p ~/.sourcegraph/config

# Install mkcert and generate root CA, certificate and key 
wget https://github.com/FiloSottile/mkcert/releases/download/v1.3.0/mkcert-v1.3.0-linux-amd64 -O /usr/local/bin/mkcert
chmod a+x /usr/local/bin/mkcert
mkcert -install
mkcert -cert-file ~/.sourcegraph/config/sourcegraph.crt -key-file ~/.sourcegraph/config/sourcegraph.key $(curl http://169.254.169.254/latest/meta-data/public-hostname)

#
# Configure the nginx.conf file for SSL.
#
# This so the nginx.conf file contents does not have to be hard-coded in this file, 
# which means a new instance will always use the original nginx.conf file from that
# image version.
#
wget https://raw.githubusercontent.com/sourcegraph/sourcegraph/v${SOURCEGRAPH_VERSION}/cmd/server/shared/assets/nginx.conf -O ~/.sourcegraph/config/nginx.conf
export NGINX_FILE_PATH="${HOME}/.sourcegraph/config/nginx.conf"
cp ${NGINX_FILE_PATH} ${NGINX_FILE_PATH}.bak
python -u -c "import os; print(open(os.environ['NGINX_FILE_PATH'] + '.bak').read().replace('listen 7080;', '''listen 7080 ssl;

        # Presumes .crt and.key files are in the same directory as this nginx.conf (/etc/sourcegraph in the container)
        ssl_certificate         sourcegraph.crt;
        ssl_certificate_key     sourcegraph.key;

'''
))" > ${NGINX_FILE_PATH}

# TODO: Zip up CAroot files for easy downloading and installing on developer machines

docker network create sourcegraph
docker container run \
    --name sourcegraph \
    -d \
    --restart on-failure \
    \
    --network sourcegraph \
    --hostname sourcegraph \
    --network-alias sourcegraph \
    \
    -p 80:7080 \
    -p 443:7080 \
    -p 2633:2633 \
    \
    -v ~/.sourcegraph/config:/etc/sourcegraph \
    -v ~/.sourcegraph/data:/var/opt/sourcegraph \
    \
    sourcegraph/server:${SOURCEGRAPH_VERSION}

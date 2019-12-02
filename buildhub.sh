#!/bin/bash
# 2019-05-24

if [[ ! -f .env ]]; then
    echo "Copying environment template..."
    cp .env-template .env
fi
# generate PostGreSQL password and proxy token
# update .env with values
echo "Generating PostGreSQL passwords and JupyterHub proxy tokens..."
./pg_pass.sh
./proxy_token.sh

if [[ ! -f userlist ]]; then
    echo "Copying userlist template..."
  cp userlist-template userlist
fi

source .env

./stophub.sh

if [[ "$(docker images -q jupyterhub:latest)" == "" ]]; then
  echo "JupyterHub image does not exist."
else
  echo "Deleting Docker images..."
  docker rmi $(docker images -a | grep jupyterhub | awk '{print $3}')
fi

# get images for base notebooks for Dockerfile.custom and Dockerfile.stacks
if [[ "$(docker images -q jupyter/minimal-notebook)" == "" ]]; then
    echo "Pulling jupyter stacks images..."
    docker pull jupyter/datascience-notebook:$IMAGE_TAG
    docker pull jupyter/scipy-notebook:$IMAGE_TAG
    docker pull jupyter/r-notebook:$IMAGE_TAG
    docker pull jupyter/minimal-notebook:$IMAGE_TAG
    docker pull quay.io/letsencrypt/letsencrypt:latest
fi

echo "Creating network and data volumes..."
make network volumes
docker volume create --name=nginx_vhostd
docker volume create --name=nginx_html

echo "Creating SSL certificate..."
./create-certs.sh

echo "Building Docker images..."
echo "JUPYTERHUB_SSL = $JUPYTERHUB_SSL"
case $JUPYTERHUB_SSL in
    use_ssl_ss)
        echo "Shutting down JupyterHub..."
        docker-compose -f docker-compose.yml down
        ;;
    use_ssl_le)
        echo "Shutting down JupyterHub-LetsEncrypt..."
        docker-compose -f docker-compose-letsencrypt.yml down
        ;;
esac
# Get jupyterhub host IP address
echo "Obtaining JupyterHub host ip address..."
FILE1='secrets/jupyterhub_host_ip'
if [ -f $FILE1 ]; then
    rm $FILE1
else
    touch $FILE1
fi
unset JUPYTERHUB_SERVICE_HOST_IP
echo "JUPYTERHUB_SSL = $JUPYTERHUB_SSL"
case $JUPYTERHUB_SSL in
    use_ssl_ss)
        echo "Starting up JupyterHub..."
        docker-compose -f docker-compose.yml up -d
        ;;
    use_ssl_le)
        echo "Starting up JupyterHub-LetsEncrypt..."
        docker-compose -f docker-compose-letsencrypt.yml up -d
        sleep 60
        cp secrets/$JH_FQDN/fullchain.pem secrets/jupyterhub.pem
        cp secrets/$JH_FQDN/key.pem secrets/jupyterhub.key
        ;;
esac
echo "Saving data to $FILE1..."
echo "JUPYTERHUB_SERVICE_HOST_IP='`docker inspect --format '{{ .NetworkSettings.Networks.jupyterhubnet.IPAddress }}' jupyterhub`'" >> $FILE1
echo "JUPYTERHUB_SSL = $JUPYTERHUB_SSL"
case $JUPYTERHUB_SSL in
    use_ssl_ss)
        echo "Shutting down JupyterHub..."
        docker-compose -f docker-compose.yml down
        ;;
    use_ssl_le)
        echo "Shutting down JupyterHub-LetsEncrypt..."
        docker-compose -f docker-compose-letsencrypt.yml down
        ;;
esac
echo 'Set Jupyterhub Host IP:'
cat $FILE1
source $FILE1
rm $FILE1
echo "JUPYTERHUB_SERVICE_HOST_IP is now set to:"
echo $JUPYTERHUB_SERVICE_HOST_IP
echo "..."
sed -i -e "s/REPLACE_IP/$JUPYTERHUB_SERVICE_HOST_IP/g" .env
docker stop $(docker ps -a | grep jupyter- | awk '{print $1}')
docker rm $(docker ps -a | grep jupyter- | awk '{print $1}')
docker rmi $(docker images -q jupyterhub:latest)
docker rmi $(docker images -q postgres-hub:latest)
#docker rmi -f $(docker images -q jupyterhub-user:latest)
if [ ! -f 'singleuser/drive.jupyterlab-settings' ]; then
    echo "Copying Google drive JupyterLab settings template..."
    cp singleuser/drive.jupyterlab-settings-template singleuser/drive.jupyterlab-settings
fi
echo "Rebuilding JupyterHub and Single-user Docker images..."
echo "JUPYTERHUB_SSL = $JUPYTERHUB_SSL"
case $JUPYTERHUB_SSL in
    use_ssl_ss)
        echo "Rebuilding JupyterHub..."
        docker-compose -f docker-compose.yml build
        ;;
    use_ssl_le)
        echo "Rebuilding JupyterHub-LetsEncrypt..."
        docker-compose -f docker-compose-letsencrypt.yml build
        ;;
esac

echo "Building notebook image..."
make notebook_base
make notebook_body
make notebook_image
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Error was: $rc" >> errorlog.txt
else
  if [ -f .env-e ]; then
      rm .env-e
  fi
  echo "Build complete!"
  echo "Run starthub.sh from the command line..."
fi

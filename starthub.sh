#!/bin/bash
source .env
echo "Starting up JupyterHub"
echo "..."
echo "JUPYTERHUB_SSL = $JUPYTERHUB_SSL"
case $JUPYTERHUB_SSL in
    use_ssl_ss)
        echo "Starting up JupyterHub..."
        docker-compose -f docker-compose.yml up -d
        docker-compose -f docker-compose.yml logs -f -t --tail='all'
        ;;
    use_ssl_le)
        echo "Starting up JupyterHub-LetsEncrypt..."
        if [[ ! -f  secrets/jupyterhub.pem ]]; then
            echo "Copying JupyterHub SSL certificate - please provide sudo password..."
            sudo cp secrets/$JH_FQDN/fullchain.pem secrets/jupyterhub.pem
            sudo cp secrets/$JH_FQDN/key.pem secrets/jupyterhub.key
        fi
        docker-compose -f docker-compose-letsencrypt.yml up -d
        docker-compose -f docker-compose-letsencrypt.yml logs -f -t --tail='all'
        ;;
esac
bash logs.sh

#!/bin/bash
USER=${1:-viet}
PW=${2:-viet}
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"

sudo useradd -m -p $PW -s /bin/bash $USER

sudo mkdir /home/$USER/.ssh
sudo chown -R $USER:$USER /home/$USER/.ssh
sudo chmod -R go-rwx /home/$USER/.ssh

sudo apt update -y
sudo apt install -y docker-ce
sudo usermod -aG docker $USER

# Then carry on to manually add authorized_keys and check out the relevant git repos.

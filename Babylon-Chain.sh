#!/bin/bash

function colors {
  GREEN="\e[32m"
  RED="\e[39m"
  YELLOW="\e[33m"
  NORMAL="\e[0m"
}

function logo {
  curl -s https://raw.githubusercontent.com/Creator-CB/FILES/main/TDM-Crypto.sh | bash
}

function line {
  echo -e "${RED}-----------------------------------------------------------------------------${NORMAL}"
}

function get_nodename {
    sed -i '/alias client/d' $HOME/.profile

    # source $HOME/.profile
    # sleep 1
    # if [ ! ${BABYLON_MONIKER} ]; then
    echo -e "${GREEN}Name your node:${NORMAL}"
    read BABYLON_MONIKER
    echo 'export BABYLON_MONIKER='$BABYLON_MONIKER >> $HOME/.profile
    # fi
}

function install_go {
    bash <(curl -s https://raw.githubusercontent.com/Creator-CB/FILES/main/go.sh)
    source $HOME/.profile
    sleep 1
}

function source_build_git {
    cd $HOME
    rm -rf babylon
    git clone https://github.com/babylonchain/babylon.git
    cd babylon
    git checkout v0.8.3

    make build

    mkdir -p $HOME/.babylond/cosmovisor/genesis/bin
    mv build/babylond $HOME/.babylond/cosmovisor/genesis/bin/
    rm -rf build

    sudo ln -s $HOME/.babylond/cosmovisor/genesis $HOME/.babylond/cosmovisor/current -f
    sudo ln -s $HOME/.babylond/cosmovisor/current/bin/babylond /usr/local/bin/babylond -f

    go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
}

function systemd {
    sudo tee /etc/systemd/system/babylon.service > /dev/null << EOF
[Unit]
Description=babylon node service
After=network-online.target

[Service]
User=$USER
ExecStart=$HOME/go/bin/cosmovisor run start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/.babylond"
Environment="DAEMON_NAME=babylond"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$HOME/.babylond/cosmovisor/current/bin"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable babylon.service
}

function init_chain {
    babylond config chain-id bbn-test-3
    babylond config keyring-backend test
    

    babylond init $BABYLON_MONIKER --chain-id bbn-test-3

    

sed -i -e "s|^seeds *=.*|seeds = \"49b4685f16670e784a0fe78f37cd37d56c7aff0e@3.14.89.82:26656,9cb1974618ddd541c9a4f4562b842b96ffaf1446@3.16.63.237:26656\"|" $HOME/.babylond/config/config.toml

sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0.00001ubbn\"|" $HOME/.babylond/config/app.toml

sed -i -e "s|^network *=.*|network = \"signet\"|" $HOME/.babylond/config/app.toml

  sed -i \
  -e 's|^pruning *=.*|pruning = "custom"|' \
  -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
  -e 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|' \
  -e 's|^pruning-interval *=.*|pruning-interval = "19"|' \
  $HOME/.babylond/config/app.toml


   
}

function download_snapshot {
wget https://github.com/babylonchain/networks/raw/main/bbn-test-3/genesis.tar.bz2
tar -xjf genesis.tar.bz2 && rm genesis.tar.bz2
mv genesis.json ~/.babylond/config/genesis.json
 
}

function start {
    sudo systemctl start babylon
    sudo systemctl start babylond.service
}

function main {
    colors
    logo
    get_nodename
    install_go
    source_build_git
    systemd
    init_chain
    download_snapshot
    start
}

main

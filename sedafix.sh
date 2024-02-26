#!/bin/bash

# Required packages installation
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl git jq lz4 build-essential unzip logrotate jq sed wget coreutils systemd

# Go installation
sudo rm -rf /usr/local/go
curl -Ls https://go.dev/dl/go1.17.7.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
eval $(echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/golang.sh)
eval $(echo 'export PATH=$PATH:$HOME/go/bin' | tee -a $HOME/.profile)
go version

# Download and build binaries

cd $HOME
rm -rf seda-chain
git clone https://github.com/sedaprotocol/seda-chain.git
cd seda-chain
git checkout v0.0.5
make build

# Prepare binaries for Cosmovisor
mkdir -p $HOME/.seda-chain/cosmovisor/genesis/bin
mv build/seda-chaind $HOME/.seda-chain/cosmovisor/genesis/bin/
rm -rf build

# Create application symlinks
sudo ln -s $HOME/.seda-chain/cosmovisor/genesis $HOME/.seda-chain/cosmovisor/current -f
sudo ln -s $HOME/.seda-chain/cosmovisor/current/bin/seda-chaind /usr/local/bin/seda-chaind -f

# Download and install Cosmovisor
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0

# Create service
sudo tee /etc/systemd/system/seda.service > /dev/null << EOF
[Unit]
Description=seda node service
After=network-online.target

[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/.seda-chain"
Environment="DAEMON_NAME=seda-chaind"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$HOME/.seda-chain/cosmovisor/current/bin"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable seda.service

# Set node configuration
seda-chaind config chain-id seda-1-testnet
seda-chaind config keyring-backend test
seda-chaind config node tcp://localhost:17357

# Initialize the node
seda-chaind init $MONIKER --chain-id seda-1-testnet

# Download genesis and addrbook
curl -Ls https://snapshots.kjnodes.com/seda-testnet/genesis.json > $HOME/.seda-chain/config/genesis.json
curl -Ls https://snapshots.kjnodes.com/seda-testnet/addrbook.json > $HOME/.seda-chain/config/addrbook.json

# Add seeds
sed -i -e "s|^seeds *=.*|seeds = \"3f472746f46493309650e5a033076689996c8881@seda-testnet.rpc.kjnodes.com:17359\"|" $HOME/.seda-chain/config/config.toml

# Set minimum gas price
sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0aseda\"|" $HOME/.seda-chain/config/app.toml

# Set pruning
sed -i \
  -e 's|^pruning *=.*|pruning = "custom"|' \
  -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
  -e 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|' \
  -e 's|^pruning-interval *=.*|pruning-interval = "19"|' \
  $HOME/.seda-chain/config/app.toml

# Set custom ports
sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:17358\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:17357\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:17360\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:17356\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":17366\"%" $HOME/.seda-chain/config/config.toml
sed -i -e "s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:17317\"%; s%^address = \":8080\"%address = \":17380\"%; s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:17390\"%; s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:17391\"%; s%:8545%:17345%; s%:8546%:17346%; s%:6065%:17365%" $HOME/.seda-chain/config/app.toml

# Download latest chain snapshot
curl -L https://snapshots.kjnodes.com/seda-testnet/snapshot_latest.tar.lz4 | tar -Ilz4 -xf - -C $HOME/.seda-chain
[[ -f $HOME/.seda-chain/data/upgrade-info.json ]] && cp $HOME/.seda-chain/data/upgrade-info.json $HOME/.seda-chain/cosmovisor/genesis/upgrade-info.json

# Start service and check the logs
sudo systemctl start seda.service && sudo journalctl -u seda.service -f --no-hostname -o cat

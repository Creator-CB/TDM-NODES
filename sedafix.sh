#!/bin/bash

# Set the moniker
set_moniker() {
    echo -e "${YELLOW}Enter the node name (create one):${NORMAL}"
    line
    read MONIKER
    echo 'export MONIKER='$MONIKER >> $HOME/.profile
}

# Required packages installation
sudo apt update
sleep 2
sudo apt upgrade -y
sleep 2
sudo apt install -y curl git jq lz4 build-essential unzip logrotate jq sed wget coreutils systemd
sleep 2

# Go installation
sudo rm -rf /usr/local/go
sleep 2
curl -Ls https://go.dev/dl/go1.17.7.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
sleep 2
eval $(echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/golang.sh)
sleep 2
eval $(echo 'export PATH=$PATH:$HOME/go/bin' | tee -a $HOME/.profile)
sleep 2
go version
sleep 2

# Download and build binaries
cd $HOME
sleep 2
rm -rf seda-chain
sleep 2
git clone https://github.com/sedaprotocol/seda-chain.git
sleep 2
cd seda-chain
sleep 2
git checkout v0.0.5
sleep 2
make build
sleep 2

# Prepare binaries for Cosmovisor
mkdir -p $HOME/.seda-chain/cosmovisor/genesis/bin
sleep 2
mv build/seda-chaind $HOME/.seda-chain/cosmovisor/genesis/bin/
sleep 2
rm -rf build
sleep 2

# Create application symlinks
sudo ln -s $HOME/.seda-chain/cosmovisor/genesis $HOME/.seda-chain/cosmovisor/current -f
sleep 2
sudo ln -s $HOME/.seda-chain/cosmovisor/current/bin/seda-chaind /usr/local/bin/seda-chaind -f
sleep 2

# Download and install Cosmovisor
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0
sleep 2

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
sleep 2
sudo systemctl enable seda.service
sleep 2

# Set node configuration
seda-chaind config chain-id seda-1-testnet
sleep 2
seda-chaind config keyring-backend test
sleep 2
seda-chaind config node tcp://localhost:17357
sleep 2

# Initialize the node
seda-chaind init $MONIKER --chain-id seda-1-testnet
sleep 2

# Download genesis and addrbook
curl -Ls https://snapshots.kjnodes.com/seda-testnet/genesis.json > $HOME/.seda-chain/config/genesis.json
sleep 2
curl -Ls https://snapshots.kjnodes.com/seda-testnet/addrbook.json > $HOME/.seda-chain/config/addrbook.json
sleep 2

# Add seeds
sed -i -e "s|^seeds *=.*|seeds = \"3f472746f46493309650e5a033076689996c8881@seda-testnet.rpc.kjnodes.com:17359\"|" $HOME/.seda-chain/config/config.toml
sleep 2

# Set minimum gas price
sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0aseda\"|" $HOME/.seda-chain/config/app.toml
sleep 2

# Set pruning
sed -i \
  -e 's|^pruning *=.*|pruning = "custom"|' \
  -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
  -e 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|' \
  -e 's|^pruning-interval *=.*|pruning-interval = "19"|' \
  $HOME/.seda-chain/config/app.toml
sleep 2

# Set custom ports
sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:17358\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:17357\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:17360\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:17356\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":17366\"%" $HOME/.seda-chain/config/config.toml
sleep 2
sed -i -e "s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:17317\"%; s%^address = \":8080\"%address = \":17380\"%; s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:17390\"%; s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:17391\"%; s%:8545%:17345%; s%:8546%:17346%; s%:6065%:17365%" $HOME/.seda-chain/config/app.toml
sleep 2

# Download latest chain snapshot
curl -L https://snapshots.kjnodes.com/seda-testnet/snapshot_latest.tar.lz4 | tar -Ilz4 -xf - -C $HOME/.seda-chain
sleep 2
[[ -f $HOME/.seda-chain/data/upgrade-info.json ]] && cp $HOME/.seda-chain/data/upgrade-info.json $HOME/.seda-chain/cosmovisor/genesis/upgrade-info.json

# Start service and check the logs
sudo systemctl start seda.service && sudo journalctl -u seda.service -f --no-hostname -o cat

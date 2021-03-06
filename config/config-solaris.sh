function setMainVars() {
## set network dependent variables
NETWORK=""
NODE_USER=${FORK}${NETWORK}
COINPORT=60000
COINRPCPORT=61000
COINAPIPORT=62000
}

function setTestVars() {
## set network dependent variables
NETWORK="-testnet"
NODE_USER=${FORK}${NETWORK}
COINPORT=60009
COINRPCPORT=61009
COINAPIPORT=62009
}

function setGeneralVars() {
## set general variables
# COINRUNCMD="dotnet ./Stratis.SolarisD.dll ${NETWORK} -agentprefix=trustaking -datadir=/home/${NODE_USER}/.${FORK}node -maxblkmem=2 -txindex=1 \${stakeparams} \${rpcparams}"
# COINGITHUB=https://github.com/SolarisPlatform/SolarisBitcoinFullNode.git
# COINDSRC=/home/${NODE_USER}/code/src/Stratis.SolarisD
COINRUNCMD="dotnet ./Solaris.Node.dll ${NETWORK} -agentprefix=trustaking -datadir=/home/${NODE_USER}/.blockcore -maxblkmem=2 -minimumsplitcoinvalue=15000000000 -enablecoinstakesplitting=1 \${stakeparams} \${rpcparams}"
COINGITHUB=https://github.com/block-core/blockcore-nodes.git
COINDSRC=/home/${NODE_USER}/code/XLR/src/Solaris.Node
CONF=release
COINDAEMON=${FORK}d
COINCONFIG=${FORK}.conf
COINSTARTUP=/home/${NODE_USER}/${FORK}d
COINDLOC=/home/${NODE_USER}/${FORK}node
COINSERVICELOC=/etc/systemd/system/
COINSERVICENAME=${COINDAEMON}@${NODE_USER}
SWAPSIZE="1024" ## =1GB
# variables for node website
howtourl="https://www.solarisplatform.com/howto-trustaking.html";
withdrawurl="https://www.solarisplatform.com/howto-withdraw.html";
addurl="https://www.solarisplatform.com/howto-addmorecoins.html";
howtovpsurl="https://www.solarisplatform.com/howto-coldstakingvps.html";
walleturl="https://www.solarisplatform.com/wallets.html";
vpsurl="https://github.com/thecrypt0hunter/node-installer";
segwit="false";
whitelist=1;
payment=1;
exchange=0;
}
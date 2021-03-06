#!/bin/bash
NONE='\033[00m'
RED='\033[01;31m'
GREEN='\033[01;32m'
YELLOW='\033[01;33m'
PURPLE='\033[01;35m'
CYAN='\033[01;36m'
WHITE='\033[01;37m'
BOLD='\033[1m'
UNDERLINE='\033[4m'

OS_VER="Ubuntu*"
ARCH="linux-x64"
DATE_STAMP="$(date +%y-%m-%d-%s)"
NODE_IP=$(curl --silent whatismyip.akamai.com)

usage() { echo "Usage: $0 [-f coin name] [-u rpc username] [-p rpc password] [-n (m/t/u) main, test or upgrade] [-b github branch/tags] [-d dotnet version]" 1>&2; exit 1; }

while getopts ":f:u:p:n:b:d:" option; do
    case "${option}" in
        f) FORK=${OPTARG};;
        u) RPCUSER=${OPTARG};;
        p) RPCPASS=${OPTARG};;
        n) NET=${OPTARG};;
        b) BRANCH=${OPTARG};;
        d) DOTNETVER=${OPTARG};;
        *) usage ;;
    esac
done
shift "$((OPTIND-1))"

source ~/config-${FORK}.sh

if [ "${BRANCH}" = "" ]; then 
BRANCH="master";
fi

function check_root() {
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}* Sorry, this script needs to be run as root. Do \"su root\" and then re-run this script${NONE}"
    exit 1
    echo -e "${NONE}${GREEN}* All Good!${NONE}";
fi
}

function create_user() {
    echo
    echo "* Checking for user & add if required. Please wait..."
    # our new mnode unpriv user acc is added
    if id "${NODE_USER}" >/dev/null 2>&1; then
        echo "user exists already, do nothing"
    else
        echo -e "${NONE}${GREEN}* Adding new system user ${NODE_USER}${NONE}"
        adduser --disabled-password --gecos "" ${NODE_USER} &>> ${SCRIPT_LOGFILE}
        usermod -aG sudo ${NODE_USER} &>> ${SCRIPT_LOGFILE}
        echo -e "${NODE_USER} ALL=(ALL) NOPASSWD:ALL" &>> /etc/sudoers.d/90-cloud-init-users
    fi
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function set_permissions() {
    chown -R ${NODE_USER}:${NODE_USER} ${COINSTARTUP} ${COINDLOC} &>> ${SCRIPT_LOGFILE}
    # make group permissions same as user, so vps-user can be added to node group
    chmod -R g=u ${COINSTARTUP} ${COINDLOC} ${COINSERVICELOC} &>> ${SCRIPT_LOGFILE}
}

function checkOSVersion() {
   echo
   echo "* Checking OS version..."
    if [[ `cat /etc/issue.net`  == ${OS_VER} ]]; then
        echo -e "${GREEN}* You are running `cat /etc/issue.net` . Setup will continue.${NONE}";
    else
        echo -e "${RED}* You are not running ${OS_VER}. You are running `cat /etc/issue.net` ${NONE}";
        echo && echo "Installation cancelled" && echo;
        exit;
    fi
}

function updateAndUpgrade() {
    echo
    echo "* Running update and upgrade. Please wait..."
    apt-get update -qq -y &>> ${SCRIPT_LOGFILE}
    apt-get upgrade -y -qq &>> ${SCRIPT_LOGFILE}
    apt-get autoremove -y -qq &>> ${SCRIPT_LOGFILE}
    echo -e "${GREEN}* Done${NONE}";
}

function setupSwap() {
#check if swap is available
    echo
    echo "* Creating Swap File. Please wait..."
    if [ $(free | awk '/^Swap:/ {exit !$2}') ] || [ ! -f "/swap.img" ];then
    echo -e "${GREEN}* No proper swap, creating it.${NONE}";
    # needed because ant servers are ants
    rm -f /swap.img &>> ${SCRIPT_LOGFILE}
    dd if=/dev/zero of=/swap.img bs=1024k count=${SWAPSIZE} &>> ${SCRIPT_LOGFILE}
    chmod 0600 /swap.img &>> ${SCRIPT_LOGFILE}
    mkswap /swap.img &>> ${SCRIPT_LOGFILE}
    swapon /swap.img &>> ${SCRIPT_LOGFILE}
    echo '/swap.img none swap sw 0 0' | tee -a /etc/fstab &>> ${SCRIPT_LOGFILE}
    echo 'vm.swappiness=10' | tee -a /etc/sysctl.conf &>> ${SCRIPT_LOGFILE}
    echo 'vm.vfs_cache_pressure=50' | tee -a /etc/sysctl.conf &>> ${SCRIPT_LOGFILE}
else
    echo -e "${GREEN}* All good, we have a swap.${NONE}";
fi
}

function installFail2Ban() {
    echo
    echo -e "* Installing fail2ban. Please wait..."
    apt-get -y install fail2ban &>> ${SCRIPT_LOGFILE}
    systemctl enable fail2ban &>> ${SCRIPT_LOGFILE}
    systemctl start fail2ban &>> ${SCRIPT_LOGFILE}
    # Add Fail2Ban memory hack if needed
    if ! grep -q "ulimit -s 256" /etc/default/fail2ban; then
       echo "ulimit -s 256" | tee -a /etc/default/fail2ban &>> ${SCRIPT_LOGFILE}
       systemctl restart fail2ban &>> ${SCRIPT_LOGFILE}
    fi
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function installFirewall() {
    echo
    echo -e "* Installing UFW. Please wait..."
    apt-get -y install ufw &>> ${SCRIPT_LOGFILE}
    ufw allow OpenSSH &>> ${SCRIPT_LOGFILE}
    ufw allow $COINPORT/tcp &>> ${SCRIPT_LOGFILE}
    if [ "${DNSPORT}" != "" ] ; then
        ufw allow ${DNSPORT}/tcp &>> ${SCRIPT_LOGFILE}
        ufw allow ${DNSPORT}/udp &>> ${SCRIPT_LOGFILE}
    fi
    echo "y" | ufw enable &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function installDependencies() {
    echo
    echo -e "* Installing dependencies. Please wait..."
    timedatectl set-ntp no &>> ${SCRIPT_LOGFILE}
    apt-get install git ntp nano wget curl software-properties-common -y &>> ${SCRIPT_LOGFILE}
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${VERSION_ID}" = "16.04" ]]; then
            wget -q https://packages.microsoft.com/config/ubuntu/16.04/packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            dpkg -i packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            apt-get install apt-transport-https -y &>> ${SCRIPT_LOGFILE}
            apt-get update -y &>> ${SCRIPT_LOGFILE}
            apt-get install -y dotnet-sdk-${DOTNETVER} --allow-downgrades &>> ${SCRIPT_LOGFILE}
            echo -e "${NONE}${GREEN}* Done${NONE}";
        fi
        if [[ "${VERSION_ID}" = "18.04" ]]; then
            wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            dpkg -i packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            add-apt-repository universe -y &>> ${SCRIPT_LOGFILE}
            apt-get install apt-transport-https -y &>> ${SCRIPT_LOGFILE}
            apt-get update -y &>> ${SCRIPT_LOGFILE}
            apt-get install -y dotnet-sdk-${DOTNETVER} --allow-downgrades &>> ${SCRIPT_LOGFILE}
            echo -e "${NONE}${GREEN}* Done${NONE}";
        fi
        if [[ "${VERSION_ID}" = "19.04" ]]; then
            wget -q https://packages.microsoft.com/config/ubuntu/19.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            dpkg -i packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            apt-get install apt-transport-https -y &>> ${SCRIPT_LOGFILE}
            apt-get update -y &>> ${SCRIPT_LOGFILE}
            apt-get install -y  dotnet-sdk-${DOTNETVER} --allow-downgrades &>> ${SCRIPT_LOGFILE}
            wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl1.0/libssl1.0.0_1.0.2n-1ubuntu6_amd64.deb &>> ${SCRIPT_LOGFILE}
            dpkg -i libssl1.0.0_1.0.2n-1ubuntu6_amd64.deb &>> ${SCRIPT_LOGFILE}
            echo -e "${NONE}${GREEN}* Done${NONE}";
        fi
        if [[ "${VERSION_ID}" = "20.04" ]]; then
            wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            dpkg -i packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            apt-get install apt-transport-https -y &>> ${SCRIPT_LOGFILE}
            apt-get update -y &>> ${SCRIPT_LOGFILE}
            apt-get install -y dotnet-sdk-${DOTNETVER} --allow-downgrades &>> ${SCRIPT_LOGFILE}
            echo -e "${NONE}${GREEN}* Done${NONE}";
        fi
        else
        echo -e "${NONE}${RED}* Version: ${VERSION_ID} not supported.${NONE}";
    fi
}

function compileWallet() {
    echo
    echo -e "* Compiling wallet. Please wait, this might take a while to complete..."
    if [ ! -d /home/${NODE_USER} ]; then 
        mkdir /home/${NODE_USER} 
    fi
    cd /home/${NODE_USER}/
    git clone --recurse-submodules --branch=${BRANCH} ${COINGITHUB} code &>> ${SCRIPT_LOGFILE}
    cd /home/${NODE_USER}/code
    git submodule update --init --recursive &>> ${SCRIPT_LOGFILE}
    cd ${COINDSRC}
    dotnet publish -c ${CONF} -r ${ARCH} -v m -o ${COINDLOC} &>> ${SCRIPT_LOGFILE} ### compile & publish code
    # Workaround to install FodyNlogAdapter
    #wget -P /home/${NODE_USER}/code https://globalcdn.nuget.org/packages/stratis.fodynlogadapter.3.0.4.1.nupkg &>> ${SCRIPT_LOGFILE}
    #unzip -qq -o /home/${NODE_USER}/code/stratis.fodynlogadapter.3.0.4.1.nupkg -d /home/${NODE_USER}/code &>> ${SCRIPT_LOGFILE}
    #mv /home/${NODE_USER}/code/lib/netstandard2.0/* ${COINDLOC} &>> ${SCRIPT_LOGFILE}
    rm -rf /home/${NODE_USER}/code &>> ${SCRIPT_LOGFILE} 	                       ### Remove source
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function installWallet() {
    echo
    echo -e "* Installing wallet. Please wait..."
    cd /home/${NODE_USER}/
    echo -e "#!/bin/bash\nexport DOTNET_CLI_TELEMETRY_OPTOUT=1\nexport LANG=en_US.UTF-8\nif [ -f /var/secure/cred-${FORK}.sh ]; then\nsource /var/secure/cred-${FORK}.sh\nstakeparams=\"-stake -walletname=\${STAKINGNAME} -walletpassword=\${STAKINGPASSWORD}\"\nrpcparams=\"-server -rpcuser=\${RPCUSER} -rpcpassword=\${RPCPASS}\"\nfi\ncd $COINDLOC\n$COINRUNCMD" > ${COINSTARTUP}
    echo -e "[Unit]\nDescription=${COINDAEMON}\nAfter=network-online.target\n\n[Service]\nType=simple\nUser=${NODE_USER}\nGroup=${NODE_USER}\nExecStart=${COINSTARTUP}\nTimeoutStopSec=180\nExecStop=/bin/kill -2 $MAINPID\nRestart=always\nRestartSec=5\nPrivateTmp=true\nTimeoutStopSec=60s\nTimeoutStartSec=5s\nStartLimitInterval=120s\nStartLimitBurst=15\n\n[Install]\nWantedBy=multi-user.target" >${COINSERVICENAME}.service
    mv $COINSERVICENAME.service ${COINSERVICELOC} &>> ${SCRIPT_LOGFILE}
    chmod 777 ${COINSTARTUP} &>> ${SCRIPT_LOGFILE}
    systemctl --system daemon-reload &>> ${SCRIPT_LOGFILE}
    systemctl enable ${COINSERVICENAME} &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function startWallet() {
    echo
    echo -e "* Starting wallet daemon...${COINSERVICENAME}"
    service ${COINSERVICENAME} start &>> ${SCRIPT_LOGFILE}
    sleep 2
    echo -e "${GREEN}* Done${NONE}";
}
function stopWallet() {
    echo
    echo -e "* Stopping wallet daemon...${COINSERVICENAME}"
    service ${COINSERVICENAME} stop &>> ${SCRIPT_LOGFILE}
    sleep 2
    echo -e "${GREEN}* Done${NONE}";
}

function installUnattendedUpgrades() {
    echo
    echo "* Installing Unattended Upgrades..."
    apt-get install unattended-upgrades -y &>> ${SCRIPT_LOGFILE}
    sleep 3
    sh -c 'echo "Unattended-Upgrade::Allowed-Origins {" >> /etc/apt/apt.conf.d/50unattended-upgrades'
    sh -c 'echo "        '\${distro_id}:\${distro_codename}';" >> /etc/apt/apt.conf.d/50unattended-upgrades'
    sh -c 'echo "        '\${distro_id}:\${distro_codename}-security';" >> /etc/apt/apt.conf.d/50unattended-upgrades'
    sh -c 'echo "APT::Periodic::AutocleanInterval '7';" >> /etc/apt/apt.conf.d/20auto-upgrades'
    sh -c 'echo "APT::Periodic::Unattended-Upgrade '1';" >> /etc/apt/apt.conf.d/20auto-upgrades'
    cat /etc/apt/apt.conf.d/20auto-upgrades &>> ${SCRIPT_LOGFILE}
    echo -e "${GREEN}* Done${NONE}";
}

function displayServiceStatus() {
	echo
	echo
	on="${GREEN}ACTIVE${NONE}"
	off="${RED}OFFLINE${NONE}"
	if systemctl is-active --quiet ${COINSERVICENAME}; then echo -e "Service: ${on}"; else echo -e "Service: ${off}"; fi
}

clear
cd
echo && echo
echo -e "${PURPLE}**********************************************************************${NONE}"
echo -e "${PURPLE}*      This script will install and configure your full node.        *${NONE}"
echo -e "${PURPLE}**********************************************************************${NONE}"
echo -e "${BOLD}"

    check_root

echo -e "${BOLD}"

if [[ "$NET" =~ ^([mM])+$ ]]; then
    setMainVars
    setGeneralVars
    SCRIPT_LOGFILE="/tmp/${NODE_USER}_${DATE_STAMP}_output.log"
    echo -e "${BOLD} The log file can be monitored here: ${SCRIPT_LOGFILE}${NONE}"
    echo -e "${BOLD}"
    checkOSVersion
    updateAndUpgrade
    create_user
    setupSwap
    installFail2Ban
    installFirewall
    installDependencies
    compileWallet
    installWallet
    installUnattendedUpgrades
    startWallet
    set_permissions
    displayServiceStatus

echo
echo -e "${GREEN} Installation complete. Check service with: journalctl -f -u ${COINSERVICENAME} ${NONE}"
echo -e "${GREEN} thecrypt0hunter(2019)${NONE}"

 else
    if [[ "$NET" =~ ^([tT])+$ ]]; then
        setTestVars
        setGeneralVars
        SCRIPT_LOGFILE="/tmp/${NODE_USER}_${DATE_STAMP}_output.log"
        echo -e "${BOLD} The log file can be monitored here: ${SCRIPT_LOGFILE}${NONE}"
        echo -e "${BOLD}"
        checkOSVersion
        updateAndUpgrade
        create_user
        setupSwap
        installFail2Ban
        installFirewall
        installDependencies
        compileWallet
        installWallet
        installUnattendedUpgrades
        startWallet
        set_permissions
        displayServiceStatus
	
echo
echo -e "${GREEN} Installation complete. Check service with: journalctl -f -u ${COINSERVICENAME} ${NONE}"
echo -e "${GREEN} thecrypt0hunter(2019)${NONE}"
 else
    if [[ "$NET" =~ ^([uU])+$ ]]; then
        check_root
        ##TODO: Test for servicefile and only upgrade as required 
        ##TODO: Setup for testnet - test if file exists
        ##[ ! -f ${COINSERVICELOC}$COINSERVICENAME.service ] << Test for service file
        #Stop Test Service
        setTestVars
        setGeneralVars
        SCRIPT_LOGFILE="/tmp/${NODE_USER}_${DATE_STAMP}_output.log"
        stopWallet
	    updateAndUpgrade
        compileWallet
        #Stop Main Service
        setMainVars
        setGeneralVars
        SCRIPT_LOGFILE="/tmp/${NODE_USER}_${DATE_STAMP}_output.log"
        stopWallet
        compileWallet
        #Start Test Service
        setTestVars
        setGeneralVars
        startWallet
        #Start Main Service
        setMainVars
        setGeneralVars
        startWallet
        echo -e "${GREEN} thecrypt0hunter 2019${NONE}"
    else
      echo && echo -e "${RED} Installation cancelled! ${NONE}" && echo
    fi
  fi
fi
cd ~
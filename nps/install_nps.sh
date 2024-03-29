#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cur_dir=`pwd`

# Is need github private access token, 0:no, 1:yes
is_need_token="0"
private_token=""

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# Get version
get_os_version(){
    if [[ -s /etc/redhat-release ]];then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else
        grep -oE  "[0-9.]+" /etc/issue
    fi
}

# CentOS version
sys_version(){
    local code=$1
    local version="`get_os_version`"
    local main_ver=${version%%.*}
    if [ $main_ver == $code ];then
        return 0
    else
        return 1
    fi        
}

fun_randstr(){
    strNum=$1
    [ -z "${strNum}" ] && strNum="16"
    strRandomPass=""
    strRandomPass=`tr -cd '[:alnum:]' < /dev/urandom | fold -w ${strNum} | head -n1`
    echo $strRandomPass
}

# Disable selinux
disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}

# check kernel version for fast open
version_gt(){
    test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"
}
check_kernel_version(){
    local kernel_version=$(uname -r | cut -d- -f1)
    if version_gt ${kernel_version} 3.7.0; then
        return 0
    else
        return 1
    fi
}
check_kernel_headers(){
    if rpm -qa | grep -q headers-$(uname -r); then
        return 0
    else
        return 1
    fi
}

download() {
    local filename=${1}
    local cur_dir=`pwd`
    local need_token=${3}
    [ ! "$(command -v wget)" ] && yum install -y -q wget

    if [ "$need_token" == "1" ] && [ -z ${private_token} ]; then
        while true
        do
        read -p $'[\e\033[0;32mINFO\033[0m] Input Github repo Access Token please: ' access_token
        if [ -z ${access_token} ]; then
            echo -e "\033[41;37m ERROR \033[0m Access Token required!!!"
            continue
        fi
        private_token=${access_token}
        break
        done
    fi

    if [ -s ${filename} ]; then
        echo -e "[${green}INFO${plain}] ${filename} already exists."
    else
        echo -e "[${green}INFO${plain}] ${filename} downloading now, Please wait..."
        if [ "${need_token}" == "1" ]; then
            wget --header="Authorization: token ${private_token}" --no-check-certificate -cq -t3 ${2} -O ${1}
        else
            wget --no-check-certificate -cq -t3 ${2} -O ${1}
        fi
        if [ $? -eq 0 ]; then
            echo -e "[${green}INFO${plain}] ${filename} download completed..."
        else
            echo -e "\033[41;37m ERROR \033[0m Failed to download ${filename}, please download it to ${1} directory manually and try again."
            echo -e "Download link: ${2}"
            echo ""
            exit 1
        fi
    fi
}

add_firewall() {
    PORT=$1

    echo -e "[${green}INFO${plain}] Configuring firewall..."

    if sys_version 6; then
        # check iptables is installed
        iptables_installed=`rpm -qa | grep iptables | wc -l`
        if [ $iptables_installed -ne 0 ]; then
            # check port is in use
            is_port_in_use=`iptables -nL | grep "\:$PORT\b" | wc -l`
            if [ $is_port_in_use -eq 0 ]; then
                iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
                iptables -I INPUT -p udp --dport $PORT -j ACCEPT
                service iptables save > /dev/null

                # check is iptable start
                is_iptables_started=`iptables -vL | grep "\b:\b" | awk '{split($NF,a,":");print a[2]}' | wc -l`
                if [ $is_iptables_started -ne 0 ]; then
                    service iptables restart > /dev/null
                else
                    echo -e "\033[41;37m WARNING \033[0m iptables looks like shutdown, please manually set it if necessary."
                fi
            else
                echo -e "[${green}INFO${plain}] Port $PORT has been set up."
            fi
        else
            echo -e "\033[41;37m WARNING \033[0m iptables looks like not installed, please manually set it if necessary."
        fi
    elif sys_version 7; then
        firewalld_installed=`rpm -qa | grep firewalld | wc -l`
        if [ $firewalld_installed -ne 0 ]; then
            systemctl status firewalld > /dev/null 2>&1
            if [ $? -eq 0 ];then
                firewall-cmd --permanent --zone=public --add-port=$PORT/tcp -q
                firewall-cmd --permanent --zone=public --add-port=$PORT/udp -q
                firewall-cmd --reload -q
            else
                echo -e "[${green}INFO${plain}] Firewalld looks like not running, try to start..."
                systemctl start firewalld -q
                if [ $? -eq 0 ];then
                    firewall-cmd --permanent --zone=public --add-port=$PORT/tcp -q
                    firewall-cmd --permanent --zone=public --add-port=$PORT/udp -q
                    firewall-cmd --reload -q
                else
                    echo -e "\033[41;37m WARNING \033[0m Try to start firewalld failed. please manually set it if necessary."
                fi
            fi
        else
            echo -e "\033[41;37m WARNING \033[0m Firewalld looks like not installed, please manually set it if necessary."
        fi
    fi

    echo -e "[${green}INFO${plain}] Firewall setup completed..."
}

download_nps() {
    # Download file
    echo -e "[${green}INFO${plain}] Starting install latest NPS..."
    ver=$(wget --no-check-certificate -qO- https://api.github.com/repos/cnlh/nps/releases/latest | grep 'tag_name' | cut -d\" -f4)
    [ -z ${ver} ] && echo -e "\033[41;37m ERROR \033[0m Get NPS latest version failed" && exit 1
    local nps_file="linux_amd64_server.tar.gz"
    download_link="https://github.com/cnlh/nps/releases/download/${ver}/${nps_file}"
    download "${nps_file}" "${download_link}"
    echo "Unziping file..."
    tar -zxf ${nps_file}
}

configure_nps() {
    # Config startup script
    echo ""
    echo -e "[${green}INFO${plain}] Downloading NPS startup script."
    download "/etc/init.d/nps" "https://raw.githubusercontent.com/luoweihua7/vps-install/master/nps/nps.d.sh" "${is_need_token}"
    chmod 755 /etc/init.d/nps
    echo -e "[${green}INFO${plain}] Configuring startup script."
    chkconfig --add nps
    chkconfig nps on
    echo -e "[${green}INFO${plain}] Startup script setup completed."
}

configure_secret() {
    # WebUI Port
    local WEBPORT_DEFAULT=8080
    while true
    do
    echo ""
    read -p "Please input WebUI port number (Default: ${WEBPORT_DEFAULT}): " WEBPORT
    [ -z "$WEBPORT" ] && WEBPORT=$WEBPORT_DEFAULT
    expr $WEBPORT + 0 &>/dev/null
    if [ $? -eq 0 ]; then
        if [ $WEBPORT -ge 1 ] && [ $WEBPORT -le 65535 ]; then
            break
        else
            echo -e "\033[41;37m ERROR \033[0m Input error! Please input correct numbers."
        fi
    else
        echo -e "\033[41;37m ERROR \033[0m Input error! Please input correct numbers."
    fi
    done

    # Web Username
    local USERNAME_DEFAULT="admin"
    echo ""
    read -p "Please input default user (Default: $USERNAME_DEFAULT): " USERNAME
    [ -z "$USERNAME" ] && USERNAME=$USERNAME_DEFAULT

    # Web Password
    local PWD_DEFAULT=`fun_randstr`
    echo ""
    read -p "Please input default password (Default: $PWD_DEFAULT): " PWD
    [ -z "$PWD" ] && PWD=$PWD_DEFAULT

    # Auth KEY
    local AUTH_KEY_DEFAULT=`fun_randstr 8`
    echo ""
    read -p "Please input default auth key (Default: $AUTH_KEY_DEFAULT): " AUTH_KEY
    [ -z "$AUTH_KEY" ] && AUTH_KEY=$AUTH_KEY_DEFAULT

    local AUTH_CRYPT_KEY=`fun_randstr`

    # Remove default setting
    local nps_conf="/usr/local/nps/conf/nps.conf"
    sed -i -e "s/web_port/#web_port/g" ${nps_conf}
    sed -i -e "s/web_username/#web_username/g" ${nps_conf}
    sed -i -e "s/web_password/#web_password/g" ${nps_conf}
    sed -i -e "s/auth_key/#auth_key/g" ${nps_conf}
    sed -i -e "s/auth_crypt_key/#auth_crypt_key/g" ${nps_conf}
	sed -i -e "s/http_proxy_port/#http_proxy_port/g" ${nps_conf}
	sed -i -e "s/https_proxy_port/#https_proxy_port/g" ${nps_conf}

    echo "
web_port=${WEBPORT}
web_username=${USERNAME}
web_password=${PWD}
auth_key=${AUTH_KEY}
auth_crypt_key=${AUTH_CRYPT_KEY}
#http_proxy_port=8080
system_info_display=true
    " >> ${nps_conf}
}

install() {
    download_nps
    configure_nps
    configure_secret

    # startup
    service nps start
}

uninstall() {
	echo "Removing NPS service and files..."
    service nps stop
	rm -rf /usr/bin/nps
	rm -rf /etc/nps
	rm -rf /usr/local/nps
	echo "NPS service removed."
}

install_nps
#! /bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# Get version
function get_os_version(){
    if [[ -s /etc/redhat-release ]];then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else    
        grep -oE  "[0-9.]+" /etc/issue
    fi    
}

# CentOS version
function sys_version(){
    local code=$1
    local version="`get_os_version`"
    local main_ver=${version%%.*}
    if [ $main_ver == $code ];then
        return 0
    else
        return 1
    fi        
}

function get_char(){
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

function fun_randstr(){
  index=0
  strRandomPass=""
  for i in {a..z}; do arr[index]=$i; index=`expr ${index} + 1`; done
  for i in {A..Z}; do arr[index]=$i; index=`expr ${index} + 1`; done
  for i in {0..9}; do arr[index]=$i; index=`expr ${index} + 1`; done
  for i in {1..16}; do strRandomPass="$strRandomPass${arr[$RANDOM%$index]}"; done
  echo $strRandomPass
}

function random(){  
    min=$1  
    max=$(($2-$min+1))  
    num=$(($RANDOM+1000000000))  
    echo $(($num%$max+$min))  
}

function install_shadowsocks() {
	cd ~/
	echo ""
    read -p "Which version do you want to install? (Default: 2.5.3) " VERSION
    [ -z "$VERSION" ] && VERSION="2.5.3"

    yum install -y wget unzip openssl-devel gcc swig python python-devel python-setuptools autoconf libtool libevent xmlto
    yum install -y automake make curl curl-devel zlib-devel openssl-devel perl perl-devel cpio expat-devel gettext-devel asciidoc pcre-devel

    wget --no-check-certificate https://github.com/shadowsocks/shadowsocks-libev/archive/v$VERSION.zip -O shadowsocks-libev-$VERSION.zip
    unzip -o shadowsocks-libev-$VERSION.zip
    cd shadowsocks-libev-$VERSION
    ./configure
    make && make install

    # clean up
    cd ~/
    rm -rf ./shadowsocks-libev-$VERSION* > /dev/null

    echo "Shadowsocks-libev installed"
    echo ""
}

function install_kcptun() {
    wget --no-check-certificate https://github.com/clangcn/kcp-server/raw/master/install-kcp-server.sh -O ~/install-kcp-server.sh
    sh ~/install-kcp-server.sh install

    echo "Kcptun Server installed"
    echo ""
}

function install_all(){
    install_shadowsocks
    install_kcptun
    start
}

function add_service() {
    default_kcp_path="/usr/local/kcp-server/kcp-server"
    default_kcp_port=`random 10000 30000`
    default_kcp_mode="fast2"
    default_ss_path="/usr/local/bin/ss-server"
    default_ss_port=`random 30001 60000`
    default_ss_pwd=`fun_randstr`
    default_ss_encrypt="chacha20"

    # set Kcptun port
    while true
    do
    echo ""
    read -p "Please input Kcptun port (Default $default_kcp_port)[1-65535] " kcpport
    [ -z "$kcpport" ] && kcpport=$default_kcp_port
    expr $kcpport + 0 &>/dev/null
    if [ $? -eq 0 ]; then
        if [ $kcpport -ge 1 ] && [ $kcpport -le 65535 ]; then
            break
        else
            echo "Input error! Please input correct port numbers."
        fi
    else
        echo "Input error! Please input correct port numbers."
    fi
    done

    # set Kcptun fast mode
    echo ""
    echo "Please select Kcptun fast mode"
    echo "1: fast"
    echo "2: fast2"
    echo "3: fast3"
    echo "4: normal"
    read -p "Enter your choice (1, 2, 3, 4. default [2]) " kcpmode
    case "$kcpmode" in
        1|[fF][aA][sS][tT])
            kcpmode="fast"
            ;;
        2|[fF][aA][sS][tT]2)
            kcpmode="fast2"
            ;;
        3|[fF][aA][sS][tT]3)
            kcpmode="fast3"
            ;;
        4|[nN][oO][rR][mM][aA][lL])
            kcpmode="normal"
            ;;
        *)
            kcpmode=$default_kcp_mode
            ;;
    esac

    # set Shadowsocks password
    echo ""
    read -p "Please input Shadowsocks password (Default: $default_ss_pwd) " sspwd
    [ -z "$sspwd" ] && sspwd=$default_ss_pwd

    # set Shadowsocks port
    while true
    do
    echo ""
    read -p "Please input Shadowsocks port (Default: $default_ss_port) " ssport
    [ -z "$ssport" ] && ssport=$default_ss_port
    expr $ssport + 0 &>/dev/null
    if [ $? -eq 0 ]; then
        if [ $ssport -ge 1 ] && [ $ssport -le 65535 ]; then
            break
        else
            echo "Input error! Please input correct port numbers."
        fi
    else
        echo "Input error! Please input correct port numbers."
    fi
    done

    # set shadowsocks encrypt mode
    echo "Please select shadowsocks encrypt mode"
    echo "1: rc4-md5"
    echo "2: aes-128-cfb"
    echo "3: aes-256-cfb"
    echo "4: chacha20"
    echo "5: chacha20-ietf"
    read -p "Enter your choice (1, 2, 3, 4 or 5. default [4]) " ssencrypt
    case "$ssencrypt" in
        1)
            ssencrypt="rc4-md5"
            ;;
        2)
            ssencrypt="aes-128-cfb"
            ;;
        3)
            ssencrypt="aes-256-cfb"
            ;;
        4)
            ssencrypt="chacha20"
            ;;
        5)
            ssencrypt="chacha20-ietf"
            ;;
        *)
            ssencrypt=$default_ss_encrypt
            ;;
    esac

    # get local ip
    localip=`ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk 'NR==1 { print $1}'`

    echo ""
    echo "Press any key to start...or Press Ctrl+c to cancel"
    char=`get_char`

    add_firewall $kcpport

    nohup $default_kcp_path -l :$kcpport -t 127.0.0.1:$ssport --crypt none --mtu 1350 --nocomp --mode $kcpmode --dscp 46 > /dev/null 2>&1 & $default_ss_path -s 0.0.0.0 -p $ssport -k $sspwd -m $ssencrypt -u > /dev/null & 2>&1 &

    echo "nohup $default_kcp_path -l :$kcpport -t 127.0.0.1:$ssport --crypt none --mtu 1350 --nocomp --mode $kcpmode --dscp 46 > /dev/null 2>&1 & $$default_ss_path -s 0.0.0.0 -p $ssport -k $sspwd -m $ssencrypt -u > /dev/null & 2>&1 &" >> /etc/rc.local

    sleep 2

    echo ""
    echo -e "Server IP is\t\t\t\033[32m$localip\033[0m"
    echo -e "Shadowsocks Port is\t\t\033[32m$ssport\033[0m"
    echo -e "Shadowsocks Password is\t\t\033[32m$sspwd\033[0m"
    echo -e "Shadowsocks Encrypt Method is\t\033[32m$ssencrypt\033[0m"
    echo -e "Kcptun Port is\t\t\t\033[32m$kcpport\033[0m"
    echo -e "Kcptun Parameter is\t\t\033[32m--crypt none --mtu 1350 --nocomp --mode $kcpmode --dscp 46\033[0m"
    echo ""
    echo ""
}

function add_firewall() {
    PORT=$1

    echo ""
    if sys_version 6; then
        /etc/init.d/iptables status > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            iptables -L -n | grep '$PORT' | grep 'ACCEPT' > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport $PORT -j ACCEPT
                iptables -I INPUT -m state --state NEW -m udp -p udp --dport $PORT -j ACCEPT
                service iptables save
                service iptables restart
            else
                echo "Port $PORT has been set up."
            fi
        else
            echo -e "\033[41;37m WARNING \033[0m iptables looks like shutdown or not installed, please manually set it if necessary."
        fi
    elif sys_version 7; then
        systemctl status firewalld > /dev/null 2>&1
        if [ $? -eq 0 ];then
            firewall-cmd --permanent --zone=public --add-port=$PORT/tcp
            firewall-cmd --permanent --zone=public --add-port=$PORT/udp
            firewall-cmd --reload
        else
            echo "Firewalld looks like not running, try to start..."
            systemctl start firewalld
            if [ $? -eq 0 ];then
                firewall-cmd --permanent --zone=public --add-port=$PORT/tcp
                firewall-cmd --permanent --zone=public --add-port=$PORT/udp
                firewall-cmd --reload
            else
                echo -e "\033[41;37m WARNING \033[0m Try to start firewalld failed. please enable port $PORT manually if necessary."
            fi
        fi
    fi
    echo "Firewall setup completed..."
}

function start() {
	echo ""
    echo "Which do you want to? Input the number and press enter (other to exit)"
    echo "1. Install Kcptun and Shadowsocks-libev"
    echo "2. Add shadowsocks over kcptun task"
    read num

    case "$num" in
    [1] ) (install_all);;
    [2] ) (add_service);;
    *) echo "";;
    esac
}

start

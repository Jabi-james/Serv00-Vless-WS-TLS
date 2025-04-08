#!/bin/bash

re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }
export LC_ALL=C
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}
export SUB_TOKEN=${SUB_TOKEN:-${UUID:0:8}}
export DOMAIN=${DOMAIN:-''} 
export SOCKS=${SOCKS:-''}

if [[ -z "$DOMAIN" ]]; then
    if [[ "$HOSTNAME" =~ ct8 ]]; then
        CURRENT_DOMAIN="${USERNAME}.ct8.pl"
    elif [[ "$HOSTNAME" =~ useruno ]]; then
        CURRENT_DOMAIN="${USERNAME}.useruno.com"
    else
        CURRENT_DOMAIN="${USERNAME}.serv00.net"
    fi
    export CFIP="$CURRENT_DOMAIN"
else
    CURRENT_DOMAIN="$DOMAIN"
    export CFIP="ip.sb"
fi

WORKDIR="${HOME}/domains/${CURRENT_DOMAIN}/public_nodejs"
[[ ! -d "$WORKDIR" ]] && mkdir -p "$WORKDIR" && chmod 777 "$WORKDIR" >/dev/null 2>&1
bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || { red "Error: neither curl nor wget found, please install one of them." >&2; exit 1; }

check_port () {
purple "Installing, please wait...\n"
if [[ "$SOCKS" == "true" ]]; then
  port_list=$(devil port list)
  tcp_ports=$(echo "$port_list" | grep -c "tcp")
  udp_ports=$(echo "$port_list" | grep -c "udp")

  if [[ $tcp_ports -lt 1 ]]; then
      red "No TCP port available, adjusting..."

      if [[ $udp_ports -ge 3 ]]; then
          udp_port_to_delete=$(echo "$port_list" | awk '/udp/ {print $1}' | head -n 1)
          devil port del udp $udp_port_to_delete
          green "Deleted udp port: $udp_port_to_delete"
      fi

      while true; do
          tcp_port=$(shuf -i 10000-65535 -n 1)
          result=$(devil port add tcp $tcp_port 2>&1)
          if [[ $result == *"Ok"* ]]; then
              green "TCP port added: $tcp_port"
              tcp_port1=$tcp_port
              break
          else
              yellow "Port $tcp_port is not available, try another port..."
          fi
      done

      green "The port has been adjusted, The SSH connection will be disconnected, Please reconnect SSH and re-execute the script"
      devil binexec on >/dev/null 2>&1
      kill -9 $(ps -o ppid= -p $$) >/dev/null 2>&1
  else
      tcp_ports=$(echo "$port_list" | awk '/tcp/ {print $1}')
      tcp_port1=$(echo "$tcp_ports" | sed -n '1p')
  fi
  export S5_PORT=$tcp_port1
  purple "TCP port used by socks5: $tcp_port1\n"
else
    yellow "Socks5 is not currently enabled\n"
fi
}

check_website() {
CURRENT_SITE=$(devil www list | awk -v domain="${CURRENT_DOMAIN}" '$1 == domain && $2 == "nodejs"')
if [ -n "$CURRENT_SITE" ]; then
    green "The node site of ${CURRENT_DOMAIN} already exists and does not need to be modified\n"
else
    EXIST_SITE=$(devil www list | awk -v domain="${CURRENT_DOMAIN}" '$1 == domain')
    
    if [ -n "$EXIST_SITE" ]; then
        devil www del "${CURRENT_DOMAIN}" >/dev/null 2>&1
        devil www add "${CURRENT_DOMAIN}" nodejs /usr/local/bin/node18 > /dev/null 2>&1
        green "The old site was deleted and a new one created${CURRENT_DOMAIN} nodejs site\n"
    else
        devil www add "${CURRENT_DOMAIN}" nodejs /usr/local/bin/node18 > /dev/null 2>&1
        green "Created ${CURRENT_DOMAIN} nodejs site\n"
    fi
fi
}

apply_configure() {
    APP_URL="https://00.ssss.nyc.mn/wss.js"
    $COMMAND "${WORKDIR}/app.js" "$APP_URL"
    cat > ${WORKDIR}/.env <<EOF
UUID=${UUID}
CFIP=${CFIP}
DOMAIN=${DOMAIN}
SUB_TOKEN=${SUB_TOKEN}
SOCKS=${SOCKS}
S5_PORT=${S5_PORT}
EOF
    ln -fs /usr/local/bin/node18 ~/bin/node > /dev/null 2>&1
    ln -fs /usr/local/bin/npm18 ~/bin/npm > /dev/null 2>&1
    mkdir -p ~/.npm-global
    npm config set prefix '~/.npm-global'
    echo 'export PATH=~/.npm-global/bin:~/bin:$PATH' >> $HOME/.bash_profile && source $HOME/.bash_profile
    rm -rf $HOME/.npmrc > /dev/null 2>&1
    cd ${WORKDIR} && npm install dotenv ws socksv5 --silent > /dev/null 2>&1
    devil www restart ${CURRENT_DOMAIN} > /dev/null 2>&1
}


get_links(){
IP=$(devil vhost list | awk '$2 ~ /web/ {print $1}')
ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26}' | sed -e 's/ /_/g' || echo "0")
get_name() { if [ "$HOSTNAME" = "s1.ct8.pl" ]; then SERVER="CT8"; else SERVER=$(echo "$HOSTNAME" | cut -d '.' -f 1); fi; echo "$SERVER"; }
NAME="$ISP-$(get_name)"
     
URL="vless://${UUID}@${CFIP}:443?encryption=none&security=tls&sni=${CURRENT_DOMAIN}&fp=chrome&allowInsecure=1&type=ws&host=${CURRENT_DOMAIN}&path=%2F${USERNAME}-ed%3D2560#${NAME}-${USERNAME}"

[[ "$SOCKS" == "true" ]] && yellow "\nsocks://${USERNAME}:${USERNAME}@${IP}:${S5_PORT}#${NAME}\n\nTG代理:    https://t.me/socks?server=${IP}&port=${S5_PORT}&user=${USERNAME}&pass=${USERNAME}\n\n只可作为proxyip或tg代理使用,其他软件测试不通！！!\n"

green "\n\n$URL\n\n"
green "Node subscription link (base64): https://${CURRENT_DOMAIN}/${SUB_TOKEN}   (Applicable to v2rayN, nekobox, small rocket, karing, loon, etc.)\n"

worker_scrpit="
export default {
    async fetch(request, env) {
        let url = new URL(request.url);
        if (url.pathname.startsWith('/')) {
            var arrStr = [
                '${CURRENT_DOMAIN}',
            ];
            url.protocol = 'https:';
            url.hostname = getRandomArray(arrStr);
            let new_request = new Request(url, request);
            return fetch(new_request);
        }
        return env.ASSETS.fetch(request);
    },
};
function getRandomArray(array) {
    const randomIndex = Math.floor(Math.random() * array.length);
    return array[randomIndex];
}"

if [[ -z "$DOMAIN" ]]; then
    purple "If you want the node to use the preferred IP, please create a worker in cloudflared, copy the following code to deploy and bind the domain name, and then change the host and sni in the node to the bound domain name to change the preferred domain name or preferred IP."
    green "\ncloudflared The workers code is as follows: \n"
    echo "$worker_scrpit" | sed 's/^/    /' | sed 's/^ *$//'
else
    purple "请将 ${yellow}${CURRENT_DOMAIN} ${purple}Add an A record to the domain name in cloudflare ${yellow}${IP} ${purple}And open Link to use the node, you can change the preferred domain name or preferred IP${re}\n\n"
fi

yellow "\nServ00|ct8 Laowang vless-ws-tls|socks5 one-click installation script\n"
echo -e "${green}Feedback Forum：${re}${yellow}https://bbs.vps8.me${re}\n"
green "Running done!\n"

}

install() {
    clear
    check_port
    check_website
    apply_configure
    get_links
}
install

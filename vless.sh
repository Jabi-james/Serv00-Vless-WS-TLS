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
purple "正在安装中,请稍等...\n"
if [[ "$SOCKS" == "true" ]]; then
  port_list=$(devil port list)
  tcp_ports=$(echo "$port_list" | grep -c "tcp")
  udp_ports=$(echo "$port_list" | grep -c "udp")

  if [[ $tcp_ports -lt 1 ]]; then
      red "没有可用的TCP端口,正在调整..."

      if [[ $udp_ports -ge 3 ]]; then
          udp_port_to_delete=$(echo "$port_list" | awk '/udp/ {print $1}' | head -n 1)
          devil port del udp $udp_port_to_delete
          green "已删除udp端口: $udp_port_to_delete"
      fi

      while true; do
          tcp_port=$(shuf -i 10000-65535 -n 1)
          result=$(devil port add tcp $tcp_port 2>&1)
          if [[ $result == *"Ok"* ]]; then
              green "已添加TCP端口: $tcp_port"
              tcp_port1=$tcp_port
              break
          else
              yellow "端口 $tcp_port 不可用，尝试其他端口..."
          fi
      done

      green "端口已调整完成, 将断开SSH连接, 请重新连接SSH并重新执行脚本"
      devil binexec on >/dev/null 2>&1
      kill -9 $(ps -o ppid= -p $$) >/dev/null 2>&1
  else
      tcp_ports=$(echo "$port_list" | awk '/tcp/ {print $1}')
      tcp_port1=$(echo "$tcp_ports" | sed -n '1p')
  fi
  export S5_PORT=$tcp_port1
  purple "socks5使用的tcp端口: $tcp_port1\n"
else
    yellow "当前未开启socks5\n"
fi
}

check_website() {
CURRENT_SITE=$(devil www list | awk -v domain="${CURRENT_DOMAIN}" '$1 == domain && $2 == "nodejs"')
if [ -n "$CURRENT_SITE" ]; then
    green "已存在 ${CURRENT_DOMAIN} 的node站点,无需修改\n"
else
    EXIST_SITE=$(devil www list | awk -v domain="${CURRENT_DOMAIN}" '$1 == domain')
    
    if [ -n "$EXIST_SITE" ]; then
        devil www del "${CURRENT_DOMAIN}" >/dev/null 2>&1
        devil www add "${CURRENT_DOMAIN}" nodejs /usr/local/bin/node18 > /dev/null 2>&1
        green "已删除旧的站点并创建新的${CURRENT_DOMAIN} nodejs站点\n"
    else
        devil www add "${CURRENT_DOMAIN}" nodejs /usr/local/bin/node18 > /dev/null 2>&1
        green "已创建 ${CURRENT_DOMAIN} nodejs站点\n"
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
green "节点订阅链接(base64): https://${CURRENT_DOMAIN}/${SUB_TOKEN}   (适用于v2rayN,nekobox,小火箭,karing,loon等)\n"

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
    purple "如果想要节点使用优选ip,请在cloudflared创建一个workers,复制以下代码部署并绑定域名,然后将节点里的host和sni改为绑定的域名即可换优选域名或优选ip"
    green "\ncloudflared workers代码如下: \n"
    echo "$worker_scrpit" | sed 's/^/    /' | sed 's/^ *$//'
else
    purple "请将 ${yellow}${CURRENT_DOMAIN} ${purple}域名在cloudflare添加A记录指向 ${yellow}${IP} ${purple}并开启小黄云,才可使用节点,可更换优选域名或优选ip${re}\n\n"
fi

yellow "\nServ00|ct8老王vless-ws-tls|socks5一键安装脚本\n"
echo -e "${green}反馈论坛：${re}${yellow}https://bbs.vps8.me${re}\n"
echo -e "${green}TG反馈群组：${re}${yellow}https://t.me/vps888${re}\n"
purple "转载请著名出处，请勿滥用\n"
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

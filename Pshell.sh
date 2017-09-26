#! /bin/bash
#####################################################################################
# 版本（请不要随便修改）
VERSION="5.0"
#####################################################################################
# 设置守护容器的镜像
DOCKER_IMAGE="zuolan/pshell:local"
#####################################################################################
# 当 IP 为 127.0.0.1 时只允许本地访问，通过 -d 参数指定网卡可以分享给特定网络。
# 修改后可允许其他电脑使用你的 Socks5 代理（或者直接改为 0.0.0.0，允许所有人访问）。
IP=127.0.0.1
# 设置虚拟网卡的 IP 地址，如果服务端容器启动时没有指定 VIP_GATE 参数，则 VIP 保留默认即可。
VIP=10.1.2.1
#####################################################################################
# 代理列表文件名（不建议修改）
LIST_FILE="proxy.list"
# 设置代理列表各项的分隔符（不建议修改）
FILE_SEPARATOR=":"
# 设置绝对路径以保证 alias 能够读取到配置文件（不建议修改）
LIST_PATH="$(
cd $(dirname $0)
pwd
)/$LIST_FILE"
# 设置代理列表各项的含义（不建议修改）
VAR="NODE_NAME CONTAINER_NAME CONTAINER_PORT SOCKS_PORT SERVER_IP PASSWORD ID_RSA"
#####################################################################################
# Proxychains4 配置路径，脚本根据这个路径自动生成代理配置（不建议修改）
PROXY_CHAINS_CONFIG_PATH="$(
	cd $(dirname $0)
	pwd
)/config"
# 设置 Privoxy 配置路径（这个是系统默认的路径，一般不用修改）
PRIVOXY_CONFIGFILE="/etc/privoxy/config"
#####################################################################################
# 懒得打分割线
separator="---------------------------------------------------------------"
# Autossh 全局变量
AUTOSSH_PIDFILE=/tmp/autossh.pid
AUTOSSH_POLL=5
AUTOSSH_FIRST_POLL=2
AUTOSSH_GATETIME=0
AUTOSSH_DEBUG=1
#####################################################################################

# 安装软件
install_base() {
	software_deps="git make privoxy libpcap-dev gcc sudo autossh"
	if command -v apt >/dev/null 2>&1; then
		sudo apt install -y $software_deps
		separator
		echo "  软件依赖已经安装完成。"
		separator
	elif command -v yum >/dev/null 2>&1; then
		sudo yum install -y $software_deps
		separator
		echo "  软件依赖已经安装完成。"
		separator
	else
		separator
		echo "  没有找到合适的包管理工具，请手动安装 git make privoxy libpcap-dev 等依赖。"
		separator
	fi
}
install_proxychains4() {
	echo "  正在拉取并编译安装 Proxychains4 ...."
	separator
	git clone https://github.com/rofl0r/proxychains-ng.git /tmp/proxychains-ng/
	cd /tmp/proxychains-ng/
	sudo ./configure –prefix=/usr –sysconfdir=/etc
	sudo make && sudo make install && sudo make install-config
}
install_docker() {
	command -v docker >/dev/null 2>&1
	if [ $? != 0 ]; then curl -sSL https://get.docker.com/ | sh; fi
	command -v systemctl >/dev/null 2>&1
	if [ $? = 0 ]; then
		DOCKER_STATUS=$(systemctl status docker | grep "Active:" | cut -d'(' -f2 | cut -d')' -f1)
		if [ "$DOCKER_STATUS" != "running" ]; then systemctl restart docker; fi
	else
		DOCKER_STATUS=$(service docker status | cut -d'/' -f2 | cut -d',' -f1)
		if [ "$DOCKER_STATUS" != "running" ]; then service docker restart; fi
	fi
	groups $USER | grep "docker" >/dev/null 2>&1
	if [ $? = 0 -o "$USER" = "root" ]; then
		echo "  Docker 初始化完成。"
	else
		sudo usermod -aG docker $USER
		echo "  Docker初始化完成，需要注销之后才能生效，请手动注销之后再执行一次本脚本。"
	fi
}

# 服务器安装并运行 Pshell
server_daemon() {
	if [ $(id -u) -eq 0 ]; then echo "  开始安装 Pshell 服务端。"; else
		echo "  请使用 Root 用户执行本脚本。"
		exit 1
	fi
	install_docker
	# if [ -n "$PASSWORD" ]; then break; fi
	while true; do
		echo -n "  输入 Pshell 密码："
		read -s FIRST_PASSWORD
		echo ""
		echo -n "  再输入一次 Pshell 密码："
		read -s SECOND_PASSWORD
		echo ""
		if [ "$FIRST_PASSWORD" = "$SECOND_PASSWORD" ]; then
			PASSWORD=$FIRST_PASSWORD
			break
		else echo "  两次密码不相同。"; fi
	done
	docker ps -a | grep "pshell_server" >/dev/null 2>&1
	if [ $? = 0 ]; then docker rm -f pshell_server; fi
	docker run -dit --name=pshell_server \
		--network=host --privileged \
		-e PASSWORD=$PASSWORD \
		--restart=always zuolan/pshell:server
	echo "  Pshell 已经启动。"
	separator
}

# 本地运行守护容器
local_daemon() {
	command -v git make curl gcc sudo privoxy >/dev/null 2>&1
	if [ $? != 0 ]; then install_base; fi
	install_docker
	command -v proxychains4 >/dev/null 2>&1
	if [ $? != 0 ]; then install_proxychains4; fi
	separator
	echo "  正在启动守护容器，原有同名容器会被强制删除。"
	separator
	while IFS=$FILE_SEPARATOR read $VAR; do
		docker kill $CONTAINER_NAME >/dev/null 2>&1 && docker rm -f $CONTAINER_NAME >/dev/null 2>&1
		echo "  $CONTAINER_NAME 容器已经删除。"
		docker run -dit --name=$CONTAINER_NAME \
			--network=host --privileged --cpus=".05" \
			-e IP="$SERVER_IP" \
			-e MIDDLE_PORT=$CONTAINER_PORT \
			-e PASSWORD=$PASSWORD \
			-p 127.0.0.1:$CONTAINER_PORT:$CONTAINER_PORT \
			--restart=always $DOCKER_IMAGE
		echo "  $CONTAINER_NAME 容器已经启动。"
		cp -f $PROXY_CHAINS_CONFIG_PATH/default.conf $PROXY_CHAINS_CONFIG_PATH/$CONTAINER_NAME.conf
		sed -i '$d' $PROXY_CHAINS_CONFIG_PATH/$CONTAINER_NAME.conf
		bash -c "echo 'socks5 $IP $SOCKS_PORT' >> $PROXY_CHAINS_CONFIG_PATH/$CONTAINER_NAME.conf"
		echo "  Proxychains4 配置已经设置完成。"
		separator
		# 清除旧的容器
		NOW_CONTAINER_LIST=$(eval docker ps -a -f 'ancestor=$DOCKER_IMAGE' | grep "$DOCKER_IMAGE" | awk '{print $NF}')
		while read NOW_CONTAINER_NAME; do
			cat $LIST_PATH | grep "$NOW_CONTAINER_NAME" >/dev/null 2>&1
			if [ $? != 0 ]; then docker rm -f $NOW_CONTAINER_NAME >/dev/null 2>&1; fi
		done <<EOF
$NOW_CONTAINER_LIST
EOF
	done <$LIST_PATH
}

# 分割线
separator() {
	echo "$separator"
}

# 帮助函数
help() {
	cat <<EOF
------------------------------------------------------------------------------
   ___ ____ __  __ ____   _____ ____    ____  _          _ _ 
  |_ _/ ___|  \/  |  _ \ / /_ _|  _ \  / ___|| |__   ___| | |
   | | |   | |\/| | |_) / / | || |_) | \___ \| '_ \ / _ \ | |
   | | |___| |  | |  __/ /  | ||  __/   ___) | | | |  __/ | |
  |___\____|_|  |_|_| /_/  |___|_|     |____/|_| |_|\___|_|_|
  Email: i@zuolan.me                 Blog: https://zuolan.me
  一个隧道部署与代理管理的脚本。不加参数直接运行脚本即可连接。
------------------------------------------------------------------------------
  可选参数         -  说明
------------------------------------------------------------------------------
  -d (driver)    -  指定网卡（enp3s0|wlp2s0|eth0|wlan0），默认全部。
  -e (edit)      -  编辑配置列表。
  -f (fast)      -  快速模式（切换为 IP 协议隧道，速度更快，安全性降低）。
  -h (help)      -  显示帮助信息。更详细说明请阅读 README 文件。
  -k (kill)      -  杀死 autossh 和 sshd 进程（当连接长时间中断时使用）。
  -l (local)     -  安装本地守护容器。
  -m (monitor)   -  查看代理与容器运行的情况。
  -n (net)       -  统计代理端口的流量（-n set/unset 开启/重置流量统计）。
  -p (port)      -  选择本地 HTTP 代理端口（默认配置/etc/privoxy/config）。
  -s (server)    -  安装服务器守护进程。
  -u (update)    -  检测版本以及更新脚本。
------------------------------------------------------------------------------
EOF
}

# 脚本更新
update() {
	NEW_VERSION=$(curl -s https://raw.githubusercontent.com/izuolan/Pshell/master/VERSION | head -n1)
	if [ "$VERSION" = "$NEW_VERSION" ]; then
		echo "当前脚本已经是最新版本。"
	else
		echo -n "脚本有新版本，是否更新？（回车更新，按 Ctrl-C 取消。）"
		read -s CONFIRM
		curl -s https://raw.githubusercontent.com/izuolan/Pshell/master/Pshell.sh >$(
		cd $(dirname $0)
		pwd
		)/Pshell.sh
		echo "脚本更新完成。"
	fi
}

# ICMP 模式的自动重连
auto_connect() {
    while IFS=$FILE_SEPARATOR read $VAR; do
		# ssh 反应速度有限，根据硬盘速度适当调整下面的值，以免出现“进程不存在”的提示。
		sleep 0.2
		nohup autossh -M 0 -4 -ND $IP:$SOCKS_PORT -p $CONTAINER_PORT \
            -o ServerAliveInterval=5 \
            -o ServerAliveCountMax=2 \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -i $ID_RSA root@localhost >/dev/null 2>&1 &
    done <$LIST_PATH
}
fix_auto_connect() {
	pkill -9 /usr/lib/autossh/autossh >/dev/null 2>&1
	killall -9 /usr/bin/ssh >/dev/null 2>&1
	auto_connect
}

# IP 模式的自动重连
fast_auto_connect() {
    while IFS=$FILE_SEPARATOR read $VAR; do
		# ssh 反应速度有限，根据硬盘速度适当调整下面的值，以免出现“进程不存在”的提示。
		sleep 0.2
		nohup autossh -M 0 -4 -ND $IP:$SOCKS_PORT \
            -o ServerAliveInterval=5 \
            -o ServerAliveCountMax=2 \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -i $ID_RSA root@$VIP >/dev/null 2>&1 &
    done <$LIST_PATH
}
fast_fix_auto_connect() {
	pkill -9 /usr/lib/autossh/autossh >/dev/null 2>&1
	killall -9 /usr/bin/ssh >/dev/null 2>&1
	fast_auto_connect
}

# 断开连接
disconnect() {
	while IFS=$FILE_SEPARATOR read $VAR; do
		get_connect_pid
		kill $connect_pid >/dev/null 2>&1
	done <$LIST_PATH
}

# 获取ssh的pid
get_connect_pid() {
	connect_pid=$(ps -A ssh | grep "/ssh" | grep $SOCKS_PORT | awk '{print $2}')
	if [ ! -n "$connect_pid" ]; then connect_pid="进程不存在"; fi
}

# 状态查看函数
monitor() {
	# sleep 0.5
	separator
	echo -e "  节点  \t-  代理端口  \t-  容器状态  \t-  PID"
	separator
	while IFS=$FILE_SEPARATOR read $VAR; do
		get_connect_pid
		container_status=$(docker inspect --format='{{.State.Status}}' $CONTAINER_NAME 2>&1)
		# if [ "$container_status" = "running" ]; then container_status="OK"; else container_status="ERROR"; fi
		echo -e "  $NODE_NAME  \t-  $SOCKS_PORT  \t-  $container_status  \t-  $connect_pid"
	done <$LIST_PATH
	separator
	NOW_PORT=$(cat $PRIVOXY_CONFIGFILE | tail -n 20 | grep "forward-socks5t" | awk '{print $3}' | cut -d: -f2)
	PROXY_IP=$(ps -p $connect_pid -o args 2>&1 | grep "ssh" | cut -d: -f1 | awk '{print $4}')
	echo "  socks5->http: $NOW_PORT->8118 | Socks5 Proxy IP: $PROXY_IP"
	separator
	CONNECT_ADDR=$(ps -p $connect_pid -o args 2>&1 | grep ssh | awk '{print $NF}' | cut -d@ -f2)
	if [ "$CONNECT_ADDR" = "$VIP" ]; then
		echo "  当前为 IP 模式，速度不限制，请注意 DDoS 警报。"
	elif [ "$CONNECT_ADDR" = "localhost" ]; then
		echo "  当前为 ICMP 模式，使用 -f 选项可切换到“快速模式”。"
	else
		echo "  网络错误，请重新建立连接。"
	fi
	separator
}

# 流量统计
net_montior() {
	if [ "$NET" = "set" ]; then
		set_net_montior
		echo "端口流量统计已开启。现在可以使用 -n 或者 -m 选项查看流量统计。"
		exit 0
	elif [ "$NET" = "unset" ]; then
		unset_net_montior
		echo "端口流量统计已关闭并清零。使用 -n set 可以再次开启流量统计。"
		exit 0
	else
		check_net_montior
	fi
	separator
	echo -e "  节点  \t-  CPU  \t-  下载  \t-  上传"
	separator
	container_list=$(cut -d: -f 2 $LIST_PATH | xargs)
	# docker stats --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.NetIO}}' --no-stream $container_list \
	container_cpu=$(docker stats --format '{{.Name}}:{{.CPUPerc}}' --no-stream $container_list \
		| grep '[a-z]' \
		| awk '{print $1,$2,$3,$5}' \
		| tr ' ' '\t' \
		| sed 's/%\t/%\t\t/g' \
		| sed 's/^/  /g')
	while IFS=$FILE_SEPARATOR read CONTAINER_NAME CPU; do
		c_name=$(echo $CONTAINER_NAME | sed 's|^[ \t]*||g')
		cpu=$(echo $CPU | sed 's|^[ \t]*||g')
		eval "$c_name"_"cpu"=$cpu
		# eval eval echo '$c_name: "$"{"$c_name"_"cpu"}'
		# eval echo '$'{"$c_name"_"cpu"}
	done <<EOF
$container_cpu
EOF
	while IFS=$FILE_SEPARATOR read $VAR; do
		input_bytes=$(sudo iptables -L -v -n -x | grep "dpt:$SOCKS_PORT" | awk '{print $2}')
		output_bytes=$(sudo iptables -L -v -n -x | grep "spt:$SOCKS_PORT" | awk '{print $2}')
		INPUT=$((input_bytes/1048576))
		OUTPUT=$((output_bytes/1048576))
		eval CPU="$"{"$CONTAINER_NAME"_"cpu"}
		echo -e "  $NODE_NAME  \t-  $CPU  \t-  $OUTPUT MB  \t-  $INPUT MB"
	done <$LIST_PATH
	separator
}
set_net_montior() {
	unset_net_montior
	while IFS=$FILE_SEPARATOR read $VAR; do
		sudo iptables -A INPUT -p tcp --dport $SOCKS_PORT
		sudo iptables -A OUTPUT -p tcp --sport $SOCKS_PORT
	done <$LIST_PATH
}
unset_net_montior() {
	while IFS=$FILE_SEPARATOR read $VAR; do
		sudo iptables -D INPUT -p tcp --dport $SOCKS_PORT >/dev/null 2>&1
		sudo iptables -D OUTPUT -p tcp --sport $SOCKS_PORT >/dev/null 2>&1
	done <$LIST_PATH
}
check_net_montior() {
	while IFS=$FILE_SEPARATOR read $VAR; do
		sudo iptables -C INPUT -p tcp --dport $SOCKS_PORT >/dev/null 2>&1
		if [ "$?" = "1" ]; then INPUT_STAT=1; fi
		sudo iptables -C OUTPUT -p tcp --sport $SOCKS_PORT >/dev/null 2>&1
		if [ "$?" = "1" ]; then OUTPUT_STAT=1; fi
		if [ "$INPUT_STAT" = "1" -o "$OUTPUT_STAT" = "1" ]; then
			echo "  流量统计没有开启。使用 -n set/unset 可以开启/重置流量统计。"
			exit 0
		fi
	done <$LIST_PATH
}

# 设置网卡
driver() {
	IP=$(ip -o -4 addr list $DRIVER | awk '{print $4}' | cut -d/ -f1)
}

# 设置socks5转发端口
socks_to_http() {
	grep "CONFIGFILE=$PRIVOXY_CONFIGFILE" /etc/init.d/privoxy >/dev/null 2>&1 &
	if [ "$?" = "1" ]; then
		sudo sed -i "s:CONFIGFILE=/etc/privoxy/config:CONFIGFILE=$PRIVOXY_CONFIGFILE:g" /etc/init.d/privoxy
	fi
	sudo bash -c "/etc/init.d/privoxy restart" >/dev/null 2>&1 &
	if [ "$?" = "1" ]; then echo "  Privoxy 重启失败，请手动重启。"; else echo "  Privoxy 重启完成。"; fi
	cat $PRIVOXY_CONFIGFILE | tail -n 20 | grep "forward-socks5t" >/dev/null 2>&1
	if [ "$?" = "1" ]; then
		# sudo bash -c "echo 'listen-address  $IP:8118' >> $PRIVOXY_CONFIGFILE"
		sudo bash -c "echo 'forward-socks5t / $IP:$NEW_PORT .' >> $PRIVOXY_CONFIGFILE"
	else
		NOW_URI=$(cat $PRIVOXY_CONFIGFILE | tail -n 20 | grep "forward-socks5t" | awk '{print $3}')
		let line_end=$(wc -l $PRIVOXY_CONFIGFILE | awk '{print $1}')
		let line_start=$line_end-20
		sudo sed -i "$line_start,$line_end s/$NOW_URI/$IP:$NEW_PORT/g" $PRIVOXY_CONFIGFILE
	fi
	separator
	echo "  转发端口设置成功（HTTP 代理为 localhost:8118）！"
}

# 关闭所有代理隧道
kill_all() {
	disconnect
	pkill -9 /usr/lib/autossh/autossh >/dev/null 2>&1
	pkill -9 /usr/bin/ssh >/dev/null 2>&1
	sudo killall sshd >/dev/null 2>&1
	echo "全部代理已重置，代理隧道进程已终止，请手动重新建立代理连接。"
}

# 编辑配置文件
edit_config() {
	$EDITOR $LIST_PATH
	echo "如配置文件改变，请重新执行 --local 部署。"
}

while [ -n "$1" ]; do
	case "$1" in
		-d | --driver)
			DRIVER=$2
			driver
			shift
			;;
		-e | --edit)
			edit_config
			exit 0
			;;
		-f | --fast)
			fast_fix_auto_connect
			monitor
			exit 0
			;;
		-h | --help)
			help
			exit 0
			;;
		-k | --kill)
			kill_all
			exit 0
			;;
		-l | --local)
			local_daemon
			;;
		-m | --monitor)
			monitor
			net_montior
			exit 0
			;;
		-n | --net)
			NET=$2
			net_montior
			exit 0
			;;
		-p | --port)
			NEW_PORT=$2
			socks_to_http
			shift
			;;
		-s | --server)
			server_daemon
			exit 0
			;;
		-u | --update)
			update
			exit 0
			;;
		*)
			echo "  参数错误，请阅读帮助文档："
			$0 -h
			exit 1
			;;
	esac
	shift
done

if [ ! -f $LIST_PATH ]; then touch "$LIST_PATH"; fi

main() {
	disconnect
	fix_auto_connect
	monitor
}

main
exit 0
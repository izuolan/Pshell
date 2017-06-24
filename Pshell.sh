#! /bin/bash
########################################################################
# 设置守护容器的镜像
DOCKER_IMAGE="zuolan/ptunnel:local"

# 设置文件分隔符
FILE_SEPARATOR=":"

# 设置socks5转http配置文件的路径，默认情况下不用修改。
# 当IP为127.0.0.1时只允许本地访问，可以通过 -n 参数指定网卡，修改后可允许其他电脑使用你的Socks5代理（或者直接使用0.0.0.0，允许所有人访问）。
IP=0.0.0.0

# Proxy列表定义
LIST_FILE="proxy.list"
# 为alias设置绝对路径。
LIST_PATH="$(
cd $(dirname $0)
pwd
)/$LIST_FILE"

# Proxychains4 配置路径
PROXY_CHAINS_CONFIG_PATH="$(
	cd $(dirname $0)
	pwd
)/config"
# 设置 Privoxy 配置路径
PRIVOXY_CONFIGFILE="/etc/privoxy/config"

# 设置服务端的日志文件
PTUNNEL_LOG="ptunnel.log"

# 懒得打分割线
separator="-------------------------------------------------------------"

# 设置超时时间（单位为秒）
TIME_OUT=2

# 测试连通站点
TEST_SITE="baidu.com"
TEST_SITE_SIZE_HEADER="335"

########################################################################

# 安装软件
install_base() {
	software_deps="git make privoxy libpcap-dev gcc sudo autossh"
	command -v apt >/dev/null 2>&1
	if [ $? = 0 ]; then
		sudo apt install -y $software_deps
		separator
		echo "  软件依赖已经安装完成。"
		separator
	else
		command -v yum >/dev/null 2>&1
		if [ $? = 0 ]; then
			sudo yum install -y $software_deps
			separator
			echo "  软件依赖已经安装完成。"
			separator
		else
			separator
			echo "  没有找到合适的包管理工具，请手动安装 git make privoxy libpcap-dev 等依赖。"
			separator
		fi
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

# 服务器安装并运行 Ptunnel
server_daemon() {
	if [ $(id -u) -eq 0 ]; then echo "  开始安装 Ptunnel 服务端。"; else
		echo "  请使用 Root 用户执行本脚本。"
		exit 1
	fi
	install_docker
	# if [ -n "$PASSWORD" ]; then break; fi
	while true; do
		echo -n "  输入 Ptunnel 密码："
		read -s FIRST_PASSWORD
		echo ""
		echo -n "  再输入一次 Ptunnel 密码："
		read -s SECOND_PASSWORD
		echo ""
		if [ "$FIRST_PASSWORD" = "$SECOND_PASSWORD" ]; then
			PASSWORD=$FIRST_PASSWORD
			break
		else echo "  两次密码不相同。"; fi
	done
	docker ps -a | grep "ptunnel_server" >/dev/null 2>&1
	if [ $? = 0 ]; then docker rm -f ptunnel_server; fi
	docker run -dit --name=ptunnel_server --net=host -e PASSWORD=$PASSWORD --restart=always zuolan/ptunnel:server
	echo "  Ptunnel 已经启动。"
	separator
	exit 0
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
	while IFS=: read NODE_NAME CONTAINER_NAME CONTAINER_PORT SOCKS_PORT SERVER_IP PASSWORD ID_RSA; do
		docker kill $CONTAINER_NAME >/dev/null 2>&1 && docker rm -f $CONTAINER_NAME >/dev/null 2>&1
		echo "  $CONTAINER_NAME 容器已经删除。"
		docker run -dit --name=$CONTAINER_NAME --cpus=".05" -e IP="$SERVER_IP" -e MIDDLE_PORT=$CONTAINER_PORT -e PASSWORD=$PASSWORD -p 127.0.0.1:$CONTAINER_PORT:$CONTAINER_PORT --restart=always $DOCKER_IMAGE
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
   ____  _                          _   ____  _          _ _ 
  |  _ \| |_ _   _ _ __  _ __   ___| | / ___|| |__   ___| | |
  | |_) | __| | | | '_ \| '_ \ / _ \ | \___ \| '_ \ / _ \ | |
  |  __/| |_| |_| | | | | | | |  __/ |  ___) | | | |  __/ | |
  |_|    \__|\__,_|_| |_|_| |_|\___|_| |____/|_| |_|\___|_|_|
  Email: i@zuolan.me                  Blog: https://zuolan.me
------------------------------------------------------------------------------
  一个关于 Ptunnel 部署以及代理管理的脚本。不加参数直接运行脚本即可连接。
  可选参数   -  说明
------------------------------------------------------------------------------
  -c (--connect)   -  直接连接模式（默认为自动重连模式）。
  -m (--monitor)   -  查看代理运行情况。
  -d (--driver)    -  使用 -d [enp3s0|wlp2s0|eth0|wlan0] 指定网卡(默认全部)。
  -p (--port)      -  选择本地 HTTP 代理端口（默认配置/etc/privoxy/config）。
  -k (--kill)      -  重启 autossh 和 sshd 进程（当连接长时间终端时使用）。
  -l (--local)     -  安装本地守护容器。
  -s (--server)    -  安装服务器守护进程。
  -u (--update)    -  检测版本以及更新脚本。
  -e (--edit)      -  编辑配置列表。
  -h (--help)      -  显示帮助信息。详细说明阅读 README 文件。
EOF
	exit 0
}

# 脚本更新
update() {
	NEW_VERSION=$(curl -s https://raw.githubusercontent.com/izuolan/Pshell/master/VERSION | head -n1)
	if [ "$VERSION" = "$NEW_VERSION" ]; then
		echo "当前脚本已经是最新版本。"
	else
		echo -n "脚本有新版本，是否更新？[Y/n]"
		read -s CONFIRM
		if [ "$CONFIRM" = "y" || "$CONFIRM" = "Y" ]; then
			curl -s https://raw.githubusercontent.com/izuolan/Pshell/master/Pshell.sh >$(
				cd $(dirname $0)
				pwd
			)/Pshell.sh
			echo "脚本更新完成。"
		else
			echo "脚本暂时不更新。"
		fi
	fi
}

# 连接函数
connect() {
	# cat $HOME/.ssh/ssh_config | tail -n 1 | grep "StrictHostKeyChecking no" >/dev/null 2>&1
	# if [ "$?" = "1" ]; then echo "StrictHostKeyChecking no" >>$HOME/.ssh/ssh_config; fi
	while IFS=: read NODE_NAME CONTAINER_NAME CONTAINER_PORT SOCKS_PORT SERVER_IP PASSWORD ID_RSA; do
		nohup ssh -p $CONTAINER_PORT -ND $IP:$SOCKS_PORT \
			-o StrictHostKeyChecking=no \
			-o UserKnownHostsFile=/dev/null \
			-i $ID_RSA root@localhost >/dev/null 2>&1 &
	done <$LIST_PATH
}

# 断开连接
disconnect() {
	while IFS=: read NODE_NAME CONTAINER_NAME CONTAINER_PORT SOCKS_PORT SERVER_IP PASSWORD ID_RSA; do
		get_connect_pid
		kill $connect_pid >/dev/null 2>&1
	done <$LIST_PATH
}

# 获取ssh的pid
get_connect_pid() {
	connect_pid=$(ps -A ssh | grep "/ssh" | grep $SOCKS_PORT | awk '{print $2}')
	if [ ! -n "$connect_pid" ]; then connect_pid="进程不存在"; fi
}

# 自动重连
auto_connect() {
	export AUTOSSH_PIDFILE=/tmp/autossh.pid
	export AUTOSSH_POLL=60
	export AUTOSSH_FIRST_POLL=30
	export AUTOSSH_GATETIME=0
	export AUTOSSH_DEBUG=1
    while IFS=: read NODE_NAME CONTAINER_NAME CONTAINER_PORT SOCKS_PORT SERVER_IP PASSWORD ID_RSA; do
		nohup autossh -M 0 -4 -p $CONTAINER_PORT -ND $IP:$SOCKS_PORT \
            -o ServerAliveInterval=60 \
            -o ServerAliveCountMax=3 \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -i $ID_RSA root@localhost >/dev/null 2>&1 &
    done <$LIST_PATH
}
fix_auto_connect() {
	pkill -9 autossh
	auto_connect
}

# 状态查看函数
monitor() {
	separator
	echo -en '  代理节点  \t-  Socks 端口  \t-  容器状态  \t-  PID\n'
	separator
	while IFS=: read NODE_NAME CONTAINER_NAME CONTAINER_PORT SOCKS_PORT SERVER_IP PASSWORD ID_RSA; do
		get_connect_pid
		container_status=$(docker inspect --format='{{.State.Status}}' $CONTAINER_NAME 2>&1)
		echo -en '  '$NODE_NAME'  \t-  '$SOCKS_PORT'  \t-  '$container_status'  \t-  '$connect_pid'\n'
	done <$LIST_PATH
	separator
	NOW_PORT=$(cat $PRIVOXY_CONFIGFILE | tail -n 20 | grep "forward-socks5t" | awk '{print $3}' | cut -d: -f2)
	echo -en '  socks5->http:'$NOW_PORT'->8118 | Proxy IP:'$(ps -A ssh | grep ssh | grep 10001 | awk '{print $14}' | cut -d: -f1)'\n'
	separator
	echo -en '  容器  CPU  \t\t下载  \t上传\n'
	separator
	container_list=$(cut -d: -f 2 $LIST_PATH | xargs)
	docker stats --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.NetIO}}' --no-stream $container_list | grep '[a-z]' | awk '{print $1,$2,$3,$5}' | tr ' ' '\t' | sed 's/%\t/%\t\t/g' | sed 's/^/  /g'
	separator
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

# 重启sshd进程
restart_sshd() {
	disconnect
	sudo killall sshd >/dev/null 2>&1
	echo "全部代理已重置，sshd 进程已终止，正在重新建立代理连接。"
}

# 编辑配置文件
edit_config() {
	$EDITOR $LIST_PATH
	echo "配置文件改变，请重新执行--local部署。"
	exit 0
}
while [ -n "$1" ]; do
	case "$1" in
		-c | --connect)
			disconnect; connect; exit 0;
			;;
		-m | --monitor)
			monitor
			exit 0
			;;
		-d | --driver)
			DRIVER=$2
			driver
			shift
			;;
		-p | --port)
			NEW_PORT=$2
			socks_to_http
			shift
			;;
		-k | --kill)
			restart_sshd
			fix_auto_connect
			monitor
			exit 0
			;;
		-e | --edit)
			edit_config
			;;
		-h | --help)
			help
			;;
		-s | --server)
			server_daemon
			;;
		-l | --local)
			local_daemon
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
debug() {
	echo $PROXY_CHAINS_CONFIG_PATH
}

main() {
	disconnect
	fix_auto_connect
	monitor
}

#debug
main
exit 0

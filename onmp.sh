#!/bin/sh
# @Author: xzhih
# @Date:   2017-07-29 06:10:54
# @Last Modified by:   Fangshing87
# @Last Modified time: 2019-06-09 11:39:26

# 软件包列表
pkglist="wget unzip grep sed tar ca-certificates coreutils-whoami php7 php7-cgi php7-cli php7-fastcgi php7-fpm php7-mod-pdo nginx-extras"

phpmod="php7-mod-calendar php7-mod-ctype php7-mod-curl php7-mod-dom php7-mod-exif php7-mod-fileinfo php7-mod-ftp php7-mod-gd php7-mod-gettext php7-mod-gmp php7-mod-hash php7-mod-iconv php7-mod-intl php7-mod-json php7-mod-ldap php7-mod-session php7-mod-mbstring php7-mod-opcache php7-mod-openssl php7-mod-pcntl php7-mod-phar php7-mod-session php7-mod-shmop php7-mod-simplexml php7-mod-snmp php7-mod-soap php7-mod-sockets php7-mod-sqlite3 php7-mod-sysvmsg php7-mod-sysvsem php7-mod-sysvshm php7-mod-tokenizer php7-mod-xml php7-mod-xmlreader php7-mod-xmlwriter php7-mod-zip php7-pecl-dio php7-pecl-http php7-pecl-libevent php7-pecl-propro php7-pecl-raphf snmpd snmp-mibs snmp-utils zoneinfo-core zoneinfo-asia"

# 后续可能增加的包(缺少源支持)
# php7-mod-imagick imagemagick imagemagick-jpeg imagemagick-png imagemagick-tiff imagemagick-tools


# 通用环境变量获取
get_env()
{
    # 获取用户名
    if [[ $USER ]]; then
        username=$USER
    elif [[ -n $(whoami 2>/dev/null) ]]; then
        username=$(whoami 2>/dev/null)
    else
        username=$(cat /etc/passwd | sed "s/:/ /g" | awk 'NR==1'  | awk '{printf $1}')
    fi

    # 获取路由器IP
    localhost=$(ifconfig  | grep "inet addr" | awk '{ print $2}' | awk -F: '{print $2}' | awk 'NR==1')
    if [[ ! -n "$localhost" ]]; then
        localhost="你的路由器IP"
    fi
}

##### 软件包状态检测 #####
install_check()
{
    notinstall=""
    for data in $pkglist ; do
        if [[ `opkg list-installed | grep $data | wc -l` -ne 0 ]];then
            echo "$data 已安装"
        else
            notinstall="$notinstall $data"
            echo "$data 正在安装..."
            opkg install $data
        fi
    done
}

# 安装PHP mod 
install_php_mod()
{
    notinstall=""
    for data in $phpmod ; do
        if [[ `opkg list-installed | grep $data | wc -l` -ne 0 ]];then
            echo "$data 已安装"
        else
            notinstall="$notinstall $data"
            echo "$data 正在安装..."
            opkg install $data
        fi
    done
}

############## 安装软件包 #############
install_onmp_ipk()
{
    opkg update

    # 软件包状态检测
    install_check

    for i in 'seq 3'; do
        if [[ ${#notinstall} -gt 0 ]]; then
            install_check
        fi
    done

    if [[ ${#notinstall} -gt 0 ]]; then
        echo "可能会因为某些问题某些核心软件包无法安装，请保持/opt/目录足够干净，如果是网络问题，请挂全局VPN再次运行命令"
    else
        echo "----------------------------------------"
        echo "|********** ONMP软件包已完整安装 *********|"
        echo "----------------------------------------"
        echo "是否安装PHP的模块(Nextcloud这类应用需要)，你也可以手动安装"
#
read -p "输入你的选择[y/n]: " input
case $input in
    y) install_php_mod;;
n) echo "如果程序提示需要安装插件，你可以自行使用opkg命令安装";;
*) echo "你输入的不是 y/n"
exit;;
esac 
        echo "现在开始初始化ONMP"
        init_onmp
        echo ""
    fi
}

################ 初始化onmp ###############
init_onmp()
{
    # 初始化网站目录
    rm -rf /opt/wwwroot
    mkdir -p /opt/wwwroot/default
    chmod -R 777 /opt/tmp

    # 初始化Nginx
    init_nginx > /dev/null 2>&1

    # 初始化PHP
    init_php > /dev/null 2>&1

    # 添加探针
    # 获取php探针文件
    curl -kfsSL https://raw.githubusercontent.com/WuSiYu/PHP-Probe/master/tz.php > /opt/wwwroot/default/tz.php
    add_vhost 81 default
    sed -e "s/.*\#php-fpm.*/    include \/opt\/etc\/nginx\/conf\/php-fpm.conf\;/g" -i /opt/etc/nginx/vhost/default.conf
    chmod -R 777 /opt/wwwroot/default

    # 生成ONMP命令
    set_onmp_sh
    onmp start
}

############### 初始化Nginx ###############
init_nginx()
{
    get_env
    /opt/etc/init.d/S80nginx stop > /dev/null 2>&1
    rm -rf /opt/etc/nginx/vhost 
    rm -rf /opt/etc/nginx/conf
    mkdir -p /opt/etc/nginx/vhost
    mkdir -p /opt/etc/nginx/conf

# 初始化nginx配置文件
cat > "/opt/etc/nginx/nginx.conf" <<-\EOF
user theOne root;
pid /opt/var/run/nginx.pid;
worker_processes auto;

events {
    use epoll;
    multi_accept on;
    worker_connections 1024;
}

http {
    charset utf-8;
    include mime.types;
    default_type application/octet-stream;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 60;
    
    client_max_body_size 2000m;
    client_body_temp_path /opt/tmp/;
    
    gzip on; 
    gzip_vary on;
    gzip_proxied any;
    gzip_min_length 1k;
    gzip_buffers 4 8k;
    gzip_comp_level 2;
    gzip_disable "msie6";
    gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript application/javascript image/svg+xml;

    include /opt/etc/nginx/vhost/*.conf;
}
EOF

sed -e "s/theOne/$username/g" -i /opt/etc/nginx/nginx.conf

# 特定程序的nginx配置
nginx_special_conf

}

##### 特定程序的nginx配置 #####
nginx_special_conf()
{
# php-fpm
cat > "/opt/etc/nginx/conf/php-fpm.conf" <<-\OOO
location ~ \.php(?:$|/) {
    fastcgi_split_path_info ^(.+\.php)(/.+)$; 
    fastcgi_pass unix:/opt/var/run/php7-fpm.sock;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    include fastcgi_params;
}
OOO

}

############## PHP初始化 #############
init_php()
{
# PHP7设置 
/opt/etc/init.d/S79php7-fpm stop > /dev/null 2>&1

mkdir -p /opt/usr/php/tmp/
chmod -R 777 /opt/usr/php/tmp/

sed -e "/^doc_root/d" -i /opt/etc/php.ini
sed -e "s/.*memory_limit = .*/memory_limit = 128M/g" -i /opt/etc/php.ini
sed -e "s/.*output_buffering = .*/output_buffering = 4096/g" -i /opt/etc/php.ini
sed -e "s/.*post_max_size = .*/post_max_size = 8000M/g" -i /opt/etc/php.ini
sed -e "s/.*max_execution_time = .*/max_execution_time = 2000 /g" -i /opt/etc/php.ini
sed -e "s/.*upload_max_filesize.*/upload_max_filesize = 8000M/g" -i /opt/etc/php.ini
sed -e "s/.*listen.mode.*/listen.mode = 0666/g" -i /opt/etc/php7-fpm.d/www.conf

# PHP配置文件
cat >> "/opt/etc/php.ini" <<-\PHPINI
session.save_path = "/opt/usr/php/tmp/"
opcache.enable=1
opcache.enable_cli=1
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=60
opcache.fast_shutdown=1

mysqli.default_socket=/opt/var/run/mysqld.sock
pdo_mysql.default_socket=/opt/var/run/mysqld.sock
PHPINI

cat >> "/opt/etc/php7-fpm.d/www.conf" <<-\PHPFPM
env[HOSTNAME] = $HOSTNAME
env[PATH] = /opt/bin:/usr/local/bin:/usr/bin:/bin
env[TMP] = /opt/tmp
env[TMPDIR] = /opt/tmp
env[TEMP] = /opt/tmp
PHPFPM
}

################ 卸载onmp ###############
remove_onmp()
{
    /opt/etc/init.d/S79php7-fpm stop > /dev/null 2>&1
    /opt/etc/init.d/S80nginx stop > /dev/null 2>&1
    
    killall -9 nginx php-fpm > /dev/null 2>&1
    for pkg in $pkglist; do
        opkg remove $pkg --force-depends
    done
    for mod in $phpmod; do
        opkg remove $mod --force-depends
    done
    rm -rf /opt/wwwroot
    rm -rf /opt/etc/nginx/vhost
    rm -rf /opt/bin/onmp
    rm -rf /opt/etc/nginx/
    rm -rf /opt/etc/php*
}

################ 生成ONMP命令 ###############
set_onmp_sh()
{
# 删除
rm -rf /opt/bin/onmp

# 写入文件
cat > "/opt/bin/onmp" <<-\EOF
#!/bin/sh

# 获取路由器IP
localhost=$(ifconfig | grep "inet addr" | awk '{ print $2}' | awk -F: '{print $2}' | awk 'NR==1')
if [[ ! -n "$localhost" ]]; then
    localhost="你的路由器IP"
fi

vhost_list()
{
    echo "网站列表："
    logger -t "【ONMP】" "网站列表："
    for conf in /opt/etc/nginx/vhost/*;
    do
        path=$(cat $conf | awk 'NR==4' | awk '{print $2}' | sed 's/;//')
        port=$(cat $conf | awk 'NR==2' | awk '{print $2}' | sed 's/;//')
        echo "$path        $localhost:$port"
        logger -t "【ONMP】" "$path     $localhost:$port"
    done
    echo "浏览器地址栏输入：$localhost:81 查看php探针"
}

onmp_restart()
{
    /opt/etc/init.d/S79php7-fpm stop > /dev/null 2>&1
    /opt/etc/init.d/S80nginx stop > /dev/null 2>&1
    killall -9 nginx php-fpm > /dev/null 2>&1
    sleep 3
    /opt/etc/init.d/S79php7-fpm start > /dev/null 2>&1
    /opt/etc/init.d/S80nginx start > /dev/null 2>&1
    sleep 3
    num=0
    for PROC in 'nginx' 'php-fpm'; do 
        if [ -n "`pidof $PROC`" ]; then
            echo $PROC "启动成功";
        else
            echo $PROC "启动失败";
            num=`expr $num + 1`
        fi 
    done

    if [[ $num -gt 0 ]]; then
        echo "onmp启动失败"
        logger -t "【ONMP】" "启动失败"
    else
        echo "onmp已启动"
        logger -t "【ONMP】" "已启动"
        vhost_list
    fi
}

case $1 in
    open ) 
    /opt/onmp/onmp.sh
    ;;

    start )
    echo "onmp正在启动"
    logger -t "【ONMP】" "正在启动"
    onmp_restart
    ;;

    stop )
    echo "onmp正在停止"
    logger -t "【ONMP】" "正在停止"
    /opt/etc/init.d/S79php7-fpm stop > /dev/null 2>&1
    /opt/etc/init.d/S80nginx stop > /dev/null 2>&1
    echo "onmp已停止"
    logger -t "【ONMP】" "已停止"
    ;;

    restart )
    echo "onmp正在重启"
    logger -t "【ONMP】" "正在重启"
    onmp_restart
    ;;

    php )
    case $2 in
        start ) /opt/etc/init.d/S79php7-fpm start;;
        stop ) /opt/etc/init.d/S79php7-fpm stop;;
        restart ) /opt/etc/init.d/S79php7-fpm restart;;
        * ) echo "onmp php start|restart|stop";;
    esac
    ;;

    nginx )
    case $2 in
        start ) /opt/etc/init.d/S80nginx start;;
        stop ) /opt/etc/init.d/S80nginx stop;;
        restart ) /opt/etc/init.d/S80nginx restart;;
        * ) echo "onmp nginx start|restart|stop";;
    esac
    ;;

    list )
    vhost_list
    ;;
    * )
#
cat << HHH
=================================
 onmp 管理命令
 onmp open

 启动 停止 重启
 onmp start|stop|restart

 查看网站列表 onmp list

 Nginx 管理命令
 onmp nginx start|restart|stop
 PHP 管理命令
 onmp php start|restart|stop
=================================
HHH
    ;;
esac
EOF

chmod +x /opt/bin/onmp
#
cat << HHH
=================================
 onmp 管理命令
 onmp open

 启动 停止 重启
 onmp start|stop|restart

 查看网站列表 onmp list

 Nginx 管理命令
 onmp nginx start|restart|stop
 PHP 管理命令
 onmp php start|restart|stop
=================================
HHH

}

############# 添加到虚拟主机 #############
add_vhost()
{
# 写入文件
cat > "/opt/etc/nginx/vhost/$2.conf" <<-\EOF
server {
    listen 81;
    server_name localhost;
    root /opt/wwwroot/www/;
    index index.html index.htm index.php tz.php;
    #php-fpm
    #otherconf
}
EOF

sed -e "s/.*listen.*/    listen $1\;/g" -i /opt/etc/nginx/vhost/$2.conf
sed -e "s/.*\/opt\/wwwroot\/www\/.*/    root \/opt\/wwwroot\/$2\/\;/g" -i /opt/etc/nginx/vhost/$2.conf
}

############## 网站管理 ##############
web_manager()
{
    onmp stop > /dev/null 2>&1
    i=1
    for conf in /opt/etc/nginx/vhost/*;
    do
        path=$(cat $conf | awk 'NR==4' | awk '{print $2}' | sed 's/;//')
        echo "$i. $path"
        eval web_conf$i="$conf"
        eval web_file$i="$path"
        i=$((i + 1))
    done
    read -p "请选择要删除的网站：" webnum
    eval conf=\$web_conf"$webnum"
    eval file=\$web_file"$webnum"
    rm -rf "$conf"
    rm -rf "$file"
    onmp start > /dev/null 2>&1
    echo "网站已删除"
}

###########################################
################# 脚本开始 #################
###########################################
start()
{
# 输出选项
cat << EOF
      ___           ___           ___           ___    
     /  /\         /__/\         /__/\         /  /\   
    /  /::\        \  \:\       |  |::\       /  /::\  
   /  /:/\:\        \  \:\      |  |:|:\     /  /:/\:\ 
  /  /:/  \:\   _____\__\:\   __|__|:|\:\   /  /:/~/:/ 
 /__/:/ \__\:\ /__/::::::::\ /__/::::| \:\ /__/:/ /:/  
 \  \:\ /  /:/ \  \:\~~\~~\/ \  \:\~~\__\/ \  \:\/:/   
  \  \:\  /:/   \  \:\  ~~~   \  \:\        \  \::/    
   \  \:\/:/     \  \:\        \  \:\        \  \:\    
    \  \::/       \  \:\        \  \:\        \  \:\   
     \__\/         \__\/         \__\/         \__\/   

=======================================================

(1) 安装ONMP
(2) 卸载ONMP
(3) 全部重置（会删除网站目录，请注意备份）
(4) 网站管理
(0) 退出

EOF

read -p "输入你的选择[0-9]: " input
case $input in
    1) install_onmp_ipk;;
2) remove_onmp;;
3) init_onmp;;
4) web_manager;;
0) exit;;
*) echo "你输入的不是 0 ~ 8 之间的!"
exit;;
esac 
}

re_sh="renewsh"

if [ "$1" == "$re_sh" ]; then
    set_onmp_sh
    exit;
fi  

start

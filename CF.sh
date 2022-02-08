#!/bin/bash
#路由器上扫CF的脚本
#运行目录下创建一个cfip.txt定义扫描范围
#每行定义一个网段，例如1.0.0.0/24
#0.0.0.0/0则全网扫描
#扫描结果：查看log.txt
#本次测速结果：查看speedlog.txt
#历史测速结果：查看hspeedlog.txt

#支持输入参数:
#-n <num>表示并发任务数量，默认100。路由运行如果内存不足挂死，可适当调小。手机termux下建议400。
#-k 表示跳过扫描，仅测速。
#-s 表示跳过测速，仅扫描。
#-m <mode>表示扫描模式，0表示https，1表示http
#-c 表示清除断点文件从头扫描，不会清除log.txt、speedlog.txt和hspeedlog.txt文件
#-a <asn>表示以ASN作为扫描范围，例如AS54994则输入-a 54994
#-r 当ftp服务器或worker备份服务器参数已配置时，携带-r参数从服务器上最近一次备份恢复运行环境（断点、log等），当worker和ftp都配置时，从worker恢复。
#-e 表示仅结束脚本时通过ftp或worker备份环境，中途不备份
#-i 表示断点模式测速，保留speedlog.txt并跳过其中已有测速记录的IP

#版本号，请勿修改
ver=20211222-00

######START######
###以下为脚本默认命令行参数，如果不想运行脚本时输入参数，可以直接修改这里
p_default_para="-m 0 -n 880"

######以下为内置参数######
###自定义扫描参数设置###
p_to=2; 
#单个ip扫描超时时间，默认5秒
p_max_load=1000;
#负载控制，高于该负载暂停启新任务，规避老毛子概率性跑死问题，老毛子建议20，没有跑死问题调到1000，相当于没有限制。
###自定义扫描参数设置结束###

###自定义测速设置###
p_st=1; 
#测速次数，可多次测速，取最大值输出
p_delay_mode=0
#时延测试模式，1为ping时延，0为http时延，即测速url的http/https响应时间
p_st_to=10
#每个IP测速时间，默认10秒
p_st_https_url="https://speed.cloudflare.com/__down?measId=6891185455449098&bytes=500000000"
#https测速地址
p_st_http_url="http://speed.cloudflare.com/__down?measId=6891185455449098&bytes=500000000"
#http测速地址
p_speed_filter='| grep HKG' 
#定义从log.txt中筛选测速IP的规则。例如不测洛杉矶的p_speed_filter='| grep -v LAX'
###自定义测速设置结束###

###以下为ftp备份和恢复参数，周期上传到ftp服务器，技能要求高，不懂不要用。
p_bk_ftp_srv="";
#备份服务器地址，例如p_bk_ftp_srv="ftp://user:password@valid.scan.cf:21";，留空表示不备份
p_bk_ftp_dir=/scancf/openwrt/;
#ftp服务器上的备份目录
p_bk_ftp_mode=0;
#ftp模式，1表示被动模式，0主动模式
p_bk_ftp_period=30; 
#备份周期，默认30分钟
p_ftp_rslt_file="cf_speed_result.txt"
#把speedlog.txt重命名后上传到一个命名不带时间的固定目录，方便通过固定URL分享，留空表示不重命名上传。
###ftp备份参数定义区域结束

###以下为worker备份和恢复设置，需要搭建CF worker
p_wk_env_srv=""
#worker备份运行环境的地址，例如"scancfupate.doremi.workers.dev"
p_bk_wk_period=30
#worker备份周期
############

###以下为公共TG推送设置
api_host=""
nickname="神仙"
ipflag="🚀🚀🚀"
msgemoji="🔥"
chat_id="-1001549398293"
###公共TG推送设置结束

###以下为私有TG推送设置（定制功能，不考虑通用性）
p_priv_api_url=""
p_priv_chat_id=""
###私有TG推送设置结束
######内置参数定义区域结束######
######END######

#解析脚本输入参数
parse_para()
{
  for i in $(seq $(($#+1)))
  do
    eval "arg=\${$i}"
    key=$(echo "~$arg" | sed 's/^.//' | grep "^-" | tr '-' '_')
    if [ "$key"x = x ];then
      continue
    fi
    j=$((i+1))
    eval "value=\${$j}"
    value=$(echo "~$value" | sed 's/^.//' | grep -v "^-")
    if [ "$value"x = x ];then
      eval "p$key=1"
    else
      eval "p$key='$value'"
    fi
  done
}

#根据参数注释生成全0的参数默认值
parse_para $(cat $0 | grep -Eo "^#-([A-Z]|[a-z]|[_])* " | tr -d "#" | tr -d "\n" | sed 's/ / 0 /g')
#生成用户自定义参数默认值
parse_para $p_default_para
#解析脚本输入参数
parse_para "$@"

#TG推送
push_msg()
{
if [ ! "$api_host"x = x ];then
api_url="https://$api_host/"
post_url="https://$api_host/put"
#推送到服务器
{
touch log.txt
isrunning=x
oldlog=$(cat log.txt)
while [ ! "$isrunning"x = x ]
do
    sleep 10
    #规避免费域名概率性不解析，每10秒ping，触发解析
    ping -c1 -W 1 $api_host &> /dev/null
    newlog=$(cat log.txt)
    rawtxt=$(echo -e "$newlog\n$oldlog" | sort | uniq -u)
    if [ ! "$rawtxt"x = x ];then
    pushtxt=""
    rawtxt=$(echo "$rawtxt" | tr " " "~")
    for line in $rawtxt
    do
    ip=$(echo "$line" | tr -d "ip=colh" | awk -F~ "{print \$1}")
    colo=$(echo "$line" | tr -d "ip=colh" | awk -F~ "{print \$3}")
    pushtxt=$pushtxt,$(echo -e "{\"user\":\"$nickname\",\"ip\":\"$ip\",\"colo\":\"$colo\",\"flag\":\"$ipflag\"}")
    done
    pushtxt=$(echo $pushtxt | sed "s/^,/\[/" | sed "s/\$/\]/")
    curl -s -X POST "$post_url" -d "$pushtxt" &> /dev/null
    #定制推送
    if [ ! "$p_priv_api_url"x = x ];then
    pushtxt=$(echo -e "$ipflag $nickname 新中转 \n$rawtxt" | tr "~" " ")
    curl -s -X POST -d "chat_id=$p_priv_chat_id&text=$pushtxt" "$p_priv_api_url/sendMessage" &> /dev/null
    fi
    fi
    oldlog=$newlog
    isrunning=`ps | sed "s/^/ /" | grep " $$ " | grep -v grep`
done
subfix=$(TZ=UTC-8 date +_%Y%m%d%H%M%S)
prefix=$(echo $nickname"_" | tr " " "-")
logfile="log$subfix.txt"
speedfile="speedlog$subfix.txt"
cp log.txt $logfile &> /dev/null
cp speedlog.txt $speedfile &> /dev/null
mv $logfile $prefix$logfile &> /dev/null
if [ $? -eq 0 ];then
    logfile=$prefix$logfile
fi
mv $speedfile $prefix$speedfile &> /dev/null
if [ $? -eq 0 ];then
    speedfile=$prefix$speedfile
fi
curl -v -F "chat_id=$chat_id" -F document=@./$logfile "$api_url/sendDocument" &> /dev/null
curl -v -F "chat_id=$chat_id" -F document=@./$speedfile "$api_url/sendDocument" &> /dev/null

 #定制推送
if [ ! "$p_priv_api_url"x = x ];then
    curl -v -F "chat_id=$p_priv_chat_id" -F document=@./$logfile "$p_priv_api_url/sendDocument" &> /dev/null
    curl -v -F "chat_id=$p_priv_chat_id" -F document=@./$speedfile "$p_priv_api_url/sendDocument" &> /dev/null
fi

rm -rf $logfile $speedfile &> /dev/null
}&

#推送进度到TG，1小时一次
{
start=$(TZ=UTC-8 date +%Y-%m-%d" "%H:%M:%S)
isrunning=x
loop=0
while [ ! "$isrunning"x = x ]
do
    sleep 10
    isrunning=`ps | sed "s/^/ /" | grep " $$ " | grep -v grep`
    loop=$((loop+1))
    if [ ! $loop -eq 360 ];then
        continue
    fi
    loop=0
    if [ ! -f tmpip.txt ];then
        continue
    fi
    total=$(cat tmpip.txt | wc -l)
    now=$(TZ=UTC-8 date +%Y-%m-%d" "%H:%M:%S)
    span=$((($(date +%s -d "$now") - $(date +%s -d "$start"))/60))
    finish=0
    if [ -f finiship.txt ];then
        finish=$(cat finiship.txt | wc -l)
    fi
    pushtxt=$(echo -e "$msgemoji$nickname$msgemoji\n版本：$ver\n进度：$finish/$total，$(echo | awk "{print $finish/$total*100}" | tr -d "\n")%\n用时：$span"分钟)
    curl -s -X POST "$api_url/sendMessage" -d "chat_id=$chat_id&text=$pushtxt" &> /dev/null
    #定制推送
    if [ ! "$p_priv_api_url"x = x ];then
    curl -s -X POST -d "chat_id=$p_priv_chat_id&text=$pushtxt" "$p_priv_api_url/sendMessage" &> /dev/null
    fi
done
}&
fi
}

scan_single_ip(){
read -u6;
./$scancmdfile $1
}

scan_subnet(){
raw=`echo $1.32 | tr '/' '.' | grep -Eo "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,2}"`;

if [ "$raw"x = x ];then
    return;
fi

mask=`echo $raw | awk -F. '{print $5}'`;

if [ "$mask"x = x ];then
    return;
fi

i=`echo $raw | awk -F. '{print $1}'`;
j=`echo $raw | awk -F. '{print $2}'`;
k=`echo $raw | awk -F. '{print $3}'`;
l=`echo $raw | awk -F. '{print $4}'`;

if [ $i -le 0 ];then
    i=1;
fi

echo scanning:$i.$j.$k.$l/$mask

ipstart=$(((i<<24)|(j<<16)|(k<<8)|l));
hostend=$((2**(32-mask)-1));
loop=0;
while [ $loop -le $hostend ]
do
    ip=$((ipstart|loop));
    i=$(((ip>>24)&255));
    j=$(((ip>>16)&255));
    k=$(((ip>>8)&255));
    l=$(((ip>>0)&255));
    loop=$((loop+1));
    scan_single_ip $i.$j.$k.$l;
done
}

#测速
speedtest(){
ip=`echo $1 | tr '/' '.' | grep -Eo "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"`;
if [ "$ip"x = x ];then
    return;
fi

if [ $p_m -eq 0 ];then
    st_url="$p_st_https_url"
    st_host=$(echo "$st_url" | awk -F/ '{print $3":443"}')
else
    st_url="$p_st_http_url"
    st_host=$(echo "$st_url" | awk -F/ '{print $3":80"}')
fi

bw_delay=$(for i in $(seq $p_st);do curl -s --resolve "$st_host:$ip" -o /dev/null --connect-timeout 1 --max-time $p_st_to -w %{time_namelookup}-%{time_connect}-%{time_starttransfer}-%{time_total}-%{speed_download}"\n" "$st_url" | awk -F- '{print $5,$3}'; done | awk 'BEGIN {bw=0;dl=10} {if($1+0>bw+0)bw=$1;if(($2+0>0.000000001)&&($2+0<dl+0))dl=$2} END {printf "%.0f %.0f\n",bw,dl*1000}')

if [ "$bw_delay"x = x ];then
    bw_delay="0 10000"
fi

max=$(echo "$bw_delay" | awk '{print $1}')
delay=$(echo "$bw_delay" | awk '{print $2}')
if [ $max -eq 0 ];then
    delay='*'
fi

max=$((max/1024));
if [ ! $max -eq 0 ] && [ $p_delay_mode -eq 1 ]; then
    delay='*';
    pi=`ping -c 3 -W 1 $ip`;
    delay=`echo $pi | grep -oE "([0-9]{1,10}\.[0-9]{1,10}\/){2}[0-9]{1,10}.[0-9]{1,10}" | awk -F'/' '{print $2}' | awk -F'.' '{print $1}'`;
fi
if [ "$delay"x = x ]; then
	delay='*';
fi

#如果有测速历史，看第一次出现相距多少天
span=1;
if [ -f hspeedlog.txt ];then
first=`head -n $(cat hspeedlog.txt | grep "^$ip " -n | head -n 1 | awk -F: '{print $1}') hspeedlog.txt 2>/dev/null | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -n 1`
last=$(TZ=UTC-8 date +%Y-%m-%d)
if [ "$first"x = x ]; then
	first=$last;
fi
basespan=$(cat hspeedlog.txt | awk "{print \$0}END{print \"$ip 1ms 1days\"}" | grep "^$ip " | head -n 1 | tr -d ' ' | grep -Eo '[0-9]{1,9}days' | awk '{print $0-1}')
span=$((($(date +%s -d $last) - $(date +%s -d $first))/86400+1));
span=$((span+basespan));
fi

if [ $max -eq 0 ]; then
    span='*';
fi

colo=`cat log.txt | grep "ip=$ip " | awk '{print $3}' | awk -F= '{print $2}' | tail -n 1`

max=`echo $max | awk '{printf ("%.2f\n",$1/1024)}'`;
echo $ip "$max"MB/s "$delay"ms "$span"days $colo;
echo $ip "$max"MB/s "$delay"ms "$span"days $colo >> speedlog.txt
}

#把比较大的网段拆小，提升断点执行效率
divsubnet(){
mask=$5;i=$1;j=$2;k=$3;l=$4;
echo "拆分子网:$i.$j.$k.$l/$mask";

if [ $mask -ge 8 ] && [ $mask -le 23 ];then
    ipstart=$(((i<<24)|(j<<16)|(k<<8)|l));
    hostend=$((2**(32-mask)-1));
    loop=0;
    while [ $loop -le $hostend ]
    do
        subnet=$((ipstart|loop));
        i=$(((subnet>>24)&255));
        j=$(((subnet>>16)&255));
        k=$(((subnet>>8)&255));
        l=$(((subnet>>0)&255));
        loop=$((loop+256));
        echo $i.$j.$k.$l/24 >> tmpip.txt;
    done
else
    echo $i.$j.$k.$l/$mask >> tmpip.txt;
fi
}

#ftp备份和恢复处理
safe_curl='#!/bin/bash
CURL(){
    ret=0
    for i in $(seq 10)
    do
        curl "$@"
        ret=$?
        if [ $ret -eq 0 ];then
            break
        fi
    done
    return $ret
}

ftp_upload()
{
    eval file=\$$#
    cmd="CURL"
    for i in $(seq $(($#-2)))
    do
        eval arg=\$$i
        cmd="$cmd \"$arg\""
    done
    filebak="$file.bak"
    rm -rf "$filebak" &>/dev/null
    cp "$file" "$filebak" &>/dev/null
    eval "$cmd -T \"$filebak\""
    if [ $? -eq 0 ];then
        eval "$cmd -Q \"-RNFR $filebak\" -Q \"-RNTO $file\""
    fi
    rm -rf "$filebak" &>/dev/null
}

ftpupload=$(echo "$*" | grep "\-T")
if [ ! "$ftpupload"x = x ];then
    ftp_upload "$@"
else
    CURL "$@"
fi
'
echo "$safe_curl" > CURL.sh
chmod 777 CURL.sh

worker_restore_env()
{
if [ ! "$p_wk_env_srv"x = x ] && [ $p_r -eq 1 ];then

workerfilename=$(echo $nickname | md5sum | awk "{print \$1}" | sed "s/$/.txt/")
curl -o $workerfilename -s -H "authorization: Basic YWRtaW46anM=" "https://$p_wk_env_srv/get?key=$workerfilename"
total=$(cat $workerfilename | wc -l)
file=""
begin=1
end=1
for line in $(cat $workerfilename | grep -n "FILE:")
do
    end=$(echo $line | awk -F: '{print $1}')
    if [ ! "$file"x = x ] && [ $((end-begin-1)) -gt 0 ];then
    eval cat $workerfilename | head -n $((end-1)) | tail -n $((end-begin-1)) > $file
    fi
    file=$(echo $line | awk -F: '{print $3}')
    begin=$end
done
end=$(cat $workerfilename | wc -l)
end=$((end+1))
if [ ! "$file"x = x ] && [ $((end-begin-1)) -gt 0 ];then
eval cat $workerfilename | head -n $((end-1)) | tail -n $((end-begin-1)) > $file
fi
rm -rf $workerfilename 2>/dev/null
fi
}

ftp_restore_env()
{
if [ ! "$p_bk_ftp_srv"x = x ] && [ $p_r -eq 1 ] && [ "$p_wk_env_srv"x = x ] ;then
p_bk_cmd="./CURL.sh --ftp-create-dirs --retry 5"
if [ $p_bk_ftp_mode -eq 0 ];then
    p_bk_cmd="$p_bk_cmd -P -";
fi
p_bk_cmd="$p_bk_cmd $p_bk_ftp_srv$p_bk_ftp_dir";
latestbkdir=`$p_bk_cmd 2>/dev/null | grep ^d | grep -v "\." | grep -Eo  "[0-9]{8}" | sort -nr | tr '\n' ' ' | awk '{print $1}'`;
    if [ ! "$latestbkdir"x = x ];then
    $p_bk_cmd$latestbkdir/log.txt -o log.txt;
    $p_bk_cmd$latestbkdir/speedlog.txt -o speedlog.txt;
    $p_bk_cmd$latestbkdir/hspeedlog.txt -o hspeedlog.txt;
    $p_bk_cmd$latestbkdir/tmpip.txt -o tmpip.txt;
    $p_bk_cmd$latestbkdir/finiship.txt -o finiship.txt;
    $p_bk_cmd"task/cfip.txt" -o cfip.txt;
    fi
fi
}

worker_backup_env()
{
if [ ! "$p_wk_env_srv"x = x ];then
wkbkcmdfile="wkbkcf.sh"
wkbkcf='#!/bin/bash
{
nickname=$1
p_bk_wk_period=$2
p_wk_env_srv=$3
p_e=$4
workerfilename=$(echo $nickname | md5sum | awk "{print \$1}" | sed "s/$/.txt/")
p="x"
loop=0;
while [ ! "$p"x = x ];
do
sleep 60
p=`ps | sed "s/^/ /" | grep " $$ " | grep -v grep`;
if [ ! $p_e -eq 0 ];then
    continue
fi
if [ $loop -eq $p_bk_wk_period ];then
    loop=0;
    if [ -f tmpip.txt ];then
        echo "FILE:tmpip.txt" > $workerfilename
        cat tmpip.txt >> $workerfilename
    fi
    if [ -f finiship.txt ];then
        echo "FILE:finiship.txt" >> $workerfilename
        cat finiship.txt >> $workerfilename
    fi
    if [ -f log.txt ];then
        echo "FILE:log.txt" >> $workerfilename
        cat log.txt >> $workerfilename
    fi
    if [ -f speedlog.txt ];then
        echo "FILE:speedlog.txt" >> $workerfilename
        cat speedlog.txt >> $workerfilename
    fi
    if [ -f hspeedlog.txt ];then
        echo "FILE:hspeedlog.txt" >> $workerfilename
        cat hspeedlog.txt >> $workerfilename
    fi
    if [ -f cfip.txt ];then
        echo "FILE:cfip.txt" >> $workerfilename
        cat cfip.txt >> $workerfilename
    fi
    ./CURL.sh -H "authorization: Basic YWRtaW46anM=" -X POST --data-binary @./$workerfilename "https://$p_wk_env_srv/put?key=$workerfilename" 2> /dev/null
    rm -rf $workerfilename 2> /dev/null
fi
loop=$((loop+1))
done
if [ -f tmpip.txt ];then
    echo "FILE:tmpip.txt" > $workerfilename
    cat tmpip.txt >> $workerfilename
fi
if [ -f finiship.txt ];then
    echo "FILE:finiship.txt" >> $workerfilename
    cat finiship.txt >> $workerfilename
fi
if [ -f log.txt ];then
    echo "FILE:log.txt" >> $workerfilename
    cat log.txt >> $workerfilename
fi
if [ -f speedlog.txt ];then
    echo "FILE:speedlog.txt" >> $workerfilename
    cat speedlog.txt >> $workerfilename
fi
if [ -f hspeedlog.txt ];then
    echo "FILE:hspeedlog.txt" >> $workerfilename
    cat hspeedlog.txt >> $workerfilename
fi
if [ -f cfip.txt ];then
    echo "FILE:cfip.txt" >> $workerfilename
    cat cfip.txt >> $workerfilename
fi
./CURL.sh -H "authorization: Basic YWRtaW46anM=" -X POST --data-binary @./$workerfilename "https://$p_wk_env_srv/put?key=$workerfilename" 2> /dev/null
rm -rf $workerfilename 2> /dev/null
}&
'
echo "$wkbkcf" | sed "s/\\\$\\\$/$$/g" > $wkbkcmdfile
chmod 777 $wkbkcmdfile
./$wkbkcmdfile "$nickname" "$p_bk_wk_period" "$p_wk_env_srv" "$p_e"
fi
}

ftp_backup_env()
{
if [ ! "$p_bk_ftp_srv"x = x ];then
bkcmdfile="bkcf.sh"
p_bk_cmd="./CURL.sh --ftp-create-dirs --retry 5"
if [ $p_bk_ftp_mode -eq 0 ];then
    p_bk_cmd="$p_bk_cmd -P -";
fi
p_bk_cmd="$p_bk_cmd $p_bk_ftp_srv$p_bk_ftp_dir";
bkcf='#!/bin/bash
{
p_bk_cmd="$1"
bk_period="$2"
rslt_file="$3"
p_e=$4
p="run";
loop=0;
while [ ! "$p"x = x ];
do
    sleep 60
    p=`ps | sed "s/^/ /" | grep " $$ " | grep -v grep`
    if [ ! $p_e -eq 0 ];then
        continue
    fi
    bktime=$(TZ=UTC-8 date +%Y%m%d);
    if [ $loop -eq $bk_period ];then
        $p_bk_cmd$bktime/ -T tmpip.txt
        $p_bk_cmd$bktime/ -T finiship.txt
        $p_bk_cmd$bktime/ -T log.txt
        $p_bk_cmd$bktime/ -T speedlog.txt
        $p_bk_cmd$bktime/ -T hspeedlog.txt
        if [ ! -f tmpip.txt ];then
            $p_bk_cmd$bktime/ -X "DELE tmpip.txt"
            $p_bk_cmd$bktime/ -X "DELE finiship.txt"
        fi
        loop=0;
    fi
    loop=$((loop+1))
done
echo done
bktime=$(TZ=UTC-8 date +%Y%m%d);
$p_bk_cmd$bktime/ -T tmpip.txt
$p_bk_cmd$bktime/ -T finiship.txt
$p_bk_cmd$bktime/ -T log.txt
$p_bk_cmd$bktime/ -T speedlog.txt
$p_bk_cmd$bktime/ -T hspeedlog.txt
rm -rf $rslt_file &>/dev/null
cp speedlog.txt $rslt_file &>/dev/null
$p_bk_cmd -T $rslt_file
rm -rf $rslt_file &>/dev/null

if [ ! -f tmpip.txt ];then
    $p_bk_cmd$bktime/ -X "DELE tmpip.txt"
    $p_bk_cmd$bktime/ -X "DELE finiship.txt"
fi
}&
'
echo "$bkcf" | sed "s/\\\$\\\$/$$/g" > $bkcmdfile
chmod 777 $bkcmdfile
./$bkcmdfile "$p_bk_cmd" "$p_bk_ftp_period" "$p_ftp_rslt_file" "$p_e"
fi
}

worker_restore_env
ftp_restore_env
worker_backup_env
ftp_backup_env

##推送TG和服务器
push_msg

##创建FIFO控制并发进程数
tmp_fifofile="./$$.fifo"
mkfifo $tmp_fifofile &> /dev/null
#有些linux系统不支持mkfifo
if [ ! $? -eq 0 ];then
    mknod $tmp_fifofile p
fi
exec 6<>$tmp_fifofile
rm -f $tmp_fifofile
for i in `seq $p_n`;
do
    echo >&6
done

#创建一个新sh文件扫描，避免各种怪异内存泄露
scancmdfile=scancfcmdfile.sh
if [ $p_k -eq 0 ];then
cat >$scancmdfile<<EOF
#!/bin/bash
{
if [ $p_m -eq 0 ];then
    curl --resolve speedtest.galgamer.eu.org:443:\$1 https://speedtest.galgamer.eu.org/cdn-cgi/trace --connect-timeout $p_to -m $p_to --max-filesize 1 2>/dev/null | grep 'h=\|colo=' | tr '\n' ' ' | sed "s/^/ip=\$1 &/g" | grep 'speedtest.galgamer.eu.org' | grep 'colo=' | sed "s/speedtest.galgamer.eu.org/valid.scan.cf/g" >> log.txt
else
    curl --resolve valid.scan.cf:80:\$1 http://valid.scan.cf/cdn-cgi/trace --connect-timeout $p_to -m $p_to 2>/dev/null | grep 'h=\|colo=' | tr '\n' ' ' | sed "s/^/ip=\$1 &/g" | grep 'valid' | grep 'colo=' >> log.txt
fi
echo >&6 ;
}&
EOF
chmod 777 $scancmdfile
fi

if [ $p_c -eq 1 ];then
    rm tmpip.txt &> /dev/null;
    rm finiship.txt &> /dev/null;
fi

if [ ! -f cfip.txt ];then
  echo "2.0.0.0/24" >> cfip.txt
fi

#生成断点文件
if [ $p_k -eq 0 ];then
    if [ ! -f tmpip.txt ];then
        echo "生成断点文件时间较长，请耐心等待！";
        rm finiship.txt &> /dev/null
        if [ $p_a -eq 0 ];then
        cat cfip.txt | sed 's/<\/a>//g' | grep -Eo "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})*?" | awk '{print $0"/32"}' | awk -F/ '{print $1"/"$2}' > cfip1.txt
        cat cfip1.txt | awk -F/ '$2 >=24' > tmpip.txt;
        cat cfip1.txt | awk -F/ '$2 <24' > tmpip1.txt;
        rm cfip1.txt;
        cat tmpip1.txt | awk -F/ '{print $2}' > mask.txt
        cat tmpip1.txt | awk -F. '{print $1}' > i.txt
        cat tmpip1.txt | awk -F. '{print $2}' > j.txt
        cat tmpip1.txt | awk -F. '{print $3}' > k.txt
        cat tmpip1.txt | awk -F. '{print $4}' | awk -F/ '{print $1}' > l.txt
        rm tmpip1.txt;
        while read -u3 i && read -u4 j  && read -u5 k && read -u7 l && read -u8 mask
        do
            divsubnet $i $j $k $l $mask
        done 3<i.txt 4<j.txt 5<k.txt 7<l.txt 8<mask.txt
        else
        echo "获取AS$p_a对应的IP段";
        curl http://ip.bczs.net/AS$p_a | sed 's/<\/a>//g' | grep -Eo "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})*?" | awk '{print $0"/32"}' | awk -F/ '{print $1"/"$2}' > cfip1.txt
        cat cfip1.txt | awk -F/ '$2 >=24' > tmpip.txt;
        cat cfip1.txt | awk -F/ '$2 <24' > tmpip1.txt;
        rm cfip1.txt;
        cat tmpip1.txt | awk -F/ '{print $2}' > mask.txt
        cat tmpip1.txt | awk -F. '{print $1}' > i.txt
        cat tmpip1.txt | awk -F. '{print $2}' > j.txt
        cat tmpip1.txt | awk -F. '{print $3}' > k.txt
        cat tmpip1.txt | awk -F. '{print $4}' | awk -F/ '{print $1}' > l.txt
        rm tmpip1.txt;
        while read -u3 i && read -u4 j  && read -u5 k && read -u7 l && read -u8 mask
        do
            divsubnet $i $j $k $l $mask
        done 3<i.txt 4<j.txt 5<k.txt 7<l.txt 8<mask.txt
        fi
        rm i.txt j.txt k.txt l.txt mask.txt
    cat tmpip.txt | tr '/' '.' | awk -F. '{printf "%.6f %s\n",sqrt(($1*(2^24))+($2*(2^16))+($3*(2^8))+$4),$1"."$2"."$3"."$4"/"$5}' | sort -n | awk '{print $2}' | uniq > tmp.txt;cat tmp.txt > tmpip.txt;rm tmp.txt;
    rm finiship.txt &> /dev/null;
    fi
fi

#扫描流程
if [ $p_k -eq 0 ];then
    echo "开始扫描"
    touch tmpip.txt
    if [ -f finiship.txt ];then
        finishline=$(cat tmpip.txt | grep -n "^" | grep "$(cat finiship.txt | grep -n "^" | tail -n 1)" | awk -F: "{print \$1}")
        #如果不为空，可认为tmpip.txt和finiship.txt都没有被修改过，直接按行取效率高
        if [ ! "$finishline"x = x ];then
        totalline=$(cat tmpip.txt | wc -l)
        newlinenum=$((totalline-finishline))
        cat tmpip.txt | tail -n $newlinenum > tmp.txt;cat tmp.txt > tmpip.txt;rm tmp.txt;
        else
        cat finiship.txt tmpip.txt | tr '/' '.' | awk -F. '{printf "%.6f %s\n",sqrt(($1*(2^24))+($2*(2^16))+($3*(2^8))+$4),$1"."$2"."$3"."$4"/"$5}' | sort -n | awk '{print $2}' | uniq > tmp.txt;cat tmp.txt > tmpip.txt;rm tmp.txt;
        fi
    fi
    rm finiship.txt &> /dev/null;
    scanresult=`cat tmpip.txt | sed '/^\s*$/d' | wc -l`
if [ $scanresult -eq 0 ];then
    echo "错误：cfip.txt或网络ASN数据库中没有符合格式的子网地址或IP地址。"
fi
    for line in ` awk '{print $1}' tmpip.txt `
    do
        load=`uptime | awk -F 'load average: ' '{print $2}' | awk -F. '{print $1}'`
        while [ $load -ge $p_max_load ];
        do
            sleep 1
            load=`uptime | awk -F 'load average: ' '{print $2}' | awk -F. '{print $1}'`
        done
        if [ ! "$line"x = x ];then
            scan_subnet $line
        fi
    #sed -i '1d' tmpip.txt;
    #sed用一个备份文件实现编辑，太费flash，换一种实现
    echo $line >> finiship.txt
    done
    rm tmpip.txt;
    rm $scancmdfile;
    sleep 10
fi

#等待扫描任务结束
#for i in `seq $p_n`;
#do
#    read -u6;
#done

exec 6>&-

#测速流程
if [ $p_s -eq 0 ];then
echo "开始测速";
touch log.txt;
touch speedlog.txt
#去除log.txt中重复ip
awk ' !x[$1]++ ' log.txt > tmp.txt;cat tmp.txt > log.txt;rm tmp.txt;
sed -i '/^\s*$/d' log.txt
ghasspeedtest=0;
cat speedlog.txt 2&>/dev/null >> hspeedlog.txt
speedtime=$(TZ=UTC-8 date +%Y-%m-%d" "%H:%M:%S);

if [ $p_i -eq 0 ];then
    echo "[$speedtime]" > speedlog.txt
fi

for line in $(eval "cat speedlog.txt log.txt | sed \"s/^ip=//g\" | awk ' ! x[\$1]++ ' | grep valid $p_speed_filter" | tr ' ' '~')
do
    line=`echo $line | tr '~' ' '`;
    ip=`echo $line | awk '{print $1}' | tr -d 'ip='`;
    if [ "$ip"x = x ];then
        continue;
    fi
    ghasspeedtest=1;
    speedtest $ip;
    cat speedlog.txt | grep -v '\[' | awk '{print $2,$1,$3,$4,$5}' | sort -nr | awk '{print $2,$1,$3,$4,$5}' | sed "1s/^/[$speedtime]\n/" > tmp.txt;rm -rf speedlog.txt;mv tmp.txt speedlog.txt
done

if [ $ghasspeedtest -eq 0 ];then
    echo "错误：没有待测速的结果，即log.txt中没有合法的记录或断点模式测速时所有IP都已完成测速"
fi
fi

exit 0

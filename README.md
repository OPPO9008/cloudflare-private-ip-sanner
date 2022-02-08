# cloudflare-private-ip-sanner

cloudflare 私有/中转 ip扫描工具 
路由器上扫CF的脚本 
运行目录下创建一个cfip.txt定义扫描范围 
每行定义一个网段，例如1.0.0.0/24 
0.0.0.0/0则全网扫描  
扫描结果：查看log.txt  
本次测速结果：查看speedlog.txt  
历史测速结果：查看hspeedlog.txt  

支持输入参数:

```
 -n <num>表示并发任务数量，默认100。路由运行如果内存不足挂死，可适当调小。手机termux下建议400。 
 -k 表示跳过扫描，仅测速。
 -s 表示跳过测速，仅扫描。
 -m <mode>表示扫描模式，0表示https，1表示http
 -c 表示清除断点文件从头扫描，不会清除log.txt、speedlog.txt和hspeedlog.txt文件
 -a <asn>表示以ASN作为扫描范围，例如AS54994则输入-a 54994
 -r 当ftp服务器或worker备份服务器参数已配置时，携带-r参数从服务器上最近一次备份恢复运行环境（断点、log等），当worker和ftp都配置时，从worker恢复。
 -e 表示仅结束脚本时通过ftp或worker备份环境，中途不备份
 -i 表示断点模式测速，保留speedlog.txt并跳过其中已有测速记录的IP
```

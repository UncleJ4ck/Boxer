#!/usr/bin/bash



clear 
if [ ! -f /usr/bin/nmap ]; then
    echo -e "\e[1;31m[-]\e[0m Nmap is not installed. Installing nmap."
    sudo apt-get -y install nmap
    clear
fi

if [ ! -f /usr/bin/dirb ]; then
    echo -e "\e[1;31m[-]\e[0m Dirb is not installed. Installing dirb."
    sudo apt-get -y install dirb
    clear
fi

if [ ! -f /usr/bin/gobuster ]; then
    echo -e "\e[1;31m[-]\e[0m Gobuster is not installed. Installing gobuster."
    sudo apt-get -y install gobuster
    clear
fi

if [ ! -f /usr/bin/enum4linux ]; then
    echo -e "\e[1;31m[-]\e[0m enum4linux is not installed. Installing enum4linux."
    sudo apt-get install enum4linux
    clear
fi

if [ ! -f /usr/sbin/showmount ]; then 
    echo -e "\e[1;31m[-]\e[0m nfs-common is not installed. Installing nfs-common."
    sudo apt-get install rpcbind nfs-common  
    clear  
fi
 
if [ ! -d "./reports" ]; then 
    mkdir ./reports
else 
    rm -rf ./reports
    mkdir ./reports
fi 

if [ $# -eq 0 ]; then
    echo "Usage: ./boxer.sh <target>"
    exit 1
fi

([ -d "./reports/$1" ] && echo -e "\e[1;31m[-]\e[0m Folder target already exists, creating new one..." && rm -rf ./reports/$1 && mkdir ./reports/$1) || mkdir ./reports/$1

if [[ $1 =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6}$ || $1 =~ ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then 
    echo "  ____   ____"                
    echo " |  _ \ / __ \ "              
    echo " | |_) | |  | |_  _____ _ __ "
    echo " |  _ <| |  | \ \/ / _ \ '__|"
    echo " | |_) | |__| |>  <  __/ |"   
    echo " |____/ \____//_/\_\___|_|"   
    echo
    echo -e "\e[1;32m[+]\e[0m Starting on $1"
else
    echo -e "\e[1;31m[-]\e[0m Invalid domain name."
    exit 1
fi

ping -c 1 $1 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "\e[1;31m[-]\e[0m I can't reach the host: $1! please check you vpn connection."
    exit 1
fi


echo -e "\e[1;32m[+]\e[0m Running nmap scan..."
nmap -sC -sV -p- $1 -oN ./reports/$1/nmap.txt &> /dev/null
echo -e "\e[1;32m[+]\e[0m Getting open ports..."

if [ $(cat ./reports/$1/nmap.txt | grep open | wc -l) -gt 0 ]; then
    cat ./reports/$1/nmap.txt | grep open
else
    echo -e "\e[1;31m[-]\e[0m No open ports found."
    rm -r ./reports/$1
    exit 1
fi

echo 
if [ $(cat ./reports/$1/nmap.txt | grep ftp -m 1 | wc -l) -gt 0 ]; then
    echo -e "\e[1;32m[+]\e[0m FTP service found."
    FTP_PORT=$(cat ./reports/$1/nmap.txt | grep ftp -m 1 | cut -d "/" -f 1)
    echo -e "\e[1;32m[+]\e[0m FTP port: $FTP_PORT"

    echo -e "\e[1;32m[+]\e[0m Checking if FTP anon login is enabled..."
    ftp -n $1 << EOF &>/dev/null
    quote USER Anonymous
    quote PASS Anonymous
    quit
EOF
    if [ $? == "Login incorrect." ]; then
        echo -e "\e[1;31m[-]\e[0m FTP anonymous login is not enabled."
    else
        echo -e "\e[1;32m[+]\e[0m FTP anonymous login is enabled."
    fi
fi

echo   
echo -e "\e[1;32m[+]\e[0m Checking if there is any web server running on the target..."
if [ $(cat ./reports/$1/nmap.txt | grep http | wc -l) -gt 0 ]; then
    for i in $(cat ./reports/$1/nmap.txt | grep open | grep http | cut -d "/" -f 1); do
        echo -e "\e[1;32m[+]\e[0m HTTP port: $i"
        echo -e "\e[1;32m[+]\e[0m Running dirb..."
        dirb http://$1:$i -o ./reports/$1/dirb-$i.txt &> /dev/null
        echo -e "\e[1;32m[+]\e[0m Getting paths from dirb output..."
        if [ $(grep -Eo '(http|https)://[^/"]+/.* ' ./reports/$1/dirb-$i.txt | wc -l) -gt 1 ]; then
            echo -e "\e[1;32m[+]\e[0m Paths found for http://$1:$i/ :"
            grep -Eo '\e[1;32m[*]\e[0m (http|https)://[^/"]+/.* ' ./reports/$1/dirb-$i.txt | sort -u | uniq
        else
            echo -e "\e[1;31m[-]\e[0m No paths found from dirb output."
        fi
    done
else
    echo -e "\e[1;31m[-]\e[0m HTTP services not found"
    exit 1
fi

echo 
echo -e "\e[1;32m[+]\e[0m Running gobuster for vhosts discovery..."
gobuster vhost -u https://$1 -w ./wordlists/vhosts.txt -t 100 -r -m 5 -o ./reports/$1/gobuster_vhosts.txt &> /dev/null

if [ $(cat ./reports/$1/gobuster_vhosts.txt | grep "Found" | wc -l) -gt 0 ]; then
    echo -e "\e[1;32m[+]\e[0m Vhosts found: "
    cat ./reports/$1/gobuster_vhosts.txt | grep "Found" | awk '{print $2}'
    echo -e "\e[1;32m[+]\e[0m Running dirb..."
    for i in $(cat ./reports/$1/gobuster_vhosts.txt | grep "Found" | awk '{print $2}'); do
        dirb http://$i -o ./reports/$1/dirb-$i.txt &> /dev/null
        echo -e "\e[1;32m[+]\e[0m Getting paths from dirb output..."
        if [ $(grep -Eo '(http|https)://[^/"]+/.* ' ./reports/$1/dirb-$i.txt | wc -l) -gt 1 ]; then
            echo -e "\e[1;32m[+]\e[0m Paths found for http://$i/ :"
            grep -Eo '(http|https)://[^/"]+/.* ' ./reports/$1/dirb-$i.txt | sort -u | uniq
        else
            echo -e "\e[1;31m[-]\e[0m No paths found from dirb output."
        fi
    done
else
    echo -e "\e[1;31m[-]\e[0m No vhosts found."
fi




echo 
echo -e "\e[1;32m[+]\e[0m Checking for SMB..."
if [ $(cat ./reports/$1/nmap.txt | grep netbios-ssn | wc -l) -gt 0 ]; then
    for i in $(cat ./reports/$1/nmap.txt | grep open | grep netbios-ssn | cut -d "/" -f 1); do
        SMB=$(cat ./reports/$1/nmap.txt | grep open | grep netbios-ssn | grep 445 | cut -d "/" -f 1)
        echo
        echo -e "\e[1;32m[+]\e[0m SMB found: "
        echo -e "\e[1;32m[+]\e[0m SMB port: $i / $SMB"
    echo -e "\e[1;32m[+]\e[0m Running Enum4Linux..."
    enum4linux $1 -a &> ./reports/$1/enum-smb-$1.txt
    echo  
    echo -e "\e[1;32m[*]\e[0m Do you want to see the report ?"
    echo -e "\e[1;32m[*]\e[0m 1) Yes "
    echo -e "\e[1;32m[*]\e[0m 2) No "
    echo -e "\e[1;32m[*]\e[0m Option: "; read option
    case $option in

    Yes | yes | 1)
    head ./reports/$1/enum.txt 
    ;;

    No | no | 2)
    echo -e "\e[1;32m[+]\e[0m Let's go to the next service"
    ;;

    *) 
    echo -e "\e[1;31m[-]\e[0m Invalid answer! Please try again!"
    ;;
    esac
    done
else
    echo -e "\e[1;31m[-]\e[0m SMB service not found"
fi

echo 
echo -e "\e[1;32m[+]\e[0m Checking for NFS..."
    if [ $(cat ./reports/$1/nmap.txt | grep nfs | wc -l) -gt 0 ]; then
        for i in $(cat ./reports/$1/nmap.txt | grep open | grep nfs | cut -d "/" -f 1); do    
            echo -e "\e[1;32m[+]\e[0m NFS found: "
            echo -e "\e[1;32m[+]\e[0m NFS port: $i"
            showmount -e $1 
        done 
    else 
            echo -e "\e[1;31m[-]\e[0m No NFS Shares found."
fi 

echo 
echo -e "\e[1;32m[+]\e[0m Checking for MySQL..."
nmap -sV -p3306 --script=mysql-enum,mysql-databases,mysql-brute,mysql-users,mysql-audit,mysql-dump-hashes,mysql-empty-password,mysql-enum,mysql-info,mysql-query,mysql-variables $1 -oN ./reports/$1/nmap-mysql.txt &> /dev/null
    if [[ $(cat ./reports/$1/nmap-mysql.txt | grep mysql) = "0" ]]; then
        for i in $(cat ./reports/$1/nmap-mysql.txt | grep open | grep mysql | cut -d "/" -f 1); do    
            echo -e "\e[1;32m[+]\e[0m MySQL found: "
            echo -e "\e[1;32m[+]\e[0m MySQL port: $i"
            echo -e "\e[1;32m[+]\e[0m Getting all infos about MySQL..."
            echo 
            cat ./reports/$1/nmap-mysql.txt | grep "|"
            echo 
        done 
    else 
            echo -e "\e[1;31m[-]\e[0m MySQL services not found"
fi 


echo 
echo -e "\e[1;32m[+]\e[0m Checking for RDP..."
nmap -sV --script=rdp-enum-encryption,rdp-vuln-ms12-020,rdp-ntlm-info -p3389 -T4 $1 -oN ./reports/$1/nmap-rdp.txt &> /dev/null
    if [[ "$(cat ./reports/$1/nmap-rdp.txt | grep ms-wbt-server)" = "0" ]]; then
        for i in $(cat ./reports/$1/nmap-rdp.txt | grep open | grep ms-wbt-server | cut -d "/" -f 1); do    
            echo -e "\e[1;32m[+]\e[0m RDP found: "
            echo -e "\e[1;32m[+]\e[0m RDP port: $i"
            echo -e "\e[1;32m[+]\e[0m Getting all infos about RDP..."
            echo 
            cat ./reports/$1/nmap-rdp.txt | grep "|"
            echo 
        done 
    else 
            echo -e "\e[1;31m[-]\e[0m RDP service not found"
fi 


echo 
echo -e "\e[1;32m[+]\e[0m Checking for Telnet..."
nmap -sV --script telnet-encryption,telnet-ntlm-info,telnet-brute --script-args userdb=myusers.lst,passdb=mypwds.lst,telnet-brute.timeout=8s -p23,8012 -vvv $1 -oN ./reports/$1/nmap-telnet.txt &> /dev/null
    if [[ "$(cat ./reports/$1/nmap-telnet.txt | grep -E 'open | closed'| grep -E 'telnet | unknown')" = "0" ]]; then
        for i in $(cat ./reports/$1/nmap-telnet.txt | grep -E 'open | closed'| grep -E 'telnet | unknown'); do  
            TLN=$(cat ./reports/$1/nmap-telnet.txt  | grep -E 'open | closed' | grep 8012 | cut -d "/" -f 1)
            echo -e "\e[1;32m[+]\e[0m Telnet found: "
            echo -e "\e[1;32m[+]\e[0m Telnet port: $i/$TLN"
            echo -e "\e[1;32m[+]\e[0m Getting all infos about Telnet..."
            echo 
            cat ./reports/$1/nmap-telnet.txt | grep "|"
            echo 
        done 
    else 
            echo -e "\e[1;31m[-]\e[0m Telnet service not found"
fi 

echo
echo -e "\e[1;32m[*]\e[0m You can check the report at the reports/$1 directory"
echo -e "\e[1;32m[*]\e[0m Good Hacking !"
exit 0
#!/usr/bin/bash

clear 

RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'

check_tool_installed () {
    if ! command -v $1 &> /dev/null
    then
        echo -e "${RED}[-]${NC} $1 is not installed. Installing $1."
        if sudo apt-get -y install $1
        then
            echo -e "${GREEN}[+]${NC} $1 is now installed."
            clear
        else
            echo -e "${RED}[-]${NC} Failed to install $1."
            exit 1
        fi
    fi
}

REQUIRED_TOOLS=("nmap" "dirb" "gobuster" "enum4linux" "amass")
for tool in "${REQUIRED_TOOLS[@]}"; do
   check_tool_installed "$tool"
done

if [ ! -f /usr/sbin/showmount ]; then 
    echo -e "${RED}[-]${NC} nfs-common is not installed. Installing nfs-common."
    if ! sudo apt-get install rpcbind nfs-common 
    then
        echo -e "${RED}[-]${NC} Failed to install rpcbind or nfs-common."
        exit 1
    fi
    clear  
fi

REPORT_DIR="./reports"
if [ ! -d "$REPORT_DIR" ]; then 
    mkdir "$REPORT_DIR"
else 
    rm -rf "$REPORT_DIR"/*
fi 

if [ $# -eq 0 ]; then
    echo "Usage: ./boxer.sh <target>"
    exit 1
fi

TARGET_DIR="$REPORT_DIR/$1"
mkdir -p "$TARGET_DIR"

if [[ $1 =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6}$ || $1 =~ ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then 
    echo "  ____   ____"                
    echo " |  _ \ / __ \ "              
    echo " | |_) | |  | |_  _____ _ __ "
    echo " |  _ <| |  | \ \/ / _ \ '__|"
    echo " | |_) | |__| |>  <  __/ |"   
    echo " |____/ \____//_/\_\___|_|"   
    echo
    echo -e "${GREEN}[+]${NC} Starting on $1"
else
    echo -e "${RED}[-]${NC} Invalid domain name."
    exit 1
fi

ping -c 1 $1 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}[-]${NC} I can't reach the host: $1! Please check your VPN connection."
    exit 1
fi

echo -e "${GREEN}[+]${NC} Running nmap scan..."
nmap -p- $1 -oN "$TARGET_DIR/nmap.txt" &> /dev/null
echo -e "${GREEN}[+]${NC} Getting open ports..."

if [ $(cat "$TARGET_DIR/nmap.txt" | grep open | wc -l) -gt 0 ]; then
    cat "$TARGET_DIR/nmap.txt" | grep open
else
    echo -e "${RED}[-]${NC} No open ports found."
    rm -r "$TARGET_DIR"
    exit 1
fi

if [ $(cat ./reports/$1/nmap.txt | grep open | wc -l) -gt 0 ]; then
    cat ./reports/$1/nmap.txt | grep open
else
    echo -e "\e[1;31m[-]\e[0m No open ports found."
    rm -r ./reports/$1
    exit 1
fi

echo 
if [ $(cat "./reports/$1/nmap.txt" | grep ftp -m 1 | wc -l) -gt 0 ]; then
    echo -e "${GREEN}[+]${NC} FTP service found."
    FTP_PORT=$(cat "./reports/$1/nmap.txt" | grep ftp -m 1 | cut -d "/" -f 1)
    echo -e "${GREEN}[+]${NC} FTP port: $FTP_PORT"

    echo -e "${GREEN}[+]${NC} Checking if FTP anon login is enabled..."
    FTP_RESPONSE=$(ftp -n -v $1 2>&1 << EOF
    quote USER Anonymous
    quote PASS Anonymous
    quit
EOF
    )
    if echo "$FTP_RESPONSE" | grep -q "Login incorrect."; then
        echo -e "${RED}[-]${NC} FTP anonymous login is not enabled."
    else
        echo -e "${GREEN}[+]${NC} FTP anonymous login is enabled."
    fi

fi

echo   
echo -e "${GREEN}[+]${NC} Checking if there is any web server running on the target..."
if [ $(cat "./reports/$1/nmap.txt" | grep http | wc -l) -gt 0 ]; then
    for i in $(cat "./reports/$1/nmap.txt" | grep open | grep http | cut -d "/" -f 1); do
        echo -e "${GREEN}[+]${NC} HTTP port: $i"
        echo -e "${GREEN}[+]${NC} Running dirb..."
        dirb http://$1:$i -o "./reports/$1/dirb-$i.txt" &> /dev/null
        echo -e "${GREEN}[+]${NC} Getting paths from dirb output..."
        if [ $(grep -Eo '(http|https)://[^/"]+/.* ' "./reports/$1/dirb-$i.txt" | wc -l) -gt 1 ]; then
            echo -e "${GREEN}[+]${NC} Paths found for http://$1:$i/ :"
            grep -Eo '(http|https)://[^/"]+/.* ' "./reports/$1/dirb-$i.txt" | sort -u | uniq
        else
            echo -e "${RED}[-]${NC} No paths found from dirb output."
        fi
    done
else
    echo -e "${RED}[-]${NC} HTTP services not found"
    exit 1
fi

echo 
echo -e "${GREEN}[+]${NC} Running gobuster for vhosts discovery..."
gobuster vhost -u https://$1 -w ./wordlists/vhosts.txt -t 100 -r -m 5 -o "./reports/$1/gobuster_vhosts.txt" &> /dev/null

if [ $(cat "./reports/$1/gobuster_vhosts.txt" | grep "Found" | wc -l) -gt 0 ]; then
    echo -e "${GREEN}[+]${NC} Vhosts found: "
    cat "./reports/$1/gobuster_vhosts.txt" | grep "Found" | awk '{print $2}'
    echo -e "${GREEN}[+]${NC} Running dirb..."
    for i in $(cat "./reports/$1/gobuster_vhosts.txt" | grep "Found" | awk '{print $2}'); do
        dirb http://$i -o "./reports/$1/dirb-$i.txt" &> /dev/null
        echo -e "${GREEN}[+]${NC} Getting paths from dirb output..."
        if [ $(grep -Eo '(http|https)://[^/"]+/.* ' "./reports/$1/dirb-$i.txt" | wc -l) -gt 1 ]; then
            echo -e "${GREEN}[+]${NC} Paths found for http://$i/ :"
            grep -Eo '(http|https)://[^/"]+/.* ' "./reports/$1/dirb-$i.txt" | sort -u | uniq
        else
            echo -e "${RED}[-]${NC} No paths found from dirb output."
        fi
    done
else
    echo -e "${RED}[-]${NC} No vhosts found."
fi

echo
echo -e "${GREEN}[+]${NC} Adding the amass effect++..."
amass enum -d $1 -o "./reports/$1/amass.txt" &> /dev/null
if [ $(cat "./reports/$1/amass.txt" | wc -l) -gt 0 ]; then
    echo -e "${GREEN}[+]${NC} Subdomains found: "
    cat "./reports/$1/amass.txt"
else
    echo -e "${RED}[-]${NC} No subdomains found."
fi

echo 
echo -e "${GREEN}[+]${NC} Checking for SSH..."
nmap -sV --script ssh-hostkey,sshv1,ssh-auth-methods,ssh-brute --script-args userdb=myusers.lst,passdb=mypwds.lst,ssh-brute.timeout=8s -p22 $1 -oN ./reports/$1/nmap-ssh.txt &> /dev/null
if [ $(grep -c ssh ./reports/$1/nmap-ssh.txt) -gt 0 ]; then
    for i in $(grep ssh ./reports/$1/nmap-ssh.txt | grep open | cut -d "/" -f 1); do  
        echo -e "${GREEN}[+]${NC} SSH found: "
        echo -e "${GREEN}[+]${NC} SSH port: $i"
        echo -e "${GREEN}[+]${NC} Getting all infos about SSH..."
        echo 
        cat ./reports/$1/nmap-ssh.txt | grep "|"
        echo 
    done 
else 
    echo -e "${RED}[-]${NC} SSH service not found"
fi 

echo 
echo -e "${GREEN}[+]${NC} Checking for SMB..."
if [ $(cat "./reports/$1/nmap.txt" | grep netbios-ssn | wc -l) -gt 0 ]; then
    for i in $(cat "./reports/$1/nmap.txt" | grep open | grep netbios-ssn | cut -d "/" -f 1); do
        SMB=$(cat "./reports/$1/nmap.txt" | grep open | grep netbios-ssn | grep 445 | cut -d "/" -f 1)
        echo
        echo -e "${GREEN}[+]${NC} SMB found: "
        echo -e "${GREEN}[+]${NC} SMB port: $i / $SMB"
        echo -e "${GREEN}[+]${NC} Running Enum4Linux..."
        enum4linux $1 -a &> "./reports/$1/enum-smb-$1.txt"
        echo  
        echo -e "${GREEN}[*]${NC} Do you want to see the report ?"
        echo -e "${GREEN}[*]${NC} 1) Yes "
        echo -e "${GREEN}[*]${NC} 2) No "
        echo -e "${GREEN}[*]${NC} Option: "; read option
        case $option in

        Yes | yes | 1)
        head "./reports/$1/enum-smb-$1.txt" 
        ;;

        No | no | 2)
        echo -e "${GREEN}[+]${NC} Let's go to the next service"
        ;;

        *) 
        echo -e "${RED}[-]${NC} Invalid answer! Please try again!"
        ;;
        esac
    done
else
    echo -e "${RED}[-]${NC} SMB service not found"
fi

echo 
echo -e "${GREEN}[+]${NC} Checking for NFS..."
    if [ $(cat "./reports/$1/nmap.txt" | grep nfs | wc -l) -gt 0 ]; then
        for i in $(cat "./reports/$1/nmap.txt" | grep open | grep nfs | cut -d "/" -f 1); do    
            echo -e "${GREEN}[+]${NC} NFS found: "
            echo -e "${GREEN}[+]${NC} NFS port: $i"
            showmount -e $1 
        done 
    else 
            echo -e "${RED}[-]${NC} No NFS Shares found."
fi 

e
echo 
echo -e "${GREEN}[+]${NC} Checking for MySQL..."
nmap -sV -p3306 --script=mysql-enum,mysql-databases,mysql-brute,mysql-users,mysql-audit,mysql-dump-hashes,mysql-empty-password,mysql-enum,mysql-info,mysql-query,mysql-variables $1 -oN ./reports/$1/nmap-mysql.txt &> /dev/null
    if [[ $(cat ./reports/$1/nmap-mysql.txt | grep mysql | wc -l) -gt 0 ]]; then
        for i in $(cat ./reports/$1/nmap-mysql.txt | grep open | grep mysql | cut -d "/" -f 1); do    
            echo -e "${GREEN}[+]${NC} MySQL found: "
            echo -e "${GREEN}[+]${NC} MySQL port: $i"
            echo -e "${GREEN}[+]${NC} Getting all infos about MySQL..."
            echo 
            cat ./reports/$1/nmap-mysql.txt | grep "|"
            echo 
        done 
    else 
            echo -e "${RED}[-]${NC} MySQL services not found"
fi 

echo 
echo -e "${GREEN}[+]${NC} Checking for RDP..."
nmap -sV --script=rdp-enum-encryption,rdp-vuln-ms12-020,rdp-ntlm-info -p3389 -T4 $1 -oN ./reports/$1/nmap-rdp.txt &> /dev/null
    if [[ $(cat ./reports/$1/nmap-rdp.txt | grep ms-wbt-server | wc -l) -gt 0 ]]; then
        for i in $(cat ./reports/$1/nmap-rdp.txt | grep open | grep ms-wbt-server | cut -d "/" -f 1); do    
            echo -e "${GREEN}[+]${NC} RDP found: "
            echo -e "${GREEN}[+]${NC} RDP port: $i"
            echo -e "${GREEN}[+]${NC} Getting all infos about RDP..."
            echo 
            cat ./reports/$1/nmap-rdp.txt | grep "|"
            echo 
        done 
    else 
            echo -e "${RED}[-]${NC} RDP service not found"
fi 


echo 
echo -e "${GREEN}[+]${NC} Checking for Telnet..."
nmap -sV --script telnet-encryption,telnet-ntlm-info,telnet-brute --script-args userdb=myusers.lst,passdb=mypwds.lst,telnet-brute.timeout=8s -p23,8012 -vvv $1 -oN ./reports/$1/nmap-telnet.txt &> /dev/null
    if [[ $(cat ./reports/$1/nmap-telnet.txt | grep -E 'open|closed' | grep -E 'telnet|unknown' | wc -l) -gt 0 ]]; then
        for i in $(cat ./reports/$1/nmap-telnet.txt | grep -E 'open|closed' | grep -E 'telnet|unknown' | cut -d "/" -f 1); do  
            TLN=$(cat ./reports/$1/nmap-telnet.txt  | grep -E 'open|closed' | grep 8012 | cut -d "/" -f 1)
            echo -e "${GREEN}[+]${NC} Telnet found: "
            echo -e "${GREEN}[+]${NC} Telnet port: $i/$TLN"
            echo -e "${GREEN}[+]${NC} Getting all infos about Telnet..."
            echo 
            cat ./reports/$1/nmap-telnet.txt | grep "|"
            echo 
        done 
    else 
            echo -e "${RED}[-]${NC} Telnet service not found"
fi 


echo
echo -e "\e[1;32m[*]\e[0m You can check the report at the reports/$1 directory"
echo -e "\e[1;32m[*]\e[0m Good Hacking !"
exit 0

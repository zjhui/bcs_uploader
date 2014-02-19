#!/usr/bin/env bash

eerror() { echo "!!! $*" 1>&2; }
einfo() { echo "* $*"; }

type curl > /dev/null 2>&1 || eerror "请先确认是否安装了 curl"

RESPONSE_FILE=/tmp/pcs_$RANDOM
CONFIG_FILE=~/.pcs_uploader

API_CODE_URL="https://openapi.baidu.com/oauth/2.0/device/code"
API_TOKEN_URL="https://openapi.baidu.com/oauth/2.0/token"

# 去除文件名前后的空格
function trim {
    sed -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*\$//g'
}

# 判断是目录还是文件
function pcs_stat {
    local FILE="$1"
    curl -s --show-error --globoff -i -k -L "https://pcs.baidu.com/rest/2.0/pcs/file?method=meta&access_token=$ACCESS_TOKEN&path=/apps/$APP_FOLDER/$FILE" -o $RESPONSE_FILE
    if grep -q "HTTP/1.1 404 Not Found" $RESPONSE_FILE;then
        eerror "文件不存在，请检查输入的文件名是否正确或该文件是否已经被删除！"
    fi
    grep -q "^HTTP/1.1 200 OK" $RESPONSE_FILE > /dev/null 2>&1
    if [ $? -eq 0 ];then
        local IS_DIR=
    fi
}

# ACCESS_TOKEN过期后重新刷新
function refresh_access_token() {
    curl -k -L -d "grant_type=refresh_token&refresh_token=$REFRESH_TOKEN&client_id=$APIKEY&client_secret=$SECRETKEY" \
"https://openapi.baidu.com/oauth/2.0/token" -o $RESPONSE_FILE
    REFRESH_TOKEN=`awk -F\" '{print $6}' $RESPONSE_FILE`
    ACCESS_TOKEN=`awk -F\" '{print $10}' $RESPONSE_FILE`
    # 替换旧的 access_token
    sed -i "s/ACCESS_TOKEN=[0-9 A-Z a-z].*/ACCESS_TOKEN=$ACCESS_TOKEN/g" $CONFIG_FILE
    # 替换旧的 refresh_token
    sed -i "s/REFRESH_TOKEN=[0-9 A-Z a-z].*/REFRESH_TOKEN=$REFRESH_TOKEN/g" $CONFIG_FILE
}

# 上传单个小于2G的文件
function pcs_upload_small_file {
    local SRC="$1"
    local DST="$2"
    curl -s --show-error --globoff -i -k -L -F "file=@$SRC" "https://c.pcs.baidu.com/rest/2.0/pcs/file?method=upload&path=/apps/$APP_FOLDER/$DST&access_token=$ACCESS_TOKEN" -o $RESPONSE_FILE
    grep -q "^HTTP/1.1 200 OK" $RESPONSE_FILE > /dev/null 2>&1
    if [ $? -eq 0 ];then
        einfo "$SRC上传成功！" 
    else
        eerror "上传失败！"
        eerror "具体的错误信息，请查看$RESPONSE_FILE"
    fi
}

# 上传大于2G的文件
#function pcs_upload_large_file {
#       
#}

# 下载文件
function pcs_download_file {
    local FILE="$1"
    local DST="$2"

    # 当DST参数未提供时，默认在当前的文件夹下
    if [[ $DST == "" ]];then
        DST=`pwd`
    fi

    [ ! -d $DST ] && mkdir -p "$DST"
    einfo "将下载 $FILE 到 $DST..."
    curl -s --show-error --globoff -i -k -L "https://d.pcs.baidu.com/rest/2.0/pcs/file?method=download&access_token=$ACCESS_TOKEN&path=/apps/$APP_FOLDER/$FILE" -o $DST/$FILE -D $RESPONSE_FILE
    grep -q "^HTTP/1.1 200 OK" $RESPONSE_FILE > /dev/null 2>&1
    if [ $? -eq 0 ];then
        einfo "下载成功！"
    else
        eerror "下载失败，请查看$RESPONSE_FILE..."
    fi
}

# 创建目录
function pcs_mkdir {
    local DST_DIR="$1"
    #修正目录的格式，去除前后的空格
    DST_DIR=`echo "$DST_DIR" | trim`
    einfo "即将创建文件夹/apps/$APP_FOLDER/$DST_DIR..."
    curl -s --show-error --globoff -i -k -L "https://pcs.baidu.com/rest/2.0/pcs/file?method=mkdir&access_token=$ACCESS_TOKEN&path=/apps/$APP_FOLDER/$DST_DIR" -o $RESPONSE_FILE
    grep -q "^HTTP/1.1 200 OK" $RESPONSE_FILE > /dev/null 2>&1
    if [ $? -eq 0 ];then
        einfo "$DST_DIR创建成功！"
    else
        eerror "创建文件夹失败，请查看$RESPONSE_FILE"
    fi
}

# 删除文件/目录
function pcs_delete {
    local DST_DIR="$1"
    read -p "删除/apps/$APP_FOLDER/$DST_DIR ? [y/n] " ans
    case "${ans}" in
        [Yy][Ee][Ss]|[Yy]|"")
            : ;;
        *)
            einfo "Right. Aborting..."
            exit 1
            ;;
    esac
    curl -s --show-error --globoff -i -k -L "https://pcs.baidu.com/rest/2.0/pcs/file?method=delete&access_token=$ACCESS_TOKEN&path=/apps/$APP_FOLDER/$DST_DIR" -o $RESPONSE_FILE
    grep -q "^HTTP/1.1 200 OK" $RESPONSE_FILE > /dev/null 2>&1
    if [ $? -eq 0 ];then
        einfo "$DST_DIR删除成功！"
    else
        eerror "删除失败，请查看$RESPONSE_FILE! "
    fi
}

# 完成一些初始化配置
if [ -f $CONFIG_FILE ];then
    source $CONFIG_FILE
else
    while (true); do
        echo -n "# API KEY: "
        read APIKEY
    
        echo -n "# Secret Key: "
        read SECRETKEY

        echo -n "# App Folder: "
        read APP_FOLDER
    
        read -p "API KEY $APIKEY? Secret Key $SECRETKEY?[y/n]" ans
        if [[ $ans == "y" || $ans == "Y" ]]; then
            break;
        fi
    done
    
    # 获得当前程序运行的路径,from: http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
    DIR="$( cd "$( dirname "$0" )" && pwd )" 

    # 通过APIKEY获得device_code和user_code
    einfo "获取code中..."
    curl -s -k -L -d "client_id=$APIKEY&response_type=device_code&scope=basic,netdisk" $API_CODE_URL -o $RESPONSE_FILE 
#    DEVICE_CODE=`awk -F\" '{print $4}' $RESPONSE_FILE`
#    USER_CODE=`awk -F\" '{print $8}' $RESPONSE_FILE`
    DEVICE_CODE=${tail -1 $RESPONSE_FILE | bash /$DIR/JSON.sh/JSON.sh -l | awk '/device_code/{print $2}' | tr -d \"}
    USER_CODE=${tail -1 $RESPONSE_FILE | bash /$DIR/JSON.sh/JSON.sh -l | awk '/user_code/{print $2}' | tr -d \"}
    while (true);do
        einfo "请打开链接 http://openapi.baidu.com/device?code=$USER_CODE&display=page&force_login= 点击授权。"
        einfo "完成后请按回车"
        read
    
        einfo "获取access_token和refresh_token..."
        curl -s -k -L -d "grant_type=device_token&code=$DEVICE_CODE&client_id=$APIKEY&client_secret=$SECRETKEY" $API_TOKEN_URL -o $RESPONSE_FILE
#       cat $RESPONSE_FILE
#       REFRESH_TOKEN=`awk -F\" '{print $6}' $RESPONSE_FILE`
        REFRESH_TOKEN=${tail -1 $RESPONSE_FILE | bash /$DIR/JSON.sh/JSON.sh -l | awk '/refresh_token/{print $2}' | tr -d \"}
        echo $REFRESH_TOKEN
#        ACCESS_TOKEN=`awk -F\" '{print $10}' $RESPONSE_FILE`
        ACCESS_TOKEN=${tail -1 $RESPONSE_FILE | bash /$DIR/JSON.sh/JSON.sh -l | awk '/access_token/{print $2}' | tr -d \"}
        echo $ACCESS_TOKEN
        if [[ $REFRESH_TOKEN != "" && $ACCESS_TOKEN != "" ]];then
            einfo "ok\n"
            echo "APIKEY=$APIKEY" >> "$CONFIG_FILE"
            echo "SECRETKEY=$SECRETKEY" >> "$CONFIG_FILE"
            echo "APP_FOLDER"=$APP_FOLDER >> "$CONFIG_FILE"
            echo "ACCESS_TOKEN=$ACCESS_TOKEN" >> "$CONFIG_FILE"
            echo "REFRESH_TOKEN=$REFRESH_TOKEN" >> "$CONFIG_FILE"
            einfo "设置完成\n"
            break
        else
            eerror "Failed!\n"
        fi
    done
fi


# 开始
COMMAND=${@:$OPTIND:1}
ARG1=${@:$OPTIND+1:1}
ARG2=${@:$OPTIND+2:1}

case $COMMAND in
    upload)
        FILE_SRC=$ARG1
        FILE_DST=$ARG2
        pcs_upload_small_file "$FILE_SRC" "$FILE_DST"
    ;;
    download)
        FILE_SRC=$ARG1
        FILE_DST=$ARG2
        if [[ $FILE_SRC == "" ]];then
            eerror "请输入要下载的文件。"
            exit 1
        fi
        pcs_download_file "$FILE_SRC" "$FILE_DST"
    ;;
    mkdir)
        DIR_DST=$ARG1
        pcs_mkdir "$DIR_DST"
    ;;
    delete)
        FILE_DST=$ARG1
        pcs_delete "$FILE_DST"
    ;;
    stat)
        FILE_DST=$ARG1
        pcs_stat "$FILE_DST"
    ;;
esac

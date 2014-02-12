pcs_uploader
============

Author: zjhui  
Email: jiahui.tar.gz@gmail.com  

首先，你应该知道通过这个脚本只能操作百度网盘下*我的应用数据 > APP文件夹*  
*使用方法*: 
    bash Pcs_Uploader.sh COMMAND ...  
COMMAND:
    * upload <LOCAL_FILE> <REMOTE_FILE>  
    上传本地文件到PCS。目前只能上传小于2G的文件  
      
    * download <REMOTE_FILE> [LOCAL_FILE]  
    下载PCS端文件到本地。如果没有指定本地文件夹，默认将下载到当前目录  

    * mkdir <REMOTE_DIR>  
    在PCS端创建文件夹


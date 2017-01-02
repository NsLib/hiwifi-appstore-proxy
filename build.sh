#!/bin/sh

appname=hiwifi-appstore-proxy

(cd $appname && tar -czvf ${appname}.tgz * && mv ${appname}.tgz ../)
[ $? -eq 0 ] && echo "Done: ${appname}.tgz"

#!/bin/sh

# 构建脚本：自动打包 Box 模块为 zip 文件
VERSION=$(cat module.prop | grep 'version=' | awk -F '=' '{print $2}' | tr -d '\r')
zip -r -o -X -ll box-${VERSION}.zip ./ -x '.git/*' -x 'CHANGELOG.md' -x 'update.json' -x 'build.sh' -x '.github/*' -x 'LICENSE'
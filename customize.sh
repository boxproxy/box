
#!/system/bin/sh

SKIPUNZIP=1
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

if [ "$BOOTMODE" != true ]; then
  abort "-----------------------------------------------------------"
  ui_print "! 请在 Magisk/KernelSU/APatch Manager 中安装本模块"
  ui_print "! 不支持从 Recovery 安装"
  abort "-----------------------------------------------------------"
elif [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
  abort "-----------------------------------------------------------"
  ui_print "! 请升级您的 KernelSU 及其管理器"
  abort "-----------------------------------------------------------"
fi

service_dir="/data/adb/service.d"
if [ "$KSU" = "true" ]; then
  ui_print "- 检测到 KernelSU 版本: $KSU_VER ($KSU_VER_CODE)"
  [ "$KSU_VER_CODE" -lt 10683 ] && service_dir="/data/adb/ksu/service.d"
elif [ "$APATCH" = "true" ]; then
  APATCH_VER=$(cat "/data/adb/ap/version")
  ui_print "- 检测到 APatch 版本: $APATCH_VER"
else
  ui_print "- 检测到 Magisk 版本: $MAGISK_VER ($MAGISK_VER_CODE)"
fi

mkdir -p "${service_dir}"
if [ -d "/data/adb/modules/box_for_magisk" ]; then
  rm -rf "/data/adb/modules/box_for_magisk"
  ui_print "- 已删除旧模块。"
fi

ui_print "- 正在安装 Box for Magisk/KernelSU/APatch"
unzip -o "$ZIPFILE" -x 'META-INF/*' -x 'webroot/*' -d "$MODPATH" >&2
if [ -d "/data/adb/box" ]; then
  ui_print "- 备份现有 box 数据"
  temp_bak=$(mktemp -d -p "/data/adb/box" box.XXXXXXXXXX)
  temp_dir="${temp_bak}"
  mv /data/adb/box/* "${temp_dir}/"
  mv "$MODPATH/box/"* /data/adb/box/
  backup_box="true"
else
  mv "$MODPATH/box" /data/adb/
fi

ui_print "- 创建目录"
mkdir -p /data/adb/box/ /data/adb/box/run/ /data/adb/box/bin/

ui_print "- 提取 uninstall.sh 和 box_service.sh"
unzip -j -o "$ZIPFILE" 'uninstall.sh' -d "$MODPATH" >&2
unzip -j -o "$ZIPFILE" 'box_service.sh' -d "${service_dir}" >&2

ui_print "- 设置权限"
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm_recursive /data/adb/box/ 0 3005 0755 0644
set_perm_recursive /data/adb/box/scripts/ 0 3005 0755 0700
set_perm ${service_dir}/box_service.sh 0 0 0755
set_perm $MODPATH/uninstall.sh 0 0 0755
chmod ugo+x ${service_dir}/box_service.sh $MODPATH/uninstall.sh /data/adb/box/scripts/*

KEY_LISTENER_PID=""
KEY_FIFO=""

start_key_listener() {
    if [ -n "$KEY_LISTENER_PID" ] && kill -0 "$KEY_LISTENER_PID" 2>/dev/null; then
        return
    fi
    KEY_FIFO=$(mktemp -u -p /dev/tmp)
    mkfifo "$KEY_FIFO" || exit 1
    getevent -ql > "$KEY_FIFO" &
    KEY_LISTENER_PID=$!
}

stop_key_listener() {
    if [ -n "$KEY_LISTENER_PID" ]; then
        kill "$KEY_LISTENER_PID" >/dev/null 2>&1
        KEY_LISTENER_PID=""
    fi
    if [ -n "$KEY_FIFO" ]; then
        rm -f "$KEY_FIFO"
        KEY_FIFO=""
    fi
}

volume_key_detection() {
    local timeout_seconds="${1:-0}"
    local detection_result_file=$(mktemp -u -p /dev/tmp)
    
    (
        while read -r line; do
            if echo "$line" | grep -Eiq "(KEY_)?VOLUME ?UP|KEYCODE_VOLUME_UP" && echo "$line" | grep -Eiq "DOWN|PRESS"; then
                echo "0" > "$detection_result_file"
                exit 0
            elif echo "$line" | grep -Eiq "(KEY_)?VOLUME ?DOWN|KEYCODE_VOLUME_DOWN" && echo "$line" | grep -Eiq "DOWN|PRESS"; then
                echo "1" > "$detection_result_file"
                exit 0
            fi
        done < "$KEY_FIFO"
    ) &
    local detection_pid=$!
    
    if [ "$timeout_seconds" -gt 0 ]; then
        (
            sleep "$timeout_seconds"
            if kill -0 "$detection_pid" 2>/dev/null; then
                kill "$detection_pid" 2>/dev/null
                echo "2" > "$detection_result_file"
            fi
        ) &
        local timeout_pid=$!
        
        wait "$detection_pid" 2>/dev/null
        kill "$timeout_pid" 2>/dev/null
        wait "$timeout_pid" 2>/dev/null
    else
        wait "$detection_pid" 2>/dev/null
    fi
    
    if [ -f "$detection_result_file" ]; then
        local result=$(cat "$detection_result_file")
        rm -f "$detection_result_file"
        return "$result"
    fi
    
    rm -f "$detection_result_file"
    return 2
}

handle_choice() {
    local question="$1"
    local choice_yes="${2:-是}"
    local choice_no="${3:-否}"
    local timeout_seconds="${4:-10}"

    ui_print " "
    ui_print "-----------------------------------------------------------"
    ui_print "- ${question}"
    ui_print "- [ 音量加(+) ]: ${choice_yes}"
    ui_print "- [ 音量减(-) ]: ${choice_no}"
    ui_print "- [ ${timeout_seconds}秒内未选择将默认选择: ${choice_yes} ]"

    timeout 0.1 getevent -c 1 >/dev/null 2>&1

    start_key_listener
    volume_key_detection "$timeout_seconds"
    local result=$?
    stop_key_listener
    
    if [ "$result" -eq 0 ]; then
        ui_print "  => 您选择了: ${choice_yes}"
        return 0
    elif [ "$result" -eq 1 ]; then
        ui_print "  => 您选择了: ${choice_no}"
        return 1
    else
        ui_print "  => 超时未选择，默认选择: ${choice_yes}"
        return 0
    fi
}

ui_print " "
ui_print "==========================================================="
ui_print "==         Box for Magisk/KernelSU/APatch 安装程序         =="
ui_print "==========================================================="


if handle_choice "是否需要下载内核或数据文件？" "是，进行下载" "否，全部跳过"; then

    if handle_choice "是否使用镜像加速接下来的下载？" "使用加速" "直接下载"; then
        ui_print "- 已启用镜像加速。"
        sed -i 's/use_ghproxy=.*/use_ghproxy="true"/' /data/adb/box/settings.ini
    else
        ui_print "- 已禁用镜像加速。"
        sed -i 's/use_ghproxy=.*/use_ghproxy="false"/' /data/adb/box/settings.ini
    fi

    COMPONENTS_TO_DOWNLOAD=""

    if handle_choice "是否需要自定义下载内容？" "自定义" "一键下载所有组件"; then
        ui_print "- 进入自定义下载..."
        if handle_choice "是否下载 GeoX 数据文件 (geoip/geosite)？" "下载" "跳过"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD geox"
        fi
        if handle_choice "是否下载实用工具 (yq, curl)？" "下载" "跳过"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD utils"
        fi
        
        ui_print " "
        ui_print "-----------------------------------------------------------"
        ui_print "- 请选择您需要下载的内核:"
        if handle_choice "  - 下载 sing-box 内核？" "下载" "跳过"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD sing-box"
        fi
        if handle_choice "  - 下载 mihomo 内核？" "下载" "跳过"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD mihomo"
        fi
        if handle_choice "  - 下载 mihomo_smart (带Smart策略组) 内核？（与mihomo冲突，请勿同时下载）" "下载" "跳过"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD mihomo_smart"
        fi
        if handle_choice "  - 下载 xray 内核？" "下载" "跳过"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD xray"
        fi
        if handle_choice "  - 下载 v2fly 内核？" "下载" "跳过"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD v2fly"
        fi
        if handle_choice "  - 下载 hysteria 内核？" "下载" "跳过"; then
            COMPONENTS_TO_DOWNLOAD="$COMPONENTS_TO_DOWNLOAD hysteria"
        fi
    else
        ui_print "- 已选择一键下载所有组件。"
        COMPONENTS_TO_DOWNLOAD="geox utils sing-box mihomo xray v2fly hysteria"
    fi

    ui_print " "
    ui_print "==========================================================="
    ui_print "- 下载任务预览"
    ui_print "-----------------------------------------------------------"
    
    if [ -z "$COMPONENTS_TO_DOWNLOAD" ]; then
        ui_print "  - 无任何下载任务。"
    else
        COMPONENTS_TO_DOWNLOAD=$(echo "$COMPONENTS_TO_DOWNLOAD" | sed 's/^ *//')
        ui_print "  - 将要下载: ${COMPONENTS_TO_DOWNLOAD}"
    fi
    ui_print "==========================================================="

    if [ -n "$COMPONENTS_TO_DOWNLOAD" ]; then
        if handle_choice "是否开始执行以上下载任务？" "开始下载" "取消全部"; then
            ui_print "- 开始执行下载..."
            for component in $COMPONENTS_TO_DOWNLOAD; do
              case "$component" in
                geox)
                  ui_print "  -> 正在下载 GeoX..."
                  /data/adb/box/scripts/box.tool upgeox_all
                  ;;
                utils)
                  ui_print "  -> 正在下载 yq..."
                  /data/adb/box/scripts/box.tool upyq
                  ui_print "  -> 正在下载 curl..."
                  /data/adb/box/scripts/box.tool upcurl
                  ;;
                *)
                  ui_print "  -> 正在下载内核: $component..."
                  /data/adb/box/scripts/box.tool upkernel "$component"
                  ;;
              esac
            done
            ui_print "- 所有下载任务已完成！"
        else
            ui_print "- 已取消所有下载任务。"
        fi
    fi
else
    ui_print "- 已跳过所有下载步骤。"
fi


if [ "${backup_box}" = "true" ]; then
  ui_print " "
  ui_print "- 正在恢复用户配置和数据..."

  if [ -f "${temp_dir}/settings.ini" ]; then
    if [ -f "/data/adb/box/settings.ini" ]; then
      if handle_choice "检测到旧的 settings.ini，选择如何处理？" "覆盖（使用新版覆盖旧版）" "增量合并（仅把旧值写入新版已有键）"; then
        ui_print "  - 已选择使用新版 settings.ini（不应用旧版设置）"
      else
        mv /data/adb/box/settings.ini /data/adb/box/settings.ini.new
        grep -E '^[a-zA-Z0-9_]+=' "${temp_dir}/settings.ini" | while IFS='=' read -r key value; do
          [ -z "${key}" ] && continue
          echo "${key}" | grep -qE '^[a-zA-Z0-9_]+' || continue
          if grep -q -E "^${key}=" "/data/adb/box/settings.ini.new"; then
            escaped_value=$(printf '%s' "${value}" | sed -e 's/[&\\#]/\\&/g')
            sed -i "s#^${key}=.*#${key}=${escaped_value}#" "/data/adb/box/settings.ini.new"
          fi
        done
        mv /data/adb/box/settings.ini.new /data/adb/box/settings.ini
        ui_print "  - 已将用户自定义项增量合并至新版 settings.ini"
      fi
    else
      cp -f "${temp_dir}/settings.ini" "/data/adb/box/settings.ini"
      ui_print "  - 已恢复 settings.ini"
    fi
  fi

  restore_config_dir() {
    config_dir="$1"
    if [ -d "${temp_dir}/${config_dir}" ]; then
        ui_print "  - 恢复 ${config_dir} 目录配置"
        cp -af "${temp_dir}/${config_dir}/." "/data/adb/box/${config_dir}/"
    fi
  }
  for dir in mihomo xray v2fly sing-box hysteria; do
    restore_config_dir "$dir"
  done

  ui_print "  - 恢复根目录配置文件"
  for conf_file in ap.list.cfg package.list.cfg gid.list.cfg crontab.cfg; do
    if [ -f "${temp_dir}/${conf_file}" ]; then
      cp -f "${temp_dir}/${conf_file}" "/data/adb/box/${conf_file}"
    fi
  done

  restore_binary() {
    local bin_path_fragment="$1"
    local target_path="/data/adb/box/bin/${bin_path_fragment}"
    local backup_path="${temp_dir}/bin/${bin_path_fragment}"

    if [ ! -f "${target_path}" ] && [ -f "${backup_path}" ]; then
      ui_print "  - 恢复二进制文件: ${bin_path_fragment}"
      mkdir -p "$(dirname "${target_path}")"
      cp -f "${backup_path}" "${target_path}"
      chmod 755 "${target_path}"
    fi
  }
  for bin_item in curl yq xray sing-box v2fly hysteria mihomo; do
    restore_binary "$bin_item"
  done

  if [ -d "${temp_dir}/run" ]; then
    ui_print "  - 恢复日志、pid等运行时文件"
    cp -af "${temp_dir}/run/." "/data/adb/box/run/"
  fi
fi

[ -z "$(find /data/adb/box/bin -type f -name '*' ! -name '*.bak')" ] && sed -Ei 's/^description=(\[.*][[:space:]]*)?/description=[ 😱 模块已安装但需手动下载内核 ] /g' $MODPATH/module.prop

if [ "$KSU" = "true" ]; then
  sed -i "s/name=.*/name=Box for KernelSU/g" $MODPATH/module.prop
elif [ "$APATCH" = "true" ]; then
  sed -i "s/name=.*/name=Box for APatch/g" $MODPATH/module.prop
else
  sed -i "s/name=.*/name=Box for Magisk/g" $MODPATH/module.prop
fi
unzip -o "$ZIPFILE" 'webroot/*' -d "$MODPATH" >&2

ui_print "- 清理残留文件"
rm -rf /data/adb/box/bin/.bin $MODPATH/box $MODPATH/box_service.sh

if [ "$backup_box" = "true" ] && [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
  ui_print " "
  if handle_choice "检测到更新残留备份文件，是否删除？" "删除备份" "保留备份"; then
    ui_print "- 正在删除备份: ${temp_dir}"
    rm -rf "${temp_dir}"
    ui_print "- 备份已删除"
  else
    ui_print "- 备份已保留在: ${temp_dir}"
  fi
fi

ui_print "- 安装完成，请重启设备。"
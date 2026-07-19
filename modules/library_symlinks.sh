#!/bin/bash
# Library目录迁移模块 (macOS专用)
# 将~/Library中占用空间较大的目录迁移到外部存储
# 通过创建软链接节省系统盘空间
#
# 使用方式:
#   在 install.sh 中选择对应菜单项
#   或: source modules/library_symlinks.sh && configure_library_symlinks

# 默认外部存储Library路径
LIB_DEFAULT_EXTERNAL="/Volumes/1T/Library"

# ============================================================
# 目录定义
# ============================================================

# 获取可迁移的Library目录标识列表
get_library_dirs() {
    echo "Caches CoreSimulator Huawei LarkShell Code MicrosoftEdge Docker"
}

# 获取目录的本地路径 ($HOME/Library/...)
get_library_path() {
    local name="$1"
    case "$name" in
        Caches)        echo "$HOME/Library/Caches" ;;
        CoreSimulator) echo "$HOME/Library/Developer/CoreSimulator" ;;
        Huawei)        echo "$HOME/Library/Huawei" ;;
        LarkShell)     echo "$HOME/Library/Application Support/LarkShell" ;;
        Code)          echo "$HOME/Library/Application Support/Code" ;;
        MicrosoftEdge) echo "$HOME/Library/Application Support/Microsoft Edge" ;;
        Docker)        echo "$HOME/Library/Containers/com.docker.docker" ;;
        *)             echo "" ;;
    esac
}

# 获取目录的描述
get_library_desc() {
    local name="$1"
    case "$name" in
        Caches)        echo "应用缓存, 自动重建, 最安全" ;;
        CoreSimulator) echo "iOS模拟器设备镜像, 可重下" ;;
        Huawei)        echo "华为SDK开发工具包, 可重下" ;;
        LarkShell)     echo "飞书工作台数据, 可重装" ;;
        Code)          echo "VS Code扩展和数据, 可重装" ;;
        MicrosoftEdge) echo "Edge浏览器数据, 可重装" ;;
        Docker)        echo "Docker容器镜像数据" ;;
        *)             echo "" ;;
    esac
}

# 获取目录对外部存储的子路径
get_library_external_subpath() {
    local name="$1"
    # 默认和标识同名，特殊映射的在这里处理
    echo "$name"
}

# ============================================================
# 辅助函数
# ============================================================

# 计算目录大小 (人类可读)
get_library_size() {
    local path="$1"
    if [ -d "$path" ]; then
        du -sh "$path" 2>/dev/null | cut -f1
    else
        echo "-"
    fi
}

# 检查一个目录是否已经迁移 (是软链接且指向外部)
is_already_migrated() {
    local name="$1"
    local path=$(get_library_path "$name")
    local ext_base="$2"

    if [ -L "$path" ]; then
        local target=$(readlink "$path")
        if [[ "$target" == "$ext_base"* ]] || [[ "$target" == "$(get_library_external_subpath "$name")"* ]]; then
            return 0
        fi
    fi
    return 1
}

# 显示当前状态概览表
show_library_status_table() {
    local external_path="$1"

    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│               Library 存储迁移状态概览                         │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "外部存储路径: ${GREEN}$external_path${NC}"
    echo ""

    total_savable=0

    printf "  ${YELLOW}%-18s %8s %12s   %s${NC}\n" "目录标识" "当前大小" "状态" "说明"
    printf "  ${YELLOW}%-18s %8s %12s   %s${NC}\n" "--------" "--------" "----" "----"

    for dir in $(get_library_dirs); do
        local path=$(get_library_path "$dir")
        local size=$(get_library_size "$path")
        local desc=$(get_library_desc "$dir")
        local status_text="${CYAN}待迁移${NC}"

        if [ -L "$path" ]; then
            local target=$(readlink "$path")
            if [ -d "$path" ]; then
                status_text="${GREEN}✓ 已迁移${NC}"
            else
                status_text="${RED}✗ 链接断裂${NC}"
            fi
        elif [ ! -d "$path" ]; then
            # 目录不存在，用灰色显示
            status_text="${PURPLE}不存在${NC}"
            size="-"
        else
            # 是普通目录，计算可节省大小
            local size_num=$(du -sk "$path" 2>/dev/null | cut -f1)
            total_savable=$((total_savable + size_num))
        fi

        printf "  %-18s %8s  %b   %s\n" "$dir" "$size" "$status_text" "$desc"
    done

    echo ""
    if [ "$total_savable" -gt 0 ]; then
        local total_savable_hr=$(echo "scale=1; $total_savable / 1024 / 1024" | bc 2>/dev/null || echo "?")
        echo -e "  预计可节省: ${GREEN}${total_savable_hr} Gi${NC}"
    fi
}

# ============================================================
# 一键清理（安全可恢复的临时文件）
# ============================================================

quick_cleanup() {
    echo -e "\n${YELLOW}一键清理临时文件:${NC}"
    echo "  以下操作会删除可安全重建的缓存和临时文件"
    echo ""

    local freed=0

    # 1. 废纸篓
    if [ -d "$HOME/.Trash" ] && [ "$(ls -A "$HOME/.Trash" 2>/dev/null)" ]; then
        local trash_size=$(du -sk "$HOME/.Trash" 2>/dev/null | cut -f1)
        if confirm_action "清空废纸篓 (~${trash_size}KiB)"; then
            run rm -rf "$HOME/.Trash"/*
            log_success "废纸篓已清空"
            freed=$((freed + trash_size))
        fi
    else
        log_info "废纸篓已空，跳过"
    fi

    # 2. Homebrew 缓存
    if [ -d "$(brew --cache 2>/dev/null)" ]; then
        if confirm_action "清理 Homebrew 缓存 (brew cleanup --prune=all)"; then
            run brew cleanup --prune=all
            log_success "Homebrew 缓存已清理"
        fi
    fi

    # 3. go-build 缓存
    local go_cache="$HOME/Library/Caches/go-build"
    if [ -d "$go_cache" ]; then
        local go_size=$(du -sk "$go_cache" 2>/dev/null | cut -f1)
        if confirm_action "清理 Go 编译缓存 (~${go_size}KiB)"; then
            run go clean -cache 2>/dev/null || run rm -rf "$go_cache"
            log_success "Go 编译缓存已清理"
            freed=$((freed + go_size))
        fi
    fi

    # 4. Xcode DerivedData
    local derived_data="$HOME/Library/Developer/Xcode/DerivedData"
    if [ -d "$derived_data" ]; then
        local dd_size=$(du -sk "$derived_data" 2>/dev/null | cut -f1)
        if confirm_action "清理 Xcode DerivedData (~${dd_size}KiB) [可重建]"; then
            run rm -rf "$derived_data"/*
            log_success "Xcode DerivedData 已清理"
            freed=$((freed + dd_size))
        fi
    fi

    # 5. iOS Simulator (删除不可用的)
    if command_exists xcrun; then
        if confirm_action "删除不可用的 iOS 模拟器 (xcrun simctl delete unavailable)"; then
            run xcrun simctl delete unavailable 2>/dev/null
            log_success "iOS 模拟器已清理"
        fi
    fi

    # 6. pip 缓存
    local pip_cache="$HOME/Library/Caches/pip"
    if [ -d "$pip_cache" ]; then
        local pip_size=$(du -sk "$pip_cache" 2>/dev/null | cut -f1)
        if confirm_action "清理 pip 缓存 (~${pip_size}KiB)"; then
            run rm -rf "$pip_cache"
            log_success "pip 缓存已清理"
            freed=$((freed + pip_size))
        fi
    fi

    local freed_hr=$(echo "scale=1; $freed / 1024 / 1024" | bc 2>/dev/null || echo "?")
    echo ""
    log_success "清理完成，共释放约 ${freed_hr} Gi"
}

# ============================================================
# 扫描未列出的 >1G 大目录
# ============================================================

scan_large_directories() {
    echo -e "\n${YELLOW}扫描 ~/Library 中 >1G 的大目录...${NC}"
    echo ""

    local tmpfile=$(mktemp)
    du -sk "$HOME/Library"/*/ 2>/dev/null | sort -rn | while read size path; do
        if [ "$size" -gt 1048576 ]; then  # >1G in KiB
            local size_hr=$(echo "scale=1; $size / 1024 / 1024" | bc)
            local name=$(basename "$path")
            printf "  ${CYAN}%-30s${NC} %s Gi\n" "$name" "$size_hr"
        fi
    done > "$tmpfile"

    if [ -s "$tmpfile" ]; then
        cat "$tmpfile"
    fi

    # 也扫描两级深度的
    echo ""
    echo -e "${YELLOW}深层扫描 (Application Support, Containers, Developer 子目录)...${NC}"
    for sub in "Application Support" Containers Developer; do
        local base="$HOME/Library/$sub"
        if [ -d "$base" ]; then
            du -sk "$base"/*/ 2>/dev/null | sort -rn | while read size path; do
                if [ "$size" -gt 1048576 ]; then
                    local size_hr=$(echo "scale=1; $size / 1024 / 1024" | bc)
                    local name=$(basename "$path")
                    printf "  ${CYAN}%-30s${NC} %s Gi  (%s)\n" "$sub/$name" "$size_hr" "$path"
                fi
            done
        fi
    done > "$tmpfile"

    if [ -s "$tmpfile" ]; then
        cat "$tmpfile"
    fi

    rm -f "$tmpfile"
}

# ============================================================
# 核心迁移逻辑
# ============================================================

setup_library_symlinks() {
    local external_path="$1"

    log_info "开始迁移 Library 目录到外部存储..."

    local migrated=0
    local failed=0
    local skipped=0

    for dir in $(get_library_dirs); do
        local local_path=$(get_library_path "$dir")
        local desc=$(get_library_desc "$dir")
        local ext_subpath=$(get_library_external_subpath "$dir")

        echo ""
        log_info "处理: $dir ($desc)"

        # 检查是否已迁移
        if is_already_migrated "$dir" "$external_path"; then
            log_info "$dir 已迁移，跳过"
            skipped=$((skipped + 1))
            continue
        fi

        # 检查本地目录是否存在
        if [ ! -d "$local_path" ]; then
            log_info "$dir 本地目录不存在，跳过"
            skipped=$((skipped + 1))
            continue
        fi

        if [ -L "$local_path" ]; then
            # 已存在软链接但不是指向我们的外部路径
            local old_target=$(readlink "$local_path")
            log_warning "$dir 已是软链接但指向其他地方: $old_target"
            if confirm_action "是否替换为新的外部路径"; then
                rm "$local_path"
            else
                log_info "跳过 $dir"
                skipped=$((skipped + 1))
                continue
            fi
        fi

        # 使用已有的 create_dev_symlink 函数进行迁移
        # 参数: tool_name, home_path, external_base
        if create_dev_symlink "$ext_subpath" "$local_path" "$external_path"; then
            log_success "✓ $dir 迁移完成"
            migrated=$((migrated + 1))
        else
            log_error "✗ $dir 迁移失败"
            failed=$((failed + 1))
        fi
    done

    echo ""
    echo -e "${CYAN}迁移结果: ${GREEN}$migrated 成功${NC}, "
    echo -e "           ${YELLOW}$skipped 跳过${NC}, ${RED}$failed 失败${NC}"
    echo ""

    if [ "$migrated" -gt 0 ]; then
        log_success "Library 存储迁移完成！"
        echo ""
        echo "注意事项:"
        echo "  • 某些 App 可能正在使用已迁移的目录，建议重启这些 App"
        echo "  • 如果 App 找不到数据，检查外置硬盘是否已挂载"
        echo "  • 如果外置硬盘未挂载，某些 App 会自动创建空目录覆盖软链接"
        echo "    建议参考下文配置 launchd 监控外置硬盘挂载"
    fi
}

# ============================================================
# 恢复（反向操作）
# ============================================================

restore_library_symlinks() {
    local external_path="$1"

    log_info "开始恢复 Library 目录回系统盘..."

    local restored=0
    local failed=0

    for dir in $(get_library_dirs); do
        local local_path=$(get_library_path "$dir")
        local ext_subpath=$(get_library_external_subpath "$dir")
        local external_dir="$external_path/$ext_subpath"

        if [ ! -L "$local_path" ]; then
            log_info "$dir 不是软链接，跳过"
            continue
        fi

        local target=$(readlink "$local_path")
        log_info "恢复: $dir (当前指向: $target)"

        # 删除软链接
        rm "$local_path"

        # 检查外部目录是否有数据
        if [ -d "$external_dir" ] && [ "$(ls -A "$external_dir" 2>/dev/null)" ]; then
            log_info "从外部存储复制数据回系统盘..."
            run cp -R "$external_dir" "$local_path"
            if [ $? -eq 0 ]; then
                log_success "✓ $dir 已恢复 (数据已复制回系统盘)"
                restored=$((restored + 1))

                # 询问是否删除外部数据
                if confirm_action "是否删除外部存储中的 $dir 数据（以释放外置盘空间）"; then
                    run rm -rf "$external_dir"
                    log_info "外部数据已删除"
                fi
            else
                log_error "✗ $dir 恢复失败"
                failed=$((failed + 1))
                # 尝试重新建立软链接，保证不丢数据
                ln -sf "$external_dir" "$local_path"
            fi
        else
            log_warning "外部存储中没有 $dir 的数据，创建空目录"
            ensure_dir "$local_path"
            log_success "✓ $dir 已恢复 (空目录)"
        fi
    done

    echo ""
    log_success "$restored 个目录已恢复, $failed 个失败"
}

# ============================================================
# 配置 launchd 监控外置硬盘（防止外置盘未挂载时被覆盖）
# ============================================================

setup_launchd_watcher() {
    local external_base="$1"

    log_info "配置 launchd 监控外置硬盘挂载..."

    # 提取挂载点根路径
    local mount_point=$(echo "$external_base" | cut -d/ -f1-3)  # 如 /Volumes/1T

    local plist_path="$HOME/Library/LaunchAgents/com.user.ext4t-watcher.plist"

    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.library-symlink-watcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>test -d "${mount_point}" && test -f "${HOME}/.dev_rc" && source "${HOME}/.dev_rc" && echo "External drive mounted: ${mount_point}" || echo "External drive NOT mounted: ${mount_point}"</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>/Volumes</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/library-symlink-watcher.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/library-symlink-watcher.log</string>
</dict>
</plist>
EOF

    # 卸载旧的并加载新的
    launchctl bootout gui/$(id -u) "$plist_path" 2>/dev/null || true
    launchctl bootstrap gui/$(id -u) "$plist_path" 2>/dev/null || true

    log_success "launchd 监控已配置: $plist_path"
    log_info "当外置硬盘挂载时，日志记录在: ~/Library/Logs/library-symlink-watcher.log"
}

# ============================================================
# 主菜单
# ============================================================

show_library_menu() {
    local external_path="$1"

    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║              macOS 系统存储迁移管理                      ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"

    # 显示状态表
    show_library_status_table "$external_path"

    echo ""
    echo "操作选项:"
    echo "  1. 开始迁移 - 将上述目录移到外部存储并创建软链接"
    echo "  2. 扫描未列出的大目录 (>1G)"
    echo "  3. 一键清理 - 安全清除缓存/废纸篓等临时文件"
    echo "  4. 恢复迁移 - 将软链接目录恢复回系统盘"
    echo "  5. 配置启动监控 - 防止外置盘未挂载时软链接被覆盖"
    echo "  0. 返回主菜单"
    echo ""
    echo -e -n "${BLUE}请选择 [0-5]: ${NC}"
}

# 获取或确认外部存储路径
ensure_external_path() {
    local default_external="$1"
    local external_path_var="$2"  # 变量名引用

    # 如果已经设置过，直接返回
    local current_value="${!external_path_var}"
    if [ -n "$current_value" ]; then
        return 0
    fi

    echo ""
    echo -e "${YELLOW}请指定外部存储路径${NC}"
    echo -e "建议使用: ${CYAN}$default_external${NC}"
    echo -n -e "${BLUE}回车使用默认，或输入自定义路径: ${NC}"
    read -r input_path

    if [ -z "$input_path" ]; then
        input_path="$default_external"
    fi

    # 检查外部存储是否可用
    local mount_point=$(echo "$input_path" | cut -d/ -f1-3)
    if [ ! -d "$mount_point" ]; then
        log_error "外部存储设备未挂载: $mount_point"
        log_info "请先连接外置硬盘后重试"
        return 1
    fi

    # 通过间接赋值更新上层变量
    eval "$external_path_var=\"$input_path\""
    return 0
}

# 主入口
configure_library_symlinks() {
    # 只在 macOS 上运行
    if ! is_macos; then
        log_error "Library 存储迁移仅在 macOS 上支持"
        return 1
    fi

    local default_external="$LIB_DEFAULT_EXTERNAL"
    local external_path=""

    # 主循环 —— 先显示菜单，必要时再问路径
    while true; do
        # 初始路径未知时用默认值预显示状态表
        local display_path="${external_path:-$default_external}"
        show_library_menu "$display_path"
        read -r choice

        case $choice in
            0)
                log_info "返回主菜单"
                break
                ;;
            1)
                # 迁移需要路径
                if [ -z "$external_path" ]; then
                    ensure_external_path "$default_external" external_path || continue
                fi
                echo ""
                log_info "将迁移以下目录到: $external_path"
                echo ""
                for dir in $(get_library_dirs); do
                    local size=$(get_library_size "$(get_library_path "$dir")")
                    printf "  • %-20s %s\n" "$dir" "$size"
                done
                echo ""
                if confirm_action "确认迁移"; then
                    setup_library_symlinks "$external_path"
                else
                    log_info "已取消"
                fi
                wait_for_key "按任意键继续..."
                ;;
            2)
                scan_large_directories
                wait_for_key "按任意键继续..."
                ;;
            3)
                quick_cleanup
                wait_for_key "按任意键继续..."
                ;;
            4)
                # 恢复需要路径
                if [ -z "$external_path" ]; then
                    ensure_external_path "$default_external" external_path || continue
                fi
                echo ""
                if confirm_action "确认将已迁移的目录恢复回系统盘 (此操作将复制数据回来)"; then
                    restore_library_symlinks "$external_path"
                fi
                wait_for_key "按任意键继续..."
                ;;
            5)
                # launchd 监控需要路径
                if [ -z "$external_path" ]; then
                    ensure_external_path "$default_external" external_path || continue
                fi
                setup_launchd_watcher "$external_path"
                wait_for_key "按任意键继续..."
                ;;
            *)
                log_error "无效选项: $choice"
                sleep 1
                ;;
        esac
    done
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "此模块需要从 install.sh 中运行，或使用:"
    echo "  source modules/library_symlinks.sh"
    echo "  configure_library_symlinks"
fi

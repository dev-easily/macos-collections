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
# 智能扫描 + 迁移（不局限于预设列表）
# ============================================================

# 检查路径或其任意父级是否为软链接（判断是否已迁移）
path_has_symlink_ancestor() {
    local p="$1"
    while [ "$p" != "$HOME/Library" ] && [ "$p" != "$HOME" ] && [ "$p" != "/" ]; do
        if [ -L "$p" ]; then
            return 0
        fi
        p="$(dirname "$p")"
    done
    return 1
}

# 扫描 ~/Library 下的大目录（真实目录，非已迁移的软链接）
# 参数: 阈值(KiB)，默认 300MiB = 307200KiB
# 输出: 找到的目录列表到 stdout，每行: "size_kib path"
scan_library_dirs() {
    local min_size_kib="${1:-307200}"  # 默认 300MiB
    local tempfile

    tempfile=$(mktemp)

    # 1) 扫描 ~/Library 一级子目录
    du -sk "$HOME/Library"/*/ 2>/dev/null >> "$tempfile"

    # 2) 扫描二级目录：Application Support, Containers, Developer, Caches 的子目录
    for sub in "Application Support" Containers Developer/CoreSimulator Caches; do
        local base="$HOME/Library/$sub"
        [ -d "$base" ] && du -sk "$base"/*/ 2>/dev/null >> "$tempfile"
    done

    # 3) 扫描三级目录：Application Support 下有一些更深的重要目录
    for sub in "Application Support"/*/; do
        [ -d "$sub" ] && du -sk "$sub"*/ 2>/dev/null >> "$tempfile"
    done

    # 过滤：>= 阈值 且 是真实目录（不是已迁移的软链接）
    while read -r size path; do
        # 过滤无限大的空行
        [ -z "$size" ] || [ -z "$path" ] && continue
        [ "$size" -lt "$min_size_kib" ] && continue

        # 去掉尾部斜杠（du 从 glob 带斜杠进来，会干扰 -L 检测）
        path="${path%/}"
        # 跳过已迁移的父子目录链（软链接及其子树）
        if path_has_symlink_ancestor "$path"; then
            continue
        fi

        # 跳过已知的系统级目录（不应该整体迁移）
        local rel="${path#$HOME/Library/}"
        case "/$rel/" in
            /Containers/|/Application\ Support/|/Developer/|/Caches/|/Metadata/|/Group\ Containers/|/Logs/|/WebKit/)
                continue
                ;;
        esac

        # 跳过深度过大的奇怪路径
        local depth=$(echo "$path" | tr '/' '\n' | wc -l | tr -d ' ')
        [ "$depth" -gt 10 ] && continue

        echo "$size $path"
    done < "$tempfile" | sort -rn -k1

    rm -f "$tempfile"
}

# 显示扫描结果，让用户选择并迁移
smart_scan_and_migrate() {
    local external_path="$1"

    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║              智能扫描 — 不局限固定列表                      ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "扫描 ${CYAN}~/Library${NC} 及子目录中 > ${CYAN}300 MiB${NC} 的目录（排除已迁移的软链接）..."
    echo ""

    local min_size_kib=$((300 * 1024))  # 300 MiB
    local results=()
    local result_sizes=()
    local result_paths=()

    # 执行扫描
    while IFS=' ' read -r size path; do
        [ -z "$size" ] || [ -z "$path" ] && continue
        # 跳过已经以软链接存在的预设列表目录
        results+=("$size $path")
        result_sizes+=("$size")
        result_paths+=("$path")
    done < <(scan_library_dirs "$min_size_kib")

    local count=${#results[@]}

    if [ "$count" -eq 0 ]; then
        log_success "没有找到超过 300 MiB 的待迁移目录！"
        echo ""
        log_info "你的系统盘存储状态很好，无需额外迁移。"
        return 0
    fi

    # 显示扫描结果表
    echo -e "${CYAN}发现 $count 个可迁移的大目录:${NC}"
    echo ""
    printf "  ${YELLOW}%3s  %-12s  %-45s  %s${NC}\n" "#" "大小" "路径" "相对 ~/Library/"
    printf "  ${YELLOW}%3s  %-12s  %-45s  %s${NC}\n" "---" "----------" "---" "-------------"

    local total_savable=0
    local idx=1
    for item in "${results[@]}"; do
        local size=$(echo "$item" | cut -d' ' -f1)
        local path=$(echo "$item" | cut -d' ' -f2-)
        local rel_path="${path#$HOME/Library/}"
        local size_hr=$(echo "scale=1; $size / 1024 / 1024" | bc 2>/dev/null)
        printf "  ${CYAN}%2d)${NC} %7s Gi  %s\n" "$idx" "$size_hr" "$rel_path"
        total_savable=$((total_savable + size))
        idx=$((idx + 1))
    done

    local total_hr=$(echo "scale=1; $total_savable / 1024 / 1024" | bc 2>/dev/null)
    echo ""
    echo -e "预计可节省: ${GREEN}${total_hr} Gi${NC}"
    echo ""

    # 让用户选择迁移哪些
    echo "选择要迁移的目录（迁移后会在原始位置创建软链接指向外置盘）:"
    echo "  • 输入序号迁移单个: 1"
    echo "  • 输入范围迁移多个: 1-5"
    echo "  • 输入 all 迁移全部"
    echo "  • 输入 q 取消"
    echo ""
    echo -n -e "${BLUE}你的选择: ${NC}"
    read -r selection

    [ -z "$selection" ] && selection="q"

    # 解析选择
    local selected_indices=()

    if [ "$selection" = "all" ]; then
        for ((i = 1; i <= count; i++)); do
            selected_indices+=("$i")
        done
    elif [ "$selection" = "q" ]; then
        log_info "已取消"
        return 0
    elif [[ "$selection" =~ ^[0-9]+$ ]]; then
        # 单个数字
        if [ "$selection" -ge 1 ] && [ "$selection" -le "$count" ]; then
            selected_indices+=("$selection")
        else
            log_error "无效序号: $selection (有效范围: 1-$count)"
            return 1
        fi
    elif [[ "$selection" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        # 范围: 1-5
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        if [ "$start" -ge 1 ] && [ "$end" -le "$count" ] && [ "$start" -le "$end" ]; then
            for ((i = start; i <= end; i++)); do
                selected_indices+=("$i")
            done
        else
            log_error "无效范围: $selection (有效范围: 1-$count)"
            return 1
        fi
    else
        log_error "无效输入，已取消"
        return 1
    fi

    # 确认并迁移
    echo ""
    echo -e "${YELLOW}将迁移以下 ${#selected_indices[@]} 个目录:${NC}"
    for idx in "${selected_indices[@]}"; do
        local path="${result_paths[$((idx - 1))]}"
        local rel="${path#$HOME/Library/}"
        local size=$(echo "scale=1; ${result_sizes[$((idx - 1))]} / 1024 / 1024" | bc 2>/dev/null)
        echo "  • ${rel} (${size} Gi)"
    done
    echo ""

    if ! confirm_action "确认迁移"; then
        log_info "已取消"
        return 0
    fi

    # 执行迁移
    local migrated=0 failed=0
    for idx in "${selected_indices[@]}"; do
        local path="${result_paths[$((idx - 1))]}"
        local rel="${path#$HOME/Library/}"
        local label=$(echo "$rel" | tr '/' '-')

        echo ""
        log_info "迁移: $rel"

        if create_dev_symlink "$rel" "$path" "$external_path"; then
            log_success "✓ $rel 迁移完成"
            migrated=$((migrated + 1))
        else
            log_error "✗ $rel 迁移失败"
            failed=$((failed + 1))
        fi
    done

    echo ""
    log_success "智能扫描迁移完成: $migrated 成功, $failed 失败"
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

# ============================================================
# 配置 launchd 自动修复（防止外置盘未挂载时软链接被覆盖）
# ============================================================

# 生成软链接修复脚本
generate_repair_script() {
    local external_base="$1"
    local repair_script="$HOME/.config/os_symlink_repair.sh"
    local manifest_file="$HOME/.config/os_symlinks.txt"

    mkdir -p "$HOME/.config"

    # 收集所有已知的软链接映射
    # 包括预设列表 + 从外部存储反向扫描发现的额外链接
    echo "#!/bin/bash" > "$repair_script"
    echo "# OS Symlink Repair Script - 自动修复被覆盖的软链接" >> "$repair_script"
    echo "# Generated by os-init-unix on $(date)" >> "$repair_script"
    echo "" >> "$repair_script"
    echo "EXTERNAL_BASE=\"$external_base\"" >> "$repair_script"
    echo "EXTERNAL_MOUNT=\"$(echo "$external_base" | cut -d/ -f1-3)\"" >> "$repair_script"
    echo 'LOG_FILE="$HOME/Library/Logs/os-symlink-repair.log"' >> "$repair_script"
    echo "" >> "$repair_script"
    echo 'log() { echo "[$(date "+%Y-%m-%d %H:%M:%S")] $*" >> "$LOG_FILE"; }' >> "$repair_script"
    echo "" >> "$repair_script"
    echo '# 检查外置盘是否挂载' >> "$repair_script"
    echo 'if [ ! -d "$EXTERNAL_MOUNT" ]; then' >> "$repair_script"
    echo '  log "外置盘未挂载，跳过修复"' >> "$repair_script"
    echo '  exit 0' >> "$repair_script"
    echo 'fi' >> "$repair_script"
    echo "" >> "$repair_script"
    echo 'log "开始检查软链接完整性..."' >> "$repair_script"
    echo "" >> "$repair_script"
    echo '# 修复单个软链接的函数' >> "$repair_script"
    echo 'repair_symlink() {' >> "$repair_script"
    echo '  local local_path="$1"' >> "$repair_script"
    echo '  local target="$2"' >> "$repair_script"
    echo '' >> "$repair_script"
    echo '  # 情况1: 软链接正常 → 跳过' >> "$repair_script"
    echo '  if [ -L "$local_path" ]; then' >> "$repair_script"
    echo '    local current=$(readlink "$local_path")' >> "$repair_script"
    echo '    if [ "$current" = "$target" ] && [ -d "$target" ]; then' >> "$repair_script"
    echo '      return 0  # 完好' >> "$repair_script"
    echo '    fi' >> "$repair_script"
    echo '  fi' >> "$repair_script"
    echo '' >> "$repair_script"
    echo '  # 情况2: 被 App 覆盖成了真实目录 → 修复' >> "$repair_script"
    echo '  if [ -d "$local_path" ] && [ ! -L "$local_path" ]; then' >> "$repair_script"
    echo '    if [ -d "$target" ] && [ "$(ls -A "$target" 2>/dev/null)" ]; then' >> "$repair_script"
    echo '      # 外部数据还在，准备修复' >> "$repair_script"
    echo '      local local_size=$(du -sk "$local_path" 2>/dev/null | cut -f1)' >> "$repair_script"
    echo '      local ext_size=$(du -sk "$target" 2>/dev/null | cut -f1)' >> "$repair_script"
    echo '      log "⚠ 检测到覆盖: $local_path"' >> "$repair_script"
    echo '      log "  └ 本地: ${local_size}KiB | 外部: ${ext_size}KiB"' >> "$repair_script"
    echo '' >> "$repair_script"
    echo '      # 如果本地有新数据（App 运行产生的），备份到外部' >> "$repair_script"
    echo '      local new_files=$(comm -23 <(ls "$local_path" 2>/dev/null) <(ls "$target" 2>/dev/null) 2>/dev/null)' >> "$repair_script"
    echo '      if [ -n "$new_files" ]; then' >> "$repair_script"
    echo '        log "  └ 发现本地新增数据，合并到外部..."' >> "$repair_script"
    echo '        cp -R "$local_path"/* "$target"/ 2>/dev/null' >> "$repair_script"
    echo '        cp -R "$local_path"/.[^.]* "$target"/ 2>/dev/null' >> "$repair_script"
    echo '      fi' >> "$repair_script"
    echo '' >> "$repair_script"
    echo '      # 删除本地目录，重建软链接' >> "$repair_script"
    echo '      rm -rf "$local_path"' >> "$repair_script"
    echo '      ln -sf "$target" "$local_path"' >> "$repair_script"
    echo '      log "  ✅ 已修复: $local_path -> $target"' >> "$repair_script"
    echo '    elif [ -d "$target" ]; then' >> "$repair_script"
    echo '      # 外部目录为空，移动本地数据过去' >> "$repair_script"
    echo '      log "  └ 外部目录为空，移动本地数据..."' >> "$repair_script"
    echo '      mkdir -p "$target"' >> "$repair_script"
    echo '      cp -R "$local_path"/* "$target"/ 2>/dev/null' >> "$repair_script"
    echo '      cp -R "$local_path"/.[^.]* "$target"/ 2>/dev/null' >> "$repair_script"
    echo '      rm -rf "$local_path"' >> "$repair_script"
    echo '      ln -sf "$target" "$local_path"' >> "$repair_script"
    echo '      log "  ✅ 已修复（数据已迁移）"' >> "$repair_script"
    echo '    else' >> "$repair_script"
    echo '      log "  ❌ 外部目标不存在: $target，无法修复"' >> "$repair_script"
    echo '    fi' >> "$repair_script"
    echo '  fi' >> "$repair_script"
    echo '}' >> "$repair_script"
    echo "" >> "$repair_script"
    echo '# 预设列表中的目录' >> "$repair_script"
    echo 'log "检查预设目录..."' >> "$repair_script"

    # 添加预设目录
    for dir in $(get_library_dirs); do
        local home_path=$(get_library_path "$dir")
        local ext_subpath=$(get_library_external_subpath "$dir")
        local external_dir="$external_base/$ext_subpath"
        echo "repair_symlink \"$home_path\" \"$external_dir\"" >> "$repair_script"
    done

    # 额外扫描外部存储中已有的其他映射
    # 通过检查外部存储目录结构反向查找
    log_info "扫描外部存储中已有的其他软链接映射..."
    echo "" >> "$repair_script"
    echo '# 外部存储目录存在性检查，用于自定义映射' >> "$repair_script"
    if [ -d "$external_base" ]; then
        find -L "$external_base" -maxdepth 5 -type d 2>/dev/null | while read ext_dir; do
            # 跳过基础目录本身
            [ "$ext_dir" = "$external_base" ] && continue
            # 构造对应的本地路径
            local rel="${ext_dir#$external_base/}"
            local local_path="$HOME/Library/$rel"
            # 检查对应的本地路径是否也是软链接（可能不是预设列表里的）
            if [ -L "$local_path" ]; then
                local current=$(readlink "$local_path")
                if [ "$current" != "$ext_dir" ]; then
                    # 软链接存在但指向不同位置，也加入修复清单
                    echo "# Extra mapping: $rel" >> "$repair_script"
                    echo "repair_symlink \"$local_path\" \"$ext_dir\"" >> "$repair_script"
                fi
            elif [ -d "$local_path" ] && [ ! -L "$local_path" ]; then
                # 本地是真实目录但外部有对应数据 → 需要修复
                echo "# Detected overwritten: $rel" >> "$repair_script"
                echo "repair_symlink \"$local_path\" \"$ext_dir\"" >> "$repair_script"
            fi
        done
    fi

    echo "" >> "$repair_script"
    echo 'log "软链接检查完成"' >> "$repair_script"

    chmod +x "$repair_script"
    echo "$repair_script"
}

setup_launchd_watcher() {
    local external_base="$1"

    log_info "配置 launchd 自动修复软链接..."

    # 生成修复脚本
    local repair_script=$(generate_repair_script "$external_base")
    local plist_path="$HOME/Library/LaunchAgents/com.user.library-symlink-repair.plist"

    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.library-symlink-repair</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$repair_script</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>/Volumes</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/os-symlink-repair.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/os-symlink-repair.log</string>
</dict>
</plist>
EOF

    # 先运行一次修复脚本，确保当前状态正常
    log_info "首次运行修复脚本..."
    bash "$repair_script"

    # 卸载旧的并加载新的
    launchctl bootout gui/$(id -u) "$plist_path" 2>/dev/null || true
    launchctl bootstrap gui/$(id -u) "$plist_path" 2>/dev/null || true

    log_success "launchd 自动修复已配置!"
    echo ""
    echo -e "${CYAN}配置说明:${NC}"
    echo "  • 修复脚本: $repair_script"
    echo "  • launchd: $plist_path"
    echo "  • 日志: ~/Library/Logs/os-symlink-repair.log"
    echo "  • 触发时机: 登录时 + /Volumes 变化时 + 每 5 分钟"
    echo ""
    echo -e "${YELLOW}自动修复逻辑:${NC}"
    echo "  1. 检测到软链接被真实目录覆盖 → 备份本地新数据 → 重建软链接"
    echo "  2. 如果本地目录有新文件（App 运行产生的），合并到外部存储"
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
    echo "  1. 开始迁移 - 将预设列表中的目录移到外部存储（使用中请先迁移预设目录）"
    echo "  2. 智能扫描 - 扫描 ~/Library 下所有 >300MiB 目录，选择迁移"
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
                # 智能扫描需要路径
                if [ -z "$external_path" ]; then
                    ensure_external_path "$default_external" external_path || continue
                fi
                smart_scan_and_migrate "$external_path"
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

#!/bin/bash
# 跨平台开发环境智能安装器
# 版本: 3.0.0
# 支持: macOS, Ubuntu (使用Homebrew)

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# 导入通用函数
source "$MODULES_DIR/common.sh"

# 全局变量
INSTALLED_COMPONENTS=()
FAILED_COMPONENTS=()
INSTALL_LOG="$HOME/.config/os_setup.log"
DRY_RUN=false

# 检测操作系统
detect_os() {
    if is_macos; then
        OS_TYPE="macos"
    elif is_ubuntu; then
        OS_TYPE="ubuntu"
    else
        log_warning "未检测到支持的操作系统，尝试继续安装..."
        OS_TYPE="unknown"
    fi
    export OS_TYPE
    log_info "检测到操作系统: $OS_TYPE"
}

# 初始化日志
init_logging() {
    ensure_dir "$(dirname "$INSTALL_LOG")"
    echo "=== 开发环境安装 $(date) ===" >> "$INSTALL_LOG"
}

# 显示欢迎界面
show_welcome() {
    clear
    echo -e "${BLUE}"
    cat << EOF
╔══════════════════════════════════════════════════════════════╗
║                  跨平台开发环境安装器                         ║
║                      版本: 3.0.0                             ║
║                                                              ║
║  支持: macOS / Ubuntu (使用Homebrew)                         ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    show_system_info
}

# 系统检查
system_check() {
    log_info "执行系统检查..."

    # 检查磁盘空间
    local required_space=20
    check_disk_space "$required_space"

    # macOS特殊检查
    if is_macos; then
        check_xcode_tools
    fi

    # 检测并安装git (如果不存在)
    ensure_git_installed

    log_success "系统检查通过"
}

# 设置镜像源
setup_mirrors() {
    log_info "设置安装过程中的临时镜像源..."

    # Homebrew镜像
    export HOMEBREW_INSTALL_FROM_API=1
    export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
    export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
    export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
    export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"

    # Rust镜像
    export RUSTUP_DIST_SERVER="https://rsproxy.cn"
    export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"

    # Node.js镜像
    export NVM_NODEJS_ORG_MIRROR="https://mirrors.ustc.edu.cn/node/"

    # Python镜像
    export PYTHON_BUILD_MIRROR_URL_SKIP_CHECKSUM=1
    export PYTHON_BUILD_MIRROR_URL="https://registry.npmmirror.com/-/binary/python"

    # Flutter镜像
    export PUB_HOSTED_URL="https://pub.flutter-io.cn"
    export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

    log_success "镜像源配置完成"
}

# 显示预设模式菜单
show_preset_menu() {
    echo -e "\n${YELLOW}选择安装模式:${NC}"
    echo "1. 配置开发目录 - 将缓存和工具目录链接到外部存储 (推荐先运行)"
    echo "2. 配置系统存储 - 将~/Library大目录迁移到外置硬盘"
    echo "3. 完整安装 - 安装所有可用组件"
    echo "4. 自定义安装 - 手动选择组件"
    echo "0. 退出"
    echo -n -e "\n${BLUE}请选择 [0-4]: ${NC}"
}

# 显示组件菜单
show_component_menu() {
    echo -e "\n${YELLOW}选择要安装的组件:${NC}"
    echo "1. 系统初始化 - Homebrew、Git配置、Shell环境 [必需]"
    echo "2. 编程语言SDK - 各种编程语言的开发环境"
    echo "3. 开发工具 - 编辑器、终端、数据库等开发工具"
    echo "4. 实用工具 - 系统监控等实用工具"
    echo -n -e "\n${BLUE}请选择组件 (多选用空格分隔): ${NC}"
}

# 安装预设模式
install_preset() {
    log_info "安装预设: 完整安装"

    # 安装系统组件
    install_system_init

    # 安装语言
    install_languages

    # 安装开发工具
    install_dev_tools

    # 安装实用工具
    install_utility_tools
}

# 安装系统初始化
install_system_init() {
    log_info "开始系统初始化..."

    # 设置镜像环境变量
    setup_mirrors

    # 运行系统模块
    if [ -f "$MODULES_DIR/system.sh" ]; then
        source "$MODULES_DIR/system.sh"
        if main; then
            INSTALLED_COMPONENTS+=("系统初始化")
            log_success "系统初始化完成"
        else
            FAILED_COMPONENTS+=("系统初始化")
            log_error "系统初始化失败"
        fi
    else
        log_error "系统模块不存在: $MODULES_DIR/system.sh"
    fi
}

# 安装编程语言
install_languages() {
    local selected_languages="$1"

    log_info "开始安装编程语言..."

    if [ -f "$MODULES_DIR/languages.sh" ]; then
        source "$MODULES_DIR/languages.sh"

        # 如果没有指定语言，显示菜单
        if [ -z "$selected_languages" ]; then
            main
        else
            # 安装指定的语言
            for lang in $selected_languages; do
                case "$lang" in
                    "rust") install_rust ;;
                    "nodejs") install_nodejs ;;
                    "python") install_python ;;
                    "golang") install_golang ;;
                    "java") install_java ;;
                    "php") install_php ;;
                    "ruby") install_ruby ;;
                    "flutter") install_flutter ;;
                    *) log_warning "未知语言: $lang" ;;
                esac
            done
        fi

        if [[ ! " ${INSTALLED_COMPONENTS[*]} " =~ "编程语言SDK" ]]; then
            INSTALLED_COMPONENTS+=("编程语言SDK")
        fi
    else
        log_error "语言模块不存在: $MODULES_DIR/languages.sh"
        FAILED_COMPONENTS+=("编程语言SDK")
    fi
}

# 安装开发工具
install_dev_tools() {
    local selected_tools="$1"

    log_info "开始安装开发工具..."

    if [ -z "$selected_tools" ] || [[ $selected_tools == *"neovim"* ]]; then
        install_neovim_simple
    fi

    if [ -z "$selected_tools" ] || [[ $selected_tools == *"vscode"* ]]; then
        install_vscode_simple
    fi

    if [ -z "$selected_tools" ] || [[ $selected_tools == *"docker"* ]]; then
        source "$MODULES_DIR/system.sh"
        install_docker
    fi

    if [[ ! " ${INSTALLED_COMPONENTS[*]} " =~ "开发工具" ]]; then
        INSTALLED_COMPONENTS+=("开发工具")
    fi
}

# 简化版Neovim安装
install_neovim_simple() {
    if ! command_exists nvim; then
        log_info "安装 Neovim..."
        run brew install neovim ripgrep
        if [[ " ${INSTALLED_COMPONENTS[*]} " != *"Neovim"* ]]; then
            INSTALLED_COMPONENTS+=("Neovim")
        fi
        log_success "Neovim 安装完成"
    else
        log_info "Neovim 已安装，跳过"
    fi
}

# 简化版VSCode安装
install_vscode_simple() {
    if ! brew list --cask visual-studio-code &>/dev/null && ! command_exists code; then
        log_info "安装 Visual Studio Code..."
        if is_macos; then
            run brew install --cask visual-studio-code
        else
            # Ubuntu Homebrew also supports --cask
            run brew install --cask visual-studio-code
        fi
        if [[ " ${INSTALLED_COMPONENTS[*]} " != *"Visual Studio Code"* ]]; then
            INSTALLED_COMPONENTS+=("Visual Studio Code")
        fi
        log_success "Visual Studio Code 安装完成"
    else
        log_info "Visual Studio Code 已安装，跳过"
    fi
}

# 安装实用工具
install_utility_tools() {
    log_info "开始安装实用工具..."

    local tools=("htop" "tree" "jq" "wget" "unzip")

    if is_macos; then
        # macOS apps
        local cask_tools=()
        if brew list --cask stats &>/dev/null; then
            : # already installed
        else
            cask_tools+=("stats")
        fi
    fi

    for tool in "${tools[@]}"; do
        if ! brew list "$tool" &>/dev/null; then
            log_info "安装 $tool..."
            run brew install "$tool"
        else
            log_info "$tool 已安装，跳过"
        fi
    done

    for tool in "${cask_tools[@]}"; do
        if ! brew list --cask "$tool" &>/dev/null; then
            log_info "安装 $tool..."
            run brew install --cask "$tool"
        fi
    done

    if [[ ! " ${INSTALLED_COMPONENTS[*]} " =~ "实用工具" ]]; then
        INSTALLED_COMPONENTS+=("实用工具")
    fi

    log_success "实用工具安装完成"
}

# 自定义安装
custom_install() {
    show_component_menu
    read -r selections

    # 定义与显示顺序对应的包名
    local display_order=("system_init" "languages" "dev_tools" "utility_tools")

    for selection in $selections; do
        if [ $selection -ge 1 ] && [ $selection -le ${#display_order[@]} ]; then
            local package_key="${display_order[$selection - 1]}"

            case "$package_key" in
                "system_init") install_system_init ;;
                "languages") install_languages ;;
                "dev_tools") install_dev_tools ;;
                "utility_tools") install_utility_tools ;;
                *) log_warning "未知组件: $package_key" ;;
            esac
        else
            log_warning "无效选项: $selection"
        fi
    done
}

# 显示安装结果
show_results() {
    echo -e "\n${CYAN}安装结果:${NC}"
    echo "========================================"

    if [ ${#INSTALLED_COMPONENTS[@]} -gt 0 ]; then
        echo -e "${GREEN}成功安装的组件:${NC}"
        for component in "${INSTALLED_COMPONENTS[@]}"; do
            echo "  ✓ $component"
        done
    fi

    if [ ${#FAILED_COMPONENTS[@]} -gt 0 ]; then
        echo -e "\n${RED}安装失败的组件:${NC}"
        for component in "${FAILED_COMPONENTS[@]}"; do
            echo "  ✗ $component"
        done
    fi

    echo "========================================"
    echo -e "${YELLOW}安装日志: $INSTALL_LOG${NC}"
    echo -e "${YELLOW}请重启终端或运行 'source ~/.dev_rc' 以使配置生效${NC}"
}

# 主函数
main() {
    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run|-n)
                DRY_RUN=true
                log_info "DRY-RUN 模式启用：仅打印操作，不实际修改"
                shift
                ;;
            --help|-h)
                echo "Usage: ./install.sh [OPTIONS]"
                echo "Options:"
                echo "  -n, --dry-run    Dry run mode - only print what would be done"
                echo "  -h, --help       Show this help"
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                exit 1
                ;;
        esac
    done

    # 初始化
    init_logging
    check_not_root
    detect_os

    # 显示欢迎界面
    show_welcome

    # 系统检查
    system_check

    # 主循环
    while true; do
        show_preset_menu
        read -r choice

        case $choice in
            0)
                log_info "感谢使用！"
                break
                ;;
            1)
                # 导入系统模块获取 configure_dev_directory 函数
                if [ -f "$MODULES_DIR/system.sh" ]; then
                    source "$MODULES_DIR/system.sh"
                fi
                configure_dev_directory
                ;;
            2)
                # 导入Library存储迁移模块
                if [ -f "$MODULES_DIR/library_symlinks.sh" ]; then
                    source "$MODULES_DIR/library_symlinks.sh"
                    configure_library_symlinks
                else
                    log_error "存储迁移模块不存在: $MODULES_DIR/library_symlinks.sh"
                fi
                ;;
            3)
                if confirm_action "确认安装 完整安装"; then
                    install_preset "complete"
                fi
                ;;
            4)
                custom_install
                ;;
            *)
                log_error "无效选项"
                continue
                ;;
        esac

        show_results
        wait_for_key "按任意键继续..."
    done
}

# 运行主函数
main "$@"

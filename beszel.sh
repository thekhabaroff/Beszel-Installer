#!/bin/bash

#==============================================================================
# Beszel Interactive Installer
# Установка hub или agent с красивым меню
#==============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # Сброс цвета

# Функции вывода
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                  Beszel Installer v1.0                     ║"
    echo "║          Мониторинг нескольких VPS в одном месте           ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Проверка Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker не установлен!"
        echo ""
        read -p "Установить Docker автоматически? (y/n): " install_docker
        if [[ $install_docker =~ ^[Yy]$ ]]; then
            info "Установка Docker..."
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker $USER
            success "Docker установлен. Перезайдите в систему для применения прав."
            exit 0
        else
            error "Установка невозможна без Docker."
            exit 1
        fi
    fi
    
    if ! docker compose version &> /dev/null; then
        error "Docker Compose не найден!"
        exit 1
    fi
    
    success "Docker и Docker Compose обнаружены"
}

# Меню выбора компонента
show_main_menu() {
    print_header
    echo -e "${CYAN}Выберите компонент для установки:${NC}"
    echo ""
    echo "  1) Hub (панель управления)"
    echo "  2) Agent (агент мониторинга)"
    echo "  3) Выход"
    echo ""
    read -p "Ваш выбор [1-3]: " choice
    
    case $choice in
        1) install_hub ;;
        2) install_agent ;;
        3) exit 0 ;;
        *) 
            error "Неверный выбор!"
            sleep 2
            show_main_menu
            ;;
    esac
}

# Установка Hub
install_hub() {
    print_header
    echo -e "${GREEN}═══ Установка Beszel Hub ═══${NC}"
    echo ""
    
    # Параметры
    read -p "Директория для Hub [~/beszel]: " hub_dir
    hub_dir=${hub_dir:-~/beszel}
    hub_dir=$(eval echo $hub_dir)
    
    read -p "Порт для веб-интерфейса [8090]: " hub_port
    hub_port=${hub_port:-8090}
    
    # Создание директории
    info "Создание директории $hub_dir..."
    mkdir -p "$hub_dir"
    cd "$hub_dir"
    
    # Создание docker-compose.yml
    info "Создание docker-compose.yml..."
    cat > docker-compose.yml <<EOF
services:
  beszel:
    image: henrygd/beszel:latest
    container_name: beszel
    restart: unless-stopped
    ports:
      - ${hub_port}:8090
    volumes:
      - ./beszel_data:/beszel_data
      - ./beszel_socket:/beszel_socket
EOF
    
    # Запуск
    info "Запуск контейнера..."
    docker compose up -d
    
    sleep 3
    
    if docker ps | grep -q beszel; then
        success "Hub успешно установлен!"
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  Откройте в браузере:                            ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}http://$(hostname -I | awk '{print $1}'):${hub_port}${NC}                 ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                    ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  Создайте admin-аккаунт и добавьте системы       ${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
    else
        error "Ошибка запуска! Проверьте логи: docker logs beszel"
        exit 1
    fi
    
    echo ""
    read -p "Нажмите Enter для выхода..."
}

# Установка Agent
install_agent() {
    print_header
    echo -e "${GREEN}═══ Установка Beszel Agent ═══${NC}"
    echo ""
    
    warning "Перед установкой агента создайте систему в Hub и получите KEY/TOKEN"
    echo ""
    
    # Параметры
    read -p "Директория для Agent [~/beszel-agent]: " agent_dir
    agent_dir=${agent_dir:-~/beszel-agent}
    agent_dir=$(eval echo $agent_dir)
    
    read -p "IP-адрес Hub сервера: " hub_ip
    if [[ -z "$hub_ip" ]]; then
        error "IP адрес Hub обязателен!"
        sleep 2
        install_agent
        return
    fi
    
    read -p "Порт Hub [8090]: " hub_port
    hub_port=${hub_port:-8090}
    
    read -p "KEY (публичный ключ из Hub): " agent_key
    if [[ -z "$agent_key" ]]; then
        error "KEY обязателен!"
        sleep 2
        install_agent
        return
    fi
    
    read -p "TOKEN (из Hub): " agent_token
    if [[ -z "$agent_token" ]]; then
        error "TOKEN обязателен!"
        sleep 2
        install_agent
        return
    fi
    
    read -p "Порт агента [45876]: " agent_port
    agent_port=${agent_port:-45876}
    
    # Создание директории
    info "Создание директории $agent_dir..."
    mkdir -p "$agent_dir"
    cd "$agent_dir"
    
    # Создание docker-compose.yml
    info "Создание docker-compose.yml..."
    cat > docker-compose.yml <<EOF
services:
  beszel-agent:
    image: henrygd/beszel-agent:latest
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./beszel_agent_data:/var/lib/beszel-agent
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      LISTEN: ${agent_port}
      KEY: "${agent_key}"
      TOKEN: "${agent_token}"
      HUB_URL: "http://${hub_ip}:${hub_port}"
EOF
    
    # Запуск
    info "Запуск контейнера..."
    docker compose up -d
    
    sleep 3
    
    if docker ps | grep -q beszel-agent; then
        success "Agent успешно установлен!"
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  Проверьте статус в Hub панели                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  Сервер должен появиться со статусом ${GREEN}ONLINE${NC}       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                    ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  Логи: docker logs beszel-agent                  ${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
    else
        error "Ошибка запуска! Проверьте логи: docker logs beszel-agent"
        exit 1
    fi
    
    echo ""
    read -p "Нажмите Enter для выхода..."
}

# Главная функция
main() {
    print_header
    info "Проверка зависимостей..."
    check_docker
    echo ""
    sleep 1
    show_main_menu
}

# Запуск
main

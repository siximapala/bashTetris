# Ландышев-Шиляев Тимофей Васильевич, ИЕНИМ УРФУ, МЕН-422204 

# Тетрис на bash

set -euo pipefail

# константы игры
readonly WIDTH=10
readonly HEIGHT=20
readonly EMPTY='.'
readonly BORDER='█'

# цвета (ANSI коды)
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[1;31m'
readonly COLOR_GREEN='\033[1;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[1;34m'
readonly COLOR_MAGENTA='\033[1;35m'
readonly COLOR_LIGNT_BLUE='\033[1;36m'
readonly COLOR_WHITE='\033[1;37m'

# фигурки тетриса
readonly FIGURES=(
    "0,0:1,0:2,0:3,0"  # I фигура
    "0,0:1,0:2,0:2,1"  # J
    "0,0:1,0:2,0:0,1"  # L
    "0,0:1,0:0,1:1,1"  # O
    "1,0:2,0:0,1:1,1"  # S
    "0,0:1,0:2,0:1,1"  # T
    "0,0:1,0:1,1:2,1"  # Z
)

# цвета фигур
readonly FIGURE_COLORS=(
    "$COLOR_LIGNT_BLUE"
    "$COLOR_BLUE"
    "$COLOR_YELLOW"
    "$COLOR_WHITE"
    "$COLOR_GREEN"
    "$COLOR_MAGENTA"
    "$COLOR_RED"
)

# глобальные переменные
current_x=0
current_y=0
current_figure=0
current_rotation=0
current_color=""
next_figure=0
score=0
level=1
lines_cleared=0
game_over=0
frame_counter=0
drop_speed=20

# игровое поле массив
declare -a board

# временный файл, туда будет записываться состояние игры и каждый цикл оно будет выдаваться через cat
TEMP_DISPLAY=$(mktemp 2>/dev/null || echo "/tmp/tetris_display_$$")

# Очистка при завершении
cleanup() {
    rm -f "$TEMP_DISPLAY" 2>/dev/null || true
    stty echo icanon 2>/dev/null || true
    # Показываем курсор
    printf '\033[?25h' 2>/dev/null || true
    printf '%b' "$COLOR_RESET"
}

trap cleanup EXIT INT TERM

# инициализация игрового поля
init_board() {
    local i j
    for ((i=0; i<HEIGHT; i++)); do
        for ((j=0; j<WIDTH; j++)); do
            board[$((i*WIDTH + j))]=$EMPTY
        done
    done
}

# отрисовка показа какая фигура будет следующая
draw_next_figure() {
    local fig points x y color idx i j
    fig="${FIGURES[$next_figure]}"
    color="${FIGURE_COLORS[$next_figure]}"
    
    local -a mini_board
    for ((i=0; i<16; i++)); do
        mini_board[$i]=' '
    done
    
    IFS=':' read -ra points <<< "$fig"
    for point in "${points[@]}"; do
        IFS=',' read -r x y <<< "$point"
        mini_board[$((y*4 + x))]='█'
    done
    
    for ((i=0; i<4; i++)); do
        for ((j=0; j<4; j++)); do
            idx=$((i*4 + j))
            if [[ "${mini_board[$idx]}" == '█' ]]; then
                printf '%b██%b' "$color" "$COLOR_RESET" #escape последовательности для цвета
            else
                printf '  '
            fi
        done
        if (( i < 3 )); then
            printf '\n'
        fi
    done
}

# получаем случайную фигуру
get_random_figure() {
    echo $((RANDOM % ${#FIGURES[@]}))
}

new_figure() {
    current_x=$((WIDTH/2 - 2))
    current_y=0
    current_figure=$next_figure
    current_color="${FIGURE_COLORS[$current_figure]}"
    current_rotation=0
    next_figure=$(get_random_figure)
    
    if ! check_collision; then
        game_over=1
    fi
}

#вычисляет текущие координаты падающей фигуры с учетом ее положения и поворота.
get_current_coords() {
    local fig points x y rx ry
    local -a rotated_coords=()
    
    fig="${FIGURES[$current_figure]}"
    IFS=':' read -ra points <<< "$fig"
    
    for point in "${points[@]}"; do
        IFS=',' read -r x y <<< "$point"
        
        # Поворот точек вокруг (0,0) для 4 состояний:
        # 0: исходная
        # 1: поворот +90 градусов -> (x,y) -> (-y,x)
        # 2: поворот +180 градусов -> (x,y) -> (-x,-y)
        # 3: поворот +270 градусов -> (x,y) -> (y,-x)
        case $current_rotation in
            0) rx=$x; ry=$y ;;
            1) rx=$((-y)); ry=$x ;;
            2) rx=$((-x)); ry=$((-y)) ;;
            3) rx=$y; ry=$((-x)) ;;
            *) rx=$x; ry=$y ;;
        esac
        
        rotated_coords+=("$((current_x + rx)),$((current_y + ry))")
    done
    
    echo "${rotated_coords[@]}"
}

#проверка коллизий со стенами
check_collision() {
    local coords x y idx
    
    read -ra coords <<< "$(get_current_coords)"
    
    local coord
    for coord in "${coords[@]}"; do
        IFS=',' read -r x y <<< "$coord"
        
        # Проверяем выход за боковые границы и за нижнюю границу поля
        if (( x < 0 || x >= WIDTH || y >= HEIGHT )); then
            return 1
        fi

        if (( y >= 0 )); then
            idx=$((y*WIDTH + x))
            if [[ "${board[$idx]}" != "$EMPTY" ]]; then
                return 1
            fi
        fi
    done
    
    return 0
}

#прибивает текущую падающую фигуру к игровому полю, когда она больше не может двигаться вниз
fix_figure() {
    local coords x y idx
    
    read -ra coords <<< "$(get_current_coords)"
    
    local coord
    for coord in "${coords[@]}"; do
        IFS=',' read -r x y <<< "$coord"
        if (( y >= 0 )); then
            idx=$((y*WIDTH + x))
            board[$idx]="$current_color"
        fi
    done
}

# проверка на то есть ли линия которую можно убрать
check_lines() {
    local lines_removed=0
    local full
    local y x ny src_idx dst_idx
    
    for ((y=HEIGHT-1; y>=0; y--)); do
        full=1
        for ((x=0; x<WIDTH; x++)); do
            if [[ "${board[$((y*WIDTH + x))]}" == "$EMPTY" ]]; then
                full=0
                break
            fi
        done
        
        if (( full )); then
            lines_removed=$((lines_removed + 1))
            lines_cleared=$((lines_cleared + 1))
            
            # Сдвигает все строки выше вниз на одну позицию
            # Начиная с текущей строки y, копируем каждую строку из (ny-1) в ny
            for ((ny=y; ny>0; ny--)); do
                for ((x=0; x<WIDTH; x++)); do
                    src_idx=$(((ny-1)*WIDTH + x))
                    dst_idx=$((ny*WIDTH + x))
                    board[$dst_idx]="${board[$src_idx]}"
                done
            done
            
            for ((x=0; x<WIDTH; x++)); do
                board[$x]=$EMPTY
            done
            
            # после удаления строки нужно заново проверить эту же y позицию,
            # тк на неё сверху спустилась новая строка поэтому инкрементируем y
            y=$((y + 1))
        fi
    done
    
    if (( lines_removed > 0 )); then
        case $lines_removed in
            1) score=$((score + 100 * level)) ;;
            2) score=$((score + 300 * level)) ;;
            3) score=$((score + 500 * level)) ;;
            4) score=$((score + 800 * level)) ;;
            *) ;;
        esac
        # вычисляем уровень по накопленным lines_cleared, меняем текущий level
        # только если вычисленный уровень больше (для того чтобы работал чит на букву P латинскую)
        local computed_level
        computed_level=$(( (lines_cleared / 10) + 1 ))
        if (( computed_level > level )); then
            level=$computed_level
        fi
        
        # Пересчитываем скорость по итоговому level
        drop_speed=$((20 - (level - 1) * 2))
        if (( drop_speed < 3 )); then
            drop_speed=3
        fi
    fi
}

#делаем движение
move() {
    local dx=$1
    local dy=$2
    
    current_x=$((current_x + dx))
    current_y=$((current_y + dy))
    
    # Если столкновение
    if ! check_collision; then
        current_x=$((current_x - dx))
        current_y=$((current_y - dy))
        
        # Если пытались двигаться вниз и уперлись
        if (( dy > 0 )); then
            # Если попытка сдвига вниз привела к коллизии фигура фиксируется
            fix_figure
            check_lines
            new_figure
            return 1 # Возвращаем 1, что означает что упали, движение закончилось
        fi
        return 0 # Коллизия со стеной/боком, движение отменено
    fi
    
    return 0
}

#попытка ротации только если нет стены, проверка на коллизии
rotate() {
    local old_rotation=$current_rotation
    
    current_rotation=$(((current_rotation + 1) % 4))
    
    # Если поворот привёл к коллизии, откатываем вращение
    if ! check_collision; then
        current_rotation=$old_rotation
        return 1 # не смогли повернуть
    fi
    
    return 0
}

# отображение игрового поля
# Параметр $1: если 1, то отображаем текущую фигуру, иначе только статичное поле
display_screen() {
    local show_current=$1  # 0 - не показывать текущую фигуру, 1 - показывать
    local -a display_board
    
    # Копируем текущее игровое поле
    for ((i=0; i<HEIGHT*WIDTH; i++)); do
        display_board[$i]="${board[$i]}"
    done
    
    # Если нужно показать текущую фигуру, накладываем её на копию поля
    if (( show_current )); then
        read -ra coords <<< "$(get_current_coords)"
        local coord
        for coord in "${coords[@]}"; do
            IFS=',' read -r x y <<< "$coord"
            if (( y >= 0 && y < HEIGHT && x >= 0 && x < WIDTH )); then
                idx=$((y*WIDTH + x))
                display_board[$idx]="$current_color"
            fi
        done
    fi
    
    # Отрисовка в временный файл
    : > "$TEMP_DISPLAY"
    {
        printf '\033[2J\033[H'
        printf 'Тетрис\n' "$COLOR_WHITE" "$COLOR_RESET"
        printf 'Управление: <- -> ↓ (движение) ^ (поворот фигуры)\n'
        printf '        можно управлять и через wasd\n'
        printf '        Q - выход\n\n'
        
        printf 'Счет: %d  Уровень: %d  Сбито линий: %d\n\n' "$score" "$level" "$lines_cleared"
        
        printf 'Следующая фигура:\n'
        draw_next_figure
        printf '\n\n'
        
        # верхняя граница
        printf '%b%s%b' "$COLOR_WHITE" "$BORDER$BORDER" "$COLOR_RESET"
        local i
        for ((i=0; i<WIDTH; i++)); do
            printf '%b%s%b' "$COLOR_WHITE" "$BORDER$BORDER" "$COLOR_RESET"
        done
        printf '\n'
        
        # Поле
        local j idx cell color
        for ((i=0; i<HEIGHT; i++)); do
            printf '%b%s%s%b' "$COLOR_WHITE" "$BORDER" "$BORDER" "$COLOR_RESET"
            for ((j=0; j<WIDTH; j++)); do
                idx=$((i*WIDTH + j))
                cell="${display_board[$idx]}"
                if [[ "$cell" == "$EMPTY" ]]; then
                    printf '  '
                else
                    color="${cell}"
                    printf '%b██%b' "$color" "$COLOR_RESET"
                fi
            done
            printf '%b%s%s%b\n' "$COLOR_WHITE" "$BORDER" "$BORDER" "$COLOR_RESET"
        done
        
        # Нижняя граница
        printf '%b%s%b' "$COLOR_WHITE" "$BORDER$BORDER" "$COLOR_RESET"
        for ((i=0; i<WIDTH; i++)); do
            printf '%b%s%b' "$COLOR_WHITE" "$BORDER$BORDER" "$COLOR_RESET"
        done
        printf '\n'
    } >> "$TEMP_DISPLAY"
    
    cat "$TEMP_DISPLAY"
}

# игровой цикл
game_loop() {
    local key rest="" 
    frame_counter=0
    
    # Настройка терминала
    stty -echo -icanon time 0 min 0 2>/dev/null || true
    printf '\033[?25l'
    
    init_board
    next_figure=$(get_random_figure)
    new_figure
    
    while [[ $game_over -eq 0 ]]; do
        frame_counter=$((frame_counter + 1))
        if read -t 0.05 -n 1 key 2>/dev/null; then
            case "$key" in
                $'\e')
                    if read -t 0.01 -n 2 rest 2>/dev/null; then
                        key+="$rest"
                    fi
                    # обработка escape последовательностей для стрелок.
                    case "$key" in
                        $'\e[A'|$'\eOA') rotate || true ;;
                        $'\e[B'|$'\eOB') move 0 1 || true ;;
                        $'\e[C'|$'\eOC') move 1 0 || true ;;
                        $'\e[D'|$'\eOD') move -1 0 || true ;;
                        *) ;;
                    esac
                    ;;
                'q'|'Q') game_over=1 ;;
                'a'|'A') move -1 0 || true ;;
                'd'|'D') move 1 0 || true ;;
                's'|'S') move 0 1 || true ;;
                'w'|'W') rotate || true ;;
                ' ') 
                    while move 0 1; do :; done 
                    ;;
                'p'|'P') 
                    # чит, при нажатии на P латинскую увеличивается уровень
                    level=$((level + 1))
                    drop_speed=$((20 - (level - 1) * 2))
                    if (( drop_speed < 3 )); then
                        drop_speed=3
                    fi
                    ;;
                *) ;;
            esac
        fi
        
        # автоматическое падение
        if (( frame_counter >= drop_speed )); then
            move 0 1 || true
            frame_counter=0
        fi
        
        display_screen 1  # отображение с текущей фигурой
    done
    
    display_screen 1  # отображение с текущей фигурой
    printf '\n\n%bGAME OVER! Финальный счет: %d%b\n' "$COLOR_RED" "$score" "$COLOR_RESET"
    printf '\nНажмите любую клавишу для выхода...'
    while read -t 0.1 -n 1; do :; done || true
    read -n 1 || true
}

main() {
    if [[ -z "${TERM:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
        export TERM=xterm-256color
    fi
    
    clear
    echo "Запуск Тетриса..."
    echo "Нажмите любую клавишу для начала игры!!!"
    read -n 1 || true
    
    game_loop
    
    cleanup
}

main "$@"
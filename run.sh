#!/bin/bash

# 设置变量
PROGRAMS_DIR="programs"
TIMEOUT_DURATION=1200  # 20分钟 = 1200秒
CRASH_LOG_DIR="crash_logs"

# 定义日志过滤函数
filter_log() {
    local log_file="$1"
    
    if [ ! -f "$log_file" ]; then
        return 1
    fi
    
    # 创建临时文件
    local temp_file="${log_file}.tmp"
    
    # 删除所有包含"executing program"的行
    grep -v "executing program" "$log_file" > "$temp_file"
    
    # 检查过滤后的文件是否为空
    if [ ! -s "$temp_file" ]; then
        # 文件为空，删除它
        rm -f "$log_file" "$temp_file"
        echo "日志文件为空，已删除"
        return 2
    else
        # 文件不为空，替换原文件
        mv "$temp_file" "$log_file"
        echo "已过滤日志文件"
        return 0
    fi
}

# 检查programs目录是否存在
if [ ! -d "$PROGRAMS_DIR" ]; then
    echo "错误: 目录 $PROGRAMS_DIR 不存在!"
    exit 1
fi

# 检查programs目录中是否有.c文件
c_files=("$PROGRAMS_DIR"/*.c)
if [ ${#c_files[@]} -eq 0 ]; then
    echo "错误: 在 $PROGRAMS_DIR 目录中没有找到.c文件!"
    exit 1
fi

# 创建输出目录和崩溃日志目录
mkdir -p "$PROGRAMS_DIR/bin"
mkdir -p "$CRASH_LOG_DIR"

echo "开始编译和运行程序..."

# 遍历所有.c文件
for c_file in "$PROGRAMS_DIR"/*.c; do
    # 获取不带扩展名的文件名
    filename=$(basename "$c_file" .c)
    executable="$PROGRAMS_DIR/bin/$filename"
    crash_log="$CRASH_LOG_DIR/${filename}_crash.log"
    
    echo "========================================"
    echo "处理: $c_file"
    
    # 编译C文件
    echo "编译: gcc -o \"$executable\" \"$c_file\" -lpthread"
    if gcc -o "$executable" "$c_file" -lpthread 2>&1; then
        echo "✓ 编译成功: $executable"
        
        # 记录开始时间
        start_time=$(date +%s)
        elapsed_time=0
        run_count=0
        
        echo "运行程序 (总共运行20分钟)..."
        
        # 循环运行程序直到达到20分钟
        while [ $elapsed_time -lt $TIMEOUT_DURATION ]; do
            run_count=$((run_count + 1))
            run_start=$(date +%s)
            
            echo "[运行 #$run_count] 启动程序..."
            
            # 计算剩余时间
            remaining_time=$((TIMEOUT_DURATION - elapsed_time))
            
            # 运行程序并设置剩余时间超时，同时记录输出
            if timeout --signal=KILL ${remaining_time}s "$executable" 2>&1 | tee -a "$crash_log"; then
                # 程序正常结束
                run_end=$(date +%s)
                run_duration=$((run_end - run_start))
                elapsed_time=$((elapsed_time + run_duration))
                
                echo "[运行 #$run_count] 程序正常结束，运行时间: ${run_duration}秒"
                echo "[运行 #$run_count] 已累计运行: ${elapsed_time}秒"
                
                # 过滤日志文件
                filter_log "$crash_log"
                
                # 如果程序提前结束但还有剩余时间，继续运行
                if [ $elapsed_time -lt $TIMEOUT_DURATION ]; then
                    echo "[运行 #$run_count] 程序提前结束，重新启动..."
                    # 在重启前添加分隔符到日志文件
                    if [ -f "$crash_log" ]; then
                        echo "--- 重启程序 (运行 #$((run_count + 1))) ---" >> "$crash_log"
                    fi
                fi
            else
                # 程序异常结束或被超时终止
                exit_code=$?
                run_end=$(date +%s)
                run_duration=$((run_end - run_start))
                elapsed_time=$((elapsed_time + run_duration))
                
                # 过滤日志文件
                filter_log "$crash_log"
                
                if [ $exit_code -eq 137 ]; then
                    echo "[运行 #$run_count] 程序被强制停止 (达到20分钟总运行时间)"
                else
                    echo "[运行 #$run_count] 程序异常结束 (退出码: $exit_code)，运行时间: ${run_duration}秒"
                    echo "[运行 #$run_count] 已累计运行: ${elapsed_time}秒"
                    
                    # 如果程序崩溃但还有剩余时间，继续运行
                    if [ $elapsed_time -lt $TIMEOUT_DURATION ]; then
                        echo "[运行 #$run_count] 程序崩溃，重新启动..."
                        # 在重启前添加分隔符到日志文件
                        if [ -f "$crash_log" ]; then
                            echo "--- 重启程序 (运行 #$((run_count + 1))) ---" >> "$crash_log"
                        fi
                    fi
                fi
            fi
            
            # 短暂暂停避免过于频繁的重启
            if [ $elapsed_time -lt $TIMEOUT_DURATION ]; then
                sleep 1
            fi
        done
        
        echo "✓ 程序 $filename 已完成20分钟总运行时间，共运行 $run_count 次"
        
        # 最终过滤日志文件
        filter_log "$crash_log"
        
        # 如果日志文件仍然存在，重命名为完整运行日志
        if [ -f "$crash_log" ]; then
            mv "$crash_log" "$CRASH_LOG_DIR/${filename}_full_run.log"
            echo "完整运行日志保存至: $CRASH_LOG_DIR/${filename}_full_run.log"
        fi
        
    else
        echo "✗ 编译失败: $c_file"
        # 将编译错误记录到日志
        echo "编译失败: $c_file" > "$crash_log"
        gcc -o "$executable" "$c_file" -lpthread 2>&1 >> "$crash_log"
        
        # 过滤编译错误日志
        filter_log "$crash_log"
    fi
    
    echo "等待5秒后继续下一个程序..."
    sleep 5
    echo
done

echo "========================================"
echo "所有程序处理完成!"
if [ -d "$CRASH_LOG_DIR" ] && [ "$(ls -A "$CRASH_LOG_DIR")" ]; then
    echo "运行日志保存在: $CRASH_LOG_DIR 目录"
else
    echo "没有生成任何日志文件"
fi
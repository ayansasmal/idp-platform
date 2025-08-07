#!/bin/bash

# IDP Async Task Manager
# Background task execution system for IDP scripts to prevent blocking operations
# Allows IDP-agent to remain responsive while long-running tasks execute

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TASK_DIR="$ROOT_DIR/.idp-tasks"
PID_DIR="$TASK_DIR/pids"
LOG_DIR="$TASK_DIR/logs"
STATUS_DIR="$TASK_DIR/status"

# Ensure task directories exist
mkdir -p "$TASK_DIR" "$PID_DIR" "$LOG_DIR" "$STATUS_DIR"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO: $1${NC}"
}

# Usage information
usage() {
    cat << EOF
IDP Async Task Manager

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    run TASK_NAME SCRIPT [ARGS...]  Start task in background
    status [TASK_NAME]              Show task status
    list                           List all tasks
    wait TASK_NAME                 Wait for task completion
    cancel TASK_NAME               Cancel running task
    logs TASK_NAME [--follow]      Show task logs
    cleanup                        Clean up completed tasks
    monitor                        Real-time task monitoring

OPTIONS:
    --json                         JSON output format
    --timeout SECONDS              Task timeout (default: 3600)
    --help                         Show this help message

EXAMPLES:
    $0 run platform-setup ./idp.sh setup                    # Run setup async
    $0 run auth-setup ./auth-management.sh setup-full       # Run auth async
    $0 status platform-setup --json                         # Check status
    $0 list --json                                          # List all tasks
    $0 cancel platform-setup                                # Cancel task
    $0 logs platform-setup --follow                         # Stream logs

EXIT CODES:
    0 - Success
    1 - Error/Failure
    2 - Task not found
    3 - Task already running
    4 - Invalid arguments

EOF
}

# Generate unique task ID
generate_task_id() {
    local base_name="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local random=$(shuf -i 1000-9999 -n 1 2>/dev/null || echo $RANDOM)
    echo "${base_name}_${timestamp}_${random}"
}

# Create task status file
create_task_status() {
    local task_id="$1"
    local task_name="$2"
    local command="$3"
    local start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$STATUS_DIR/${task_id}.json" << EOF
{
  "task_id": "$task_id",
  "task_name": "$task_name",
  "command": "$command",
  "status": "running",
  "start_time": "$start_time",
  "end_time": null,
  "duration": null,
  "exit_code": null,
  "pid": null,
  "progress": 0,
  "stage": "initializing",
  "output": {
    "stdout": "$LOG_DIR/${task_id}.out",
    "stderr": "$LOG_DIR/${task_id}.err"
  }
}
EOF
}

# Update task status
update_task_status() {
    local task_id="$1"
    local status_file="$STATUS_DIR/${task_id}.json"
    
    if [ ! -f "$status_file" ]; then
        return 1
    fi
    
    # Use jq if available, otherwise manual updates
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq "$2" "$status_file" > "$temp_file" && mv "$temp_file" "$status_file"
    else
        # Manual JSON update for simple cases
        case "$2" in
            *status*)
                local new_status="$3"
                sed -i.bak "s/\"status\": \"[^\"]*\"/\"status\": \"$new_status\"/" "$status_file"
                rm -f "${status_file}.bak"
                ;;
        esac
    fi
}

# Task wrapper function
run_task_wrapper() {
    local task_id="$1"
    local task_name="$2"
    shift 2
    local command="$*"
    
    local log_file="$LOG_DIR/${task_id}.out"
    local err_file="$LOG_DIR/${task_id}.err"
    local pid_file="$PID_DIR/${task_id}.pid"
    local status_file="$STATUS_DIR/${task_id}.json"
    
    # Store PID
    echo $$ > "$pid_file"
    
    # Update status with PID
    update_task_status "$task_id" '.pid = '$$
    
    # Set up signal handlers for graceful shutdown
    trap 'cleanup_task "$task_id" SIGTERM' SIGTERM
    trap 'cleanup_task "$task_id" SIGINT' SIGINT
    
    # Update status to running
    update_task_status "$task_id" '.status = "running" | .stage = "executing"'
    
    # Execute command and capture output
    local start_time=$(date +%s)
    local exit_code=0
    
    # Run command with both stdout and stderr captured
    if eval "$command" > "$log_file" 2> "$err_file"; then
        exit_code=0
    else
        exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local end_time_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Update final status
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq ".status = \"$([ $exit_code -eq 0 ] && echo completed || echo failed)\" | 
            .end_time = \"$end_time_iso\" | 
            .duration = $duration | 
            .exit_code = $exit_code | 
            .progress = 100 | 
            .stage = \"$([ $exit_code -eq 0 ] && echo completed || echo failed)\"" \
            "$status_file" > "$temp_file" && mv "$temp_file" "$status_file"
    fi
    
    # Cleanup PID file
    rm -f "$pid_file"
    
    exit $exit_code
}

# Cleanup task on signal
cleanup_task() {
    local task_id="$1"
    local signal="$2"
    
    update_task_status "$task_id" ".status = \"cancelled\" | .stage = \"cancelled by $signal\""
    rm -f "$PID_DIR/${task_id}.pid"
}

# Start task in background
start_task() {
    local task_name="$1"
    shift
    local command="$*"
    
    # Check if task with same name is already running
    for status_file in "$STATUS_DIR"/*.json; do
        if [ -f "$status_file" ]; then
            local existing_name=$(jq -r '.task_name // empty' "$status_file" 2>/dev/null || echo "")
            local existing_status=$(jq -r '.status // empty' "$status_file" 2>/dev/null || echo "")
            
            if [ "$existing_name" = "$task_name" ] && [ "$existing_status" = "running" ]; then
                error "Task '$task_name' is already running"
                return 3
            fi
        fi
    done
    
    # Generate unique task ID
    local task_id
    task_id=$(generate_task_id "$task_name")
    
    # Create task status
    create_task_status "$task_id" "$task_name" "$command"
    
    # Start task in background
    (run_task_wrapper "$task_id" "$task_name" "$command") &
    local task_pid=$!
    
    # Store PID temporarily
    echo "$task_pid" > "$PID_DIR/${task_id}.pid"
    
    log "Started task '$task_name' (ID: $task_id, PID: $task_pid)"
    
    # Return task info as JSON
    echo "{\"task_id\": \"$task_id\", \"task_name\": \"$task_name\", \"pid\": $task_pid, \"status\": \"running\"}"
}

# Get task status
get_task_status() {
    local task_name="$1"
    local json_output="${2:-false}"
    
    # Find most recent task with this name
    local latest_status_file=""
    local latest_time=0
    
    for status_file in "$STATUS_DIR"/*.json; do
        if [ -f "$status_file" ]; then
            local file_task_name=$(jq -r '.task_name // empty' "$status_file" 2>/dev/null || echo "")
            if [ "$file_task_name" = "$task_name" ]; then
                local file_time=$(stat -c %Y "$status_file" 2>/dev/null || stat -f %m "$status_file" 2>/dev/null || echo 0)
                if [ "$file_time" -gt "$latest_time" ]; then
                    latest_time=$file_time
                    latest_status_file="$status_file"
                fi
            fi
        fi
    done
    
    if [ -z "$latest_status_file" ]; then
        if [ "$json_output" = "true" ]; then
            echo "{\"error\": \"Task '$task_name' not found\"}"
        else
            error "Task '$task_name' not found"
        fi
        return 2
    fi
    
    if [ "$json_output" = "true" ]; then
        cat "$latest_status_file"
    else
        local task_id=$(jq -r '.task_id' "$latest_status_file")
        local status=$(jq -r '.status' "$latest_status_file")
        local stage=$(jq -r '.stage // "unknown"' "$latest_status_file")
        local start_time=$(jq -r '.start_time' "$latest_status_file")
        local duration=$(jq -r '.duration // "ongoing"' "$latest_status_file")
        
        info "Task Status: $task_name"
        echo "  ID: $task_id"
        echo "  Status: $status"
        echo "  Stage: $stage"
        echo "  Started: $start_time"
        echo "  Duration: ${duration}s"
    fi
}

# List all tasks
list_tasks() {
    local json_output="${1:-false}"
    
    if [ "$json_output" = "true" ]; then
        echo "{"
        echo "  \"tasks\": ["
        
        local first=true
        for status_file in "$STATUS_DIR"/*.json; do
            if [ -f "$status_file" ]; then
                if [ "$first" = "false" ]; then
                    echo ","
                fi
                cat "$status_file" | sed 's/^/    /'
                first=false
            fi
        done
        
        echo ""
        echo "  ]"
        echo "}"
    else
        info "Active and Recent Tasks:"
        printf "%-20s %-15s %-12s %-20s\n" "TASK NAME" "STATUS" "DURATION" "STARTED"
        printf "%-20s %-15s %-12s %-20s\n" "--------" "------" "--------" "-------"
        
        for status_file in "$STATUS_DIR"/*.json; do
            if [ -f "$status_file" ]; then
                local task_name=$(jq -r '.task_name' "$status_file")
                local status=$(jq -r '.status' "$status_file")
                local duration=$(jq -r '.duration // "ongoing"' "$status_file")
                local start_time=$(jq -r '.start_time' "$status_file" | cut -d'T' -f2 | cut -d'Z' -f1)
                
                printf "%-20s %-15s %-12s %-20s\n" "$task_name" "$status" "${duration}s" "$start_time"
            fi
        done
    fi
}

# Wait for task completion
wait_for_task() {
    local task_name="$1"
    local timeout="${2:-3600}"  # Default 1 hour timeout
    
    info "Waiting for task '$task_name' to complete (timeout: ${timeout}s)..."
    
    local start_wait_time=$(date +%s)
    local status="running"
    
    while [ "$status" = "running" ]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_wait_time))
        
        if [ $elapsed -gt $timeout ]; then
            error "Timeout waiting for task '$task_name'"
            return 1
        fi
        
        # Get current status
        local status_json
        status_json=$(get_task_status "$task_name" true 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            status=$(echo "$status_json" | jq -r '.status // "unknown"')
            
            if [ "$status" != "running" ]; then
                break
            fi
        else
            error "Task '$task_name' not found"
            return 2
        fi
        
        sleep 2
    done
    
    log "Task '$task_name' completed with status: $status"
    get_task_status "$task_name" false
}

# Cancel running task
cancel_task() {
    local task_name="$1"
    
    # Find running task
    for status_file in "$STATUS_DIR"/*.json; do
        if [ -f "$status_file" ]; then
            local file_task_name=$(jq -r '.task_name' "$status_file")
            local file_status=$(jq -r '.status' "$status_file")
            
            if [ "$file_task_name" = "$task_name" ] && [ "$file_status" = "running" ]; then
                local task_id=$(jq -r '.task_id' "$status_file")
                local pid_file="$PID_DIR/${task_id}.pid"
                
                if [ -f "$pid_file" ]; then
                    local task_pid=$(cat "$pid_file")
                    
                    # Send SIGTERM first, then SIGKILL if needed
                    if kill "$task_pid" 2>/dev/null; then
                        log "Sent SIGTERM to task '$task_name' (PID: $task_pid)"
                        sleep 5
                        
                        # Check if still running
                        if kill -0 "$task_pid" 2>/dev/null; then
                            kill -9 "$task_pid" 2>/dev/null && log "Sent SIGKILL to task '$task_name'"
                        fi
                        
                        # Update status
                        update_task_status "$task_id" '.status = "cancelled" | .stage = "cancelled by user"'
                        rm -f "$pid_file"
                        
                        log "Task '$task_name' cancelled"
                        return 0
                    else
                        warn "Could not kill task '$task_name' (PID: $task_pid)"
                        return 1
                    fi
                else
                    warn "PID file not found for task '$task_name'"
                    return 1
                fi
            fi
        fi
    done
    
    error "No running task found with name '$task_name'"
    return 2
}

# Show task logs
show_task_logs() {
    local task_name="$1"
    local follow="${2:-false}"
    
    # Find most recent task
    local latest_status_file=""
    local latest_time=0
    
    for status_file in "$STATUS_DIR"/*.json; do
        if [ -f "$status_file" ]; then
            local file_task_name=$(jq -r '.task_name' "$status_file")
            if [ "$file_task_name" = "$task_name" ]; then
                local file_time=$(stat -c %Y "$status_file" 2>/dev/null || stat -f %m "$status_file" 2>/dev/null || echo 0)
                if [ "$file_time" -gt "$latest_time" ]; then
                    latest_time=$file_time
                    latest_status_file="$status_file"
                fi
            fi
        fi
    done
    
    if [ -z "$latest_status_file" ]; then
        error "Task '$task_name' not found"
        return 2
    fi
    
    local task_id=$(jq -r '.task_id' "$latest_status_file")
    local log_file="$LOG_DIR/${task_id}.out"
    local err_file="$LOG_DIR/${task_id}.err"
    
    info "Logs for task '$task_name' (ID: $task_id):"
    echo ""
    
    if [ "$follow" = "true" ]; then
        if [ -f "$log_file" ]; then
            tail -f "$log_file" &
            local tail_pid=$!
        fi
        
        if [ -f "$err_file" ]; then
            tail -f "$err_file" >&2 &
            local tail_err_pid=$!
        fi
        
        # Wait for Ctrl+C
        trap 'kill $tail_pid $tail_err_pid 2>/dev/null; exit 0' SIGINT
        wait
    else
        if [ -f "$log_file" ]; then
            echo "=== STDOUT ==="
            cat "$log_file"
        fi
        
        if [ -f "$err_file" ] && [ -s "$err_file" ]; then
            echo ""
            echo "=== STDERR ==="
            cat "$err_file"
        fi
    fi
}

# Cleanup completed tasks
cleanup_tasks() {
    local cleaned=0
    
    for status_file in "$STATUS_DIR"/*.json; do
        if [ -f "$status_file" ]; then
            local status=$(jq -r '.status' "$status_file")
            local task_id=$(jq -r '.task_id' "$status_file")
            
            if [ "$status" != "running" ]; then
                rm -f "$status_file"
                rm -f "$LOG_DIR/${task_id}.out"
                rm -f "$LOG_DIR/${task_id}.err"
                rm -f "$PID_DIR/${task_id}.pid"
                ((cleaned++))
            fi
        fi
    done
    
    log "Cleaned up $cleaned completed tasks"
}

# Real-time task monitoring
monitor_tasks() {
    info "Real-time task monitoring (Press Ctrl+C to exit)"
    echo ""
    
    while true; do
        clear
        echo "IDP Async Task Monitor - $(date)"
        echo "========================================"
        
        list_tasks false
        
        sleep 2
    done
}

# Main command handler
main() {
    case "${1:-}" in
        run)
            if [ $# -lt 3 ]; then
                error "Usage: $0 run TASK_NAME SCRIPT [ARGS...]"
                exit 4
            fi
            local task_name="$2"
            shift 2
            start_task "$task_name" "$@"
            ;;
        status)
            if [ -z "${2:-}" ]; then
                error "Please specify task name"
                exit 4
            fi
            local json_output=false
            if [ "${3:-}" = "--json" ]; then
                json_output=true
            fi
            get_task_status "$2" "$json_output"
            ;;
        list)
            local json_output=false
            if [ "${2:-}" = "--json" ]; then
                json_output=true
            fi
            list_tasks "$json_output"
            ;;
        wait)
            if [ -z "${2:-}" ]; then
                error "Please specify task name"
                exit 4
            fi
            wait_for_task "$2" "${3:-3600}"
            ;;
        cancel)
            if [ -z "${2:-}" ]; then
                error "Please specify task name"
                exit 4
            fi
            cancel_task "$2"
            ;;
        logs)
            if [ -z "${2:-}" ]; then
                error "Please specify task name"
                exit 4
            fi
            local follow=false
            if [ "${3:-}" = "--follow" ]; then
                follow=true
            fi
            show_task_logs "$2" "$follow"
            ;;
        cleanup)
            cleanup_tasks
            ;;
        monitor)
            monitor_tasks
            ;;
        --help|help)
            usage
            ;;
        *)
            if [ -n "${1:-}" ]; then
                error "Unknown command: $1"
            else
                error "No command specified"
            fi
            echo ""
            usage
            exit 4
            ;;
    esac
}

# Run main function with all arguments
main "$@"
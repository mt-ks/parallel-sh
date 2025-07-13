#!/bin/bash

set -e


commands=(
  "npm run test:group1"
  "npm run test:group2"
  "npm run test:group1"
  "npm run test:group2"
  "npm run test:group1"
  "npm run test:group2"
)

command_names=(
  "user-test"
  "calculator-test"
  "user-test-copy1"
  "calculator-test-copy1"
  "user-test-copy2"
  "calculator-test-copy2"
)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Default parallel execution count
DEFAULT_PARALLEL_COUNT=4

# Parse command line arguments
PARALLEL_COUNT=$DEFAULT_PARALLEL_COUNT
DETACHED=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--parallel)
      PARALLEL_COUNT="$2"
      shift 2
      ;;
    -d|--detached)
      DETACHED=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  -p, --parallel COUNT    Number of commands to run in parallel (default: $DEFAULT_PARALLEL_COUNT)"
      echo "  -h, --help            Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

# Validate parallel count
if ! [[ "$PARALLEL_COUNT" =~ ^[0-9]+$ ]] || [ "$PARALLEL_COUNT" -lt 1 ]; then
  echo -e "${RED}❌ Invalid parallel count: $PARALLEL_COUNT. Must be a positive integer.${NC}"
  exit 1
fi


SESSION_NAME="parallel-tests"
TEMP_DIR="/tmp/parallel-tests-$(date +%s)"
FAILED_TESTS_FILE="$TEMP_DIR/failed_tests.txt"
DETAILED_FAILURES_FILE="$TEMP_DIR/detailed_failures.txt"
FAILED_TEST_CASES_FILE="$TEMP_DIR/failed_test_cases.txt"
BATCH_PROGRESS_FILE="$TEMP_DIR/batch_progress.txt"
QUEUE_FILE="$TEMP_DIR/command_queue.txt"

# Create temporary directory
mkdir -p "$TEMP_DIR"
echo "# Failed Tests Summary" > "$FAILED_TESTS_FILE"
echo "# Detailed Test Failures" > "$DETAILED_FAILURES_FILE"
echo "# Failed Test Cases" > "$FAILED_TEST_CASES_FILE"
echo "# Batch Progress" > "$BATCH_PROGRESS_FILE"

# Record start time for duration calculation
START_TIME=$(date +%s)

# Cleanup function to remove temporary directory
cleanup() {
  echo ""
  echo -e "${YELLOW}🧹 Cleaning up...${NC}"
  if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}

# Exit trap
trap cleanup EXIT

# Test failure parser function to parse test failures
parse_test_failures() {
  local test_name="$1"
  local output_file="$2"
  
  echo "" >> "$DETAILED_FAILURES_FILE"
  echo "## $test_name Failures:" >> "$DETAILED_FAILURES_FILE"
  echo "================================" >> "$DETAILED_FAILURES_FILE"
  
  # Parse failed tests from Jest output
if [ -f "$output_file" ]; then
  # Find test files and failed test names
  grep -E "FAIL|✕" "$output_file" | while read -r line; do
    if [[ "$line" =~ \.test\.js|\.spec\.js ]]; then
      # Extract test file name
      test_file=$(echo "$line" | grep -o '[^/]*\.test\.js\|[^/]*\.spec\.js' | head -1)
      if [ -n "$test_file" ]; then
        echo "📁 Test File: $test_file" >> "$DETAILED_FAILURES_FILE"
      fi
    fi
    
    # Find failed test cases with full test name
    if [[ "$line" =~ ✕ ]]; then
      # Extract the full test name (everything after ✕)
      test_case=$(echo "$line" | sed 's/.*✕ //')
      if [ -n "$test_case" ]; then
        echo "   $test_case" >> "$DETAILED_FAILURES_FILE"
      fi
    fi
    
    # Also look for FAIL lines with test names
    if [[ "$line" =~ FAIL ]]; then
      # Extract test name from FAIL line (format: [FAIL] - [suite] [test] › test_name)
      test_name=$(echo "$line" | sed -n 's/.*\[FAIL\] - \[\([^]]*\)\] \[\([^]]*\)\] › \(.*\)/\1.\2: \3/p')
      if [ -n "$test_name" ]; then
        echo "  ❌ $test_name" >> "$DETAILED_FAILURES_FILE"
      fi
    fi
  done
  
  # Add error messages
  echo "" >> "$DETAILED_FAILURES_FILE"
  echo "Error Details:" >> "$DETAILED_FAILURES_FILE"
  grep -A 5 -B 2 "Error:" "$output_file" | head -20 >> "$DETAILED_FAILURES_FILE"
fi
}

# Detailed test case failure parser
parse_failed_test_cases() {
  local test_name="$1"
  local output_file="$2"
  
  if [ -f "$output_file" ]; then
    echo "" >> "$FAILED_TEST_CASES_FILE"
    echo "## $test_name Failed Test Cases:" >> "$FAILED_TEST_CASES_FILE"
    echo "=====================================" >> "$FAILED_TEST_CASES_FILE"
    
    # Find FAIL lines in Jest output
if grep -q "FAIL" "$output_file"; then
  # Find line number of FAIL line
  fail_line_num=$(grep -n "FAIL" "$output_file" | head -1 | cut -d: -f1)
  
  if [ -n "$fail_line_num" ]; then
    # Get 20 lines before FAIL line and find test cases
    start_line=$((fail_line_num - 20))
    if [ $start_line -lt 1 ]; then
      start_line=1
    fi
    
    # Get lines in this range
    sed -n "${start_line},${fail_line_num}p" "$output_file" | while read -r line; do
      # Look for test case format: 4 spaces + test_name (duration)
      # Check with simple grep
      if echo "$line" | grep -q "^    [^(]*([0-9]* ms)"; then
        # Extract test case name
        test_case=$(echo "$line" | sed 's/^[[:space:]]*\([^(]*\) (.*/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Extract duration
        duration=$(echo "$line" | sed -n 's/.*(\([0-9]* ms\)).*/\1/p')
        
        if [ -n "$test_case" ]; then
          # Find file path (in lines before FAIL line)
          file_path=$(sed -n "1,${fail_line_num}p" "$output_file" | grep -E "\.test\.js|\.spec\.js" | tail -1 | sed 's/.*\(src\/.*\.test\.js\|src\/.*\.spec\.js\).*/\1/')
          
          if [ -n "$file_path" ]; then
            echo "📁 $file_path" >> "$FAILED_TEST_CASES_FILE"
          fi
          
          echo "   ✕ $test_case" >> "$FAILED_TEST_CASES_FILE"
          if [ -n "$duration" ]; then
            echo "     ⏱️  Duration: $duration" >> "$FAILED_TEST_CASES_FILE"
          fi
          echo "" >> "$FAILED_TEST_CASES_FILE"
        fi
      fi
    done
  fi
else
  echo "   No FAIL status found in output" >> "$FAILED_TEST_CASES_FILE"
fi
  fi
}

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
  echo -e "${RED}⚠️  'tmux' is not installed.${NC}"

  unameOut="$(uname -s)"
  case "${unameOut}" in
      Linux*)
        if command -v apt &> /dev/null; then
          echo -e "${BLUE}📦 Installing tmux with apt...${NC}"
          sudo apt update && sudo apt install -y tmux
        elif command -v dnf &> /dev/null; then
          echo -e "${BLUE}📦 Installing tmux with dnf...${NC}"
          sudo dnf install -y tmux
        elif command -v pacman &> /dev/null; then
          echo -e "${BLUE}📦 Installing tmux with pacman...${NC}"
          sudo pacman -Sy tmux --noconfirm
        else
          echo -e "${RED}❌ Cannot install tmux automatically on this Linux distro.${NC}"
          exit 1
        fi
        ;;
      Darwin*)
        echo -e "${BLUE}📦 Installing tmux with Homebrew...${NC}"
        if ! command -v brew &> /dev/null; then
          echo -e "${RED}❌ Homebrew not found. Please install Homebrew first: https://brew.sh/${NC}"
          exit 1
        fi
        brew install tmux
        ;;
      CYGWIN*|MINGW*|MSYS*)
        echo -e "${RED}❌ Windows detected. Please use WSL or manually install tmux.${NC}"
        exit 1
        ;;
      *)
        echo -e "${RED}❌ Unknown OS. Cannot install tmux.${NC}"
        exit 1
        ;;
  esac
fi

# Check if tmux session exists
if tmux has-session -t $SESSION_NAME 2>/dev/null; then
  echo -e "${YELLOW}⚠️ Existing tmux session '$SESSION_NAME' found. Killing it...${NC}"
  tmux kill-session -t $SESSION_NAME
  sleep 1
fi

echo -e "${CYAN}🚀 Starting all commands with $PARALLEL_COUNT parallel processes...${NC}"

# Create initial session
if tmux has-session -t $SESSION_NAME 2>/dev/null; then
  tmux kill-session -t $SESSION_NAME
  sleep 1
fi
tmux new-session -d -s $SESSION_NAME

# Run commands sequentially, up to parallel limit
cmd_idx=0
running=0

while [ $cmd_idx -lt ${#commands[@]} ] || [ $running -gt 0 ]; do
  # Check for completed commands
  for name in "${command_names[@]}"; do
    if [ -f "$TEMP_DIR/${name}_done" ]; then
      if [ ! -f "$TEMP_DIR/${name}_processed" ]; then
        touch "$TEMP_DIR/${name}_processed"
        ((running--))
        echo -e "${GREEN}✅ $name completed${NC}"
      fi
    fi
  done
  
  # Start new commands if we have capacity
  while [ $running -lt $PARALLEL_COUNT ] && [ $cmd_idx -lt ${#commands[@]} ]; do
    cmd="${commands[$cmd_idx]}"
    name="${command_names[$cmd_idx]}"
    
    # Create new pane for this command
    if [ $running -eq 0 ]; then
      # First command uses existing pane
      tmux send-keys -t $SESSION_NAME "export TERM=xterm-256color && export FORCE_COLOR=1 && export NODE_OPTIONS='--max_old_space_size=4096' && echo '🚀 Starting: $name' && $cmd 2>&1 | tee $TEMP_DIR/${name}_output.log; exit_code=\$?; if [ \$exit_code -eq 0 ]; then echo '✅ $name PASSED' >> $TEMP_DIR/${name}_success.log; else echo '❌ $name FAILED (exit code: \$exit_code)' >> $FAILED_TESTS_FILE; echo '❌ $name FAILED (exit code: \$exit_code)' >> $TEMP_DIR/${name}_failed.log; fi; touch $TEMP_DIR/${name}_done; exit" C-m
    else
      # Split window for additional commands
      tmux split-window -t $SESSION_NAME
      tmux select-layout -t $SESSION_NAME tiled
      tmux send-keys -t $SESSION_NAME "export TERM=xterm-256color && export FORCE_COLOR=1 && export NODE_OPTIONS='--max_old_space_size=4096' && echo '🚀 Starting: $name' && $cmd 2>&1 | tee $TEMP_DIR/${name}_output.log; exit_code=\$?; if [ \$exit_code -eq 0 ]; then echo '✅ $name PASSED' >> $TEMP_DIR/${name}_success.log; else echo '❌ $name FAILED (exit code: \$exit_code)' >> $FAILED_TESTS_FILE; echo '❌ $name FAILED (exit code: \$exit_code)' >> $TEMP_DIR/${name}_failed.log; fi; touch $TEMP_DIR/${name}_done; exit" C-m
    fi
    
    echo -e "${YELLOW}🚀 Started: $name${NC}"
    ((cmd_idx++))
    ((running++))
    sleep 0.5
  done
  
  sleep 1
done

# Wait for all commands to complete
echo -e "${YELLOW}⏳ Waiting for all tests to complete...${NC}"
while [ $(ls $TEMP_DIR/*_done 2>/dev/null | wc -l) -lt ${#commands[@]} ]; do
  sleep 1
done

# Parse all results
echo -e "${CYAN}📊 Parsing test results...${NC}"
for i in "${!command_names[@]}"; do
  name="${command_names[$i]}"
  output_file="$TEMP_DIR/${name}_output.log"
  
  if [ -f "$output_file" ]; then
    parse_failed_test_cases "$name" "$output_file"
    parse_test_failures "$name" "$output_file"
  fi
done


# Show raw test outputs first
echo ""
echo -e "${BLUE}📁 Raw test outputs:${NC}"
for log_file in $TEMP_DIR/*_output.log; do
  if [ -f "$log_file" ]; then
    echo ""
    echo -e "${WHITE}--- $(basename "$log_file" .log) ---${NC}"
    cat "$log_file"
  fi
done

# Show detailed failed test cases
if [ -s "$FAILED_TEST_CASES_FILE" ]; then
  echo ""
  echo -e "${PURPLE}📋 Failed Test Cases:${NC}"
  echo -e "${PURPLE}=====================${NC}"
  cat "$FAILED_TEST_CASES_FILE"
fi

# Show detailed failure information
if [ -s "$DETAILED_FAILURES_FILE" ]; then
  echo ""
  echo -e "${CYAN}📋 Detailed Test Failures:${NC}"
  echo -e "${CYAN}==========================${NC}"
  cat "$DETAILED_FAILURES_FILE"
fi

# Calculate total duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Show final results summary at the end
echo ""
echo -e "${WHITE}📊 Final Test Results Summary:${NC}"
echo -e "${WHITE}==============================${NC}"
echo -e "${CYAN}⏱️  Total Duration: ${MINUTES}m ${SECONDS}s${NC}"

# Analyze test results
passed_tests=()
failed_tests=()

for i in "${!command_names[@]}"; do
  name="${command_names[$i]}"
  output_file="$TEMP_DIR/${name}_output.log"
  
  if [ -f "$output_file" ]; then
    if grep -q "FAIL" "$output_file"; then
      failed_tests+=("$name")
    else
      passed_tests+=("$name")
    fi
  fi
done

# Show successful tests
echo ""
if [ ${#passed_tests[@]} -gt 0 ]; then
  echo -e "${GREEN}✅ PASSED Tests:${NC}"
  for test in "${passed_tests[@]}"; do
    echo -e "${GREEN}✅ $test PASSED${NC}"
  done
fi

# Show failed tests
if [ ${#failed_tests[@]} -gt 0 ]; then
  echo ""
  echo -e "${RED}❌ FAILED Tests:${NC}"
  for test in "${failed_tests[@]}"; do
    echo -e "${RED}❌ $test FAILED${NC}"
  done
  
  echo ""
  echo -e "${RED}🚫 Push blocked! Tests failed. Please fix the failing tests before pushing.${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}🎉 All tests passed! 🎉${NC}"
  exit 0
fi
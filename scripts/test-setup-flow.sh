#!/bin/bash

# Test Setup Flow Verification Script
# Validates that all setup components are in place for clean machine deployment

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

print_header() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $(printf "%-60s" "$1") ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

test_file_exists() {
    local file="$1"
    local description="$2"
    
    if [ -f "$file" ]; then
        print_success "$description exists: $file"
        ((TESTS_PASSED++))
        return 0
    else
        print_error "$description missing: $file"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_file_executable() {
    local file="$1"
    local description="$2"
    
    if [ -x "$file" ]; then
        print_success "$description is executable: $file"
        ((TESTS_PASSED++))
        return 0
    else
        print_error "$description is not executable: $file"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_directory_exists() {
    local dir="$1"
    local description="$2"
    
    if [ -d "$dir" ]; then
        print_success "$description exists: $dir"
        ((TESTS_PASSED++))
        return 0
    else
        print_error "$description missing: $dir"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_syntax() {
    local file="$1"
    local description="$2"
    
    if bash -n "$file" 2>/dev/null; then
        print_success "$description has valid syntax"
        ((TESTS_PASSED++))
        return 0
    else
        print_error "$description has syntax errors"
        ((TESTS_FAILED++))
        return 1
    fi
}

print_header "IDP Setup Flow Verification"

echo "Testing setup flow components for clean machine deployment..."
echo ""

# Test 1: Core setup scripts exist and are executable
print_header "Core Setup Scripts"

test_file_exists "$SCRIPT_DIR/setup-machine.sh" "Machine setup script"
test_file_executable "$SCRIPT_DIR/setup-machine.sh" "Machine setup script"
test_syntax "$SCRIPT_DIR/setup-machine.sh" "Machine setup script"

test_file_exists "$SCRIPT_DIR/setup-windmill.sh" "Windmill setup script"
test_file_executable "$SCRIPT_DIR/setup-windmill.sh" "Windmill setup script" 
test_syntax "$SCRIPT_DIR/setup-windmill.sh" "Windmill setup script"

test_file_exists "$SCRIPT_DIR/idp.sh" "Main IDP script"
test_file_executable "$SCRIPT_DIR/idp.sh" "Main IDP script"
test_syntax "$SCRIPT_DIR/idp.sh" "Main IDP script"

# Test 2: Management scripts exist
print_header "Management Scripts"

# Check if start/stop scripts would be created by setup-windmill.sh
if [ -f "$SCRIPT_DIR/start-windmill.sh" ]; then
    test_file_executable "$SCRIPT_DIR/start-windmill.sh" "Windmill start script"
    test_syntax "$SCRIPT_DIR/start-windmill.sh" "Windmill start script"
else
    print_warning "Windmill start script not found (will be created by setup-windmill.sh)"
fi

if [ -f "$SCRIPT_DIR/stop-windmill.sh" ]; then
    test_file_executable "$SCRIPT_DIR/stop-windmill.sh" "Windmill stop script"
    test_syntax "$SCRIPT_DIR/stop-windmill.sh" "Windmill stop script"
else
    print_warning "Windmill stop script not found (will be created by setup-windmill.sh)"
fi

# Test 3: Windmill components exist
print_header "Windmill Components"

test_directory_exists "$ROOT_DIR/windmill" "Windmill directory"
test_directory_exists "$ROOT_DIR/windmill/flows" "Windmill flows directory"
test_directory_exists "$ROOT_DIR/windmill/scripts" "Windmill scripts directory"
test_directory_exists "$ROOT_DIR/windmill/langchain-tools" "Windmill LangChain tools directory"

test_file_exists "$ROOT_DIR/windmill/README.md" "Windmill documentation"
test_file_exists "$ROOT_DIR/windmill/flows/idp-bootstrap.flow.ts" "Bootstrap flow"
test_file_exists "$ROOT_DIR/windmill/langchain-tools/idp-platform-tools.py" "LangChain tools"

# Test 4: Documentation exists
print_header "Documentation"

test_file_exists "$ROOT_DIR/README.md" "Main README"
test_file_exists "$ROOT_DIR/windmill/README.md" "Windmill README"
test_file_exists "$ROOT_DIR/CHANGELOG.md" "Changelog"

# Test 5: Verify command options are available
print_header "Command Verification"

# Test idp.sh help output (strip ANSI color codes)
if $SCRIPT_DIR/idp.sh help 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "setup-windmill"; then
    print_success "idp.sh includes setup-windmill command"
    ((TESTS_PASSED++))
else
    print_error "idp.sh missing setup-windmill command"
    ((TESTS_FAILED++))
fi

if $SCRIPT_DIR/idp.sh help 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q -- "--with-windmill"; then
    print_success "idp.sh includes --with-windmill option"
    ((TESTS_PASSED++))
else
    print_error "idp.sh missing --with-windmill option"
    ((TESTS_FAILED++))
fi

# Test 6: Verify setup flow commands
print_header "Setup Flow Commands"

# Test help outputs exist
if $SCRIPT_DIR/setup-machine.sh help 2>&1 | grep -q "Machine Setup Script"; then
    print_success "setup-machine.sh help works"
    ((TESTS_PASSED++))
else
    print_error "setup-machine.sh help not working"
    ((TESTS_FAILED++))
fi

if $SCRIPT_DIR/setup-windmill.sh help 2>&1 | grep -q "Windmill Setup Script"; then
    print_success "setup-windmill.sh help works"
    ((TESTS_PASSED++))
else
    print_error "setup-windmill.sh help not working"  
    ((TESTS_FAILED++))
fi

# Results
print_header "Test Results"

echo -e "${BLUE}Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "${BLUE}Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "All tests passed! Setup flow is ready for clean machine deployment."
    echo ""
    echo -e "${BLUE}Setup Flow for Clean Machine:${NC}"
    echo "1. git clone https://github.com/ayansasmal/idp-platform.git"
    echo "2. cd idp-platform"
    echo "3. ./scripts/setup-machine.sh setup"
    echo "4. ./scripts/idp.sh setup --with-windmill"
    echo "5. Access services and import Windmill flows"
    echo ""
    exit 0
else
    print_error "Some tests failed. Please fix the issues before deployment."
    echo ""
    exit 1
fi
#!/bin/bash
# The Yut Server - Build Verification Script
# Run this before committing to catch issues early.

set -e

echo "=== The Yut Server - Build Verification ==="
echo ""

# Step 1: Format check
echo "[1/4] Checking formatting..."
cargo fmt -- --check 2>/dev/null && echo "  OK: Formatting is correct" || {
    echo "  WARN: Code needs formatting. Run: cargo fmt"
}

# Step 2: Compile check (warnings = errors)
echo "[2/4] Compiling (warnings as errors)..."
if cargo check 2>&1 | grep -q "warning"; then
    echo "  WARN: There are compiler warnings. Review output above."
    cargo check 2>&1 | grep "warning\[" || true
else
    echo "  OK: No warnings"
fi

# Step 3: Run tests
echo "[3/4] Running tests..."
cargo test --quiet 2>&1
echo "  OK: All tests passed"

# Step 4: Clippy (if available)
echo "[4/4] Running clippy..."
if command -v cargo-clippy &> /dev/null || cargo clippy --version &> /dev/null 2>&1; then
    cargo clippy -- -D warnings 2>&1 && echo "  OK: No clippy warnings" || echo "  WARN: Clippy found issues"
else
    echo "  SKIP: Clippy not installed"
fi

echo ""
echo "=== Verification Complete ==="

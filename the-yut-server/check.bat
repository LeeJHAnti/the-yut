@echo off
REM The Yut Server - Build Verification Script (Windows)
REM Run this before committing to catch issues early.

echo === The Yut Server - Build Verification ===
echo.

echo [1/4] Checking formatting...
cargo fmt -- --check 2>nul
if %ERRORLEVEL% EQU 0 (
    echo   OK: Formatting is correct
) else (
    echo   WARN: Code needs formatting. Run: cargo fmt
)

echo [2/4] Compiling...
cargo check 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   OK: Compilation successful
) else (
    echo   FAIL: Compilation failed!
    exit /b 1
)

echo [3/4] Running tests...
cargo test --quiet 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   OK: All tests passed
) else (
    echo   FAIL: Some tests failed!
    exit /b 1
)

echo [4/4] Running clippy...
cargo clippy -- -D warnings 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   OK: No clippy warnings
) else (
    echo   WARN: Clippy found issues
)

echo.
echo === Verification Complete ===

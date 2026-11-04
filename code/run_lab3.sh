#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
# Use the same QEMU 4.1.1 installation as the previous experiments.
for lab3_qemu in "$HOME/opt/qemu-4.1.1/bin/qemu-system-riscv64" "$HOME/software/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64" "$HOME/software/qemu-4.1.1/build-debug/riscv64-softmmu/qemu-system-riscv64"; do
    if [[ -x "$lab3_qemu" ]]; then
        export PATH="$(dirname -- "$lab3_qemu"):$PATH"
        break
    fi
done
command -v riscv64-unknown-elf-gcc >/dev/null || { echo '找不到 riscv64-unknown-elf-gcc，请在之前完成 Lab2 的 Ubuntu 环境运行。'; exit 1; }
command -v qemu-system-riscv64 >/dev/null || { echo '找不到 QEMU，请使用之前 Lab2 的 PATH 配置。'; exit 1; }
qemu-system-riscv64 --version | head -n 1
if ! qemu-system-riscv64 --version | head -n 1 | grep -q 'version 4\.1\.1'; then
    echo '当前 QEMU 不是老师要求的 4.1.1，请先将 4.1.1 的 bin 目录加入 PATH。'
    exit 1
fi
lab3_arch=rv64imac_zicsr_zifencei
if ! printf '.text\ncsrr a0, sstatus\n' | riscv64-unknown-elf-gcc -march="$lab3_arch" -mabi=lp64 -x assembler -c -o /dev/null - >/dev/null 2>&1; then
    lab3_arch=rv64imac
fi
case "${1:-run}" in
run) make clean; make RISCV_ARCH="$lab3_arch" qemu ;;
grade) mkdir -p results; make RISCV_ARCH="$lab3_arch" grade 2>&1 | tee results/grade.log ;;
build) make clean; make RISCV_ARCH="$lab3_arch" ;;
*) echo '用法：bash run_lab3.sh [run|grade|build]'; exit 2 ;;
esac

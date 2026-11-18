# Lab4 提示词与 SPEC

本文件对应 ucore RISC-V Lab4：虚拟内存页操作、内核线程创建与进程调度。以下提示词根据当前工程整理，用于复现实现、检查接口和复核实验结果。实测结论以 WSL 终端输出和仓库截图为依据。

## 1. 虚拟内存页操作提示词

```text
[PROMPT]
阅读 kern/mm/pmm.c 和相关页表头文件，定位 LAB4 function1 标记。
在标记处实现 4 KiB 页映射的建立、权限更新、替换和撤销。
沿用现有 get_pte()、页分配接口和评分测试，保留教师要求的标记及学号。

[RELY]
类型和宏：pde_t、pte_t、struct Page、PDX1、PTE_V、PTE_R、PTE_W、PTE_X、PTE_U、E_NO_MEM。
已有接口：get_pte()、pte_create()、pte2page()、pde2page()、page2ppn()、
page_ref_inc()、page_ref_dec()、free_page()、tlb_invalidate()。
RISC-V 指令：sfence.vma。

[GUARANTEE]
实现以下函数：
int page_insert(pde_t *pgdir, struct Page *page, uintptr_t la, uint32_t perm);
void page_remove(pde_t *pgdir, uintptr_t la);
static void page_remove_pte(pde_t *pgdir, uintptr_t la, pte_t *ptep);

[SPECIFICATION]
1. page_insert() 调用 get_pte(pgdir, la, 1) 查找或创建叶页表项。
   - 原地址无有效映射时，增加目标物理页的引用计数。
   - 原地址已映射到同一物理页时，只更新权限，保持引用计数。
   - 原地址映射到另一物理页时，增加新页引用并撤销旧映射。
   - 用 pte_create() 生成叶项。未指定 R/W/X 或出现 W=1、R=0 时补 R，
     保留合法的仅执行权限。更新后失效对应地址的 TLB 翻译，返回 0。
   - 获取叶项失败时返回 -E_NO_MEM。如果本次已安装根项，但下一级
     分配失败，则恢复原根项、执行 sfence.vma 并释放本次分配的页表页。
     目标数据页的引用计数保持原值。
2. page_remove() 调用 get_pte(pgdir, la, 0)，查找过程不分配页表页。
   未找到叶项或叶项无效时直接返回。重复删除同一地址不会重复扣减引用。
3. page_remove_pte() 对有效叶项先取得旧物理页，再清零 PTE、
   失效对应 TLB 翻译并扣减引用计数。引用计数减至 0 时释放物理页。
输出实现代码，并说明同页更新、异页替换和分配失败时分别改变了哪些状态。
```

## 2. 内核线程创建与初始化提示词

```text
[PROMPT]
阅读 kern/process/proc.c、kern/process/proc.h 和线程首次启动相关汇编，
定位 LAB4 function2 标记。在标记处实现 PCB 初始化、idleproc 登记、
initproc 创建以及新线程运行现场的构造。
保持 kernel_thread() 的函数签名、已有汇编入口和评分代码。

[RELY]
数据结构：struct proc_struct、struct context、struct trapframe。
全局对象：proc_list、hash_list、idleproc、initproc、current、nr_process、
bootstack、boot_pgdir_pa。
宏和错误码：PROC_UNINIT、PROC_RUNNABLE、MAX_PROCESS、KSTACKSIZE、
CLONE_VM、SSTATUS_SPP、SSTATUS_SPIE、SSTATUS_SIE、E_NO_MEM、E_NO_FREE_PROC。
已有接口：kmalloc()、kfree()、memset()、list_init()、list_add_before()、
setup_kstack()、put_kstack()、get_pid()、hash_proc()、find_proc()、
set_proc_name()、wakeup_proc()、read_csr()、local_intr_save()、
local_intr_restore()、panic()。
已有入口：init_main、kernel_thread_entry、forkret、forkrets、__trapret。

[GUARANTEE]
实现以下函数：
static struct proc_struct *alloc_proc(void);
void proc_init(void);
int kernel_thread(int (*fn)(void *), void *arg, uint32_t clone_flags);
int do_fork(uint32_t clone_flags, uintptr_t stack, struct trapframe *tf);
static void copy_thread(struct proc_struct *proc, uintptr_t esp, struct trapframe *tf);
static int copy_mm(uint32_t clone_flags, struct proc_struct *proc);

[SPECIFICATION]
1. alloc_proc() 申请 PCB。失败时返回 NULL。成功时清零结构体，
   设置 state=PROC_UNINIT、pid=-1、pgdir=boot_pgdir_pa，并初始化链表结点。
2. proc_init() 初始化进程链表和哈希桶。idleproc 复用 bootstack，
   PID 为 0，状态为 PROC_RUNNABLE，并设置 need_resched=1 和 current。
   通过 kernel_thread() 创建 initproc，入口为 init_main，参数为
   "Hello world!!"。按返回的 PID 查找新线程，确认其 PID 为 1，
   并设定线程名。启动阶段创建失败时报告错误。
3. kernel_thread() 清零临时 trapframe，用 s0 保存 fn，用 s1 保存 arg。
   将 epc 指向 kernel_thread_entry，设置 SPP、SPIE 并清除 SIE。
   调用 do_fork(clone_flags | CLONE_VM, 0, &tf)，返回子线程 PID 或错误码。
4. do_fork() 检查线程数量上限，依次申请 PCB 和独立内核栈，
   设置父线程并调用 copy_mm()、copy_thread()。失败时逆序释放已申请
   的资源并返回错误码。成功后在本地中断保护下分配 PID、登记到
   哈希表和进程链表、更新计数并唤醒线程，最终返回子线程 PID。
5. copy_thread() 将 trapframe 复制到新内核栈顶部，子线程 a0 置 0。
   esp 非零时作为恢复后的 sp，否则使用新 trapframe 的地址。
   context.ra 指向 forkret，context.sp 指向新 trapframe。
6. copy_mm() 检查当前线程的 mm 为 NULL。内核线程共享 boot_pgdir_pa，
   本实验不建立独立用户地址空间，成功时返回 0。
输出实现代码，并说明 context.ra 和 trapframe.epc 如何分别决定首次运行的入口。
```

## 3. 进程调度与上下文切换提示词

```text
[PROMPT]
阅读 kern/process/proc.c、kern/schedule/sched.c、kern/process/switch.S
及 struct context 的定义，定位 LAB4 function3 标记。
在对应位置实现单核协作式调度，分别处理选线程、更新页表和寄存器切换。

[RELY]
数据结构和宏：struct proc_struct、struct context、list_entry_t、
proc_list、current、idleproc、PROC_RUNNABLE、need_resched、runs、
SATP_MODE_SV39、RISCV_PGSHIFT、REGBYTES、STORE、LOAD。
已有接口：list_next()、le2proc()、local_intr_save()、local_intr_restore()、
write_csr()、flush_tlb()。
首次运行链路：forkret → forkrets → __trapret → sret → kernel_thread_entry。

[GUARANTEE]
在 kern/process/proc.c 中实现：
void cpu_idle(void);
void proc_run(struct proc_struct *proc);

在 kern/schedule/sched.c 中实现：
void schedule(void);

在 kern/process/switch.S 中实现与下列接口对应的汇编入口：
void switch_to(struct context *from, struct context *to);

[SPECIFICATION]
1. cpu_idle() 循环检查当前线程的 need_resched，置位时调用 schedule()。
2. schedule() 保存并关闭本地中断，清除当前线程的 need_resched。
   当前线程为 idleproc 时从链表头之后开始查找，否则从当前结点的
   后继开始循环扫描。跳过链表哨兵，选取第一个 PROC_RUNNABLE 线程。
   没有可运行线程时选 idleproc。将所选线程的 runs 加一；所选线程
   与当前线程不同时调用 proc_run()。原执行流恢复后还原本层中断状态。
3. proc_run() 检查目标线程，目标已经是 current 时直接返回。
   否则保存并关闭本地中断，记录旧线程、更新 current，将 Sv39 模式
   和新根页表的物理页号写入 satp，刷新 TLB 后调用 switch_to()。
   原线程再次被调度后，从调用点继续并恢复其保存的中断状态。
4. switch_to() 中 a0 指向旧 context，a1 指向新 context。
   按 struct context 的字段顺序，以 REGBYTES 为步长保存旧线程的
   ra、sp、s0～s11，再恢复新线程的相同寄存器。用 ret 跳转到恢复出的 ra。
   新线程首次执行时进入 forkret；已有现场的线程从原切换点继续。
输出实现代码，并解释调度决策、页表切换和寄存器切换的职责。
```

## 4. 三个功能模块的 SPEC 与接口汇总

| 功能模块 | 输入与依赖 | 交付内容 | 验收依据 |
| --- | --- | --- | --- |
| 虚拟内存页操作 | Sv39 根页表、虚拟地址、物理页、权限和现有页表接口 | `page_insert()`、`page_remove()` 及内部辅助函数 | 启动自检与课程 PMM 项目通过，代码覆盖同页更新、异页替换、删除和分配失败 |
| 进程创建与初始化 | 当前执行流、启动栈、进程链表、内核栈和陷阱帧接口 | `alloc_proc()`、`proc_init()`、`kernel_thread()`、`do_fork()`、`copy_thread()`、`copy_mm()` | 课程 Process Create 项目通过，普通启动时 `initproc` 以 PID 1 运行并收到正确实参 |
| 进程调度与切换 | 就绪状态、进程链表、页表根、`struct context` 和本地中断接口 | `cpu_idle()`、`schedule()`、`proc_run()`、`switch_to()` | 课程 Schedule 项目通过，测试中的两个线程均实际执行到各自入口 |

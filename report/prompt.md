# Lab4 实验提示词

## 1. 虚拟内存页操作

````text
[PROMPT]
实现 uCore RISC-V Lab4 的虚拟内存页操作。只填写 kern/mm/pmm.c 中 LAB4 function1 标记所在区域，保留标记、现有 get_pte() 和测试。使用现有页表遍历和页分配接口，维护叶 PTE、物理页引用计数和本地 TLB。

[RELY]
类型和宏：pde_t、pte_t、struct Page、PDX1、PTE_V、PTE_R、PTE_W、PTE_X、PTE_U、E_NO_MEM。
已有函数：get_pte()、pte_create()、pte2page()、pde2page()、page2ppn()、page_ref_inc()、page_ref_dec()、free_page()、tlb_invalidate()。
RISC-V 指令：sfence.vma；普通叶映射更新使用模板提供的地址级 TLB 失效接口。

[GUARANTEE]
- 实现 int page_insert(pde_t *pgdir, struct Page *page, uintptr_t la, uint32_t perm)。
- 实现 void page_remove(pde_t *pgdir, uintptr_t la)。
- 实现内部辅助函数 static void page_remove_pte(pde_t *pgdir, uintptr_t la, pte_t *ptep)。

[SPECIFICATION]
- page_insert()：调用 get_pte(pgdir, la, 1) 获取 4 KiB 叶槽。旧槽无映射时将新页引用数加一；旧映射是同一物理页时只更新权限；旧映射是另一物理页时为新页增加引用，并撤销旧页映射。用 pte_create() 重建叶项，perm 未提供 R/W/X 或只给 W 等会导致 W=1、R=0 时补 R，合法的 X-only 保持原权限。刷新该地址的 TLB 后返回 0。获取叶槽失败时返回 -E_NO_MEM；如果本次已新建根项指向的中间表，则恢复根项、执行全局 sfence.vma，再释放该表页。失败时目标数据页引用数保持原值。
- page_remove()：调用 get_pte(pgdir, la, 0) 只查现有叶槽。没有叶槽或叶项无效时直接返回。有效映射交给 page_remove_pte() 撤销。重复删除同一地址不再扣减引用数。
- page_remove_pte()：对有效叶项先取得旧物理页，再清零 PTE、失效对应地址的 TLB 翻译、将旧页引用数减一。引用数减至 0 时释放该页；无效叶项不做操作。
````

## 2. 进程创建与初始化

````text
[PROMPT]
实现 uCore RISC-V Lab4 的内核线程创建与初始化。只填写 kern/process/proc.c 中 LAB4 function2 标记所在区域。沿用教师提供的线程入口、陷阱返回和内核栈辅助函数，保持头文件接口与评分代码。

[RELY]
数据结构和宏：struct proc_struct、struct context、struct trapframe、proc_list、hash_list、idleproc、initproc、current、nr_process、MAX_PROCESS、PROC_UNINIT、PROC_RUNNABLE、KSTACKSIZE、CLONE_VM、SSTATUS_SPP、SSTATUS_SPIE、SSTATUS_SIE、bootstack、boot_pgdir_pa、E_NO_MEM、E_NO_FREE_PROC。
已有函数：kmalloc()、kfree()、memset()、list_init()、list_add_before()、setup_kstack()、put_kstack()、get_pid()、hash_proc()、find_proc()、set_proc_name()、wakeup_proc()、read_csr()、local_intr_save()、local_intr_restore()、panic()。
已有入口：init_main、kernel_thread_entry、forkret、forkrets、__trapret。

[GUARANTEE]
- 实现 static struct proc_struct *alloc_proc(void) 和 void proc_init(void)。
- 实现 int kernel_thread(int (*fn)(void *), void *arg, uint32_t clone_flags)。
- 实现 int do_fork(uint32_t clone_flags, uintptr_t stack, struct trapframe *tf)。
- 实现 static void copy_thread(struct proc_struct *proc, uintptr_t esp, struct trapframe *tf) 和 static int copy_mm(uint32_t clone_flags, struct proc_struct *proc)。

[SPECIFICATION]
- alloc_proc()：申请 PCB，失败返回 NULL。成功时清零结构体，将 state 设为 PROC_UNINIT、pid 设为 -1、pgdir 设为 boot_pgdir_pa，并初始化进程链表与哈希结点。
- proc_init()：初始化进程链表和哈希桶；把当前执行流登记为 PID 0 的 idleproc，复用 bootstack，设为 PROC_RUNNABLE、need_resched=1，设置名称和 current，并更新计数。调用 kernel_thread() 创建运行 init_main 的 initproc，传入 "Hello world!!"。按 PID 找到该线程，确认 PID 为 1，并命名为 init。启动阶段无法创建所需线程时报告错误。
- kernel_thread()：清零临时 trapframe，用 s0 存 fn、s1 存 arg，epc 指向 kernel_thread_entry。以当前 sstatus 为基础置 SPP、SPIE 并清 SIE。调用 do_fork(clone_flags | CLONE_VM, 0, &tf)，返回子线程 PID 或负错误码。
- do_fork()：达到线程数上限时返回 -E_NO_FREE_PROC。依次分配 PCB、关联父线程、准备独立内核栈、调用 copy_mm() 和 copy_thread()。失败时逆序释放已申请资源，返回相应负错误码。成功时在本地中断保护下分配 PID、登记哈希表和进程链表、更新计数并唤醒线程，最终返回子 PID。
- copy_thread()：把 trapframe 复制到新内核栈顶部，子线程 a0 置 0。esp 非零时用作恢复后的 sp，否则使用新 trapframe 地址。context.ra 指向 forkret，context.sp 指向新 trapframe。
- copy_mm()：核对当前线程的 mm 为 NULL。本实验的内核线程共享 boot_pgdir_pa，不建立独立用户地址空间。成功时返回 0。
````

## 3. 进程调度

````text
[PROMPT]
实现 uCore RISC-V Lab4 的协作式进程调度。填写 kern/process/proc.c、kern/schedule/sched.c 和 kern/process/switch.S 中 LAB4 function3 的区域。按职责实现调度决策、页表切换和寄存器保存恢复，沿用现有进程结构和教师测试。

[RELY]
数据结构和宏：struct proc_struct、struct context、list_entry_t、proc_list、current、idleproc、PROC_RUNNABLE、need_resched、runs、SATP_MODE_SV39、RISCV_PGSHIFT、REGBYTES、STORE、LOAD。
已有函数和宏：list_next()、le2proc()、local_intr_save()、local_intr_restore()、write_csr()、flush_tlb()。
已有首次运行路径：forkret → forkrets → __trapret → sret → kernel_thread_entry。

[GUARANTEE]
- 在 kern/process/proc.c 中实现 void cpu_idle(void) 和 void proc_run(struct proc_struct *proc)。
- 在 kern/schedule/sched.c 中实现 void schedule(void)。
- 在 kern/process/switch.S 中定义全局入口 switch_to，对应 void switch_to(struct context *from, struct context *to)。

[SPECIFICATION]
- cpu_idle()：循环检查当前线程的 need_resched 标志，置位时调用 schedule()。
- schedule()：保存并关闭本地中断，清除当前线程的 need_resched。当前线程为 idle 时从链表头之后开始；否则从当前结点之后开始，循环扫描至多一圈，跳过链表头哨兵，选择第一个 PROC_RUNNABLE 线程。无可运行线程时选择 idleproc。将所选线程的 runs 加一。所选线程与当前线程不同时调用 proc_run()，恢复执行后恢复本层保存的中断状态。
- proc_run()：目标已是 current 时直接返回。否则保存并关闭本地中断，记录旧线程、更新 current，把 Sv39 模式与新根页表的物理页号编码进 satp，刷新 TLB，调用 switch_to()。旧线程以后恢复时，从调用 switch_to() 后继续并恢复本层保存的中断状态。
- switch_to()：a0 指向旧 context，a1 指向新 context。按 struct context 的字段顺序，以 REGBYTES 为步长保存旧线程的 ra、sp、s0～s11，再恢复新线程的同一组寄存器，用 ret 跳到恢复出的 ra。首次运行进入 forkret；已有现场的线程从原切换点恢复。
````

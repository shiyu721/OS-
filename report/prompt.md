# Lab3 提示词与SPEC

本文件对应 ucore RISC-V Lab3：中断处理、Trap 上下文恢复与异常返回。以下提示词结合当前工程整理，用于代码复现、报告提交与复核；不是逐字历史聊天记录，也不据此虚构失败次数。

## 1. Lab2 依赖衔接提示词

```text
请阅读当前ucore RISC-V Lab3的pmm.c、pmm.h、memlayout.h、dtb.h、
default_pmm.c和best_fit_pmm.c，先定位所有lab2标记，再补齐缺失依赖。
本任务服务于Lab3启动，不重新开展Lab2的Buddy、SLUB或双层GDB扩展。

page_init负责使用已解析的DTB内存信息，正确设置va_pa_offset、npage、pages。
当前工程仅支持DRAM_BASE起始的单段RAM；base不匹配、size为0或base+size溢出时
按框架约定assert/panic终止，不声称支持任意内存布局。
先读宏定义：当前Lab3按KERNTOP-va_pa_offset限制可管理物理上界，
不能照搬别的Lab2版本中可能不存在的PHYSICAL_MEMORY_END。
内存上界向下页对齐；pages从end之后向上页对齐；描述符末端之后再向上对齐为空闲起点。
npage是物理页号上界，Page数组元素数为npage-nbase，不能遍历npage个描述符。
在写描述符前检查元数据范围，初始化ref/flags/property并标记Reserved，
保护固件、内核和元数据。没有合法完整空闲页时不调用init_memmap。

Best-Fit实现init/init_memmap/alloc_pages/free_pages/nr_free_pages，
注册完整pmm_manager并包含check回调，原basic_check和best_fit_check逐字保留。
按地址组织空闲块，申请选满足需求的最小块，正确拆分、计数并合并物理连续块。
所有尾插分支插入完成后应退出遍历，避免把新节点再次作为待比较节点。
零页请求遵守当前assert(n>0)约定；无法满足请求时返回NULL且状态不变。

保留Lab3已有中断保护、DTB接口和工具链配置，不直接覆盖整个旧文件。
当前默认分配器仍为default_pmm_manager，不为了补依赖擅自改变策略选择。
只有明确切换并单独测试后，才把对应运行结果记录为Best-Fit的QEMU结果。
输出允许区域的完整实现及必要include，说明与当前框架的接口对应。
验收：交叉编译、正常启动及当前check_alloc_page检查；不沿用Lab2的20/20作为Lab3分数。
```

## 2. RESTORE_ALL 上下文恢复提示词

```text
【任务】ucore RISC-V Lab3：补全 RESTORE_ALL
【输入材料】kern/trap/trapentry.S 的原 SAVE_ALL、trap.h 的 trapframe、
             libs/riscv.h 中的 LOAD、STORE、REGBYTES 定义。
【输入状态】sp 指向当前中断帧，帧内是要恢复的寄存器状态。
【输出状态】恢复通用寄存器、sstatus、sepc与原栈指针，供既有sret返回。
【布局约束】
槽0～31对应x0～x31，槽32为sstatus，33为sepc，34为badvaddr，35为cause。
槽2保存的是分配中断帧之前的sp，而不是当前帧地址。
【实现要求】
1. 不修改 SAVE_ALL、struct trapframe 或 trap 函数签名。
2. sp仍指向帧时先加载并写回sstatus、sepc。
3. 恢复x1、x3～x31；用作临时变量的t0/t1也必须恢复其原值。
4. x0不必加载；最后从槽2恢复x2，之后不再使用旧帧基址读取内容。
5. 不将badvaddr/scause误当成返回必需的可写控制状态。
6. 不强制清除SPP；返回到哪种模式由保存的状态决定。
【输出】仅输出RESTORE_ALL标记处的汇编，并解释恢复顺序与偏移对应。
【验收】原SAVE_ALL逐字不变；官方现场测试能保持被检查的寄存器并返回。
```

### 保存与恢复的配套SPEC

- **背景/输入：** 原SAVE_ALL已将状态保存到当前内核栈，sp指向trapframe；结构布局由真实源码确定。
- **目标/输出：** 恢复通用寄存器、sstatus、sepc和原sp，使既有sret能够返回原执行流。
- **实现约束：** 保存宏和结构体不变；临时寄存器原值也要恢复；x2最后恢复；不强制改变SPP。
- **验收：** 槽位一一对应；原现场被检查的寄存器值保留；官方入口与断点返回项目通过。

## 3. __alltraps 汇编入口提示词

```text
【任务】ucore RISC-V Lab3：连接汇编入口与C处理函数
【文件】kern/trap/trapentry.S
【已有条件】__alltraps先执行SAVE_ALL，sp此时指向当前trapframe。
C接口为 void trap(struct trapframe *tf)，后续已有__trapret、RESTORE_ALL和sret。
【目标】将当前帧指针传入trap，处理完后继续既有恢复路径。
【要求】
1. 按RISC-V ABI将第一个参数放入a0，传入帧地址而非帧中保存的原sp。
2. 使用正常的函数调用指令连接trap，不另建一份帧。
3. 不改变现有帧布局；trap返回后sp应与调用前一致。
4. 原ra已在帧中保存，最后由RESTORE_ALL恢复；不要混淆C调用ra与原现场ra。
5. 保持入口四字节对齐，保持16字节栈对齐，不删除现有__trapret/sret。
【输出】最少必要汇编，并说明a0、sp、ra的变化。
【验收】trap能接收到正确指针；返回后现有RESTORE_ALL仍读取同一帧。
```

本模块需要明确：a0接收的是当前帧地址，而不是帧中保存的原sp；jal改变的ra属于当前函数调用，原ra最终从帧中恢复。288字节帧大小不破坏原先16字节对齐的栈。

## 4. interrupt_handler 中断分派与时钟提示词

```text
【任务】ucore RISC-V Lab3：实现 interrupt_handler
【文件与接口】kern/trap/trap.c，void interrupt_handler(struct trapframe *tf)
【可用资源】clock_set_next_event、ticks、TICK_NUM、print_ticks、
             print_trapframe、IRQ_*常量及sbi_shutdown（sbi.h）。
【输入】tf->cause为当前原因；RV64最高位是中断标志。
【功能要求】
1. 用uintptr_t宽度清除最高位，提取原因号，不直接用带标志的值与IRQ常量比较。
2. IRQ_S_TIMER每次调用clock_set_next_event并递增ticks一次。
3. 每当ticks到达TICK_NUM整数倍调用print_ticks。
4. 使用可跨调用保留的报告次数；达到SHUTDOWN_AFTER后调用sbi_shutdown。
5. 当前框架没有SHUTDOWN_AFTER定义时，用#ifndef提供默认10；它表示10次报告。
6. 不修改时钟中断的tf->epc；周期性来自重复安排事件。
7. 其他框架已有中断类型输出对应名称；IRQ_S_SOFT须包含
   Supervisor software interrupt。未知原因输出Unknown interrupt: cause N，
   然后调用print_trapframe。
【修改范围】只补Lab3标记和必要include，不改print_ticks或评分文件。
【输出】完整处理函数、默认宏及必要头文件，解释ticks与reports的区别。
【验收】官方时钟测试达到ticks=200并输出100 ticks；普通运行1000次后进入关机。
```

当前框架中TICK_NUM为100，SHUTDOWN_AFTER未预定义，本实现给出可覆盖默认值10。不能将“十次报告”写成“十次中断”，也不能将约十秒写成精确墙钟计时保证。

## 5. exception_handler 异常与EPC更新提示词

```text
【任务】ucore RISC-V Lab3：实现 exception_handler
【文件与接口】kern/trap/trap.c，void exception_handler(struct trapframe *tf)
【输入】tf->cause为同步异常原因，tf->epc为异常指令地址。
【功能】
1. CAUSE_ILLEGAL_INSTRUCTION输出Illegal instruction at及EPC。
2. CAUSE_BREAKPOINT输出Breakpoint at及EPC。
3. 对这两类异常按测试中实际指令长度推进tf->epc，确保返回后不重复执行。
4. 当前测试涵盖16位压缩断点和32位指令；读取可读内核代码的低半字，
   低两位不等于3时加2，测试范围内其余情况加4。
5. 测试中的.word 0x0000007b应推进4字节；ebreak不要无条件按4字节处理。
6. 其他异常只调用print_trapframe，不擅自推进EPC或增加通用恢复逻辑。
【边界】不宣称支持更长编码；不直接将这种内核指令读取方法用于任意用户地址。
【约束】保留函数签名、trap_dispatch、trap及原有其他函数，不改官方测试。
【输出】完整函数，解释未推进和推进错误的后果，说明适用范围。
【验收】断点和非法指令处理后继续执行，兜底分支输出满足原评分要求。
```

本次按要求跳过测试中的非法指令，不意味着真实OS应对所有非法指令这样恢复。未知异常打印帧属于诊断，不保证其返回后不再触发。

## 6. 两个必做功能模块的SPEC与接口整理

### 6.1 功能模块一：上下文恢复与入口

- **背景/输入：** `SAVE_ALL`、`struct trapframe`、`REGBYTES/LOAD`、RISC-V ABI和现有`__trapret`。
- **目标/输出：** 完成`RESTORE_ALL`与`__alltraps`，形成保存、C处理、恢复、返回的闭环。
- **实现约束：** 不修改保存宏、帧布局和`trap()`签名；x2最后恢复；a0传帧指针；保持栈对齐与平衡。
- **验收：** 原官方寄存器与断点测试通过，处理完能够继续原执行流。

### 6.2 功能模块二：中断与异常处理

- **背景/输入：** 帧中的`cause/epc`、原`trap_dispatch()`、时钟与SBI接口、原因宏和原测试。
- **目标/输出：** 实现`interrupt_handler()`和`exception_handler()`，时钟可持续触发，规定异常可正确跳过。
- **实现约束：** 每次定时事件重设并计数；报告次数跨调用保存；时钟不推进EPC；16/32位异常分别推进；未知类型打印现场。
- **验收：** 非法指令测试25分、连续时钟测试40分通过；普通运行达到1000 ticks后的关机条件。

### 6.3 既有任务的四段SPEC汇总

| 任务 | 背景与输入 | 目标与输出 | 实现约束 | 验收证据 |
|---|---|---|---|---|
| Lab2依赖 | 当前DTB、Page与pmm接口 | 补齐初始化及Best-Fit主体 | 使用当前真实上界宏，保护元数据，不覆盖Lab3接口 | 当前默认分配器检查；Best-Fit单独区分测试范围 |
| Trap布局分析 | SAVE_ALL与trap.h | 建立36槽对应关系 | RV64每槽8字节，槽2存原sp | 汇编与结构体对照、288字节帧 |
| RESTORE_ALL | sp指向的现有帧 | 恢复寄存器与控制状态 | x2最后恢复，临时寄存器原值恢复 | 官方现场测试 |
| __alltraps | SAVE_ALL后的执行状态 | 向trap传帧并调用 | a0参数、ra含义、栈平衡 | 现场和断点返回 |
| interrupt_handler | scause、ticks及时钟接口 | 分派、重设、计数、报告和关机 | 清除最高位，报告计数持久，时钟EPC不变 | 官方40/40与普通运行截图 |
| exception_handler | cause、epc和可读内核指令 | 输出原因并正确跳过 | 只处理测试16/32位长度，未知异常不通用恢复 | 官方25/25、断点返回 |
| 集成检查 | entry.S、sbi.c、Makefile | 可运行的完整工程 | 不改评分，额外改动单列 | 官方100/100 |

## 7. 集成与工具链兼容提示词

```text
【任务】ucore RISC-V Lab3：集成审查
【输入】原始Lab3工程、补全后的工程、原tools/grade.sh和inject.py。
【检查清单】
1. SAVE_ALL、trapframe布局、trap签名、basic_check和best_fit_check保持不变。
2. 核心实现只补规定位置，额外兼容修改逐项说明理由。
3. 审查sbi_call的a0/a1/a2/a7寄存器读写约束及memory clobber。
4. 审查satp写入后到高地址跳转前的可执行映射；如加启动恒等映射，
   保留原511项，并明确它不等于用户空间隔离。
5. 沿用QEMU4.1.1；探测编译器是否支持rv64imac_zicsr_zifencei，
   旧汇编器使用其接受的rv64imac；显式lp64，避免隐含gp小数据依赖。
6. 不改变评分脚本、不永久注入测试，不通过修改预期字符串规避测试。
7. 对照普通启动与评分启动，解释测试注入器在最后一次idt_init之后的行为。
【输出】修改清单、必要兼容修正及逐项验证方法；没有证据的运行结果标注未验证。
【验收】官方评分通过且普通计数达到关机条件，结论限定在已有测试覆盖内。
```

补充约束：启动恒等映射是为分页切换的过渡取指服务，不应写成用户空间安全隔离；SBI寄存器约束问题来自静态检查，不能编造为本机曾观察到的崩溃。保留修改原因与版本对应关系。

## 8. 独立验证提示词（与实现提示词分开）

```text
请针对实际Lab3工程设计验证顺序，不修改原tools/grade.sh、inject.py、测试源码或预期字符串。
先读取现有评分脚本，说明每个场景怎样注入、怎样构建、怎样判分，不另造一个100分标准。

原评分有三项：
1. Trap entry、register restore与breakpoint EPC：35分。
   检查原test_lab3_context.S实际比较哪些寄存器；不要声称检查了全部寄存器或全部CSR。
2. Illegal instruction EPC advance and return：25分。
   检查.word 0x0000007b返回；保留软件中断、未知中断和未知异常输出断言。
3. Re-armed supervisor timer and repeated trap return：40分。
   检查ticks到达200并观察100 ticks；不要把这一哨兵等同1000次关机已完成。

按实际工程执行：
cd ~/os_group_submit/OS_lab3_2411846
bash run_lab3.sh grade
记录真实输出及退出状态。遇到失败从第一条编译错误或缺失哨兵定位，
不能删断言、改分值或改预期字符串来制造通过。

评分后运行：
bash run_lab3.sh run
检查check_alloc_page() succeeded、时钟初始化、十行100 ticks及关机提示。
若需要证明QEMU正常退出，再记录返回shell提示符和退出状态；不要补画截图。
普通启动没有主动注入异常，不要求它打印Breakpoint at或Illegal instruction at。

可补充独立主机端逻辑测试：用桩接口统计重设事件、报告和关机调用次数，
用可读16位数组检验EPC分别加2和4及兜底调用。
若运行1000次模拟事件，应观察重设1000次、报告10次、关机接口一次；
桩测试不能证明CSR、sret、真实寄存器恢复或固件行为。
补充测试放在独立临时目录，不能污染原评分工程。

输出验证步骤、覆盖范围、真实结果与尚未完成项。
不存在终端证据时写待验证，不直接输出所有PASS；不虚构随机测试次数。
```

## 9. 真实验证记录与证据范围

- 本次使用提供的Lab3原工程补齐代码，原官方评分脚本和测试文件保持不变。
- 制作阶段完成修改C文件的主机语法检查、原Best-Fit的主机端检查，以及处理函数桩测试；这些不是QEMU整机评分。
- 本人WSL环境已取得官方`Total Score: 100/100`。
- 评分截图直接显示非法指令`PASS (25/25)`、连续时钟`PASS (40/40)`。现场与断点项目35分由总分与原评分结构确认，截图未完整显示该行，不拼造完整日志。
- 普通运行截图显示`check_alloc_page() succeeded!`、`++ setup timer interrupts`、十行`100 ticks`和`Shutdown after 10 timer reports.`。
- 上述普通截图直接证明累计1000次中断后进入关机分支，没有显示退出后的shell提示符，不仅凭该图扩展证明退出状态。
- 当前普通启动使用`default_pmm_manager`；不把该运行输出写成已在QEMU切换Best-Fit或Buddy。
- 根页表VA为`0xffffffffc0206000`，PA为`0x80206000`，与固定偏移对应；未新增双层GDB/TLB跟踪，不沿用Lab2调试地址作为Lab3证据。
- 本次未记录到本机评分先失败再修复的过程；寄存器恢复顺序、SBI约束和过渡映射的讨论按实际检查记录，不编造固定迭代次数。
- 报告已插入评分与时钟两张实测图，仓库链接尚需填写。

| 证据 | 对应结论 | 不扩展成的结论 |
|---|---|---|
| 官方100/100 | 原三项测试通过 | 所有异常和任意程序均正确 |
| 非法指令25/25 | 测试非法指令返回及指定兜底输出通过 | 所有非法指令安全可恢复 |
| 连续时钟40/40 | ticks达到200，重复中断和返回有效 | 已单独证明1000次后的关机 |
| 十行100 ticks与关机提示 | 达到1000次和关机分支 | 截图已经显示退出状态 |
| 主机端桩测试 | 处理函数计数和分支逻辑符合夹具预期 | 已验证真实CSR/SBI/sret |

## 10. 报告与Prompt归档提示词

```text
【任务】根据真实证据整理ucore Lab3测试结果与实验报告
【输入】当前源代码、原评分脚本、实际grade输出、时钟截图和三人分工。
【目标】形成Markdown报告及独立prompt.md。
【必须包含】实验目的、环境与工具、整体逻辑、模块职责、SPEC与完整Prompt、
实现分析、问题与解决、官方测试、普通运行、知识点对照、尚未涉及的OS内容。
【证据约束】
1. 评分为35/25/40三项，总分100；分清截图直接可见项目与由总分确认的项目。
2. 不编造原始运行日志，不把静态风险写成已发生的崩溃，不虚构失败迭代次数。
3. 普通截图包含十行100 ticks和关机提示；没有退出提示符时不单凭图片证明退出。
4. 区分主机端桩测试与RISC-V整机测试，区分默认分配器与Best-Fit实际选择。
5. 不把SBI调用写成用户系统调用，不把sret统一写成返回U态。
6. 保留提供的成员和工具记录；完整Prompt标为整理后的复现说明而非聊天逐字稿。
【格式】使用真正的Markdown标题、表格、围栏代码和相对图片路径，避免反斜杠转义。
【输出】可独立阅读的report.md、prompt.md及图片目录，仓库地址未提供则留待填写。
```

后续补充真实终端错误、修复与重跑记录时，按发生顺序追加版本、命令、输出和结论；不将尚未运行的附加测试写为已通过。使用本文件复现时，需要向AI提供当前源码，不能仅凭提示词生成另一套不匹配的框架。

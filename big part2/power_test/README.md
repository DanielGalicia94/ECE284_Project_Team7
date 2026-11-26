# 功耗对比测试：8x8 全满 vs 只有 PE(0,0)

## 文件
- full/weight.txt : 8x8 全部非零（随机 ±1..±8，seed 284）
- pe00/weight.txt : 只有 row0/col0 那个 PE = -5，其余 63 个全 0（相当于 1x1）
  （PE(0,0) 是 weight.txt 第 1 行数据的最低 4 位 1011 = -5，和 full 里的 W[0][0] 一样）
- 每个文件夹里都有自己的 golden_y0..3.txt（权重变了 golden 也跟着变，必须一起换）
- 由 gen_part2_diff.py 生成：
    python gen_part2_diff.py --wmode full --out power_test/full
    python gen_part2_diff.py --wmode pe00 --out power_test/pe00
  （不加 --wmode 时和原来一样，out_v2 结果不变）

## 用法
tb 不用改。把仿真目录里的 weight.txt 和 golden_y0..3.txt 换成 full/ 或 pe00/ 里的，
X0..X3.txt 不变，跑完看到 "No error detected" 就说明功能对，同时得到 core_tb.vcd。
（tb 里已有 $dumpfile("core_tb.vcd"); $dumpvars(0,core_tb);）
可选：VCD 太大的话可以把 $dumpvars(0,core_tb) 改成 $dumpvars(0,core_tb.core_instance.corelet_instance)，只记 corelet。

## 云端验证（iverilog，p2 RTL）
| 情况 | 结果 | mac_array 内信号翻转总数(RTL VCD) |
|---|---|---|
| full, 原 RTL | 4x256 全对 | 6,818,024 |
| pe00, 原 RTL | 4x256 全对 | 713,387（约 -90%） |
| full, 剪枝修正版 RTL | 4x256 全对 | 6,979,456 |
| pe00, 剪枝修正版 RTL | 4x256 全对 | 783,849 |
注：RTL VCD 看不到乘法器内部的门级翻转（a×0 在 RTL 里永远是 0），所以 operand isolation
的效果在 RTL 统计里几乎看不出来，要门级 VCD 才看得到。

## Quartus 里用真实翻转率测功耗
先说结论：权重是运行时从 SRAM 载入的，综合时 Quartus 不知道哪些是 0，
所以两种情况的网表、资源、Fmax 完全一样；不同的只有翻转率 -> 动态功耗。
默认 20% toggle 下两者功耗一定相同，必须喂仿真 VCD 才看得出区别。

### 方法 A（简单）：直接用 RTL 仿真的 VCD
1. 用 Vivado 或 iverilog 跑 tb，得到 core_tb.vcd（每种权重各一份）。
2. Quartus 编译好（top 仍是 corelet，和 Part5 一样）。
3. Processing > Power Analyzer Tool：
   - 勾 "Use input file(s) to initialize toggle rates and static probabilities"
   - Add Power Input File：选 core_tb.vcd
   - Entity / hierarchy 填 VCD 里 corelet 所在的层次：core_tb|core_instance|corelet_instance
     （分隔符按对话框提示，有的版本用 /）
   - 勾 "Perform glitch filtering on VCD files"
   - 没被 VCD 覆盖的节点会用 vectorless 估计（Default toggle rate 设成 12.5% 或 20%，两次保持一致）
4. Start。看报告里的 "Confidence Metric Details" / "Signal Activities"：
   被 "simulation" 覆盖的节点比例越高越可信。寄存器（a_q, b_q, c_q 等）一般能对上，
   组合逻辑（乘法器内部）多半对不上，会退回 vectorless。
5. 换另一份 VCD 再跑一次，对比 Core Dynamic Thermal Power。

### 方法 B（准确）：门级仿真 VCD
1. Assignments > Settings > EDA Tool Settings > Simulation：
   工具选 ModelSim-Altera / Questa Intel FPGA，格式 Verilog，
   勾 "Generate Value Change Dump (VCD) file script"，Design instance name 填 core_tb/core_instance/corelet_instance。
2. 重新编译，simulation/modelsim/ 下会有 corelet.vo（门级网表）和 *_dump_all_vcd_nodes.tcl。
3. 在 Questa 里：tb + core.v + SRAM/FIFO 等 RTL + corelet.vo（替换 RTL 的 corelet 及其子模块）
   + Cyclone IV 仿真库（cycloneive_ver, altera_mf_ver），先 source 那个 tcl 再 run -all，得到 VCD。
4. 按方法 A 第 3 步把这个 VCD 喂给 Power Analyzer。这样所有节点都有真实翻转率，
   operand isolation（剪枝修正版）对乘法器内部翻转的影响也能量出来。
注意：corelet 当时用了 virtual pin，如果 .vo 里 corelet 的端口对不上 tb，就先用方法 A。

### 预期
- 静态功耗(~119 mW)、I/O、时钟树两者一样，变化只在 Core Dynamic（Part5 是 82.58 mW @20%）。
- 两次分析的 VCD 时长要一致（同一个 tb，自然一致），这样平均功耗才可比。

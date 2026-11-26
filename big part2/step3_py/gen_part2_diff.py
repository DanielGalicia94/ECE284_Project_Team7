# Part2 差分输入：帧量化 + 理论答案（golden）生成脚本
#
# 用法:
#   python gen_part2_diff.py                  # 默认: frames/X0..X3.txt, 种子 284, k 自动, 输出到 out/
#   python gen_part2_diff.py --k 1            # 所有帧强制用 k=1（做误差分析用）
#   python gen_part2_diff.py --layout hwc     # 换一种 2048 个数的排列解释（见下）
#
# ---------------- 假设（都可以用命令行参数改） ----------------
# 1) 帧数据: 每帧 2048 个整数，范围约 -102..103，是有符号 8 位数（不是 0..255）。
#    2048 = 8 个输入通道 x 256 个像素。默认按 PyTorch flatten 的 (C, H, W) = (8, 16, 16) 解释，
#    即前 256 个数是通道 0。--layout hwc 则表示每连续 8 个数是同一个像素的 8 个通道。
# 2) 运算: Y = W x X，W 是 8x8（输出通道 x 输入通道）的 4 位有符号权重，相当于 1x1 卷积 / 矩阵乘。
#    这样一组权重装进 8x8 阵列后，5 个 pass 都不用重新加载，正好对应 Part2 的“权重驻留”。
# 3) 权重: 课程没给，这里用固定种子随机生成 4 位有符号数 [-8, 7]。换成 Part1 训练好的权重时，
#    把 make_weights() 改成读你的 8x8 整数权重即可（例如 squeezed 层中心 kij 的那一片）。
# 4) X0 的拆分: 因为 X0 是有符号数，用补码拆分
#        X0 = 16 * hi + lo,  hi = X0 >> 4（算术右移，有符号，-7..6），lo = X0 & 15（无符号，0..15）
#    [v2, 2026-11-24] 课程新版帧是无符号 8 位（0..255）。脚本自动识别：帧全为非负时 hi = X0 >> 4 是无符号 0..15，
#    hi pass 也用 act_signed=0（act_signed 顺序变为 0,0,1,1,1）；帧含负数时按上面的有符号处理（1,0,1,1,1）。
#    hi 是有符号 4 位，lo 是无符号 4 位。所以 hi pass 要用 act_signed=1，lo pass 用 act_signed=0。
#    这正好复用给 ΔX 准备的 act_signed 模式，不需要额外硬件。
#    （另一种做法是加 128 偏移变成无符号，再在 SFU 里减 128*sum(W)，更麻烦，不采用。）
# 5) ΔXi = Xi - X0，量化为 q = clamp(floor(ΔXi / 2^k + 0.5), -8, 7)，硬件重建 Yi = Y0 + (W x q) << k。
#    k 自动选择: 让 max|ΔXi| 不饱和的最小 k。这组数据 ΔX 本来就在 [-7, 7]，所以 k=0 无损。
# 6) 不做 ReLU（Part2 要的是原始 psum）。
#
# ---------------- 输出文件（格式与 Part1 的 core_tb 一致） ----------------
#   weight.txt                 8 行，第 t 行 = 输出通道 t 的 8 个输入通道权重，ic7 在 MSB，每个 4 位
#   act_x0_hi.txt              256 行，每行 32b = 8 个输入通道（ic7 在 MSB），有符号 4 位
#   act_x0_lo.txt              同上，无符号 4 位
#   act_dx1.txt..act_dx3.txt   同上，ΔXi_q，有符号 4 位
#   psum_x0_hi.txt / psum_x0_lo.txt / psum_dx1..3.txt
#                              每个 pass 阵列输出的原始 psum（调试 OFIFO→pmem 用），256 行 x 128b
#   golden_y0.txt              Y0 = 16*psum_hi + psum_lo，256 行 x 128b（oc7 在 MSB，每个 16 位）
#   golden_y1..3.txt           Yi_hw = Y0 + psum_dxi << k（testbench 逐位比对的就是这个）
#   true_y1..3.txt             Yi_true = W x Xi（全精度 8 位输入，误差分析用）
#   k.txt                      每帧的 k（3 行）
#   report.txt                 拆分校验、位宽、pass 数、误差分析（含 k 扫描）
import argparse
import os
import numpy as np

IC = OC = 8
NPIX = 256

p = argparse.ArgumentParser()
p.add_argument('--frames', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'frames_v2'))
p.add_argument('--out', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out_v2'))
p.add_argument('--seed', type=int, default=284)
p.add_argument('--k', default='auto', help="'auto' 或一个整数（所有帧同一个 k）")
p.add_argument('--layout', choices=['chw', 'hwc'], default='chw')
args = p.parse_args()
os.makedirs(args.out, exist_ok=True)


def load_frame(i):
    v = np.loadtxt(os.path.join(args.frames, 'X%d.txt' % i), dtype=np.int64)
    assert v.size == IC * NPIX, v.size
    assert (v.min() >= -128 and v.max() <= 127) or (v.min() >= 0 and v.max() <= 255), '帧数据既不是有符号 8 位也不是无符号 8 位'
    # 统一成 (IC, NPIX)
    return v.reshape(IC, NPIX) if args.layout == 'chw' else v.reshape(NPIX, IC).T


def make_weights():
    rng = np.random.default_rng(args.seed)
    return rng.integers(-8, 8, size=(OC, IC), dtype=np.int64)


def bits(v, n):
    return format(int(v) & ((1 << n) - 1), '0%db' % n)


def write_act(name, a):          # a: (IC, NPIX), 4 位
    assert a.min() >= -8 and a.max() <= 15
    with open(os.path.join(args.out, name), 'w') as f:
        f.write('#time0row7[msb-lsb],time0row6[msb-lst],....,time0row0[lsb]\n')
        f.write('#time1row7[msb-lsb],time1row6[msb-lst],....,time1row0[lsb]\n')
        f.write('#................\n')
        for t in range(NPIX):
            f.write(''.join(bits(a[ic, t], 4) for ic in reversed(range(IC))) + '\n')


def write_psum(name, y):         # y: (OC, NPIX), 16 位有符号
    assert y.min() >= -2**15 and y.max() < 2**15, name + ' 超出 16 位'
    with open(os.path.join(args.out, name), 'w') as f:
        f.write('#time0col7[msb-lsb],time0col6[msb-lst],....,time0col0[lsb]\n')
        f.write('#time1col7[msb-lsb],time1col6[msb-lst],....,time1col0[lsb]\n')
        f.write('#................\n')
        for t in range(NPIX):
            f.write(''.join(bits(y[oc, t], 16) for oc in reversed(range(OC))) + '\n')


def quantize_delta(d, k):
    q = np.floor(d / 2.0**k + 0.5).astype(np.int64)
    sat = int(((q < -8) | (q > 7)).sum())
    return np.clip(q, -8, 7), sat


def auto_k(d):
    for k in range(8):
        if quantize_delta(d, k)[1] == 0:
            return k
    return 7


X = [load_frame(i) for i in range(4)]
W = make_weights()
rep = []

# ---------- Step1: X0 拆分 + Y0 ----------
x0 = X[0]
UNSIGNED = all(x.min() >= 0 for x in X)   # v2: 无符号帧
hi = x0 >> 4                    # 有符号帧: 算术右移，有符号；无符号帧: 0..15 无符号
lo = x0 & 15                    # 无符号
assert np.array_equal(16 * hi + lo, x0)
if UNSIGNED:
    assert hi.min() >= 0 and hi.max() <= 15 and lo.min() >= 0 and lo.max() <= 15
else:
    assert hi.min() >= -8 and hi.max() <= 7 and lo.min() >= 0 and lo.max() <= 15
psum_hi = W @ hi
psum_lo = W @ lo
Y0 = 16 * psum_hi + psum_lo
assert np.array_equal(Y0, W @ x0)   # Y0 必须精确

with open(os.path.join(args.out, 'weight.txt'), 'w') as f:
    f.write('#col0row7[msb-lsb],col0row6[msb-lst],....,col0row0[lsb]\n')
    f.write('#col1row7[msb-lsb],col1row6[msb-lst],....,col1row0[lsb]\n')
    f.write('#................\n')
    for oc in range(OC):
        f.write(''.join(bits(W[oc, ic], 4) for ic in reversed(range(IC))) + '\n')
write_act('act_x0_hi.txt', hi)
write_act('act_x0_lo.txt', lo)
write_psum('psum_x0_hi.txt', psum_hi)
write_psum('psum_x0_lo.txt', psum_lo)
write_psum('golden_y0.txt', Y0)

rep.append('layout=%s  seed=%d  frames: %s' % (args.layout, args.seed,
           ', '.join('X%d[%d..%d]' % (i, X[i].min(), X[i].max()) for i in range(4))))
rep.append('W (oc x ic):\n' + str(W))
rep.append('frames are %s 8-bit -> act_signed per pass (hi, lo, d1, d2, d3) = %s'
           % ('UNSIGNED' if UNSIGNED else 'SIGNED', '0,0,1,1,1' if UNSIGNED else '1,0,1,1,1'))
rep.append('X0 split: hi in [%d, %d] (%s), lo in [%d, %d] (unsigned); 16*hi+lo == X0: OK'
           % (hi.min(), hi.max(), 'unsigned' if UNSIGNED else 'signed', lo.min(), lo.max()))
rep.append('Y0 == W x X0 exactly: OK   |Y0| max = %d' % np.abs(Y0).max())

# ---------- Step2/3: ΔXi 量化 + Yi ----------
ks = []
rep.append('\nframe  k  max|dX|  saturated  max|err|      MSE   SQNR(dB)   |Yi_hw| max')
maxabs = [np.abs(psum_hi).max(), np.abs(psum_lo).max(), np.abs(Y0).max()]
for i in range(1, 4):
    d = X[i] - x0
    k = auto_k(d) if args.k == 'auto' else int(args.k)
    q, sat = quantize_delta(d, k)
    psum_d = W @ q
    Yhw = Y0 + (psum_d << k)
    Ytrue = W @ X[i]
    err = Yhw - Ytrue
    mse = float(np.mean(err.astype(float)**2))
    sqnr = float('inf') if mse == 0 else 10 * np.log10(np.mean(Ytrue.astype(float)**2) / mse)
    ks.append(k)
    maxabs += [np.abs(psum_d).max(), np.abs(Yhw).max()]
    write_act('act_dx%d.txt' % i, q)
    write_psum('psum_dx%d.txt' % i, psum_d)
    write_psum('golden_y%d.txt' % i, Yhw)
    write_psum('true_y%d.txt' % i, Ytrue)
    rep.append('  X%d   %d  %6d  %9d  %8d  %9.3f  %9s  %8d' % (
        i, k, np.abs(d).max(), sat, np.abs(err).max(), mse,
        'inf' if sqnr == float('inf') else '%.2f' % sqnr, np.abs(Yhw).max()))

with open(os.path.join(args.out, 'k.txt'), 'w') as f:
    f.write('\n'.join(str(k) for k in ks) + '\n')

# ---------- k 扫描（Step6 用） ----------
rep.append('\nk sweep (all frames same k):  k  frame  saturated  max|err|  SQNR(dB)')
for k in range(0, 5):
    for i in range(1, 4):
        d = X[i] - x0
        q, sat = quantize_delta(d, k)
        err = Y0 + ((W @ q) << k) - W @ X[i]
        mse = float(np.mean(err.astype(float)**2))
        s = 'inf' if mse == 0 else '%.2f' % (10 * np.log10(np.mean((W @ X[i]).astype(float)**2) / mse))
        rep.append('                              %d   X%d   %9d  %8d  %8s' % (k, i, sat, np.abs(err).max(), s))

# ---------- 位宽 & pass 数 ----------
rep.append('\nmax |value| over all psums / Y: %d  -> fits 16-bit signed: %s'
           % (max(maxabs), max(maxabs) < 2**15))
rep.append('passes: conventional = 4 frames x 2 nibbles = 8;  differential = 2 + 1 + 1 + 1 = 5;  '
           'saving = 37.5%, speedup = 1.6x')
rep.append('NOTE: 256 pixels per pass > L0/OFIFO depth 64 -> testbench should run each pass as 4 tiles of 64 pixels.')

text = '\n'.join(rep)
open(os.path.join(args.out, 'report.txt'), 'w').write(text + '\n')
print(text)

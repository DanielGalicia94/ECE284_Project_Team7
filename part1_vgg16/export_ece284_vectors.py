"""Export the 8x8 ECE284 Team 7 core_tb.v stimulus/expected-output files.

Notebook usage (after results = verify_psum_recovered(..., num_images=1)):

    from export_ece284_vectors import export_vectors
    export_vectors(
        results['x_int'][0], results['w_int'],
        output_dir='../part4',
        psum_int=results['psum_int'][0],
    )

Alternatively add row_mask=[1,1,0,1,1,1,1,1], col_mask=[1,...]
for an isolated masked-layer hardware test. Do not pass the unpruned psum_int
as the reference when a nontrivial mask is enabled.

Expected geometry: 8 channels, 4x4 input, 3x3 kernel, pad=1, 4x4 output.
A padded 8x6x6 input can be passed using already_padded=True.
"""
from pathlib import Path
import numpy as np


def _as_integer_array(value, name):
    if hasattr(value, 'detach'):
        value = value.detach().cpu().numpy()
    value = np.asarray(value, dtype=np.float64)
    if not np.isfinite(value).all() or not np.allclose(value, np.rint(value), rtol=0, atol=1e-4):
        raise ValueError(f'{name} must contain finite, nearly exact integers')
    return np.rint(value).astype(np.int64)


def _pack(values, bits, signed=False):
    vals = list(map(int, values))
    lo, hi = (-(1 << (bits-1)), (1 << (bits-1))-1) if signed else (0, (1 << bits)-1)
    if any(v < lo or v > hi for v in vals):
        raise ValueError(f'{bits}-bit {"signed" if signed else "unsigned"} lane out of range: {vals}')
    return ''.join(format(v & ((1 << bits)-1), f'0{bits}b') for v in reversed(vals))


def _write(path, header, lines):
    if len(header) != 3 or any(any(ch.isspace() for ch in h) for h in header):
        raise ValueError('core_tb.v requires exactly three whitespace-free header tokens')
    with open(path, 'w', encoding='ascii') as f:
        for h in header:
            f.write('#' + h + '\n')
        for line in lines:
            f.write(line + '\n')


def export_vectors(x_int, w_int, output_dir, *, psum_int=None,
                   row_mask=None, col_mask=None, already_padded=False):
    """Write activation_tile0.txt, 9 weight files, acc_address.txt, out.txt.

    `x_int`: [8,4,4] integer activation; [8,6,6] if already_padded=True.
    `w_int`: [8,8,3,3] signed 4-bit weight tensor [oc,ic,kh,kw].
    `psum_int`: optional [8,4,4] un-ReLU'd integer reference for comparison.
    If masks are used, references are computed from masked weights.
    """
    x = _as_integer_array(x_int, 'x_int')
    w = _as_integer_array(w_int, 'w_int')
    expected_x = (8,6,6) if already_padded else (8,4,4)
    if x.shape != expected_x or w.shape != (8,8,3,3):
        raise ValueError(f'Expected x={expected_x} and w=(8,8,3,3); got x={x.shape}, w={w.shape}')
    if x.min() < 0 or x.max() > 15 or w.min() < -8 or w.max() > 7:
        raise ValueError('Activation must be [0,15], weight must be [-8,7].')
    row_mask = np.ones(8, dtype=np.int64) if row_mask is None else np.asarray(row_mask, dtype=np.int64)
    col_mask = np.ones(8, dtype=np.int64) if col_mask is None else np.asarray(col_mask, dtype=np.int64)
    if row_mask.shape != (8,) or col_mask.shape != (8,) or not np.isin(row_mask, [0,1]).all() or not np.isin(col_mask,[0,1]).all():
        raise ValueError('Masks must each have exactly eight binary entries.')

    # Mask products instead of deleting channels: preserves 8x8 scheduling.
    w = w * col_mask[:,None,None,None] * row_mask[None,:,None,None]
    padded = x if already_padded else np.pad(x, ((0,0),(1,1),(1,1)))
    ref = np.zeros((8,4,4), dtype=np.int64)
    for oy in range(4):
        for ox in range(4):
            for kh in range(3):
                for kw in range(3):
                    ref[:,oy,ox] += w[:,:,kh,kw] @ padded[:,oy+kh,ox+kw]
    if psum_int is not None:
        p = _as_integer_array(psum_int,'psum_int')
        if p.shape != ref.shape:
            raise ValueError(f'psum_int should be {ref.shape}; got {p.shape}')
        if not np.array_equal(ref,p):
            mismatch=np.argwhere(ref!=p)[0]
            raise AssertionError(f'Provided psum_int disagrees with integer reference at {tuple(mismatch)}: {p[tuple(mismatch)]} vs {ref[tuple(mismatch)]}')

    outdir=Path(output_dir)
    outdir.mkdir(parents=True, exist_ok=True)
    _write(outdir/'activation_tile0.txt',
          ['activation:row7..row0:unsigned4',
           '36_locations:6x6_row_major',
           'binary_words_follow'],
          (_pack(padded[:,y,x],4) for y in range(6) for x in range(6)))
    for kh in range(3):
        for kw in range(3):
            idx = 3*kh + kw
            _write(outdir/f'weight_itile0_otile0_kij{idx}.txt',
                  ['weights:input_row7..row0:signed4',
                   f'kernel_{kh}_{kw}:8_output_channels',
                   'oc0_first_oc7_last'],
                  (_pack(w[oc,:,kh,kw],4,signed=True) for oc in range(8)))
    # Generate addresses with a kernel-major SRAM base.
    addresses=[(kh*3+kw)*36 + (oy+kh)*6 + (ox+kw)
               for oy in range(4) for ox in range(4)
               for kh in range(3) for kw in range(3)]
    (outdir/'acc_address.txt').write_text(''.join(f'{a:011b}\n' for a in addresses),encoding='ascii')
    _write(outdir/'out.txt',
          ['output:col7..col0:signed16',
           '16_locations:4x4_row_major',
           'expected_post_ReLU_integer'],
          (_pack(np.maximum(ref[:,oy,ox],0),16,signed=True)
           for oy in range(4) for ox in range(4)))
    _write(outdir/'out_pre_relu.txt',
          ['output:col7..col0:signed16',
           '16_locations:4x4_row_major',
           'expected_raw_pre_ReLU_integer'],
          (_pack(ref[:,oy,ox],16,signed=True)
           for oy in range(4) for ox in range(4)))
    print('Export complete:',outdir)
    print('Created: 36 activation words; 9x8 weight words; 144 addresses; 16 post-ReLU result words.')
    print('Integer psum range:',ref.min(),'to',ref.max())
    print('Row mask:',row_mask.tolist(),'; column mask:',col_mask.tolist())
    return ref

#!/usr/bin/env python3
"""Independently verify ECE284 Part 4 actual stimulus (no external packages).

Usage:
    python3 verify_part4_actual.py /path/to/ECE284_Project_Team7-struct_pruning
"""
import argparse
from pathlib import Path
import sys


def load_binary(folder, filename, width, expected_count):
    path = folder / filename
    data = [line.strip() for line in path.read_text().splitlines()
            if line.strip() and not line.lstrip().startswith('#')]
    if len(data) != expected_count:
        raise ValueError(f'{filename}: expected {expected_count} data lines, got {len(data)}')
    for n, word in enumerate(data, 1):
        if len(word) != width or any(c not in '01' for c in word):
            raise ValueError(f'{filename}: data line {n} is not {width}-bit binary')
    return [int(line, 2) for line in data]


def unpack(word, width, count, signed=False):
    mask = (1 << width) - 1
    values = [(word >> (width * i)) & mask for i in range(count)]
    if signed:
        values = [v - (1 << width) if v & (1 << (width - 1)) else v for v in values]
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path, help='Path to extracted project repository')
    args = parser.parse_args()
    folder = args.repo / 'part4_actual'
    if not folder.is_dir():
        raise FileNotFoundError(f'Missing stimulus directory: {folder}')

    x = [unpack(word, 4, 8) for word in load_binary(folder, 'activation_tile0.txt', 32, 36)]
    w = [[unpack(word, 4, 8, signed=True) for word in load_binary(
        folder, f'weight_itile0_otile0_kij{k}.txt', 32, 8)] for k in range(9)]
    raw = [unpack(word, 16, 8, signed=True) for word in load_binary(
        folder, 'out_pre_relu.txt', 128, 16)]
    relu = [unpack(word, 16, 8, signed=True) for word in load_binary(
        folder, 'out.txt', 128, 16)]
    addrs = load_binary(folder, 'acc_address.txt', 11, 144)

    mismatches = []
    for p in range(16):
        out_y, out_x = divmod(p, 4)
        for k in range(9):
            ky, kx = divmod(k, 3)
            expected_address = 36 * k + 6 * (out_y + ky) + out_x + kx
            actual_address = addrs[p * 9 + k]
            if actual_address != expected_address:
                mismatches.append(('address', p, k, expected_address, actual_address))

        for oc in range(8):
            expected = sum(
                x[6 * (out_y + ky) + out_x + kx][ic] * w[3 * ky + kx][oc][ic]
                for ky in range(3) for kx in range(3) for ic in range(8)
            )
            if raw[p][oc] != expected:
                mismatches.append(('pre-ReLU', p, oc, expected, raw[p][oc]))
            if relu[p][oc] != max(0, expected):
                mismatches.append(('post-ReLU', p, oc, max(0, expected), relu[p][oc]))

    print('Stimulus: 36 x 8 unsigned 4-bit activations; 9 x 8 x 8 signed 4-bit weights')
    print('Expected: 16 spatial outputs x 8 signed 16-bit channels')
    print('Checks: 144 addresses, 128 pre-ReLU values, 128 post-ReLU values')
    if mismatches:
        for mismatch in mismatches[:25]:
            print('MISMATCH:', *mismatch)
        print(f'FAIL: {len(mismatches)} mismatch(es)')
        return 1
    active_per_channel = [sum(x[p][ic] != 0 for p in range(36)) for ic in range(8)]
    print('PASS: 0 mismatches in all 400 checks')
    print(f'Nonzero activations per input channel: {active_per_channel}')
    if 0 in active_per_channel:
        print('NOTE: Some input channels are always zero; use extra stress vectors for wider RTL coverage.')
    print('NOTE: This validates the stimulus mathematically, not the RTL simulation.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (FileNotFoundError, ValueError, OSError) as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Independent reference for the baseline's packed 8-channel stimulus format.

Optionally export an equivalent zero-padded fixture for a separate unmodified
baseline simulation. No PyTorch or NumPy required.
"""
import argparse
from pathlib import Path


def read_words(path, width, header=3):
    lines = path.read_text().splitlines()[header:]
    words = [line.strip() for line in lines if line.strip()]
    if any(len(word) != width or set(word) - {'0', '1'} for word in words):
        raise ValueError(f'Invalid {width}-bit binary word in {path}')
    return [int(word, 2) for word in words]


def write_words(path, words, width, header=True):
    prefix = '#packed_binary\n#original_channel_indices\n#binary_words_follow\n' if header else ''
    path.write_text(prefix + ''.join(f'{word:0{width}b}\n' for word in words))


def signed4(value):
    return value - 16 if value & 8 else value


def mask_word(word, mask):
    return word & sum(15 << (4 * row) for row in range(8) if mask & (1 << row))


def convolve(x, weights, addresses, im, om):
    raw, relu = [], []
    for p in range(len(addresses) // 9):
        sums = []
        for c in range(8):
            value = 0
            if om & (1 << c):
                for address in addresses[p*9:p*9+9]:
                    k, pixel = divmod(address, len(x))
                    for r in range(8):
                        if im & (1 << r):
                            a = (x[pixel] >> (4*r)) & 15
                            w = signed4((weights[k][c] >> (4*r)) & 15)
                            value += a*w
            if not -32768 <= value <= 32767:
                raise OverflowError(value)
            sums.append(value)
        raw.append(sum((v & 65535) << (16*c) for c, v in enumerate(sums)))
        relu.append(sum(max(v, 0) << (16*c) for c, v in enumerate(sums)))
    return raw, relu


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dataset', type=Path)
    parser.add_argument('--input-mask', type=lambda s: int(s, 16), default=255)
    parser.add_argument('--output-mask', type=lambda s: int(s, 16), default=255)
    parser.add_argument('--write-padded', type=Path, help='New directory for zero-padded baseline fixtures')
    args = parser.parse_args()
    im, om = args.input_mask, args.output_mask
    if not (0 <= im <= 255 and 0 <= om <= 255):
        parser.error('Masks must be 8-bit hexadecimal values')
    d = args.dataset
    x = read_words(d/'activation_tile0.txt', 32)
    weights = [read_words(d/f'weight_itile0_otile0_kij{k}.txt', 32) for k in range(9)]
    addresses = read_words(d/'acc_address.txt', 11, header=0)
    if not x or any(len(w) != 8 for w in weights) or len(addresses) % 9 or any(a >= 9*len(x) for a in addresses):
        raise ValueError('Unexpected stimulus dimensions/addresses')
    if (d/'out.txt').exists():
        _, original = convolve(x, weights, addresses, 255, 255)
        supplied = read_words(d/'out.txt', 128)
        if original != supplied:
            raise ValueError('Original full-channel golden does not match reference')
        print(f'{d}: supplied golden matches {len(original)}/{len(original)} positions')
    raw, relu = convolve(x, weights, addresses, im, om)
    padded_x = [mask_word(word, im) for word in x]
    padded_w = [[mask_word(word, im) if om & (1 << c) else 0 for c, word in enumerate(w)] for w in weights]
    if convolve(padded_x, padded_w, addresses, 255, 255) != (raw, relu):
        raise AssertionError('Zero-padding equivalence failed')
    print(f'input={im:02X} output={om:02X}: {im.bit_count()*om.bit_count()} active PEs; {len(raw)} positions; zero-padding equivalence PASS')
    if args.write_padded:
        out = args.write_padded
        out.mkdir(parents=True, exist_ok=False)
        write_words(out/'activation_tile0.txt', padded_x, 32)
        for k, w in enumerate(padded_w):
            write_words(out/f'weight_itile0_otile0_kij{k}.txt', w, 32)
        write_words(out/'acc_address.txt', addresses, 11, header=False)
        write_words(out/'out.txt', relu, 128)
        write_words(out/'out_pre_relu.txt', raw, 128)
        print(f'Wrote padded fixtures to {out}')


if __name__ == '__main__':
    main()

"""Validate short public notes before publishing to any customer-facing channel."""
import argparse
from pathlib import Path
import re

UNSAFE = re.compile(
    r'://|www\.|\b(?:\d{1,3}\.){3}\d{1,3}\b|'
    r'(?:[0-9a-f]{0,4}:){2,}[0-9a-f:.%]*|'
    r'\b[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9-]+)*\.[a-z][a-z0-9-]{1,}\b|'
    r'\b(?:password|username|token|secret|api[ _-]?key|sha[ -]?256|keystore|certificate)\b',
    re.I,
)


def validate_notes(source):
    notes = source.strip()
    lines = [line.strip() for line in notes.split('\n') if line.strip()]
    if (not notes or len(notes) > 600 or len(lines) > 5
            or any(len(line) > 160 for line in lines)
            or re.search(r'[\x00-\x08\x0b-\x1f\x7f]', notes)
            or UNSAFE.search(notes)):
        # Do not echo the rejected content into public workflow logs.
        raise ValueError('Public release notes must be brief and contain no addresses or sensitive details.')
    lines = [line for line in lines if not line.startswith('#')]
    if not lines:
        raise ValueError('Public release notes need a customer-facing improvement summary.')
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    notes = validate_notes(args.input.read_text(encoding='utf-8'))
    if args.output:
        args.output.write_text(notes + '\n', encoding='utf-8')
    print('Public release notes verified.')


if __name__ == '__main__':
    main()

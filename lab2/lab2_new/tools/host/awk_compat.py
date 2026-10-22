import re
import sys


def main():
    program = sys.argv[1] if len(sys.argv) > 1 else ""
    text = sys.stdin.read().split()
    match = re.search(r'match\("([^"]+)"', program)
    if match is None:
        return 0
    return 1 if match.group(1) in text else 0


raise SystemExit(main())

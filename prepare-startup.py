#!/usr/bin/env python3
"""Prepare the top-level IOC startup inside the container; leave sources intact."""

import os
from pathlib import Path
import re
import shlex
import sys


def installed_version(module, modules, base, arch, requested=None):
    candidates = []
    for version in (modules / module).glob('*'):
        install = version / ('R' + base)
        required = (install / 'lib' / arch / 'libecmc.so'
                    if module == 'ecmc' else install / 'startup.cmd')
        if required.is_file():
            candidates.append(version.name)
    candidates.sort()
    if requested:
        if requested not in candidates:
            raise ValueError(f'{module} version {requested!r} is not installed; '
                             f'available: {", ".join(candidates) or "none"}')
        return requested
    if len(candidates) != 1:
        raise ValueError(f'{module}: expected one installed version, found '
                         f'{", ".join(candidates) or "none"}. '
                         f'Use --{module}-version to select one.')
    return candidates[0]


def split_macros(value):
    """Split commas outside quoted values and nested EPICS macro expressions."""
    result, start, depth, quote = [], 0, 0, None
    for i, char in enumerate(value):
        if quote:
            if char == quote and (i == 0 or value[i - 1] != '\\'):
                quote = None
        elif char in "\"'":
            quote = char
        elif char in '{(':
            depth += 1
        elif char in '})':
            depth -= 1
        elif char == ',' and depth == 0:
            result.append(value[start:i].strip())
            start = i + 1
    if depth or quote:
        raise ValueError(f'unbalanced macro arguments: {value}')
    result.append(value[start:].strip())
    return [part for part in result if part]


def rewrite(source, ecmc, ecmccfg, ecmccomp=None):
    result, configured = [], False
    # Accept common IOC shell forms: require module version "macros",
    # require module,version,"macros", and require("module","version",...).
    for number, line in enumerate(source.splitlines(keepends=True), 1):
        match = re.match(r'^(\s*)require\b(.*)', line)
        if not match:
            result.append(line)
            continue
        args = match[2].strip()
        if args.startswith('('):
            # Strip comments before finding the closing function parenthesis.
            lexer = shlex.shlex(args, posix=False)
            lexer.whitespace_split = True
            args = ' '.join(lexer)
            if not args.endswith(')'):
                raise ValueError(f'line {number}: unsupported require syntax')
            args = args[1:-1]
        lexer = shlex.shlex(args, posix=True)
        lexer.whitespace += ','
        lexer.whitespace_split = True
        tokens = list(lexer)
        if not tokens or tokens[0] not in ('ecmc', 'ecmccfg', 'ecmccomp'):
            result.append(line)
            continue
        module, *rest = tokens
        if module == 'ecmccomp' and ecmccomp is None:
            result.append(line)
            continue
        if rest and ('=' not in rest[0] or rest[0].startswith(('${', '$('))):
            rest.pop(0)  # discard the original module version
        macros = split_macros(','.join(rest))
        # A whole macro-list substitution cannot be safely inspected/overridden.
        if any(not re.match(r'^\w+\s*=', part) for part in macros):
            raise ValueError(f'line {number}: cannot rewrite opaque macro list; '
                             'use explicit NAME=value arguments or --as-is')
        if module == 'ecmccfg':
            configured = True
            macros = [part for part in macros
                      if part.split('=', 1)[0].strip() not in ('SIM', 'ECMC_VER')]
            macros += ['SIM=1', 'ECMC_VER=' + ecmc]
        version = {'ecmc': ecmc, 'ecmccfg': ecmccfg, 'ecmccomp': ecmccomp}[module]
        macro_text = ','.join(macros).replace('\\', '\\\\').replace('"', '\\"')
        result.append(f'{match[1]}require {module} "{version}"'
                      + (f' "{macro_text}"' if macro_text else '') + '\n')
    if not configured:
        raise ValueError('no direct require ecmccfg found in startup; '
                         'pass the startup containing these lines, or use --as-is')
    return ''.join(result)


def main():
    modules = Path(os.environ.get('EPICS_MODULES', '/ioc/modules'))
    base = Path(os.environ['EPICS_BASE']).name.removeprefix('base-')
    arch = os.environ['EPICS_HOST_ARCH']
    if sys.argv[1:] == ['--component-version']:
        print(installed_version('ecmccomp', modules, base, arch,
                                os.environ.get('RUN_SIM_ECMCCOMP_VERSION')))
        return
    versions = {module: installed_version(
        module, modules, base, arch,
        os.environ.get('RUN_SIM_' + module.upper() + '_VERSION'))
        for module in ('ecmc', 'ecmccfg', 'ecmccomp')}
    source, destination = map(Path, sys.argv[1:])
    prepared = rewrite(source.read_text(), **versions)
    destination.write_text(prepared)
    print(f'run-sim: SIM=1, ecmc={versions["ecmc"]}, '
          f'ecmccfg={versions["ecmccfg"]}; prepared {destination}', file=sys.stderr)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        sys.exit(f'run-sim: {error}')

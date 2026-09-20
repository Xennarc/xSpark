#!/usr/bin/env python3
"""Check every Expert Advisor's calls into the shared components for arity.

WHY THIS EXISTS. CI does not compile MQL5 - tools/test_portable_logic.py
transpiles the headers to C++ and checks the EAs by source-level regex only.
That leaves one whole class of error invisible until someone opens MetaEditor:
an EA calling a component method with the wrong number of arguments. It is
invisible precisely because both sides are individually correct; only their
meeting is wrong.

It is not a hypothetical. XSparkICT.mq5 shipped with two of them:

    g_execution_engine.Initialize   13 passed, 12 required
    g_position_manager.ManagePositions   5 passed, 10 required

Both were transcription slips from another EA - one bool too many, and a call
written from memory against a ten-parameter signature. Every other static check
in this repository passed on that file, including one that confirmed both
methods existed. Existing is not the same as fitting.

WHAT THIS IS NOT. Not a compiler, and not a type checker: it counts arguments,
it does not check that they are the right types or in the right order. A file
that passes here can still fail to compile for a dozen other reasons. It closes
one gap, cheaply, in the place where that gap kept producing real errors.

Method overloads are handled by accepting a call that fits ANY overload of the
name, which is the same latitude the compiler gives.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

# The return types a component method may declare. Anything else is not a
# method signature this tool knows how to read, and is skipped rather than
# guessed at.
RETURN_TYPES = (r'(?:bool|void|double|int|string|datetime|ulong|long|uint|char|short|float'
                r'|EXSpark\w+|ENUM_\w+|CXSpark\w+)')


def split_top_level(text):
    """Split on commas that are not inside brackets.

    Angle brackets are deliberately NOT treated as nesting: in MQL5 they are
    comparison operators far more often than they are anything else, and
    counting them made this tool read `a > b` as an unclosed bracket and
    mis-count every argument after it.
    """
    parts, depth, current = [], 0, ''
    for ch in text:
        if ch in '([':
            depth += 1
        elif ch in ')]':
            depth -= 1
        if ch == ',' and depth == 0:
            parts.append(current)
            current = ''
        else:
            current += ch
    if current.strip():
        parts.append(current)
    return [p for p in parts if p.strip()]


def strip_noise(text):
    """Remove comments and string literals.

    Both can contain commas and brackets, and a comma inside a logged sentence
    is not an argument separator. Strings become empty strings rather than
    disappearing, so they still count as one argument each.
    """
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    return text


def class_methods(source, class_name):
    """Every method of a class, as name -> list of (required, total) arities.

    A list rather than a single pair because a name may be overloaded, and a
    call is legal if it fits any one of them.
    """
    match = re.search(r'\bclass\s+' + re.escape(class_name) + r'\b', source)
    if not match:
        return None

    # Bound the body by matching braces. Reading from the class declaration to
    # the end of the file instead would collect every LATER class's methods too,
    # so an Initialize belonging to some other component could quietly satisfy
    # a call that fits none of this one's - the exact failure this tool exists
    # to catch, reintroduced inside the tool.
    open_brace = source.find('{', match.end())
    if open_brace < 0:
        return None

    depth, index = 0, open_brace
    while index < len(source):
        if source[index] == '{':
            depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0:
                break
        index += 1

    segment = source[open_brace:index]
    methods = {}
    pattern = r'\b' + RETURN_TYPES + r'\s+(\w+)\s*\(([^;{)]*(?:\([^)]*\)[^;{)]*)*)\)\s*(?:const\s*)?\{'
    for found in re.finditer(pattern, segment, re.S):
        name, params = found.group(1), found.group(2)
        pieces = split_top_level(params)
        total = len(pieces)
        required = len([p for p in pieces if '=' not in p])
        methods.setdefault(name, []).append((required, total))
    return methods


def component_globals(ea_text):
    """The EA's own component objects, as name -> class.

    Read from the EA rather than hard-coded, because each EA names its strategy
    object the same way while pointing it at a different class; a hard-coded map
    reports the wrong class for every EA but one.
    """
    return {name: cls for cls, name in
            re.findall(r'^\s*(CXSpark\w+)\s+(\w+)\s*;', ea_text, re.M)}


def check_expert(ea_path, include_source):
    ea_text = ea_path.read_text()
    objects = component_globals(ea_text)
    clean = strip_noise(ea_text)
    problems = []

    for obj, cls in sorted(objects.items()):
        methods = class_methods(include_source, cls)
        if methods is None:
            # A class declared in the EA itself, or one this tool cannot find.
            # Reported rather than skipped silently: a missing class is either a
            # typo or a header this tool should have been pointed at.
            problems.append(f'{obj}: class {cls} was not found in MQL5/Include')
            continue

        for call in re.finditer(re.escape(obj) + r'\.(\w+)\s*\(', clean):
            name = call.group(1)
            if name not in methods:
                problems.append(f'{obj}.{name}: no such method on {cls}')
                continue

            index, depth = call.end(), 1
            while index < len(clean) and depth > 0:
                ch = clean[index]
                if ch in '([':
                    depth += 1
                elif ch in ')]':
                    depth -= 1
                    if depth == 0:
                        break
                index += 1

            passed = len(split_top_level(clean[call.end():index]))
            if not any(lo <= passed <= hi for lo, hi in methods[name]):
                wanted = ' or '.join(f'{lo}..{hi}' if lo != hi else str(lo)
                                     for lo, hi in methods[name])
                problems.append(f'{obj}.{name}: {passed} argument(s) passed, {cls} requires {wanted}')

    return problems


def main():
    include_source = ''.join(p.read_text() for p in sorted(ROOT.glob('MQL5/Include/**/*.mqh')))
    experts = sorted(ROOT.glob('MQL5/Experts/**/*.mq5'))
    if not experts:
        raise RuntimeError('No Expert Advisors found to check.')

    failures = 0
    calls_checked = 0
    for ea in experts:
        problems = check_expert(ea, include_source)
        calls_checked += len(re.findall(r'\bg_\w+\.\w+\s*\(', strip_noise(ea.read_text())))
        if problems:
            failures += len(problems)
            for problem in problems:
                print(f'{ea.relative_to(ROOT)}: {problem}', file=sys.stderr)

    if failures:
        raise RuntimeError(f'{failures} component call(s) do not fit their signature.')

    print(f'EA component calls: {len(experts)} Expert Advisor(s), '
          f'{calls_checked} call sites, every one fits its signature.')


if __name__ == '__main__':
    main()

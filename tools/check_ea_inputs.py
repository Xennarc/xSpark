#!/usr/bin/env python3
"""Enforce per-strategy input isolation across every XSpark Expert Advisor.

MetaTrader applies a .set file by input IDENTIFIER, not by which EA wrote it.
Two EAs that declare the same identifier are therefore one careless "Load" away
from cross-configuring each other - and when the shared identifier is the Magic
Number, the two bots end up managing the same positions. This is source
analysis, not a compiler: it reads the declarations and their references.

Checks:
  1. No input identifier is declared by more than one EA.
  2. Every declared input is referenced somewhere else in its own EA, so an
     input that exists only because another strategy had one cannot survive.
  3. Every EA's Magic Number default comes from the StrategyIdentity registry,
     and the registry's numbers are distinct.
  4. No EA takes an input default from a DIFFERENT strategy's constants.
  5. Every input carries a display label, and it fits MetaTrader's 63-character
     limit, so the Inputs tab never falls back to showing the raw identifier.
  6. Every member of an enum an EA uses as an input type carries the same kind of
     label, because MetaTrader renders those comments as the dropdown's choices.
     An unlabelled member shows the raw identifier to the operator, which is the
     exact failure rule 46 exists to prevent - one level down.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
EXPERTS = sorted((ROOT / "MQL5/Experts").rglob("*.mq5"))
REGISTRY = ROOT / "MQL5/Include/XSpark/Core/StrategyIdentity.mqh"

INPUT_RE = re.compile(r"^input\s+(\S+)\s+(Inp\w+)\s*=\s*([^;]*);(.*)$", re.M)
# An enum an EA names as an input type. Members are matched with their trailing
# comment, which is what MetaTrader shows in the dropdown.
ENUM_RE = re.compile(r"^enum\s+(\w+)\s*\{(.*?)\}\s*;", re.M | re.S)
ENUM_MEMBER_RE = re.compile(r"^\s*(\w+)\s*(?:=\s*[^,/]+)?\s*,?\s*(//.*)?$", re.M)
# MetaTrader renders an input's trailing comment as its name in the Inputs tab
# and truncates past this, so a longer label loses the end of its own sentence.
MAX_LABEL = 63
MAGIC_RE = re.compile(r"^#define\s+XSPARK_(\w+)_MAGIC_DEFAULT\s+(\d+)\s*$", re.M)

failures = []


def fail(message):
    failures.append(message)


if not EXPERTS:
    fail("No Expert Advisors found under MQL5/Experts.")

registry_text = REGISTRY.read_text() if REGISTRY.exists() else ""
if not registry_text:
    fail(f"Missing the strategy identity registry: {REGISTRY.relative_to(ROOT)}")

magics = {tag: int(value) for tag, value in MAGIC_RE.findall(registry_text)}
strategy_tags = set(magics)

# 3a. The registry's own numbers must be distinct.
seen_numbers = {}
for tag, number in sorted(magics.items()):
    if number in seen_numbers:
        fail(f"Magic Number {number} is claimed by both {seen_numbers[number]} and {tag} in the registry.")
    seen_numbers[number] = tag

declared_by = {}

for expert in EXPERTS:
    rel = expert.relative_to(ROOT)
    text = expert.read_text()
    declarations = INPUT_RE.findall(text)

    if not declarations:
        fail(f"{rel}: declares no inputs; expected at least a trading switch.")
        continue

    # Which strategy this EA is, taken from the Magic Number default it uses
    # rather than from a list maintained by hand.
    own_tags = {tag for tag in strategy_tags if f"XSPARK_{tag}_MAGIC_DEFAULT" in text}
    if len(own_tags) != 1:
        fail(
            f"{rel}: expected exactly one XSPARK_<STRATEGY>_MAGIC_DEFAULT from the registry, found "
            f"{sorted(own_tags) if own_tags else 'none'}."
        )
    own_tag = own_tags.pop() if len(own_tags) == 1 else None

    for _type, name, default, trailing in declarations:
        # 1. Identifier uniqueness across EAs.
        if name in declared_by:
            fail(
                f"Input '{name}' is declared by both {declared_by[name]} and {rel}. "
                "A shared identifier lets one EA's .set file silently configure the other; "
                "give each EA its own input prefix."
            )
        else:
            declared_by[name] = rel

        # 2. Declared inputs must actually be used by their own EA.
        if len(re.findall(r"\b" + re.escape(name) + r"\b", text)) < 2:
            fail(f"{rel}: input '{name}' is declared but never used.")

        # 5. A label an operator can read, within what MetaTrader will show.
        label = trailing.split("//", 1)[1].strip() if "//" in trailing else ""
        if not label:
            fail(f"{rel}: input '{name}' has no display label; add a trailing // comment.")
        elif len(label) > MAX_LABEL:
            fail(
                f"{rel}: the label on '{name}' is {len(label)} characters; MetaTrader shows only "
                f"{MAX_LABEL}, so the end would be cut off."
            )

        # 4. Defaults must not read through another strategy's constants.
        if own_tag:
            for tag in strategy_tags - {own_tag}:
                if f"XSPARK_{tag}_" in default:
                    fail(
                        f"{rel}: input '{name}' defaults to a {tag} constant ({default.strip()}). "
                        "Declare this strategy's own default instead."
                    )

    # 3b. The Magic Number input must come from the registry, not a literal.
    magic_inputs = [(n, d) for _t, n, d, _c in declarations if n.endswith("MagicNumber")]
    if len(magic_inputs) != 1:
        fail(f"{rel}: expected exactly one Magic Number input, found {len(magic_inputs)}.")
    elif own_tag and f"XSPARK_{own_tag}_MAGIC_DEFAULT" not in magic_inputs[0][1]:
        fail(
            f"{rel}: Magic Number input defaults to {magic_inputs[0][1].strip()} rather than "
            f"XSPARK_{own_tag}_MAGIC_DEFAULT from the registry."
        )

# 6. Enum members used as input types are the dropdown the operator reads.
enum_members = {}
for header in sorted((ROOT / "MQL5/Include").rglob("*.mqh")):
    for enum_name, body in ENUM_RE.findall(header.read_text()):
        members = []
        for member, comment in ENUM_MEMBER_RE.findall(body):
            if member:
                members.append((member, comment[2:].strip() if comment else ""))
        enum_members[enum_name] = (header.relative_to(ROOT), members)

BUILTIN_INPUT_TYPES = {"bool", "double", "int", "long", "uint", "ulong", "string",
                       "datetime", "color", "float", "short", "char", "uchar"}

for expert in EXPERTS:
    rel = expert.relative_to(ROOT)
    for type_name, name, _default, _trailing in INPUT_RE.findall(expert.read_text()):
        if type_name in BUILTIN_INPUT_TYPES or type_name.startswith("ENUM_"):
            continue
        if type_name not in enum_members:
            fail(f"{rel}: input '{name}' has type '{type_name}', which is not an enum this checker can find "
                 "under MQL5/Include; an operator would see an unlabelled control.")
            continue
        source, members = enum_members[type_name]
        if not members:
            fail(f"{rel}: the enum '{type_name}' behind input '{name}' declares no members ({source}).")
        for member, label in members:
            if not label:
                fail(f"{source}: '{type_name}.{member}' has no label, so the dropdown for '{name}' would show "
                     "the raw identifier; add a trailing // comment.")
            elif len(label) > MAX_LABEL:
                fail(f"{source}: the label on '{type_name}.{member}' is {len(label)} characters; MetaTrader "
                     f"shows only {MAX_LABEL} in the dropdown for '{name}'.")

for message in failures:
    print(f"FAIL: {message}")

if failures:
    print(f"\nEA input isolation: {len(failures)} problem(s).")
    sys.exit(1)

print(f"EA inputs: {len(EXPERTS)} Expert Advisor(s), {len(declared_by)} inputs, "
      "no shared identifiers, all labelled, every dropdown choice labelled.")

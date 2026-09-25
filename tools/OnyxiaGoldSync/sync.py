#!/usr/bin/env python3
"""Download the Warmane Onyxia Alliance snapshot and write a gitignored Lua file.

The addon loads without that file. This tool never writes Horde data and never
talks to WoW.
"""

import os
import sys
import time
import urllib.request

ALLIANCE_URL = "https://ah.nerfed.net/realm/getfile?id=17&faction=2"
COUNT_INDEX = 11
BUYOUT_INDEX = 17
ITEM_INDEX = 23
MAX_DEPTH = 40


class InvalidSnapshot(Exception):
    pass


def download_alliance():
    request = urllib.request.Request(
        ALLIANCE_URL,
        headers={"User-Agent": "OnyxiaGoldSync/0.1"},
    )
    try:
        response = urllib.request.urlopen(request, timeout=120)
    except Exception as exc:
        raise InvalidSnapshot("download failed: %s" % exc)
    try:
        raw = response.read()
    finally:
        response.close()
    return raw.decode("utf-8", "replace")


def extract_ropes(text):
    key = text.find('["ropes"]')
    if key < 0:
        raise InvalidSnapshot("snapshot has no ropes")
    brace = text.find("{", key)
    if brace < 0:
        raise InvalidSnapshot("snapshot ropes are not a table")
    i = brace + 1
    n = len(text)
    depth = 1
    ropes = []
    while i < n and depth > 0:
        char = text[i]
        if char == '"':
            i += 1
            chars = []
            while i < n:
                if text[i] == "\\":
                    if i + 1 >= n:
                        raise InvalidSnapshot("truncated escape in ropes")
                    chars.append(text[i + 1])
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                chars.append(text[i])
                i += 1
            else:
                raise InvalidSnapshot("unterminated rope string")
            ropes.append("".join(chars))
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        i += 1
    if not ropes:
        raise InvalidSnapshot("snapshot ropes are empty")
    return ropes


def _word(text, i, word):
    end = i + len(word)
    if text[i:end] != word:
        return False
    if end < len(text) and (text[end].isalnum() or text[end] == "_"):
        return False
    return True


class LiteralParser(object):
    def __init__(self, text):
        self.text = text
        self.i = 0
        self.n = len(text)

    def peek(self):
        if self.i >= self.n:
            return ""
        return self.text[self.i]

    def skip(self):
        while self.i < self.n:
            char = self.text[self.i]
            if char in " \t\r\n":
                self.i += 1
                continue
            if char == "-" and self.i + 1 < self.n and self.text[self.i + 1] == "-":
                self.i += 2
                while self.i < self.n and self.text[self.i] not in "\r\n":
                    self.i += 1
                continue
            break

    def parse_string(self):
        self.i += 1
        chars = []
        while self.i < self.n:
            char = self.text[self.i]
            if char == "\\":
                if self.i + 1 >= self.n:
                    raise InvalidSnapshot("truncated string")
                chars.append(self.text[self.i + 1])
                self.i += 2
                continue
            if char == '"':
                self.i += 1
                return "".join(chars)
            chars.append(char)
            self.i += 1
        raise InvalidSnapshot("unterminated string")

    def parse_number(self):
        start = self.i
        if self.peek() == "-":
            self.i += 1
        if not self.peek().isdigit():
            raise InvalidSnapshot("bad number")
        while self.peek().isdigit():
            self.i += 1
        if self.peek() == ".":
            self.i += 1
            if not self.peek().isdigit():
                raise InvalidSnapshot("bad number")
            while self.peek().isdigit():
                self.i += 1
            return float(self.text[start:self.i])
        return int(self.text[start:self.i])

    def parse_table(self):
        self.i += 1
        values = []
        while True:
            self.skip()
            if self.peek() == "}":
                self.i += 1
                return values
            if self.peek() == "":
                raise InvalidSnapshot("unclosed table")
            if self.peek() == "[":
                raise InvalidSnapshot("unexpected key in auction rope")
            values.append(self.parse_value())
            self.skip()
            if self.peek() == ",":
                self.i += 1
                continue
            if self.peek() == "}":
                continue
            raise InvalidSnapshot("expected comma in table")

    def parse_value(self):
        self.skip()
        char = self.peek()
        if char == "{":
            return self.parse_table()
        if char == '"':
            return self.parse_string()
        if char == "-" or char.isdigit():
            if char == "-" and self.i + 1 < self.n and self.text[self.i + 1] == "-":
                raise InvalidSnapshot("comment where a value was required")
            return self.parse_number()
        if _word(self.text, self.i, "nil"):
            self.i += 3
            return None
        if _word(self.text, self.i, "true"):
            self.i += 4
            return True
        if _word(self.text, self.i, "false"):
            self.i += 5
            return False
        raise InvalidSnapshot("unexpected token in auction rope")

    def parse_return(self):
        self.skip()
        if not _word(self.text, self.i, "return"):
            raise InvalidSnapshot("rope does not return a table")
        self.i += 6
        self.skip()
        if self.peek() != "{":
            raise InvalidSnapshot("rope return is not a table")
        return self.parse_table()


def require_alliance(text):
    if "AucScanData" not in text:
        raise InvalidSnapshot("not an Auctioneer snapshot")
    if '["Onyxia"]' not in text:
        raise InvalidSnapshot("snapshot is not Onyxia")
    if "Onyxia-Alliance" not in text or '["Alliance"]' not in text:
        raise InvalidSnapshot("snapshot is not Onyxia Alliance")
    if "Onyxia-Horde" in text or '["Horde"]' in text:
        raise InvalidSnapshot("refusing a file that is not Alliance-only")
    marker = text.find('["LastFullScan"]')
    if marker < 0:
        raise InvalidSnapshot("snapshot has no scan time")
    equals = text.find("=", marker)
    if equals < 0:
        raise InvalidSnapshot("snapshot has no scan time")
    number = text[equals + 1:].lstrip()
    digits = []
    for char in number:
        if char.isdigit():
            digits.append(char)
        else:
            break
    if not digits:
        raise InvalidSnapshot("snapshot has no scan time")
    return int("".join(digits))


def field(row, index):
    if not isinstance(row, list):
        return None
    if index < 1 or index > len(row):
        return None
    return row[index - 1]


def as_int(value):
    if isinstance(value, bool) or isinstance(value, float):
        return None
    if isinstance(value, int):
        return value
    return None


def percentile(levels, quantity, fraction):
    if quantity <= 0 or not levels:
        return None
    target = quantity * fraction
    if target <= 0:
        target = 1
    cumulative = 0
    last = None
    for level in levels:
        last = level["p"]
        cumulative += level["q"]
        if cumulative >= target:
            return level["p"]
    return last


def aggregate(auctions):
    buckets = {}
    for row in auctions:
        if not isinstance(row, list):
            continue
        item_id = as_int(field(row, ITEM_INDEX))
        count = as_int(field(row, COUNT_INDEX))
        buyout = as_int(field(row, BUYOUT_INDEX))
        if not item_id or item_id < 1 or item_id > 999999:
            continue
        if not count or count < 1 or not buyout or buyout < 1:
            continue
        unit = buyout // count
        if unit < 1:
            continue
        item = buckets.get(item_id)
        if item is None:
            item = {"quantity": 0, "auctions": 0, "levels": {}}
            buckets[item_id] = item
        item["quantity"] += count
        item["auctions"] += 1
        key = (unit, count)
        level = item["levels"].get(key)
        if level is None:
            item["levels"][key] = {"p": unit, "q": count, "n": 1, "s": count}
        else:
            level["q"] += count
            level["n"] += 1
    items = {}
    for item_id in buckets:
        item = buckets[item_id]
        levels = list(item["levels"].values())
        levels.sort(key=lambda level: (level["p"], level["s"]))
        p10 = percentile(levels, item["quantity"], 0.10)
        p25 = percentile(levels, item["quantity"], 0.25)
        median = percentile(levels, item["quantity"], 0.50)
        stored = levels
        covered = item["quantity"]
        if len(levels) > MAX_DEPTH:
            stored = levels[:MAX_DEPTH]
            covered = 0
            for level in stored:
                covered += level["q"]
        items[item_id] = {
            "min": levels[0]["p"],
            "p10": p10,
            "p25": p25,
            "median": median,
            "quantity": item["quantity"],
            "auctionCount": item["auctions"],
            "depthCoveredQuantity": covered,
            "depth": stored,
        }
    return items


def convert(text, imported_at):
    scanned_at = require_alliance(text)
    ropes = extract_ropes(text)
    auctions = []
    for rope in ropes:
        if not rope.startswith("return"):
            raise InvalidSnapshot("rope is not an auction return")
        parsed = LiteralParser(rope).parse_return()
        if not isinstance(parsed, list):
            raise InvalidSnapshot("rope is not a list")
        auctions.extend(parsed)
    items = aggregate(auctions)
    return render(items, scanned_at, imported_at)


def render_level(level):
    return "{ p = %d, q = %d, n = %d, s = %d }" % (
        level["p"], level["q"], level["n"], level["s"]
    )


def render(items, scanned_at, imported_at):
    lines = [
        "-- Generated by tools/OnyxiaGoldSync. Gitignored. Not a live scan.",
        "OnyxiaGoldExternalData = {",
        "  schemaVersion = 1,",
        '  source = "ah.nerfed.net",',
        '  realm = "Onyxia",',
        '  faction = "Alliance",',
        "  scannedAt = %d," % scanned_at,
        "  importedAt = %d," % imported_at,
        "  items = {",
    ]
    for item_id in sorted(items):
        row = items[item_id]
        depth = ", ".join(render_level(level) for level in row["depth"])
        lines.append(
            "    [%d] = { min = %d, p10 = %d, p25 = %d, median = %d, quantity = %d, auctionCount = %d, depthCoveredQuantity = %d, depth = { %s } },"
            % (
                item_id,
                row["min"],
                row["p10"],
                row["p25"],
                row["median"],
                row["quantity"],
                row["auctionCount"],
                row["depthCoveredQuantity"],
                depth,
            )
        )
    lines.append("  },")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def atomic_write(path, text):
    parent = os.path.dirname(path)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent)
    tmp = path + ".tmp"
    handle = open(tmp, "w")
    try:
        handle.write(text)
    finally:
        handle.close()
    os.rename(tmp, path)


def default_output():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    return os.path.join(root, "Data", "ExternalMarketData.lua")


def main(argv):
    source = None
    output = default_output()
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--input":
            i += 1
            if i >= len(argv):
                raise InvalidSnapshot("--input needs a path")
            source = argv[i]
        elif arg == "--output":
            i += 1
            if i >= len(argv):
                raise InvalidSnapshot("--output needs a path")
            output = argv[i]
        else:
            raise InvalidSnapshot("unknown argument")
        i += 1
    if source:
        handle = open(source, "r")
        try:
            text = handle.read()
        finally:
            handle.close()
    else:
        text = download_alliance()
    rendered = convert(text, int(time.time()))
    atomic_write(output, rendered)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except InvalidSnapshot as exc:
        sys.stderr.write("OnyxiaGoldSync: %s\n" % exc)
        sys.exit(1)

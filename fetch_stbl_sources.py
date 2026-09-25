#!/usr/bin/env python3
"""
fetch_stbl_sources.py  —  STBL ESS delta-hunt retrieval harness (Phase 1 + Phase 16).

WHAT IT DOES (read-only; no transactions, no funds):
  For each in-scope proxy on ETH (chainid=1) and BSC (chainid=56):
    1. Resolves the implementation via EIP-1967 slots (impl / beacon / admin) using
       Etherscan's proxy module (eth_getStorageAt), with getsourcecode fallback.
    2. Pulls the proxy's full `Upgraded(address)` event history (getLogs) to see WHICH
       implementation was set WHEN, and the PRIOR implementation.
    3. Records implementation creation block+timestamp (getcontractcreation).
    4. Downloads verified source (getsourcecode) for the CURRENT and PRIOR impl,
       preserving the multi-file tree, compiler, optimizer, and metadata.
    5. Classifies each target NEW / MODIFIED / UNCHANGED against the hunt window
       and writes STBL_NEW_CODE_TARGET_MATRIX.md.

USAGE:
    export ETHERSCAN_API_KEY=<key>          # never hardcoded; never written to output
    python3 fetch_stbl_sources.py           # stdlib only (urllib), no pip needed

  Etherscan V2 multichain: one key covers ETH (1) and BSC (56).
  Run it where outbound HTTPS to api.etherscan.io is allowed (your machine, or after
  the cloud environment's Network access allowlists api.etherscan.io).

OUTPUT (next to this script):
    sources/<label>/current/...      verified source tree of the current impl
    sources/<label>/prior/...        verified source tree of the prior impl (if any)
    metadata/<label>.json            impl addr, bytecodehash, compiler, upgrade log, dates
    abis/<label>.json
    STBL_NEW_CODE_TARGET_MATRIX.md
"""
import json, os, sys, time, urllib.parse, urllib.request, datetime, pathlib, hashlib

HERE = pathlib.Path(__file__).resolve().parent
KEY = os.environ.get("ETHERSCAN_API_KEY", "").strip()

# Hunt window (inclusive), UTC.
WINDOW_START = datetime.datetime(2026, 9, 10, tzinfo=datetime.timezone.utc)
WINDOW_END   = datetime.datetime(2026, 9, 24, 23, 59, 59, tzinfo=datetime.timezone.utc)

# EIP-1967 storage slots
SLOT_IMPL   = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
SLOT_BEACON = "0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50"
SLOT_ADMIN  = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
# keccak256("Upgraded(address)")
TOPIC_UPGRADED = "0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b"

TARGETS = [
    # (label, chainid, proxy)
    ("STBL_PT1_Vault-USDY",            1, "0xd238e964b557bd8f39feba8c2c93d6f428007232"),
    ("STBL_PT1_YieldDistributor-USDY", 1, "0x97fb98a7a7400bc651dec6a02640a36f8bdfaa0b"),
    ("STBL_LT1_Issuer-USDY",           1, "0x916442ebaa1cef4b3f5cd9b7a62170b50c3305c1"),
    ("STBL_LT1_Vault-USDY",            1, "0x5766b5d21bea4de3dda1b935f1740d194babab1f"),
    ("STBL_LT1_YieldDistributor-USDY", 1, "0xcc14f2eddeae2a3c450c7afe328fd7331355dd73"),
    ("STBL_PT1_Issuer-OUSG",           1, "0xf8acf255854c8d36010c849f1702eb350c8c4087"),
    ("STBL_PT1_Vault-OUSG",            1, "0x64bef4478942d8fd62be281707076442aa2d055e"),
    ("STBL_PT1_YieldDistributor-OUSG", 1, "0x447a8f3608fb2002c1aa8e44b076b7d62b6fa618"),
    ("STBL_LT1_Issuer-OUSG",           1, "0xbac1f4f20847669ba12841a534b2aa053d65373c"),
    ("STBL_LT1_Vault-OUSG",            1, "0x0437ee84ca723ceb7052a8cc73360e21427c42ea"),
    ("STBL_LT1_YieldDistributor-OUSG", 1, "0x50eda4294d9a57b35a9d836faaeb88d1c4fab6c9"),
    ("STBL_USST",                     56, "0x1171ce10262a60c17507580a3b70b956f20a35de"),
]

API = "https://api.etherscan.io/v2/api"

def call(chainid, params, retries=4):
    params = dict(params); params["chainid"] = chainid; params["apikey"] = KEY
    url = API + "?" + urllib.parse.urlencode(params)
    last = None
    for i in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=40) as r:
                data = json.loads(r.read().decode())
            # rate-limit / transient -> backoff
            if isinstance(data.get("result"), str) and "rate limit" in data["result"].lower():
                time.sleep(1.5 * (i + 1)); continue
            return data
        except Exception as e:
            last = e; time.sleep(1.5 * (i + 1))
    return {"status": "0", "message": "http-error", "result": str(last)}

def addr_from_slot(chainid, proxy, slot):
    d = call(chainid, {"module": "proxy", "action": "eth_getStorageAt",
                       "address": proxy, "position": slot, "tag": "latest"})
    v = d.get("result")
    if isinstance(v, str) and v.startswith("0x") and len(v) >= 42:
        a = "0x" + v[-40:]
        return None if int(a, 16) == 0 else a.lower()
    return None

def block_ts(chainid, block_hex):
    d = call(chainid, {"module": "proxy", "action": "eth_getBlockByNumber",
                       "tag": block_hex, "boolean": "false"})
    r = d.get("result") or {}
    ts = r.get("timestamp")
    return int(ts, 16) if ts else None

def upgrade_history(chainid, proxy):
    """All Upgraded(address) events on the proxy, oldest->newest, with impl + timestamp."""
    d = call(chainid, {"module": "logs", "action": "getLogs", "address": proxy,
                       "topic0": TOPIC_UPGRADED, "fromBlock": "0", "toBlock": "latest"})
    out = []
    res = d.get("result")
    if not isinstance(res, list):
        return out, d.get("message")
    for log in res:
        impl = None
        # impl is topic1 (indexed) in EIP-1967 ERC1967Upgrade; some variants put it in data
        topics = log.get("topics") or []
        if len(topics) >= 2 and len(topics[1]) >= 42:
            impl = "0x" + topics[1][-40:]
        elif log.get("data") and len(log["data"]) >= 42:
            impl = "0x" + log["data"][-40:]
        bn = int(log["blockNumber"], 16) if log.get("blockNumber") else None
        ts = int(log["timeStamp"], 16) if log.get("timeStamp") else (block_ts(chainid, log["blockNumber"]) if bn else None)
        out.append({"impl": impl.lower() if impl else None, "block": bn, "timestamp": ts})
    out.sort(key=lambda x: (x["block"] or 0))
    return out, None

def creation(chainid, impl):
    d = call(chainid, {"module": "contract", "action": "getcontractcreation",
                       "contractaddresses": impl})
    r = d.get("result")
    if isinstance(r, list) and r:
        rec = r[0]
        bn = rec.get("blockNumber")
        ts = rec.get("timestamp")
        if ts:
            ts = int(ts)
        elif bn:
            ts = block_ts(chainid, hex(int(bn)))
        return {"creator": rec.get("contractCreator"), "txHash": rec.get("txHash"),
                "block": int(bn) if bn else None, "timestamp": ts}
    return {}

def get_source(chainid, impl, dest_dir):
    d = call(chainid, {"module": "contract", "action": "getsourcecode", "address": impl})
    r = d.get("result")
    if not (isinstance(r, list) and r):
        return {"verified": False, "raw_message": d.get("message")}
    info = r[0]
    src = info.get("SourceCode", "") or ""
    meta = {k: info.get(k) for k in ("ContractName", "CompilerVersion", "OptimizationUsed",
                                     "Runs", "EVMVersion", "Proxy", "Implementation", "LicenseType")}
    meta["verified"] = bool(src)
    dest_dir.mkdir(parents=True, exist_ok=True)
    # Standard-JSON-Input verified sources come wrapped in {{ ... }}
    files_written = []
    if src.startswith("{"):
        blob = src
        if src.startswith("{{") and src.endswith("}}"):
            blob = src[1:-1]
        try:
            j = json.loads(blob)
            sources = j.get("sources", j)
            for path, obj in sources.items():
                content = obj.get("content", "") if isinstance(obj, dict) else str(obj)
                fp = dest_dir / path.replace("..", "_")
                fp.parent.mkdir(parents=True, exist_ok=True)
                fp.write_text(content)
                files_written.append(path)
        except Exception:
            (dest_dir / f"{meta.get('ContractName','contract')}.sol").write_text(src)
            files_written.append("raw.sol")
    else:
        (dest_dir / f"{meta.get('ContractName','contract')}.sol").write_text(src)
        files_written.append(f"{meta.get('ContractName','contract')}.sol")
    meta["files"] = files_written
    meta["source_sha256"] = hashlib.sha256(src.encode()).hexdigest() if src else None
    (dest_dir.parent / "abi.json").write_text(info.get("ABI", "") or "")
    return meta

def in_window(ts):
    if not ts: return None
    dt = datetime.datetime.fromtimestamp(ts, datetime.timezone.utc)
    return WINDOW_START <= dt <= WINDOW_END

def main():
    if not KEY:
        print("FATAL: ETHERSCAN_API_KEY not set in environment. `export ETHERSCAN_API_KEY=...` and retry.")
        sys.exit(2)
    rows = []
    for label, chainid, proxy in TARGETS:
        print(f"[*] {label} ({'ETH' if chainid==1 else 'BSC'}) {proxy}")
        impl = addr_from_slot(chainid, proxy, SLOT_IMPL)
        beacon = addr_from_slot(chainid, proxy, SLOT_BEACON)
        admin = addr_from_slot(chainid, proxy, SLOT_ADMIN)
        hist, herr = upgrade_history(chainid, proxy)
        # current impl: prefer live slot, else last Upgraded event
        if not impl and hist:
            impl = hist[-1]["impl"]
        prior = None
        if len(hist) >= 2:
            prior = hist[-2]["impl"]
        last_up = hist[-1] if hist else None
        cur_create = creation(chainid, impl) if impl else {}
        classify_ts = (last_up["timestamp"] if last_up else None) or cur_create.get("timestamp")
        iw = in_window(classify_ts)
        klass = "UNKNOWN"
        if iw is True:
            klass = "MODIFIED" if len(hist) >= 2 else "NEW"
        elif iw is False:
            klass = "UNCHANGED"
        meta = {"label": label, "chainid": chainid, "proxy": proxy,
                "impl_slot": impl, "beacon_slot": beacon, "admin_slot": admin,
                "current_impl": impl, "prior_impl": prior,
                "upgrade_history": hist, "upgrade_history_error": herr,
                "current_impl_creation": cur_create,
                "classify_timestamp": classify_ts,
                "classify_datetime_utc": (datetime.datetime.fromtimestamp(classify_ts, datetime.timezone.utc).isoformat() if classify_ts else None),
                "classification": klass}
        if impl:
            meta["current_source"] = get_source(chainid, impl, HERE / "sources" / label / "current")
            time.sleep(0.25)
            if prior:
                meta["prior_source"] = get_source(chainid, prior, HERE / "sources" / label / "prior")
                time.sleep(0.25)
        (HERE / "metadata" / f"{label}.json").write_text(json.dumps(meta, indent=2))
        rows.append(meta)
        time.sleep(0.25)

    # Target matrix
    lines = ["# STBL_NEW_CODE_TARGET_MATRIX",
             f"\nGenerated {datetime.datetime.now(datetime.timezone.utc).isoformat()} — window "
             f"{WINDOW_START.date()}..{WINDOW_END.date()} (UTC). Etherscan V2 multichain.\n",
             "| Target | Chain | Proxy | Current impl | Prior impl | Last upgrade (UTC) | #upg | Class | Verified |",
             "|--------|-------|-------|--------------|-----------|--------------------|------|-------|----------|"]
    for m in rows:
        cs = (m.get("current_source") or {})
        lines.append("| {label} | {chain} | `{proxy}` | `{impl}` | `{prior}` | {dt} | {n} | **{k}** | {v} |".format(
            label=m["label"], chain=("ETH" if m["chainid"]==1 else "BSC"), proxy=m["proxy"],
            impl=m.get("current_impl") or "?", prior=m.get("prior_impl") or "-",
            dt=(m.get("classify_datetime_utc") or "?"), n=len(m.get("upgrade_history") or []),
            k=m["classification"], v=("yes" if cs.get("verified") else "NO")))
    lines += ["\n## Delta focus", "",
              "Targets classified NEW or MODIFIED with a last-upgrade timestamp inside the window are the",
              "PRIMARY hunt surface. For MODIFIED targets a prior_impl is present — diff current vs prior:",
              "```", "for d in sources/*/ ; do diff -ru \"$d/prior\" \"$d/current\" > \"diff/$(basename $d).diff\" 2>/dev/null; done",
              "```", "UNCHANGED/UNKNOWN targets are context only unless they sit on a new cross-contract path."]
    (HERE / "STBL_NEW_CODE_TARGET_MATRIX.md").write_text("\n".join(lines) + "\n")
    print("\n[+] Wrote STBL_NEW_CODE_TARGET_MATRIX.md, metadata/, sources/, abis/")
    print("[+] Next: run the diff loop above, then analyze only NEW/MODIFIED regions.")

if __name__ == "__main__":
    main()

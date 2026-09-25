#!/usr/bin/env python3
"""
fetch_splitter.py — resolve the STBL periphery (Register, Core, YLD, and the SPLITTER_ROLE
holder(s)) from chain and pull their verified source. READ-ONLY Etherscan V2 (ETH chainid=1).
Needs ETHERSCAN_API_KEY in env. Run where api.etherscan.io is reachable.
Outputs: sources_ext/<label>_<addr>/... , topology.json  (then git add/commit/push).
"""
import json, os, sys, time, urllib.parse, urllib.request, pathlib, hashlib

HERE = pathlib.Path(__file__).resolve().parent
KEY = os.environ.get("ETHERSCAN_API_KEY","").strip()
API = "https://api.etherscan.io/v2/api"
CHAIN = 1

LT1_ISSUER_USDY = "0x916442ebaa1cef4b3f5cd9b7a62170b50c3305c1"
SEL_fetchRegistry = "0xdd0b9ff0"
SEL_fetchCore     = "0xcf02ecc6"
SEL_fetchYLD      = "0xef3ac1f4"
SEL_fetchTreasury = "0x00ca3aed"
SEL_roleCount     = "0xca15c873"  # getRoleMemberCount(bytes32)
SEL_roleMember    = "0x9010d07c"  # getRoleMember(bytes32,uint256)
SPLITTER_ROLE = "0xebea61bac29e76544ef1875472aaff98e28d2db11686c8cbef6c2b35dbe32407"
DEFAULT_ADMIN = "0x" + "00"*32
TOPIC_RoleGranted = "0x2f8788117e7eff1d82e926ec794901d17c78024a50270940304540a733656f0d"

def call(params, retries=4):
    p=dict(params); p["chainid"]=CHAIN; p["apikey"]=KEY
    url=API+"?"+urllib.parse.urlencode(p); last=None
    for i in range(retries):
        try:
            with urllib.request.urlopen(url,timeout=40) as r: d=json.loads(r.read().decode())
            if isinstance(d.get("result"),str) and "rate limit" in d["result"].lower(): time.sleep(1.5*(i+1)); continue
            return d
        except Exception as e: last=e; time.sleep(1.5*(i+1))
    return {"status":"0","message":"http-error","result":str(last)}

def eth_call(to, data):
    d=call({"module":"proxy","action":"eth_call","to":to,"data":data,"tag":"latest"})
    return d.get("result")

def addr_from_word(hexword):
    if not (isinstance(hexword,str) and hexword.startswith("0x")): return None
    h=hexword[2:].rjust(64,"0"); a="0x"+h[-40:]
    return None if int(a,16)==0 else a.lower()

def role_members(reg, role):
    out=[]
    cnt=eth_call(reg, SEL_roleCount+role[2:])
    try: n=int(cnt,16)
    except: n=None
    if n is not None and n < 50:
        for i in range(n):
            m=eth_call(reg, SEL_roleMember+role[2:]+hex(i)[2:].rjust(64,"0"))
            a=addr_from_word(m)
            if a: out.append(a)
            time.sleep(0.2)
        return out, "enumerable"
    # fallback: getLogs RoleGranted with topic1=role
    d=call({"module":"logs","action":"getLogs","address":reg,"topic0":TOPIC_RoleGranted,
            "topic0_1_opr":"and","topic1":role,"fromBlock":"0","toBlock":"latest"})
    res=d.get("result")
    if isinstance(res,list):
        for lg in res:
            t=lg.get("topics") or []
            if len(t)>=3:
                a=addr_from_word(t[2])
                if a and a not in out: out.append(a)
    return out, "logs"

def get_source(addr, label):
    d=call({"module":"contract","action":"getsourcecode","address":addr})
    r=d.get("result")
    if not (isinstance(r,list) and r): return {"verified":False,"msg":d.get("message")}
    info=r[0]; src=info.get("SourceCode","") or ""
    dest=HERE/"sources_ext"/f"{label}_{addr}"; dest.mkdir(parents=True,exist_ok=True)
    files=[]
    if src.startswith("{"):
        blob=src[1:-1] if src.startswith("{{") else src
        try:
            j=json.loads(blob); srcs=j.get("sources",j)
            for path,obj in srcs.items():
                c=obj.get("content","") if isinstance(obj,dict) else str(obj)
                fp=dest/path.replace("..","_"); fp.parent.mkdir(parents=True,exist_ok=True); fp.write_text(c); files.append(path)
        except Exception:
            (dest/f"{info.get('ContractName','c')}.sol").write_text(src); files.append("raw.sol")
    elif src:
        (dest/f"{info.get('ContractName','c')}.sol").write_text(src); files.append("single.sol")
    return {"verified":bool(src),"name":info.get("ContractName"),"compiler":info.get("CompilerVersion"),
            "impl":info.get("Implementation"),"proxy":info.get("Proxy"),"files":files}

def main():
    if not KEY: print("FATAL: set ETHERSCAN_API_KEY"); sys.exit(2)
    (HERE/"sources_ext").mkdir(exist_ok=True)
    topo={}
    reg=addr_from_word(eth_call(LT1_ISSUER_USDY, SEL_fetchRegistry)); topo["register"]=reg
    print("register:",reg)
    core=yld=treasury=None
    if reg:
        core=addr_from_word(eth_call(reg,SEL_fetchCore)); yld=addr_from_word(eth_call(reg,SEL_fetchYLD)); treasury=addr_from_word(eth_call(reg,SEL_fetchTreasury))
    topo.update({"core":core,"yld":yld,"treasury":treasury}); print("core:",core,"yld:",yld,"treasury:",treasury)
    splitters, how = ([], None)
    if reg:
        splitters, how = role_members(reg, SPLITTER_ROLE)
    topo["splitter_role_holders"]=splitters; topo["role_lookup"]=how
    print("SPLITTER_ROLE holders (",how,"):",splitters)
    # fetch source of everything discovered
    fetched={}
    for label,addr in [("Register",reg),("Core",core),("YLD",yld)]:
        if addr: fetched[label]=get_source(addr,label); time.sleep(0.25)
    for i,addr in enumerate(splitters):
        fetched[f"SPLITTER{i}"]=get_source(addr,f"SPLITTER{i}"); time.sleep(0.25)
    topo["fetched"]=fetched
    (HERE/"topology.json").write_text(json.dumps(topo,indent=2))
    print("\n[+] wrote topology.json + sources_ext/. Fetched:",{k:v.get('name') for k,v in fetched.items()})

if __name__=="__main__": main()

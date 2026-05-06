# Ghidra headless script: find functions referencing SEQUENT.SYS / temp.Nmg / Pascal source paths
# and dump their decompilation to a file.
# @category Custom

from ghidra.app.decompiler import DecompInterface
from ghidra.util.task import ConsoleTaskMonitor
import os

OUT = "/Users/alexscott/Projects/LEDctrl/analysis/ghidra/decomp.txt"

def find_string_addrs(needles):
    out = {}
    listing = currentProgram.getListing()
    mem = currentProgram.getMemory()
    data = listing.getDefinedData(True)
    for d in data:
        try:
            v = d.getValue()
            if v is None:
                continue
            s = str(v)
            for n in needles:
                if n in s:
                    out.setdefault(n, []).append((d.getAddress(), s))
        except:
            pass
    return out

def get_xrefs(addr):
    refs = currentProgram.getReferenceManager().getReferencesTo(addr)
    return [r.getFromAddress() for r in refs]

def fcn_for(addr):
    return currentProgram.getFunctionManager().getFunctionContaining(addr)

di = DecompInterface()
di.openProgram(currentProgram)
mon = ConsoleTaskMonitor()

needles = ["SEQUENT.SYS", "temp.Nmg", "uJetFileICMD.pas", "uJetFileIICMD.pas",
           "RUNTIME.SYS", "CONFIG.SYS", "JetFileII", "SequentList.tmps"]

found = find_string_addrs(needles)

fcns = {}
for n, hits in found.items():
    for addr, s in hits:
        for caller in get_xrefs(addr):
            f = fcn_for(caller)
            if f:
                fcns.setdefault(f.getEntryPoint().toString(), (f, set())) [1].add(n)

with open(OUT, "w") as fh:
    fh.write("=== Strings located ===\n")
    for n, hits in sorted(found.items()):
        fh.write(f"{n}: {[a.toString() for a,_ in hits]}\n")
    fh.write("\n=== Functions referencing them ===\n")
    for ep, (f, ns) in sorted(fcns.items()):
        fh.write(f"{ep}  {f.getName()}  refs={sorted(ns)}\n")
    fh.write("\n=== Decompiled ===\n")
    for ep, (f, ns) in sorted(fcns.items()):
        fh.write(f"\n\n;;; ============================================\n")
        fh.write(f";;; {ep}  {f.getName()}  refs={sorted(ns)}\n")
        fh.write(f";;; ============================================\n")
        try:
            r = di.decompileFunction(f, 60, mon)
            if r and r.getDecompiledFunction():
                fh.write(r.getDecompiledFunction().getC())
            else:
                fh.write("// decompile failed\n")
        except Exception as e:
            fh.write(f"// exception: {e}\n")

print("DONE -> %s" % OUT)

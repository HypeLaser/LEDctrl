import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

public class FindFn52c044Callers extends GhidraScript {
    @Override public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        Address tgt = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(0x0052c044L);
        ReferenceIterator refs = currentProgram.getReferenceManager().getReferencesTo(tgt);
        java.util.Set<Long> seen = new java.util.HashSet<>();
        while (refs.hasNext()) {
            Reference r = refs.next();
            Function f = currentProgram.getFunctionManager().getFunctionContaining(r.getFromAddress());
            if (f == null) {
                println("  " + r.getFromAddress() + "  (orphan)");
                continue;
            }
            long ep = f.getEntryPoint().getOffset();
            if (!seen.add(ep)) continue;
            println("\n=== caller " + f.getName() + " @ " + f.getEntryPoint() + " ===");
            DecompileResults res = d.decompileFunction(f, 60, null);
            if (res != null && res.getDecompiledFunction() != null) {
                println(res.getDecompiledFunction().getC());
            }
        }
    }
}

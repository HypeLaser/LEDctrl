import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressFactory;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

public class FindTokenXrefs extends GhidraScript {
    @Override public void run() throws Exception {
        long[] tokens = {
            0x0052cd9cL, 0x0052cdd0L, 0x0052ce04L, 0x0052ce38L,
            0x0052c3d4L, 0x0052c3e0L, 0x0052c3ecL, 0x0052c3f8L
        };
        AddressFactory af = currentProgram.getAddressFactory();
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        java.util.Set<Long> seen = new java.util.HashSet<>();
        for (long off : tokens) {
            Address a = af.getDefaultAddressSpace().getAddress(off);
            println("\n### refs to 0x" + Long.toHexString(off) + " ###");
            ReferenceIterator refs = currentProgram.getReferenceManager().getReferencesTo(a);
            while (refs.hasNext()) {
                Reference r = refs.next();
                Function f = currentProgram.getFunctionManager().getFunctionContaining(r.getFromAddress());
                if (f == null) {
                    println("  " + r.getFromAddress() + "  (not in function)");
                    continue;
                }
                println("  " + r.getFromAddress() + "  in " + f.getName() + " @ " + f.getEntryPoint());
                long ep = f.getEntryPoint().getOffset();
                if (seen.add(ep)) {
                    DecompileResults res = d.decompileFunction(f, 30, null);
                    if (res != null && res.getDecompiledFunction() != null) {
                        println("--- DECOMP " + f.getName() + " ---");
                        println(res.getDecompiledFunction().getC());
                        println("--- END ---");
                    }
                }
            }
        }
    }
}

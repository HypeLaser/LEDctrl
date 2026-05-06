// Decompile the wire dispatcher and response decoder.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class DumpDispatcher extends GhidraScript {
    public void run() throws Exception {
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);

        long[] targets = new long[]{
            0x1000f590L, // RPC dispatcher
            0x1000fdd0L, // response decoder
            0x1000f3e0L, // setup (already saw — refresh for context)
        };
        String[] names = new String[]{"FUN_1000f590_dispatch", "FUN_1000fdd0_response", "FUN_1000f3e0_setup"};

        for (int i = 0; i < targets.length; i++) {
            println("\n=================== " + names[i] + " ===================");
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(targets[i]);
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            if (f == null) { disassemble(a); f = createFunction(a, names[i]); }
            if (f == null) { println("FAILED"); continue; }
            DecompileResults res = decomp.decompileFunction(f, 60, null);
            if (res != null && res.getDecompiledFunction() != null) {
                println(res.getDecompiledFunction().getC());
            }
        }
    }
}

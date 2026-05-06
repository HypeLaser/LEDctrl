// Decompile inner RPC builders + base CBaseCMD machinery.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class DumpReadInner extends GhidraScript {
    public void run() throws Exception {
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);

        long[] targets = new long[]{
            0x100190c0L, // czReadPCBID inner
            0x10019000L, // czReadBrightInfoExt inner
            0x1000f3e0L, // base CBaseCMD setup
            0x10002f60L, // gating check (returns char)
        };
        String[] names = new String[]{"FUN_100190c0_PCBID_inner", "FUN_10019000_BrightInfo_inner",
                                       "FUN_1000f3e0_base_setup", "FUN_10002f60_gate"};

        for (int i = 0; i < targets.length; i++) {
            println("\n=================== " + names[i] + " (0x" + Long.toHexString(targets[i]) + ") ===================");
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(targets[i]);
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            if (f == null) {
                println("(no function — disassembling)");
                disassemble(a);
                f = createFunction(a, names[i]);
            }
            if (f == null) { println("FAILED to create function"); continue; }
            DecompileResults res = decomp.decompileFunction(f, 60, null);
            if (res != null && res.getDecompiledFunction() != null) {
                println(res.getDecompiledFunction().getC());
            }
        }

        // Also: find czReadCurrentState
        println("\n=================== czReadCurrentState ===================");
        Function rcs = null;
        var it = currentProgram.getSymbolTable().getAllSymbols(true);
        while (it.hasNext()) {
            var s = it.next();
            if (s.getName().contains("czReadCurrentState")) {
                rcs = currentProgram.getFunctionManager().getFunctionAt(s.getAddress());
                if (rcs != null) break;
            }
        }
        if (rcs != null) {
            println("addr=" + rcs.getEntryPoint());
            DecompileResults res = decomp.decompileFunction(rcs, 60, null);
            if (res != null) println(res.getDecompiledFunction().getC());
        } else {
            println("NOT FOUND");
        }
    }
}

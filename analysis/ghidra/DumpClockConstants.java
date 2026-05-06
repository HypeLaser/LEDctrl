// Dump the Pascal-string constants that btnIns*Click inserts, plus the
// RadioButton15 dispatcher FUN_0051274c.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.Memory;

public class DumpClockConstants extends GhidraScript {
    @Override
    public void run() throws Exception {
        Memory mem = currentProgram.getMemory();

        long[] tokenAddrs = new long[]{0x0052cd9cL, 0x0052cdd0L, 0x0052ce04L, 0x0052ce38L};
        String[] labels = new String[]{"Day", "Hour", "Min", "Sec"};

        for (int i = 0; i < tokenAddrs.length; i++) {
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(tokenAddrs[i]);
            // Delphi typed string layout for read-only constants:
            // ref-count(4) | length(4) | bytes | 00 00. Pointer in code points at the bytes.
            StringBuilder hex = new StringBuilder();
            StringBuilder ascii = new StringBuilder();
            // Read 4 bytes BEFORE for length prefix and 64 forward for content.
            for (int off = -8; off < 64; off++) {
                int b;
                try {
                    b = mem.getByte(a.add(off)) & 0xFF;
                } catch (Exception e) { break; }
                hex.append(String.format("%02x ", b));
                if (off >= 0) {
                    ascii.append((b >= 0x20 && b < 0x7F) ? (char) b : '.');
                }
            }
            println(String.format("%s @ 0x%08x", labels[i], tokenAddrs[i]));
            println("  hex (-8..+64): " + hex);
            println("  ascii (+0..+64): " + ascii);
        }

        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);

        long[] fns = new long[]{
            0x0051274cL,    // RadioButton15 dispatcher
            0x0043c8e8L,    // string-insert helper called by btnIns*
            0x0043ce24L     // probably 'get current edit-control object'
        };
        String[] fnLabels = new String[]{"FUN_0051274c_radio_dispatch", "FUN_0043c8e8_str_insert", "FUN_0043ce24_get_target"};
        for (int i = 0; i < fns.length; i++) {
            println(String.format("\n=================== %s @ 0x%08x ===================", fnLabels[i], fns[i]));
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(fns[i]);
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            if (f == null) {
                disassemble(a);
                f = createFunction(a, fnLabels[i]);
            }
            if (f == null) { println("FAILED"); continue; }
            DecompileResults res = decomp.decompileFunction(f, 90, null);
            if (res != null && res.getDecompiledFunction() != null) {
                println(res.getDecompiledFunction().getC());
            }
        }
    }
}

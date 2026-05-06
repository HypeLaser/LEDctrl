import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

public class FindMajor extends GhidraScript {
    @Override public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        // Scan all functions; decompile each and check for FUN_1000f590 calls
        Address f590 = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(0x1000f590L);
        ReferenceIterator refs = currentProgram.getReferenceManager().getReferencesTo(f590);
        java.util.Set<Function> seen = new java.util.HashSet<>();
        while (refs.hasNext()) {
            Reference r = refs.next();
            Function caller = currentProgram.getFunctionManager().getFunctionContaining(r.getFromAddress());
            if (caller != null && seen.add(caller)) {
                DecompileResults res = d.decompileFunction(caller, 30, null);
                if (res != null && res.getDecompiledFunction() != null) {
                    String c = res.getDecompiledFunction().getC();
                    int idx = c.indexOf("FUN_1000f590(");
                    while (idx >= 0) {
                        int end = c.indexOf(")", idx);
                        if (end < 0) break;
                        String args = c.substring(idx, end + 1);
                        // extract major,sub
                        int p1 = args.indexOf(',');
                        int p2 = args.indexOf(',', p1 + 1);
                        int p3 = args.indexOf(',', p2 + 1);
                        if (p1 > 0 && p2 > 0 && p3 > 0) {
                            String major = args.substring(p1 + 1, p2).trim();
                            String sub = args.substring(p2 + 1, p3).trim();
                            // normalise hex
                            int mj = parseInt(major), sb = parseInt(sub);
                            if (mj == 3 || mj == 0x7a || mj == 0x7b) {
                                println(String.format("%-40s major=0x%02x sub=0x%02x  @%s",
                                    caller.getName(), mj, sb, caller.getEntryPoint()));
                            }
                        }
                        idx = c.indexOf("FUN_1000f590(", end);
                    }
                }
            }
        }
    }
    static int parseInt(String s) {
        try {
            s = s.trim();
            if (s.startsWith("0x") || s.startsWith("0X")) return Integer.parseInt(s.substring(2), 16);
            return Integer.parseInt(s);
        } catch (Exception e) { return -1; }
    }
}

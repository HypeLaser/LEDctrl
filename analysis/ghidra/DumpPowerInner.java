import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class DumpPowerInner extends GhidraScript {
    @Override public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        long[] addrs = {0x10010d50L,0x10010dd0L};
        String[] labels = {"FUN_10010d50_powerOnOff_inner","FUN_10010dd0_getPowerState_inner"};
        for (int i = 0; i < addrs.length; i++) {
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(addrs[i]);
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            if (f == null) { disassemble(a); f = createFunction(a, labels[i]); }
            println("\n=== " + labels[i] + " @ 0x" + Long.toHexString(addrs[i]) + " ===");
            DecompileResults r = d.decompileFunction(f, 60, null);
            if (r != null && r.getDecompiledFunction() != null) println(r.getDecompiledFunction().getC());
        }
    }
}

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class DumpPowerOps extends GhidraScript {
    @Override public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        long[] addrs = {0x100100b0L,0x10010180L,0x10010250L,0x10010320L,0x10010c90L,0x10010cf0L,0x1000f3e0L};
        String[] labels = {"czResetSystem","czResetSystemCool","czPowerOnOff","czGetPowerState","FUN_10010c90","FUN_10010cf0","FUN_1000f3e0_setup"};
        for (int i = 0; i < addrs.length; i++) {
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(addrs[i]);
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            if (f == null) { disassemble(a); f = createFunction(a, labels[i]); }
            println("\n=== " + labels[i] + " @ 0x" + Long.toHexString(addrs[i]) + " ===");
            if (f != null) {
                DecompileResults r = d.decompileFunction(f, 60, null);
                if (r != null && r.getDecompiledFunction() != null) println(r.getDecompiledFunction().getC());
            }
        }
    }
}

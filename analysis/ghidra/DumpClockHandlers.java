// Resolve Delphi published-method handler addresses (4-byte LE pointer
// preceding the length-prefixed name) and decompile each.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.Memory;

public class DumpClockHandlers extends GhidraScript {
    @Override
    public void run() throws Exception {
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        Memory mem = currentProgram.getMemory();

        // {nameStringAddr (1 byte len prefix at len addr - 1), human label}
        Object[][] targets = new Object[][]{
            {0x0052bf81L, "btnInsDayClick"},
            {0x0052bf96L, "btnInsHourClick"},
            {0x0052bfacL, "btnInsMinClick"},
            {0x0052bfc1L, "btnInsSecClick"},
            {0x0051194eL, "RadioButton15Click"}
        };

        for (Object[] t : targets) {
            long nameAddr = (long) t[0];
            String label = (String) t[1];

            // Pascal short-string layout:  [len:1][name:len bytes]; pointer immediately before len byte.
            // Our nameAddr already points at the 'b'/'R' first letter, so:
            //   len byte is at nameAddr - 1
            //   function pointer 4 LE bytes is at nameAddr - 5
            Address fpAddr = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(nameAddr - 5);
            int p0 = mem.getByte(fpAddr) & 0xFF;
            int p1 = mem.getByte(fpAddr.add(1)) & 0xFF;
            int p2 = mem.getByte(fpAddr.add(2)) & 0xFF;
            int p3 = mem.getByte(fpAddr.add(3)) & 0xFF;
            long handler = ((long) p0) | ((long) p1 << 8) | ((long) p2 << 16) | ((long) p3 << 24);

            println(String.format("\n=================== %s -> handler 0x%08x ===================", label, handler));
            Address h = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(handler);
            Function f = currentProgram.getFunctionManager().getFunctionAt(h);
            if (f == null) {
                disassemble(h);
                f = createFunction(h, label);
            }
            if (f == null) {
                println("FAILED to materialise function at 0x" + Long.toHexString(handler));
                continue;
            }
            DecompileResults res = decomp.decompileFunction(f, 90, null);
            if (res != null && res.getDecompiledFunction() != null) {
                println(res.getDecompiledFunction().getC());
            }
        }
    }
}

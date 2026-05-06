import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;

public class DumpTokenScan extends GhidraScript {
    @Override public void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        long base = 0x0052c000L;
        long end = 0x0052e000L;
        for (long off = base; off < end; off++) {
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(off);
            try {
                int b0 = mem.getByte(a) & 0xFF;
                int b1 = mem.getByte(a.add(1)) & 0xFF;
                int b2 = mem.getByte(a.add(2)) & 0xFF;
                if (b0 == 0x25 && b1 >= 0x20 && b1 < 0x7F && b2 == 0) {
                    println(String.format("0x%08x  %%%c", off, (char) b1));
                } else if (b0 == 0x25 && b1 >= 0x20 && b1 < 0x7F && b2 >= 0x20 && b2 < 0x7F) {
                    int b3 = mem.getByte(a.add(3)) & 0xFF;
                    if (b3 == 0) {
                        println(String.format("0x%08x  %%%c%c", off, (char) b1, (char) b2));
                    }
                }
            } catch (Exception ignored) { break; }
        }
    }
}

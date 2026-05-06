// Decompile FUN_0052541c — the per-entry record builder.
// Also decompile its callees and surrounding entry-class functions.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressFactory;
import ghidra.program.model.address.AddressSpace;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.Memory;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.io.FileWriter;
import java.util.*;

public class DumpProtocolA extends GhidraScript {
    static final String OUT = "/Users/alexscott/Projects/LEDctrl/analysis/ghidra/decompA.txt";

    @Override
    protected void run() throws Exception {
        AddressFactory af = currentProgram.getAddressFactory();
        AddressSpace sp = af.getDefaultAddressSpace();
        Memory mem = currentProgram.getMemory();
        PrintWriter fh = new PrintWriter(new FileWriter(OUT));

        long[] targets = {
            0x0052541cL, // entry-record builder — slot1 is here
            0x00525000L, 0x00525200L, 0x00525400L, 0x00525500L, 0x00525600L, 0x00525700L, // surrounding probes
            0x0052541cL,
            0x004027a4L, 0x00402784L,  // alloc/free helpers
            0x0041b014L,                // TList.Add
            0x00525000L
        };

        Set<Function> toDecomp = new TreeSet<>(Comparator.comparing(g -> g.getEntryPoint().getOffset()));
        Set<Long> seen = new HashSet<>();

        for (long t : targets) {
            if (!seen.add(t)) continue;
            Address a = sp.getAddress(t);
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            if (f == null) f = currentProgram.getFunctionManager().getFunctionContaining(a);
            if (f == null) {
                try {
                    disassemble(a);
                    f = createFunction(a, "F_" + Long.toHexString(t));
                    if (f != null) fh.println(";;; Created " + f.getName() + "@" + f.getEntryPoint());
                } catch (Exception ex) {
                    fh.println(";;; failed " + a + " : " + ex.getMessage());
                }
            }
            if (f != null) toDecomp.add(f);
        }

        // Hex dump of the entry-record builder region
        fh.println();
        fh.println("=== Hex 0x525400..0x525700 ===");
        for (long off = 0x525400L; off < 0x525700L; off += 16) {
            StringBuilder sb = new StringBuilder(String.format("%08x:", off));
            StringBuilder ascii = new StringBuilder();
            for (int i = 0; i < 16; i++) {
                try {
                    byte b = mem.getByte(sp.getAddress(off + i));
                    sb.append(String.format(" %02x", b & 0xff));
                    ascii.append((b >= 0x20 && b < 0x7f) ? (char)(b & 0xff) : '.');
                } catch (Exception ex) { sb.append(" ??"); ascii.append('?'); }
            }
            fh.println(sb + "  |" + ascii + "|");
        }

        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);
        ConsoleTaskMonitor mon = new ConsoleTaskMonitor();

        fh.println();
        fh.println("=== Decompiled (" + toDecomp.size() + " funcs) ===");
        for (Function g : toDecomp) {
            fh.println();
            fh.println(";;; ============================================");
            fh.println(";;; " + g.getEntryPoint() + "  " + g.getName());
            fh.println(";;; ============================================");
            try {
                DecompileResults r = di.decompileFunction(g, 90, mon);
                if (r != null && r.getDecompiledFunction() != null) {
                    fh.print(r.getDecompiledFunction().getC());
                } else fh.println("// decompile failed");
            } catch (Exception ex) { fh.println("// exception: " + ex); }
        }
        fh.close();
        println("DONE -> " + OUT);
    }
}

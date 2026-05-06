// Force-disassemble + decompile the entry-adder funcs.
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

public class DumpProtocol9 extends GhidraScript {
    static final String OUT = "/Users/alexscott/Projects/LEDctrl/analysis/ghidra/decomp9.txt";

    @Override
    protected void run() throws Exception {
        AddressFactory af = currentProgram.getAddressFactory();
        AddressSpace sp = af.getDefaultAddressSpace();
        Memory mem = currentProgram.getMemory();
        PrintWriter fh = new PrintWriter(new FileWriter(OUT));

        long[] targets = {
            0x0052467cL, // entry adder #1 (temp.Nmg) — KEY for slot1
            0x00524774L, // entry adder #2 (SequentList.tmps)
            0x00524510L, // SQ ctor (re-decompile for cross-reference)
            0x00524570L, // explore neighborhood
            0x00524600L,
            0x005246a0L,
            0x00524800L,
            0x00553cdcL,
            0x00554068L,
            0x00545d40L  // wire builder candidate
        };

        Set<Function> toDecomp = new TreeSet<>(Comparator.comparing(g -> g.getEntryPoint().getOffset()));

        for (long t : targets) {
            Address a = sp.getAddress(t);
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            if (f == null) f = currentProgram.getFunctionManager().getFunctionContaining(a);
            if (f == null) {
                // Force disassemble and create
                try {
                    disassemble(a);
                    f = createFunction(a, "F_" + Long.toHexString(t));
                    if (f != null) fh.println(";;; Created " + f.getName() + "@" + f.getEntryPoint());
                    else fh.println(";;; createFunction failed at " + a);
                } catch (Exception ex) {
                    fh.println(";;; disassemble failed at " + a + " : " + ex.getMessage());
                }
            }
            if (f != null) toDecomp.add(f);
        }

        // Hex dump 0x52440c..0x524880 (SQ class region)
        fh.println();
        fh.println("=== Hex 0x52440c..0x524880 ===");
        for (long off = 0x52440cL; off < 0x524880L; off += 16) {
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

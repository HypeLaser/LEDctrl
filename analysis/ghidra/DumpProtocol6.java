// Decompile function containing 0x545f4b (temp.Nmg loader). Find SQ ctor VMT entry.
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

public class DumpProtocol6 extends GhidraScript {
    static final String OUT = "/Users/alexscott/Projects/LEDctrl/analysis/ghidra/decomp6.txt";

    @Override
    protected void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        AddressFactory af = currentProgram.getAddressFactory();
        AddressSpace sp = af.getDefaultAddressSpace();
        PrintWriter fh = new PrintWriter(new FileWriter(OUT));

        Address a = sp.getAddress(0x00545f4bL);
        Function f = currentProgram.getFunctionManager().getFunctionContaining(a);
        if (f != null) {
            fh.println(";;; Function containing 0x545f4b: " + f.getName() + "@" + f.getEntryPoint());
        } else {
            // Walk back to find function start.
            Address cur = a;
            for (int i = 0; i < 0x1000; i++) {
                cur = cur.subtract(1);
                Function ff = currentProgram.getFunctionManager().getFunctionAt(cur);
                if (ff != null) { f = ff; break; }
            }
            fh.println(";;; Backtracked function: " + (f == null ? "null" : f.getName() + "@" + f.getEntryPoint()));
        }

        // Search all bytes for LE pointer to 0x00524510 (SQ ctor).
        byte[] sqPtr = {(byte)0x10,(byte)0x45,(byte)0x52,(byte)0x00};
        fh.println();
        fh.println("=== Bytes pointing to FUN_00524510 ===");
        Address cur = mem.getMinAddress();
        Address end = mem.getMaxAddress();
        int n = 0;
        Set<Function> toDecomp = new TreeSet<>(Comparator.comparing(g -> g.getEntryPoint().getOffset()));
        if (f != null) toDecomp.add(f);
        while (cur != null && cur.compareTo(end) <= 0 && n < 100) {
            Address found = mem.findBytes(cur, end, sqPtr, null, true, monitor);
            if (found == null) break;
            Function fc = currentProgram.getFunctionManager().getFunctionContaining(found);
            String fn = (fc == null) ? "" : "  in " + fc.getName() + "@" + fc.getEntryPoint();
            fh.println("  " + found + fn);
            if (fc != null) toDecomp.add(fc);
            cur = found.add(1);
            n++;
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
            } catch (Exception ex) {
                fh.println("// exception: " + ex);
            }
        }
        fh.close();
        println("DONE -> " + OUT);
    }
}

// Trace SQ ctor callers + temp.Nmg wire literal xrefs + DT magic bytes.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressFactory;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.symbol.ReferenceManager;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.io.FileWriter;
import java.util.*;

public class DumpProtocol3 extends GhidraScript {

    static final String OUT = "/Users/alexscott/Projects/LEDctrl/analysis/ghidra/decomp3.txt";

    @Override
    protected void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        AddressFactory af = currentProgram.getAddressFactory();
        ReferenceManager rm = currentProgram.getReferenceManager();

        PrintWriter fh = new PrintWriter(new FileWriter(OUT));

        // Targets to chase xrefs from.
        long[] targets = {
            0x00524510L, // SQ ctor
            0x00546238L, // raw temp.Nmg
            0x0054624cL, // SequentList.tmps
            0x004c2e40L, // file-index lookup (uJetFileICMD)
            0x004cc624L  // file-index lookup (uJetFileIICMD)
        };

        Set<Function> toDecomp = new TreeSet<>(Comparator.comparing(f -> f.getEntryPoint().getOffset()));

        fh.println("=== Xrefs to key targets ===");
        for (long t : targets) {
            Address a = af.getDefaultAddressSpace().getAddress(t);
            fh.printf("-> 0x%x%n", t);
            ReferenceIterator it = rm.getReferencesTo(a);
            while (it.hasNext()) {
                Reference r = it.next();
                Address from = r.getFromAddress();
                Function f = currentProgram.getFunctionManager().getFunctionContaining(from);
                String fn = (f == null) ? "?" : f.getName() + "@" + f.getEntryPoint();
                fh.printf("   %s  in %s  (%s)%n", from, fn, r.getReferenceType());
                if (f != null) toDecomp.add(f);
            }
        }

        // Search bytes 44 54 0f 7f (DT header LE).
        byte[] dtHeader = {(byte)0x44,(byte)0x54,(byte)0x0f,(byte)0x7f};
        fh.println();
        fh.println("=== Bytes 44 54 0f 7f (DT header) ===");
        Address cur = mem.getMinAddress();
        Address end = mem.getMaxAddress();
        int n = 0;
        while (cur != null && cur.compareTo(end) <= 0 && n < 50) {
            Address found = mem.findBytes(cur, end, dtHeader, null, true, monitor);
            if (found == null) break;
            Function f = currentProgram.getFunctionManager().getFunctionContaining(found);
            String fn = (f == null) ? "" : "  in " + f.getName() + "@" + f.getEntryPoint();
            fh.println("  " + found + fn);
            if (f != null) toDecomp.add(f);
            cur = found.next();
            n++;
        }

        // Search bytes 53 51 04 00 (full SQ header preamble).
        byte[] sqHdr = {(byte)0x53,(byte)0x51,(byte)0x04,(byte)0x00};
        fh.println();
        fh.println("=== Bytes 53 51 04 00 (SQ header preamble) ===");
        cur = mem.getMinAddress(); n = 0;
        while (cur != null && cur.compareTo(end) <= 0 && n < 50) {
            Address found = mem.findBytes(cur, end, sqHdr, null, true, monitor);
            if (found == null) break;
            Function f = currentProgram.getFunctionManager().getFunctionContaining(found);
            String fn = (f == null) ? "" : "  in " + f.getName() + "@" + f.getEntryPoint();
            fh.println("  " + found + fn);
            if (f != null) toDecomp.add(f);
            cur = found.next();
            n++;
        }

        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);
        ConsoleTaskMonitor mon = new ConsoleTaskMonitor();

        fh.println();
        fh.println("=== Decompiled (" + toDecomp.size() + " funcs) ===");
        for (Function f : toDecomp) {
            fh.println();
            fh.println(";;; ============================================");
            fh.println(";;; " + f.getEntryPoint() + "  " + f.getName());
            fh.println(";;; ============================================");
            try {
                DecompileResults r = di.decompileFunction(f, 60, mon);
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

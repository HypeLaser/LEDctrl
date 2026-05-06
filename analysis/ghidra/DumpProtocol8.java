// Decompile the wire SQ builder + entry-adder funcs.
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

public class DumpProtocol8 extends GhidraScript {
    static final String OUT = "/Users/alexscott/Projects/LEDctrl/analysis/ghidra/decomp8.txt";

    @Override
    protected void run() throws Exception {
        AddressFactory af = currentProgram.getAddressFactory();
        AddressSpace sp = af.getDefaultAddressSpace();
        PrintWriter fh = new PrintWriter(new FileWriter(OUT));

        long[] targets = {
            0x00524510L, // SQ ctor
            0x0052467cL, // entry adder #1 (temp.Nmg)
            0x00524774L, // entry adder #2 (SequentList.tmps)
            0x00553cdcL, // called when wrap branch (0x545fd3 / 0x546010)
            0x00554068L, // called in pre-wrap path
            0x00545b78L, // called pre-tmps adder
            0x00404bccL  // string-concat helper (verify)
        };

        // Force-create function at 0x545dXX entry (real wire builder).
        // The disassembly shows 0x545e00 is INSIDE a function — find its start.
        // Look at "PUSH EBP / MOV EBP,ESP" backward from 0x545dxx. From hex,
        // 0x545df0..0x545e00 region needs scanning — ask Ghidra for the function.
        Address probe = sp.getAddress(0x00545f4bL);
        Function wireBuilder = currentProgram.getFunctionManager().getFunctionContaining(probe);
        if (wireBuilder == null) {
            // Walk backward looking for any defined function start
            Address cur = probe;
            for (int i = 0; i < 0x2000; i++) {
                cur = cur.subtract(1);
                Function ff = currentProgram.getFunctionManager().getFunctionAt(cur);
                if (ff != null && ff.getBody() != null && ff.getBody().contains(probe)) {
                    wireBuilder = ff;
                    break;
                }
            }
        }
        if (wireBuilder == null) {
            // Try creating a function at 0x00545dXX — let's try common entry: 0x00545d8c had ref earlier
            // Actually search for typical Delphi proc prologue near probe.
            // Bytes for "PUSH EBP" = 0x55. We try 0x545d00..0x545fa0 looking for 55 8B EC.
            Memory mem = currentProgram.getMemory();
            for (long o = 0x00545fa0L; o > 0x00545b00L; o--) {
                try {
                    if ((mem.getByte(sp.getAddress(o))   & 0xff) == 0x55 &&
                        (mem.getByte(sp.getAddress(o+1)) & 0xff) == 0x8b &&
                        (mem.getByte(sp.getAddress(o+2)) & 0xff) == 0xec) {
                        // Try to create function here
                        Address candidate = sp.getAddress(o);
                        try {
                            disassemble(candidate);
                            wireBuilder = createFunction(candidate, "wire_builder_" + Long.toHexString(o));
                            if (wireBuilder != null && wireBuilder.getBody().contains(probe)) {
                                fh.println(";;; Created function at " + candidate);
                                break;
                            } else if (wireBuilder != null) {
                                wireBuilder = null; // try further back
                            }
                        } catch (Exception ex) { /* try next */ }
                    }
                } catch (Exception ex) { break; }
            }
        }

        Set<Function> toDecomp = new TreeSet<>(Comparator.comparing(g -> g.getEntryPoint().getOffset()));
        if (wireBuilder != null) {
            fh.println(";;; Wire builder: " + wireBuilder.getName() + "@" + wireBuilder.getEntryPoint());
            toDecomp.add(wireBuilder);
        } else {
            fh.println(";;; Wire builder NOT located");
        }

        for (long t : targets) {
            Address a = sp.getAddress(t);
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            if (f == null) f = currentProgram.getFunctionManager().getFunctionContaining(a);
            if (f != null) toDecomp.add(f);
            else fh.println(";;; Missing function at " + a);
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

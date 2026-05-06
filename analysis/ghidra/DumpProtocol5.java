// Search bytes for LE address references to key strings + disassemble around them.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressFactory;
import ghidra.program.model.address.AddressSpace;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.mem.Memory;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.io.FileWriter;
import java.util.*;

public class DumpProtocol5 extends GhidraScript {
    static final String OUT = "/Users/alexscott/Projects/LEDctrl/analysis/ghidra/decomp5.txt";

    @Override
    protected void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        AddressFactory af = currentProgram.getAddressFactory();
        AddressSpace sp = af.getDefaultAddressSpace();

        long[] targets = {
            0x00524510L, 0x00546238L, 0x0054624cL, 0x00546268L
        };
        String[] labels = { "FUN_00524510 (SQ ctor)", "temp.Nmg", "SequentList.tmps", "Sigma" };

        PrintWriter fh = new PrintWriter(new FileWriter(OUT));

        Set<Function> toDecomp = new TreeSet<>(Comparator.comparing(f -> f.getEntryPoint().getOffset()));

        for (int i = 0; i < targets.length; i++) {
            long t = targets[i];
            byte[] pat = new byte[] {
                (byte)(t & 0xff),
                (byte)((t >> 8) & 0xff),
                (byte)((t >> 16) & 0xff),
                (byte)((t >> 24) & 0xff)
            };
            fh.printf("=== %s : raw bytes %02x %02x %02x %02x ===%n",
                labels[i], pat[0]&0xff, pat[1]&0xff, pat[2]&0xff, pat[3]&0xff);

            Address cur = mem.getMinAddress();
            Address end = mem.getMaxAddress();
            int n = 0;
            while (cur != null && cur.compareTo(end) <= 0 && n < 100) {
                Address found = mem.findBytes(cur, end, pat, null, true, monitor);
                if (found == null) break;
                Function f = currentProgram.getFunctionManager().getFunctionContaining(found);
                Instruction ins = currentProgram.getListing().getInstructionContaining(found);
                String fn = (f == null) ? "" : "  in " + f.getName() + "@" + f.getEntryPoint();
                String mnem = (ins == null) ? "(data)" : ins.toString();
                fh.printf("  %s  [%s]%s%n", found, mnem, fn);
                if (f != null) toDecomp.add(f);
                cur = found.add(1);
                n++;
            }
            fh.println();
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

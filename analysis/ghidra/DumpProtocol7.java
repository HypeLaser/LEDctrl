// Disassemble bytes around 0x545f4b, find/create true containing function, decompile.
// Also dump raw bytes 0x545e00..0x546100 for visual scan.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressFactory;
import ghidra.program.model.address.AddressSpace;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.mem.Memory;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.io.FileWriter;
import java.util.*;

public class DumpProtocol7 extends GhidraScript {
    static final String OUT = "/Users/alexscott/Projects/LEDctrl/analysis/ghidra/decomp7.txt";

    @Override
    protected void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        AddressFactory af = currentProgram.getAddressFactory();
        AddressSpace sp = af.getDefaultAddressSpace();
        Listing listing = currentProgram.getListing();
        PrintWriter fh = new PrintWriter(new FileWriter(OUT));

        // 1. Hex dump 0x545e00..0x546100 (region containing the pointer-table)
        fh.println("=== Hex 0x545e00..0x546100 ===");
        for (long off = 0x545e00L; off < 0x546100L; off += 16) {
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

        // 2. Walk through listing functions to find which one contains 0x545f4b
        fh.println();
        fh.println("=== Functions whose body covers 0x545f4b ===");
        long target = 0x545f4bL;
        Function containing = null;
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            if (f.getBody() != null && f.getBody().contains(sp.getAddress(target))) {
                fh.println("  " + f.getName() + "@" + f.getEntryPoint() + " body=" + f.getBody());
                containing = f;
            }
        }
        if (containing == null) fh.println("  NONE — 0x545f4b is not inside any defined function");

        // 3. Disassemble linearly from 0x545e00..0x546100 (whatever exists)
        fh.println();
        fh.println("=== Linear disassembly 0x545e00..0x546100 ===");
        Address cur = sp.getAddress(0x545e00L);
        Address end = sp.getAddress(0x546100L);
        ConsoleTaskMonitor mon = new ConsoleTaskMonitor();
        while (cur != null && cur.compareTo(end) < 0) {
            Instruction ins = listing.getInstructionAt(cur);
            if (ins == null) {
                // Try to disassemble at this address
                try { disassemble(cur); } catch (Exception ignored) {}
                ins = listing.getInstructionAt(cur);
            }
            if (ins != null) {
                fh.printf("%s  %s%n", cur, ins.toString());
                cur = ins.getMaxAddress().add(1);
            } else {
                fh.printf("%s  (no instr)%n", cur);
                cur = cur.add(1);
            }
        }

        // 4. If function found, decompile
        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);
        Set<Function> toDecomp = new TreeSet<>(Comparator.comparing(g -> g.getEntryPoint().getOffset()));
        if (containing != null) toDecomp.add(containing);

        // 5. Also: search wider for ANY 4-byte ref to FUN_00524510 — broader sections
        byte[] sqPtr = {(byte)0x10,(byte)0x45,(byte)0x52,(byte)0x00};
        fh.println();
        fh.println("=== Wide search for 4-byte LE 0x00524510 ===");
        // Iterate over all blocks
        for (var block : mem.getBlocks()) {
            Address bs = block.getStart();
            Address be = block.getEnd();
            Address c = bs;
            int n = 0;
            while (c != null && c.compareTo(be) <= 0 && n < 200) {
                Address found = mem.findBytes(c, be, sqPtr, null, true, mon);
                if (found == null) break;
                fh.printf("  block %s : %s%n", block.getName(), found);
                Function fc = currentProgram.getFunctionManager().getFunctionContaining(found);
                if (fc != null) toDecomp.add(fc);
                c = found.add(1);
                n++;
            }
        }

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

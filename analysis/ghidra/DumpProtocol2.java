// Hunt SQ/SEQUENT builder via byte patterns + immediates.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.symbol.ReferenceManager;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.io.FileWriter;
import java.util.*;

public class DumpProtocol2 extends GhidraScript {

    static final String OUT = "/Users/alexscott/Projects/LEDctrl/analysis/ghidra/decomp2.txt";

    // Byte patterns to scan (raw bytes in memory image).
    static final byte[] PAT_TEMP_NMG = {
        (byte)0x74, (byte)0x65, (byte)0x6d, (byte)0x70,
        (byte)0x2e, (byte)0x4e, (byte)0x6d, (byte)0x67
    };
    static final byte[] PAT_NMG_MAGIC = {
        (byte)0x01, (byte)0x5a, (byte)0x30, (byte)0x30
    };
    static final byte[] PAT_SEQUENT_LIST = "SequentList.tmps".getBytes();

    // 32-bit immediates we expect in slot/sequence builder code.
    // 0x30305a01 = "01Z00" little-endian (NMG header LE).
    // 0x00045344 = ?  ; 0x4453 'SD'; 0x5153 'SQ' little-endian = 0x5153.
    static final int[] IMMEDS = {
        0x30305a01, // NMG header LE
        0x5153,     // 'SQ'
        0x5444,     // 'DT'
        0x7f0f,     // 'DT' field flags? from notes 0x44 0x54 0x0f 0x7f -> 0x7f0f5444 LE
        0x7f0f5444, // full DT header LE
        0x0f7f,     // 'DT' suffix
    };

    @Override
    protected void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        Listing listing = currentProgram.getListing();

        PrintWriter fh = new PrintWriter(new FileWriter(OUT));

        fh.println("=== Byte pattern search ===");
        scanPattern(fh, mem, "temp.Nmg ASCII", PAT_TEMP_NMG);
        scanPattern(fh, mem, "NMG magic 01 5a 30 30", PAT_NMG_MAGIC);
        scanPattern(fh, mem, "SequentList.tmps", PAT_SEQUENT_LIST);

        fh.println();
        fh.println("=== Immediate operand search ===");
        Map<Integer, List<Address>> immHits = new LinkedHashMap<>();
        for (int v : IMMEDS) immHits.put(v, new ArrayList<>());

        InstructionIterator it = listing.getInstructions(true);
        while (it.hasNext()) {
            Instruction ins = it.next();
            int n = ins.getNumOperands();
            for (int i = 0; i < n; i++) {
                Object[] objs = ins.getOpObjects(i);
                for (Object o : objs) {
                    if (o instanceof Scalar) {
                        long v = ((Scalar)o).getUnsignedValue();
                        for (int target : IMMEDS) {
                            if (v == (target & 0xffffffffL)) {
                                immHits.get(target).add(ins.getAddress());
                            }
                        }
                    }
                }
            }
        }

        for (Map.Entry<Integer, List<Address>> e : immHits.entrySet()) {
            fh.printf("imm 0x%x : %d hits%n", e.getKey(), e.getValue().size());
            for (Address a : e.getValue()) {
                Function f = currentProgram.getFunctionManager().getFunctionContaining(a);
                String fn = (f == null) ? "?" : f.getName() + "@" + f.getEntryPoint();
                fh.printf("  %s  in %s%n", a, fn);
            }
        }

        // Decompile functions that contain immediates of interest.
        Set<Function> targets = new TreeSet<>(Comparator.comparing(f -> f.getEntryPoint().getOffset()));
        for (List<Address> addrs : immHits.values()) {
            for (Address a : addrs) {
                Function f = currentProgram.getFunctionManager().getFunctionContaining(a);
                if (f != null) targets.add(f);
            }
        }

        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);
        ConsoleTaskMonitor mon = new ConsoleTaskMonitor();

        fh.println();
        fh.println("=== Decompiled candidates ===");
        for (Function f : targets) {
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

    private void scanPattern(PrintWriter fh, Memory mem, String label, byte[] pat) {
        fh.println("-- " + label + " (" + bytesHex(pat) + ")");
        Address start = mem.getMinAddress();
        Address end = mem.getMaxAddress();
        Address cur = start;
        int count = 0;
        while (cur != null && cur.compareTo(end) <= 0 && count < 200) {
            try {
                Address found = mem.findBytes(cur, end, pat, null, true, monitor);
                if (found == null) break;
                Function f = currentProgram.getFunctionManager().getFunctionContaining(found);
                String fn = (f == null) ? "" : "  in " + f.getName() + "@" + f.getEntryPoint();
                fh.println("  " + found + fn);
                cur = found.next();
                count++;
            } catch (Exception ex) { break; }
        }
    }

    private String bytesHex(byte[] b) {
        StringBuilder s = new StringBuilder();
        for (byte x : b) s.append(String.format("%02x ", x & 0xff));
        return s.toString().trim();
    }
}

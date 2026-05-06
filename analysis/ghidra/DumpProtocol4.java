// Find SEQUENT.SYS / temp.Nmg WRITE path. Inspect Delphi string descriptors near key data.
// Look for callers of FUN_00524510 (SQ ctor) by scanning instruction operands.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressFactory;
import ghidra.program.model.address.AddressSpace;
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

public class DumpProtocol4 extends GhidraScript {
    static final String OUT = "/Users/alexscott/Projects/LEDctrl/analysis/ghidra/decomp4.txt";

    @Override
    protected void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        AddressFactory af = currentProgram.getAddressFactory();
        AddressSpace defSpc = af.getDefaultAddressSpace();
        ReferenceManager rm = currentProgram.getReferenceManager();
        Listing listing = currentProgram.getListing();

        PrintWriter fh = new PrintWriter(new FileWriter(OUT));

        // Scan ALL instruction immediates for these target addresses.
        long[] targetAddrs = {
            0x00524510L, // SQ ctor
            0x00546238L, // raw temp.Nmg ASCII
            0x00546234L, // Delphi descriptor likely 4 bytes before
            0x0054624cL, // SequentList.tmps
            0x00546248L  // Delphi descriptor
        };

        Set<Long> targetSet = new HashSet<>();
        for (long t : targetAddrs) targetSet.add(t);

        Map<Long, List<Address>> imm = new LinkedHashMap<>();
        for (long t : targetAddrs) imm.put(t, new ArrayList<>());

        InstructionIterator it = listing.getInstructions(true);
        int total = 0;
        while (it.hasNext()) {
            Instruction ins = it.next();
            int n = ins.getNumOperands();
            for (int i = 0; i < n; i++) {
                Object[] objs = ins.getOpObjects(i);
                for (Object o : objs) {
                    if (o instanceof Scalar) {
                        long v = ((Scalar)o).getUnsignedValue();
                        if (targetSet.contains(v)) {
                            imm.get(v).add(ins.getAddress());
                            total++;
                        }
                    }
                }
            }
        }

        fh.println("=== Immediate operand hits for target addresses ===");
        fh.println("Total: " + total);
        Set<Function> toDecomp = new TreeSet<>(Comparator.comparing(f -> f.getEntryPoint().getOffset()));
        for (Map.Entry<Long, List<Address>> e : imm.entrySet()) {
            fh.printf("addr 0x%x : %d hits%n", e.getKey(), e.getValue().size());
            for (Address a : e.getValue()) {
                Function f = currentProgram.getFunctionManager().getFunctionContaining(a);
                String fn = (f == null) ? "?" : f.getName() + "@" + f.getEntryPoint();
                fh.printf("  %s  in %s%n", a, fn);
                if (f != null) toDecomp.add(f);
            }
        }

        // Inspect 64 bytes around 0x546234 to confirm Delphi string layout.
        fh.println();
        fh.println("=== Bytes 0x546228..0x546278 ===");
        for (long off = 0x546228L; off < 0x546278L; off += 16) {
            StringBuilder sb = new StringBuilder(String.format("%08x:", off));
            for (int i = 0; i < 16; i++) {
                try {
                    byte b = mem.getByte(defSpc.getAddress(off + i));
                    sb.append(String.format(" %02x", b & 0xff));
                } catch (Exception ex) { sb.append(" ??"); }
            }
            sb.append("  |");
            for (int i = 0; i < 16; i++) {
                try {
                    byte b = mem.getByte(defSpc.getAddress(off + i));
                    char c = (b >= 0x20 && b < 0x7f) ? (char)b : '.';
                    sb.append(c);
                } catch (Exception ex) { sb.append('?'); }
            }
            sb.append('|');
            fh.println(sb);
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

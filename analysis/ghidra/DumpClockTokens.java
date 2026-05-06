// Decompile editor functions that emit clock/countdown/countup tokens.
// Strategy: locate format-string + button-name strings, decompile every function
// that references them.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressIterator;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.listing.Program;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.mem.Memory;

import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.Set;

public class DumpClockTokens extends GhidraScript {

    @Override
    public void run() throws Exception {
        Program program = currentProgram;
        Listing listing = program.getListing();
        Memory memory = program.getMemory();

        String[] needles = new String[]{
            "%d Day %h Hour %m Minute %s Second",
            "HH:MM AM/PM",
            "HH:MM(TimeZone)",
            "btnInsDay",
            "btnInsHour",
            "btnInsMin",
            "btnInsSec",
            "RadioButton15Click",
            "frmSpecial_D_T_T",
            "radCountDown",
            "labCountDown",
            "Count Down",
            "Count Up",
            "Insert special Time,date etc"
        };

        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(program);

        Set<Address> stringHits = new LinkedHashSet<>();

        // Scan all initialised memory for ASCII needles.
        for (MemoryBlock block : memory.getBlocks()) {
            if (!block.isInitialized()) continue;
            byte[] bytes = new byte[(int) Math.min(block.getSize(), Integer.MAX_VALUE)];
            try { memory.getBytes(block.getStart(), bytes); } catch (Exception e) { continue; }

            for (String needle : needles) {
                byte[] needleBytes = needle.getBytes("ASCII");
                int idx = 0;
                while ((idx = indexOf(bytes, needleBytes, idx)) >= 0) {
                    Address hit = block.getStart().add(idx);
                    stringHits.add(hit);
                    idx += 1;
                }
            }
        }

        println("=== string hits ===");
        for (Address a : stringHits) {
            String preview = readAscii(memory, a, 60);
            println(String.format("0x%s : %s", a, preview));
        }

        Set<Function> functions = new LinkedHashSet<>();
        for (Address strAddr : stringHits) {
            ReferenceIterator refs = program.getReferenceManager().getReferencesTo(strAddr);
            while (refs.hasNext()) {
                Reference ref = refs.next();
                Address from = ref.getFromAddress();
                Function f = program.getFunctionManager().getFunctionContaining(from);
                if (f != null) functions.add(f);
            }
        }

        println("\n=== unique referencing functions: " + functions.size() + " ===");
        for (Function f : functions) {
            println(String.format("\n--- %s @ 0x%s ---", f.getName(), f.getEntryPoint()));
            DecompileResults res = decomp.decompileFunction(f, 90, null);
            if (res != null && res.getDecompiledFunction() != null) {
                println(res.getDecompiledFunction().getC());
            } else {
                println("(decomp failed)");
            }
        }
    }

    private static int indexOf(byte[] haystack, byte[] needle, int from) {
        outer:
        for (int i = from; i + needle.length <= haystack.length; i++) {
            for (int j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) continue outer;
            }
            return i;
        }
        return -1;
    }

    private static String readAscii(Memory mem, Address start, int maxLen) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < maxLen; i++) {
            try {
                byte b = mem.getByte(start.add(i));
                if (b == 0) break;
                if (b >= 0x20 && b < 0x7F) sb.append((char) (b & 0xFF));
                else sb.append(String.format("\\x%02x", b & 0xFF));
            } catch (Exception e) { break; }
        }
        return sb.toString();
    }
}

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;

public class DumpTimeOps extends GhidraScript {
    @Override public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        SymbolIterator it = currentProgram.getSymbolTable().getAllSymbols(true);
        java.util.List<Long> wanted = new java.util.ArrayList<>();
        java.util.List<String> names = new java.util.ArrayList<>();
        while (it.hasNext()) {
            Symbol s = it.next();
            String n = s.getName();
            if (n.startsWith("cz") && (n.contains("Time") || n.contains("ate") || n.contains("Clock") || n.contains("RTC"))) {
                Function f = currentProgram.getFunctionManager().getFunctionAt(s.getAddress());
                if (f != null && !names.contains(n)) {
                    println(n + " @ " + s.getAddress());
                    wanted.add(s.getAddress().getOffset());
                    names.add(n);
                }
            }
        }
        for (int i = 0; i < wanted.size(); i++) {
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(wanted.get(i));
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            println("\n=== " + names.get(i) + " @ 0x" + Long.toHexString(wanted.get(i)) + " ===");
            DecompileResults r = d.decompileFunction(f, 60, null);
            if (r != null && r.getDecompiledFunction() != null) println(r.getDecompiledFunction().getC());
        }
    }
}

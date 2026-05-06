import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;

public class FindMore extends GhidraScript {
    @Override public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        SymbolIterator it = currentProgram.getSymbolTable().getAllSymbols(true);
        while (it.hasNext()) {
            Symbol s = it.next();
            String n = s.getName();
            if (n.startsWith("cz") || n.startsWith("_cz")) {
                if (n.contains("leep") || n.contains("link") || n.contains("ut") || n.contains("lank") || n.contains("isplay") || n.contains("ile") || n.contains("equence") || n.contains("Play") || n.contains("Stop") || n.contains("Start") || n.contains("Run")) {
                    Function f = currentProgram.getFunctionManager().getFunctionAt(s.getAddress());
                    println(n + " @ " + s.getAddress() + (f != null ? " [func]" : ""));
                }
            }
        }
        // Decompile czSleep + czBlankLED related
        long[] addrs = {};
        // Search by name
        String[] wanted = {"_czSleep@4","czPowerOnOff","czGetCurrentDisplay","czReadCurrentDisplayInfo","czGetSysSta","czGetSystemStatus"};
        for (String w : wanted) {
            SymbolIterator syms = currentProgram.getSymbolTable().getSymbols(w);
            while (syms.hasNext()) {
                Symbol s = syms.next();
                Function f = currentProgram.getFunctionManager().getFunctionAt(s.getAddress());
                if (f != null) {
                    println("\n=== " + w + " @ " + s.getAddress() + " ===");
                    DecompileResults r = d.decompileFunction(f, 60, null);
                    if (r != null && r.getDecompiledFunction() != null) println(r.getDecompiledFunction().getC());
                }
            }
        }
    }
}

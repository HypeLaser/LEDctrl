import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;

public class FindResetOps extends GhidraScript {
    @Override public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        String[] names = {"czResetSystem","czResetSystemCool","czWriteShutDownInfo","czReadShutDownInfo","czSwitchShutDown","czSetShutDown","czGetShutDown"};
        SymbolIterator it = currentProgram.getSymbolTable().getAllSymbols(true);
        while (it.hasNext()) {
            Symbol s = it.next();
            String n = s.getName();
            for (String want : names) {
                if (n.contains(want.replace("@0",""))) {
                    println("SYM " + n + " @ " + s.getAddress());
                    Function f = currentProgram.getFunctionManager().getFunctionAt(s.getAddress());
                    if (f != null) {
                        DecompileResults r = d.decompileFunction(f, 60, null);
                        if (r != null && r.getDecompiledFunction() != null) {
                            println(r.getDecompiledFunction().getC());
                        }
                    }
                }
            }
        }
        // Also scan all symbols starting with cz that have "Shut" or "Reset" or "Power"
        it = currentProgram.getSymbolTable().getAllSymbols(true);
        while (it.hasNext()) {
            Symbol s = it.next();
            String n = s.getName();
            if (n.startsWith("cz") && (n.contains("hut") || n.contains("eset") || n.contains("ower") || n.contains("tand") || n.contains("ake") || n.contains("isplay"))) {
                println("CZ " + n + " @ " + s.getAddress());
            }
        }
    }
}

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;

public class DumpTestOps extends GhidraScript {
    @Override public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        SymbolIterator it = currentProgram.getSymbolTable().getAllSymbols(true);
        while (it.hasNext()) {
            Symbol s = it.next();
            String n = s.getName();
            if (n.startsWith("cz") && (n.contains("Test") || n.contains("Disp") || n.contains("Color") || n.contains("Fill") || n.contains("Pix"))) {
                Function f = currentProgram.getFunctionManager().getFunctionAt(s.getAddress());
                if (f != null) println(n + " @ " + s.getAddress());
            }
        }
        // Decompile czStopTest + czCorePlayWindowProgram + likely DisplayTest opcodes
        long[] addrs = {0x10019540L, 0x100252b0L};
        String[] labels = {"czStopTest","czCorePlayWindowProgram"};
        for (int i = 0; i < addrs.length; i++) {
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(addrs[i]);
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            println("\n=== " + labels[i] + " @ 0x" + Long.toHexString(addrs[i]) + " ===");
            DecompileResults r = d.decompileFunction(f, 60, null);
            if (r != null && r.getDecompiledFunction() != null) println(r.getDecompiledFunction().getC());
        }
    }
}

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;

public class FindBtnIns extends GhidraScript {
    @Override public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        SymbolIterator it = currentProgram.getSymbolTable().getAllSymbols(true);
        java.util.List<Function> hits = new java.util.ArrayList<>();
        java.util.Set<Long> seen = new java.util.HashSet<>();
        while (it.hasNext()) {
            Symbol s = it.next();
            String n = s.getName();
            if (n.toLowerCase().contains("btnins") || n.contains("ClickInsert") || n.contains("InsertClk")
                || n.contains("btnIns") || n.startsWith("Ins") || n.contains("Insert")) {
                Function f = currentProgram.getFunctionManager().getFunctionAt(s.getAddress());
                if (f != null && seen.add(f.getEntryPoint().getOffset())) {
                    hits.add(f);
                    println(n + " @ " + s.getAddress());
                }
            }
        }
        // Also: refs to FUN_0043c8e8 (str_insert)
        ghidra.program.model.address.Address ins = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(0x0043c8e8L);
        ReferenceIterator refs = currentProgram.getReferenceManager().getReferencesTo(ins);
        while (refs.hasNext()) {
            Reference r = refs.next();
            Function f = currentProgram.getFunctionManager().getFunctionContaining(r.getFromAddress());
            if (f != null && seen.add(f.getEntryPoint().getOffset())) {
                hits.add(f);
                println("[ref->str_insert] " + f.getName() + " @ " + f.getEntryPoint());
            }
        }
        println("\n--- decompile " + hits.size() + " candidates ---");
        for (Function f : hits) {
            DecompileResults res = d.decompileFunction(f, 30, null);
            if (res != null && res.getDecompiledFunction() != null) {
                String c = res.getDecompiledFunction().getC();
                // Filter: must reference 0x0052c... or 0x0052d...
                if (c.contains("DAT_0052c") || c.contains("DAT_0052d") || c.contains("0x52c") || c.contains("0x52d") || c.contains("PTR_DAT_0052")) {
                    println("\n=== " + f.getName() + " @ " + f.getEntryPoint() + " ===");
                    println(c);
                }
            }
        }
    }
}

// Ghidra headless: locate functions referencing protocol strings, decompile them.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.symbol.ReferenceManager;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.PrintWriter;
import java.io.FileWriter;
import java.util.*;

public class DumpProtocol extends GhidraScript {

    static final String OUT = "/Users/alexscott/Projects/LEDctrl/analysis/ghidra/decomp.txt";
    static final String[] NEEDLES = {
        "SEQUENT.SYS", "temp.Nmg", "uJetFileICMD.pas", "uJetFileIICMD.pas",
        "RUNTIME.SYS", "CONFIG.SYS", "JetFileII", "SequentList.tmps",
        "MakeNmg", "Nmg", "TJetFIICMD", "TJetFICMD", "TBaseCMD"
    };

    @Override
    protected void run() throws Exception {
        Listing listing = currentProgram.getListing();
        ReferenceManager rm = currentProgram.getReferenceManager();

        Map<String, List<Address>> hits = new LinkedHashMap<>();
        for (String n : NEEDLES) hits.put(n, new ArrayList<>());

        DataIterator it = listing.getDefinedData(true);
        while (it.hasNext()) {
            Data d = it.next();
            try {
                Object v = d.getValue();
                if (v == null) continue;
                String s = v.toString();
                for (String n : NEEDLES) {
                    if (s.contains(n)) hits.get(n).add(d.getAddress());
                }
            } catch (Exception e) {}
        }

        Map<String, Function> fcns = new TreeMap<>();
        Map<String, Set<String>> fcnNeedles = new TreeMap<>();

        for (Map.Entry<String, List<Address>> e : hits.entrySet()) {
            for (Address a : e.getValue()) {
                ReferenceIterator refs = rm.getReferencesTo(a);
                while (refs.hasNext()) {
                    Reference r = refs.next();
                    Function f = currentProgram.getFunctionManager()
                        .getFunctionContaining(r.getFromAddress());
                    if (f == null) continue;
                    String ep = f.getEntryPoint().toString();
                    fcns.put(ep, f);
                    fcnNeedles.computeIfAbsent(ep, k -> new TreeSet<>()).add(e.getKey());
                }
            }
        }

        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);
        ConsoleTaskMonitor mon = new ConsoleTaskMonitor();

        try (PrintWriter fh = new PrintWriter(new FileWriter(OUT))) {
            fh.println("=== Strings located ===");
            for (Map.Entry<String, List<Address>> e : hits.entrySet()) {
                if (e.getValue().isEmpty()) continue;
                fh.println(e.getKey() + ": " + e.getValue());
            }
            fh.println();
            fh.println("=== Functions referencing them ===");
            for (Map.Entry<String, Function> e : fcns.entrySet()) {
                fh.println(e.getKey() + "  " + e.getValue().getName()
                    + "  refs=" + fcnNeedles.get(e.getKey()));
            }
            fh.println();
            fh.println("=== Decompiled ===");
            for (Map.Entry<String, Function> e : fcns.entrySet()) {
                Function f = e.getValue();
                fh.println();
                fh.println(";;; ============================================");
                fh.println(";;; " + e.getKey() + "  " + f.getName()
                    + "  refs=" + fcnNeedles.get(e.getKey()));
                fh.println(";;; ============================================");
                try {
                    DecompileResults r = di.decompileFunction(f, 60, mon);
                    if (r != null && r.getDecompiledFunction() != null) {
                        fh.print(r.getDecompiledFunction().getC());
                    } else {
                        fh.println("// decompile failed");
                    }
                } catch (Exception ex) {
                    fh.println("// exception: " + ex);
                }
            }
        }
        println("DONE -> " + OUT);
    }
}

// Decompile read-side RPCs in czJetFileII.dll.
// Targets: czSystemUpTimeSec, czReadPCBID, czGetDateTime, czReadStatusInfo,
// czReadBrightInfoExt, czUpdate3Info, czReadSignLog, czReadEventLog.
// @category Custom

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;

public class DumpReadAPI extends GhidraScript {
    public void run() throws Exception {
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);

        String[] targets = new String[]{
            "czSystemUpTimeSec",
            "czReadPCBID",
            "czGetDateTime",
            "czReadStatusInfo",
            "czReadBrightInfoExt",
            "czUpdate3Info",
            "czReadSignLog",
            "czReadEventLog",
            "czReadTempLog",
            "czReadPlayLogExt",
            "czReadSignWaringLog",
            "czOSGetFileSize",
            "czGetDirLongFileEx",
            "czLicGetID",
            "czErrorDesc"
        };

        for (String name : targets) {
            println("\n=================== " + name + " ===================");
            Function f = findFunc(name);
            if (f == null) {
                println("NOT FOUND: " + name);
                continue;
            }
            println("addr=" + f.getEntryPoint() + " body=" + f.getBody());
            DecompileResults res = decomp.decompileFunction(f, 60, null);
            if (res != null && res.getDecompiledFunction() != null) {
                println(res.getDecompiledFunction().getC());
            } else {
                println("(decompile failed)");
            }
        }
    }

    Function findFunc(String name) throws Exception {
        SymbolIterator it = currentProgram.getSymbolTable().getAllSymbols(true);
        while (it.hasNext()) {
            Symbol s = it.next();
            String n = s.getName();
            if (n.equals(name) || n.equals("_" + name) || n.startsWith("_" + name + "@") || n.startsWith(name + "@")) {
                Function f = currentProgram.getFunctionManager().getFunctionAt(s.getAddress());
                if (f != null) return f;
            }
        }
        return null;
    }
}

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

public class DumpPlayOps extends GhidraScript {
    @Override public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        long[] addrs = {
            0x10014a10L, // czReplayCurrFile
            0x10014ae0L, // czPlayPause
            0x10014bb0L, // czPlayContinue
            0x10014c80L, // czPlayNext
            0x10014e30L, // czGetPlayingFileName
            0x10025490L, // czCoreStopPlay
            0x10025810L, // czCoreGetPlayInfo
            0x100020b0L, // czSleep
            0x100120c0L  // czClearAllPlayFiles
        };
        String[] labels = {
            "czReplayCurrFile","czPlayPause","czPlayContinue","czPlayNext",
            "czGetPlayingFileName","czCoreStopPlay","czCoreGetPlayInfo","czSleep","czClearAllPlayFiles"
        };
        for (int i = 0; i < addrs.length; i++) {
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(addrs[i]);
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            println("\n=== " + labels[i] + " @ 0x" + Long.toHexString(addrs[i]) + " ===");
            DecompileResults r = d.decompileFunction(f, 60, null);
            if (r != null && r.getDecompiledFunction() != null) println(r.getDecompiledFunction().getC());
        }
    }
}

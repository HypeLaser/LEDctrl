import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class DumpPlayInners extends GhidraScript {
    @Override public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        long[] addrs = {
            0x100159e0L, // czReplayCurrFile inner
            0x10015a40L, // czPlayPause inner
            0x10015aa0L, // czPlayContinue inner
            0x10015b00L, // czPlayNext inner
            0x10015c40L, // czGetPlayingFileName inner
            0x10025ec0L, // czCoreStopPlay inner
            0x10026170L, // czCoreGetPlayInfo inner
            0x10012f20L  // czClearAllPlayFiles inner
        };
        String[] labels = {
            "Replay","Pause","Continue","Next","GetPlayName","CoreStop","CoreGetInfo","ClearAll"
        };
        for (int i = 0; i < addrs.length; i++) {
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(addrs[i]);
            Function f = currentProgram.getFunctionManager().getFunctionAt(a);
            if (f == null) { disassemble(a); f = createFunction(a, "inner_" + labels[i]); }
            println("\n=== " + labels[i] + " inner @ 0x" + Long.toHexString(addrs[i]) + " ===");
            DecompileResults r = d.decompileFunction(f, 60, null);
            if (r != null && r.getDecompiledFunction() != null) println(r.getDecompiledFunction().getC());
        }
    }
}

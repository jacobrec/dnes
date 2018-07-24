import std.stdio: writeln;
import nes;
import cartridge.cartridge: loadROM;

void main() {
    //writeln("DNES, a pretty bad NES emulator.");

    NES system = new NES();

    system.insertCartridge(loadROM("roms/dk.nes"));
    system.reset();

    /+ // terminal screen size demo
    for(int i = 0; i < 120; i++){
        for(int j = 0; j < 256; j++){
            writef("%s", '▀');
        }
        writeln();
    }
    +/

        
    debug{
        import core.exception : AssertError;
        int i;
        try{
            for(i = 0; ; i++){
                system.tick();
            }
        } catch(AssertError e){
            debug system.cpu.printDebugInfo();
            writeln("Did ", i, " micro ops");
        }
    } else {
        for(;;){
            system.tick();
        }
    }

}

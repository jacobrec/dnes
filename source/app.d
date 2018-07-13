import std.stdio: writeln;
import nes;
import cartridge.cartridge: loadROM;

void main() {
    //writeln("DNES, a pretty bad NES emulator.");

    NES system = new NES();

    system.insertCartridge(loadROM("roms/dk.nes"));
    system.reset();

    for(;;){
        system.tick();
    }

}

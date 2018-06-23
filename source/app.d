import std.stdio: writeln;
import nes;
import cartridge.cartridge: loadROM;

void main() {
    writeln("DNES, a pretty bad NES emulator.");

    NES system = new NES();

    system.insertCartridge(loadROM("roms/nestest.nes"));
    writeln(system.cartridge);
    system.reset();

    for(int i = 0; i < 10; i++){
        system.tick();
    }

    writeln(system);
}

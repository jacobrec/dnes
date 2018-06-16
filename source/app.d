import std.stdio: writeln;
import cpu.cpu;
import cartridge;

void main() {
    writeln("DNES, a pretty bad NES emulator.");

    loadROM("roms/back.nes");
}

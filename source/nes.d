import cpu.cpu;
import cartridge.cartridge;
import std.conv: text;

class NES{
    CPU cpu;
    Cartridge cartridge;
    // PPU ppu;
    // APU apu;

    this(){
        cpu = new CPU(this);
    }
    void insertCartridge(Cartridge cart){
        this.cartridge = cart;
    }
    override const string toString(){
        return text("NES(", cpu, ", ", cartridge, ")");
    }

    void reset(){
        cpu.reset();
    }
    
    void tick(){
        cpu.tick();
    }



    /+ {{{ NES Memory Map

        | ---------------- | 0x10000
        |      PRG-ROM     |
        |     Upper Bank   |
        | ---------------- | 0xC000
        |      PRG-ROM     |
        |    Lower Bank    |
        | ---------------- | 0x8000
        |       SRAM       |
        | ---------------- | 0x6000
        |   Expansion ROM  |
        | ---------------- | 0x4020
        |   I/O Registers  |
        | ---------------- | 0x4000
        |    Mirrors of    |
        |   PPU Registers  |
        | ---------------- | 0x2008
        |   PPU Registers  |
        | ---------------- | 0x2000
        |  Mirrors of Ram, |
        | Stack, Zero Page |
        | ---------------- | 0x0800
        |        RAM       |
        | ---------------- | 0x0200
        |       Stack      |
        | ---------------- | 0x0100
        |     Zero Page    |
        | ---------------- | 0x0000

    }}}+/
        ubyte* access(ushort loc) {
            if (loc < 0x2000) { // values stored in ram
                return &(cpu.ram[loc % 0x800]);
            }
            else if (loc < 0x4000) {
                //return this.ppu.accessMem(loc % 8);
                assert(0);
            }
            else if (loc < 0x4020) {
                // apu stuff
                assert(0);
            }
            else if (loc < 0x6000) {
                assert(0);
            }
            else if (loc < 0x8000) {
                assert(0);
            }
            else {
                return cast(ubyte*)cartridge.mapper.access(loc);
            }
        }

}

// vim:foldmethod=marker:foldlevel=0

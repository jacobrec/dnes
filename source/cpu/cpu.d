module cpu.cpu;

class CPU {
    ubyte A; // Accumulator
    ubyte X; // X index
    ubyte Y; // Y index

    // Bit order is 76543210
    //              SV BDIZC
    // (C)arry
    // (Z)ero
    // (I)nterrupt enabled
    // (D)ecimal mode status
    // (B)rk, software interrump
    // ( ) unused, should be 1 at all times
    // O(V)erflow
    // (S)ign flag, set is negative
    ubyte CCR; // Status Register
    enum CC {
        CARRY = 0,
        ZERO,
        INTERRUPT,
        DECIMAL,
        BRK,
        NULL,
        OVERFLOW,
        SIGN
    }

    ushort pc; // The program counter
    ubyte sp; // The stack pointer

    ulong cycles; // Comsumed cpu cycles

    ubyte[800] ram;

    bool getStatus(CC flag) {
        return cast(bool)(this.CCR & (1 << (cast(int) flag)));
    }

    void setStatus(CC flag, bool status) {
        this.CCR ^= (-(cast(int) status) ^ this.CCR) & (1 << flag);
        this.CCR |= 0b00100000;
    }

    /+  
        NES Memory Map
        
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

        +/
    ubyte* accessMem(ushort loc) {
        if (loc < 0x2000) { // values stored in ram
            return &(this.ram[loc % 0x800]);
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
            // cartridge
            assert(0);
        }

    }

}

// CCR test {{{
unittest {
    CPU cpu = new CPU();

    cpu.CCR = 0b11100110;
    cpu.setStatus(CPU.CC.SIGN, 0);
    cpu.setStatus(CPU.CC.BRK, 1);

    assert(cpu.CCR == 0b01110110);
    assert(cpu.getStatus(CPU.CC.ZERO));
    assert(!cpu.getStatus(CPU.CC.DECIMAL));
}
// }}}

// vim:foldmethod=marker:foldlevel=0

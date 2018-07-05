module cpu.cpu;
// Imports {{{
import nes;

import std.stdio : writeln, writef;
import std.format : format;
import std.conv : text, to;
import std.container : DList;

// }}}

// CPU {{{
class CPU {
    // Data {{{
    ubyte A; // Accumulator
    ubyte X; // X index
    ubyte Y; // Y index
    private ubyte R; // Internal registers

    // Bit order is 76543210
    //              NV BDIZC

    // (C)arry
    // (Z)ero
    // (I)nterrupt enabled
    // (D)ecimal mode status
    // (B)rk, software interrupt
    // ( ) unused, should be 1 at all times
    // O(V)erflow
    // (N)egative flag, set is negative
    ubyte CCR; // Status Register
    enum CC {
        CARRY = 0,
        ZERO,
        INTERRUPT,
        DECIMAL,
        BRK,
        NULL,
        OVERFLOW,
        NEGATIVE
    }

    enum Mem {
        IMMEDIATE,
        ABSOLUTE,
        ZEROPAGE,
    }

    ushort pc; // The program counter
    ubyte sp; // The stack pointer

    ulong cycles; // Consumed cpu cycles

    ubyte[0x800] ram;

    NES system;

    DList!(void delegate()) opline;

    // }}}
    // Micro Ops {{{

    this(NES system) {
        this.system = system;
    }

    void addMicroOp(void delegate() op) {
        this.opline.insertBack(op);
    }

    void noMicroOp() {
        this.cycles--;
    }

    void doMicroOp() {
        this.opline.front()();
        this.opline.removeFront();
    }

    bool hasMicroOp() {
        return !this.opline.empty;
    }

    void tick() {
        if (!this.hasMicroOp()) {
            this.addMicroOp({ this.readInstruction(); });
        }
        this.doMicroOp();
        this.cycles++;
    }
    /// }}} 
    // Status functions {{{
    bool getStatus(CC flag) {
        this.CCR |= 0b00100000;
        return cast(bool)(this.CCR & (1 << (cast(int) flag)));
    }

    void setStatus(CC flag, bool status) {
        this.CCR ^= (-(cast(int) status) ^ this.CCR) & (1 << flag);
        this.CCR |= 0b00100000;
    }

    void setStatus(ubyte val) {
        this.CCR = val;
        this.CCR |= 0b00100000;
    }

    void setZeroNegIf(ubyte val) {
        this.setZeroIf(val);
        this.setNegIf(val);
    }

    void setZeroIf(ubyte val) {
        this.setStatus(CC.ZERO, val == 0);
    }

    void setNegIf(ubyte val) {
        this.setStatus(CC.NEGATIVE, (val & 0b1000_0000) != 0);
    }
    // }}}
    // System {{{
    override const string toString() {
        return text("CPU(", "A:", A, "|X:", X, "|Y:", Y, "|CCR:", CCR, "|PC:",
                pc, "|SP:", sp, "|Cycles:", cycles, ")");
    }

    ushort read16(ubyte* loc) {
        return *loc | (*(loc + 1) << 8);
    }

    void reset() {
        this.A = 0;
        this.X = 0;
        this.Y = 0;
        this.pc = 0xFFFC;
        this.sp = 0xFD;
        this.setStatus(CC.INTERRUPT, true);

        //TODO: make this an interrupt
        this.pc = read16(system.access(0xFFFC));
        this.pc = 0xC000;
        //writef("Starting at: 0x%X\n", this.pc);
    }

    ubyte nextOp(bool print = true) {
        if (print)
            debug ops ~= format("%.2X ", *system.access(this.pc));
        return *system.access(this.pc++);
    }

    // }}}
    // Decoder {{{
    bool first = true;
    string regs;
    string ops;
    string disassemble;
    void readInstruction() {
        debug {
            if (!first) {
                writef(rightPad(ops, 10));
                writef(rightPad(disassemble, 32));
                writef(regs);
            }
            regs = format("A:%.2X X:%.2X Y:%.2X P:%.2X SP:%.2X CYC:%3d\n", A,
                    X, Y, CCR, sp, (cycles * 3) % 341);
            first = false;
            ops = "";
            disassemble = "";
            writef("%X  ", this.pc);
        }
        ubyte op = cast(ubyte) nextOp();

        switch (op) {
        case 0x08: // (8) PHP - implied
            debug disassemble ~= "PHP";
            this.push(&this.CCR);
            break;
        case 0x09: // (9) ORA - immediate
            debug disassemble ~= "ORA";
            this.or(getMem(Mem.IMMEDIATE));
            break;
        case 0x0A: // (10) ASL - accumulator
            debug disassemble ~= "ASL A";
            this.shift(&this.A, /+left+/true);
            break;
        case 0x10: // (16) BPL - zero page
            debug disassemble ~= "BPL";
            this.branchIf(CC.NEGATIVE, /+isSet+/ false);
            break;
        case 0x18: // (24) CLC - implied
            debug disassemble ~= "CLC";
            this.addMicroOp({ setStatus(CC.CARRY, false); });
            break;
        case 0x20: // (32) JSR - implied
            debug disassemble ~= "JSR";
            this.call();
            break;
        case 0x24: // (36) BIT - zero page
            debug disassemble ~= "BIT";
            this.testBitInMemoryWithAccumulator();
            break;
        case 0x28: // (40) PLP - implied
            debug disassemble ~= "PLP";
            this.pop(&this.CCR);
            break;
        case 0x29: // (41) AND - immediate
            debug disassemble ~= "AND";
            this.and(getMem(Mem.IMMEDIATE));
            break;
        case 0x30: // (48) BMI - relative
            debug disassemble ~= "BMI";
            this.branchIf(CC.NEGATIVE, /+isSet+/ true);
            break;
        case 0x38: // (56) SEC - implied
            debug disassemble ~= "SEC";
            this.addMicroOp({ setStatus(CC.CARRY, true); });
            break;
        case 0x40: // (64) RTI - implied
            debug disassemble ~= "RTI";
            this.returnFromInterrupt();
            break;
        case 0x48: // (72) PHA - implied
            debug disassemble ~= "PHA";
            this.push(&this.A);
            break;
        case 0x49: // (73) EOR - immediate
            debug disassemble ~= "EOR";
            this.xor(getMem(Mem.IMMEDIATE));
            break;
        case 0x4A: // (74) LSR - accumulator
            debug disassemble ~= "LSR A";
            this.shift(&this.A, /+left+/false);
            break;
        case 0x4C: // (76) JMP - immediate
            debug disassemble ~= "JMP";
            this.jump(Mem.IMMEDIATE);
            break;
        case 0x50: // (80) BVC - relative
            debug disassemble ~= "BVC";
            this.branchIf(CC.OVERFLOW, /+isSet+/ false);
            break;
        case 0x60: // (96) RTS - implied
            debug disassemble ~= "RTS";
            this.returnFromSubroutine();
            break;
        case 0x68: // (104) PLA - implied
            debug disassemble ~= "PLA";
            this.pop(&this.A);
            break;
        case 0x69: // (105) ADC - immediate
            debug disassemble ~= "ADC";
            this.add(&this.A, getMem(Mem.IMMEDIATE));
            break;
        case 0x70: // (112) BVS - relative
            debug disassemble ~= "BVS";
            this.branchIf(CC.OVERFLOW, /+isSet+/ true);
            break;
        case 0x78: // (120) SEI - implied
            debug disassemble ~= "SEI";
            this.addMicroOp({ setStatus(CC.INTERRUPT, true); });
            break;
        case 0x85: // (133) STA - zero page
            debug disassemble ~= "STA";
            this.store(&this.A, getMem(Mem.ZEROPAGE));
            break;
        case 0x86: // (134) STX - zero page
            debug disassemble ~= "STX";
            this.store(&this.X, getMem(Mem.ZEROPAGE));
            break;
        case 0x88: // (136) DEY - implied
            debug disassemble ~= "DEY";
            this.increment(&this.Y, -1);
            break;
        case 0x8A: // (138) TXA - implied
            debug disassemble ~= "TXA";
            this.transfer(&this.X, &this.A);
            break;
        case 0x8E: // (142) STX - absolute
            debug disassemble ~= "STX";
            this.store(&this.X, getMem(Mem.ABSOLUTE));
            break;
        case 0x90: // (144) BCC - relative
            debug disassemble ~= "BCC";
            this.branchIf(CC.CARRY, /+isSet+/ false);
            break;
        case 0x98: // (152) TYA - implied
            debug disassemble ~= "TYA";
            this.transfer(&this.Y, &this.A);
            break;
        case 0x9A: // (154) TXS - implied
            debug disassemble ~= "TXS";
            this.addMicroOp({ this.sp = this.X; });
            break;
        case 0xA0: // (160) LDY - immediate
            debug disassemble ~= "LDY";
            this.load(&this.Y, getMem(Mem.IMMEDIATE));
            break;
        case 0xA2: // (162) LDX - immediate
            debug disassemble ~= "LDX";
            this.load(&this.X, getMem(Mem.IMMEDIATE));
            break;
        case 0xA8: // (168) TAY - implied
            debug disassemble ~= "TAY";
            this.transfer(&this.A, &this.Y);
            break;
        case 0xA9: // (169) LDA - immediate
            debug disassemble ~= "LDA";
            this.load(&this.A, getMem(Mem.IMMEDIATE));
            break;
        case 0xAA: // (170) TAX - implied
            debug disassemble ~= "TAX";
            this.transfer(&this.A, &this.X);
            break;
        case 0xAD: // (173) LDA - absolute
            debug disassemble ~= "LDA";
            this.load(&this.A, getMem(Mem.ABSOLUTE));
            break;
        case 0xAE: // (174) LDX - absolute
            debug disassemble ~= "LDX";
            this.load(&this.X, getMem(Mem.ABSOLUTE));
            break;
        case 0xBA: // (1186) TSX - implied
            debug disassemble ~= "TSX";
            this.transfer(&this.sp, &this.X);
            break;
        case 0xB0: // (176) BCS - relative
            debug disassemble ~= "BCS";
            this.branchIf(CC.CARRY, /+isSet+/ true);
            break;
        case 0xB8: // (184) CLV - implied
            debug disassemble ~= "CLV";
            this.addMicroOp({ setStatus(CC.OVERFLOW, false); });
            break;
        case 0xC0: // (192) CPY - immediate
            debug disassemble ~= "CPY";
            this.compare(&this.Y, getMem(Mem.IMMEDIATE));
            break;
        case 0xC8: // (200) INY - implied
            debug disassemble ~= "INY";
            this.increment(&this.Y, 1);
            break;
        case 0xC9: // (201) CMP - immediate
            debug disassemble ~= "CMP";
            this.compare(&this.A, getMem(Mem.IMMEDIATE));
            break;
        case 0xCA: // (202) DEX - implied
            debug disassemble ~= "DEX";
            this.increment(&this.X, -1);
            break;
        case 0xD0: // (208) BNE - relative
            debug disassemble ~= "BNE";
            this.branchIf(CC.ZERO, /+isSet+/ false);
            break;
        case 0xD8: // (216) CLD - implied
            debug disassemble ~= "CLD";
            this.addMicroOp({ setStatus(CC.DECIMAL, false); });
            break;
        case 0xE0: // (224) CPX - immediate
            debug disassemble ~= "CPX";
            this.compare(&this.X, getMem(Mem.IMMEDIATE));
            break;
        case 0xE8: // (232) INX - implied
            debug disassemble ~= "INX";
            this.increment(&this.X, 1);
            break;
        case 0xE9: // (233) SBC - immediate
            debug disassemble ~= "SBC";
            this.subtract(&this.A, getMem(Mem.IMMEDIATE));
            break;
        case 0xEA: // (234) NOP - implied
            debug disassemble ~= "NOP";
            this.addMicroOp({  });
            break;
        case 0xF0: // (240) BEQ - relative
            debug disassemble ~= "BEQ";
            this.branchIf(CC.ZERO, /+isSet+/ true);
            break;
        case 0xF8: // (248) SED - relative
            debug disassemble ~= "SED";
            this.addMicroOp({ setStatus(CC.DECIMAL, true); });
            break;
        default:
            writef("Unimplemented Instruction: 0x%X(%d). PC: %X\n", op, op, this.pc - 1);
            writeln(this);

            assert(0);
        }
    }
    // }}}

    // Opcode helpers {{{
    void stackPush(ubyte val) {
        this.ram[this.sp-- | 0x100] = val;
    }

    ubyte stackRead() {
        return this.ram[this.sp | 0x100];
    }

    void returnFromInterrupt() {
        this.addMicroOp({ this.nextOp(false); });
        this.addMicroOp({ this.sp++; });
        this.addMicroOp({ this.setStatus(this.stackRead()); sp++; });
        this.addMicroOp({ this.pc = (this.pc & 0xFF00) | this.stackRead(); sp++; });
        this.addMicroOp({ this.pc = (this.pc & 0x00FF) | (this.stackRead() << 8); });
    }

    void returnFromSubroutine() {
        this.addMicroOp({ this.nextOp(false); });
        this.addMicroOp({ this.sp++; });
        this.addMicroOp({ this.pc = (this.pc & 0xFF00) | this.stackRead(); sp++; });
        this.addMicroOp({ this.pc = (this.pc & 0x00FF) | (this.stackRead() << 8); });
        this.addMicroOp({ this.pc++; });
    }

    void call() {
        debug disassemble ~= " $" ~ format("%.2X%.2X",
                (*system.access(cast(ushort)(this.pc + 1))), (*system.access(this.pc)));
        ushort addr = 0;
        this.addMicroOp({ addr |= nextOp(); });
        this.addMicroOp({ /* none? */ });
        this.addMicroOp({ this.stackPush((this.pc & 0xFF00) >> 8); });
        this.addMicroOp({ this.stackPush(this.pc & 0xFF); });
        this.addMicroOp({ addr |= (nextOp() << 8); this.pc = addr; });
    }

    void push(ubyte* loc) {
        // XXX: this seems wrong
        // this.addMicroOp({ nextOp(false); }); // are these supposed to burn a byte
        this.addMicroOp({  }); // or just burn a cycle

        if (loc == &this.A) {
            this.addMicroOp({ this.stackPush(*loc); });
        }
        else {
            this.addMicroOp({ this.stackPush(*loc | 0x10); }); // XXX: I dont like
            // this special case for this
        }
    }

    void pop(ubyte* loc) {
        // XXX: this seems wrong
        // this.addMicroOp({ nextOp(false); }); // are these supposed to burn a byte
        this.addMicroOp({  }); // or just burn a cycle
        this.addMicroOp({ this.sp++; });
        this.addMicroOp({
            *loc = this.stackRead();
            if (loc == &this.A) {
                this.setZeroNegIf(*loc);
            }
            else {
                this.setStatus(CC.BRK, false); // XXX: I don't like this
            }
        });
    }

    void testBitInMemoryWithAccumulator() {
        ushort addr;
        debug disassemble ~= " $" ~ format("%.2X = %.2X",
                (*system.access(this.pc)), (*system.access((*system.access(this.pc)))));
        this.addMicroOp({ addr |= nextOp(); });
        this.addMicroOp({
            ubyte val = *this.system.access(addr);
            this.setStatus(CC.NEGATIVE, cast(bool)(val & 0b1000_0000));
            this.setStatus(CC.OVERFLOW, cast(bool)(val & 0b0100_0000));
            this.setZeroIf(val & this.A);
        });

    }

    void jump(Mem type) {
        switch (type) {
        case Mem.IMMEDIATE:
            debug disassemble ~= " $" ~ format("%.2X%.2X",
                    (*system.access(cast(ushort)(this.pc + 1))), (*system.access(this.pc)));
            ushort addr = 0;
            this.addMicroOp({ addr |= nextOp(); });
            this.addMicroOp({ addr |= (nextOp() << 8); this.pc = addr; });
            break;
        case Mem.ABSOLUTE:
            ushort addr = 0;
            debug disassemble ~= " $" ~ format("%.2X%.2X",
                    (*system.access(cast(ushort)(this.pc + 1))), (*system.access(this.pc)));
            this.addMicroOp({ addr |= nextOp(); });
            this.addMicroOp({ addr |= (nextOp() << 8); });
            this.addMicroOp({ this.pc = *this.system.access(addr); });
            break;
        default:
            assert(0); // unimplemented
        }
    }

    void load(ubyte* loc, ubyte* mem) {
        this.addMicroOp({ this.setZeroNegIf(*loc = *mem); });
    }

    void and(ubyte* mem) {
        this.addMicroOp({ this.setZeroNegIf(this.A &= *mem); });
    }

    void or(ubyte* mem) {
        this.addMicroOp({ this.setZeroNegIf(this.A |= *mem); });
    }

    void xor(ubyte* mem) {
        this.addMicroOp({ this.setZeroNegIf(this.A ^= *mem); });
    }

    void shift(ubyte* mem, bool left) { // left is negative
        this.addMicroOp({
            if(left){
                setStatus(CC.CARRY, cast(bool)(*mem & 0x80));
                setZeroNegIf(*mem <<= 1);
            } else{
                setStatus(CC.CARRY, cast(bool)(*mem & 1));
                setZeroNegIf(*mem >>= 1);
            }
        });
    }

    void add(ubyte* loc, ubyte* mem) {
        this.addMicroOp({
            ubyte b = *mem;
            uint val = *loc + b + (this.CCR & 1);
            ubyte fin = cast(ubyte) val;
            this.setZeroNegIf(fin);
            this.setStatus(CC.CARRY, val > 0xFF);
            this.setStatus(CC.OVERFLOW, !((*loc ^ b) & 0x80) && ((*loc ^ (val)) & 0x80));
            *loc = fin;
        });
    }

    void subtract(ubyte* loc, ubyte* mem) {
        this.addMicroOp({
            ubyte b = *mem;
            int val = (cast(byte)*loc) - b - (getStatus(CC.CARRY) ? 0 : 1);
            ubyte fin = val & 0xFF;
            this.setZeroNegIf(fin);
            this.setStatus(CC.CARRY, *loc >= b); // XXX: idk
            this.setStatus(CC.OVERFLOW, val * (cast(byte) fin) < 0);
            *loc = fin;
        });
    }

    void increment(ubyte* loc, int amount) {
        this.addMicroOp({ this.setZeroNegIf(*loc += amount); });
    }

    void compare(ubyte* loc, ubyte* mem) {
        this.addMicroOp({
            ubyte b = *mem;
            int val = *loc - b;
            ubyte fin = cast(ubyte) val;
            this.setZeroNegIf(fin);
            this.setStatus(CC.CARRY, *loc >= b); // XXX: idk
        });
    }

    void store(ubyte* loc, ubyte* mem) {
        this.addMicroOp({ *mem = *loc; });
    }

    void transfer(ubyte* from, ubyte* to) {
        this.addMicroOp({ this.setZeroNegIf(*to = *from); });
    }

    void branchIf(CC flag, bool ifSet) {
        ubyte disp;
        ushort og_pc;
        bool shouldJump;

        debug disassemble ~= " $" ~ format("%.4X", (*system.access(pc) + pc + 1));
        this.addMicroOp({
            disp = nextOp();
            og_pc = pc;
            shouldJump = this.getStatus(flag) == ifSet;
        });
        this.addMicroOp({
            if (shouldJump) {
                pc = ((pc & 0xFF) + disp) | (pc & 0xFF00);
                og_pc += disp;
            }
            else {
                this.noMicroOp();
            }
        });
        this.addMicroOp({
            if (og_pc == pc || !shouldJump) {
                this.noMicroOp();
            }
            else {
                pc = og_pc;
            }
        });
    }

    ubyte* getMem(Mem type) {
        final switch (type) {
        case Mem.IMMEDIATE:
            debug disassemble ~= " #$" ~ format("%.2X", (*system.access(this.pc)));
            this.addMicroOp({ this.R = nextOp(); this.noMicroOp(); });
            return &R;
        case Mem.ABSOLUTE:
            ubyte low = nextOp();
            ubyte high = nextOp();
            ushort tot = low | (high << 8);
            debug {
                disassemble ~= " $" ~ format("%.4X = %.2X", tot, *system.access(tot));
            }
            this.addMicroOp({  });
            this.addMicroOp({  });
            return this.system.access(tot);
        case Mem.ZEROPAGE:
            ushort addr = nextOp();
            debug disassemble ~= " $" ~ format("%.2X = %.2X", addr, *system.access(addr));
            this.addMicroOp({  });
            return this.system.access(addr);
        }
    }

    // }}}
}
// }}}

// Other {{{
string rightPad(string inp, int len) {
    return (inp ~ "                                      ")[0 .. len];
}
// }}}
// CCR test {{{
unittest {
    CPU cpu = new CPU(cast(NES) null);

    cpu.CCR = 0b11100110;
    cpu.setStatus(CPU.CC.SIGN, 0);
    cpu.setStatus(CPU.CC.BRK, 1);

    assert(cpu.CCR == 0b01110110);
    assert(cpu.getStatus(CPU.CC.ZERO));
    assert(!cpu.getStatus(CPU.CC.DECIMAL));
}
// }}}
// Pipeline Test {{{
unittest {
    CPU cpu = new CPU(cast(NES) null);
    cpu.addMicroOp({ cpu.X++; });
    cpu.addMicroOp({ cpu.X++; });
    cpu.addMicroOp({ cpu.Y++; });
    assert(cpu.X == 0);
    assert(cpu.Y == 0);

    cpu.doMicroOp();
    cpu.doMicroOp();
    assert(cpu.X == 2);
    assert(cpu.Y == 0);
    cpu.doMicroOp();
    assert(cpu.X == 2);
    assert(cpu.Y == 1);
}
// }}}

// vim:foldmethod=marker:foldlevel=0

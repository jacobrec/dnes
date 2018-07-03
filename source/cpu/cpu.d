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
    byte A; // Accumulator
    byte X; // X index
    byte Y; // Y index

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
    byte CCR; // Status Register
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

    ubyte[800] ram;

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

    void setZeroNegIf(byte val) {
        this.setZeroIf(val);
        this.setNegIf(val);
    }

    void setZeroIf(byte val) {
        this.setStatus(CC.ZERO, val == 0);
    }

    void setNegIf(byte val) {
        this.setStatus(CC.NEGATIVE, val < 0);
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

    ubyte uNextOp(bool print = true) {
        if (print)
            debug ops ~= format("%.2X ", *system.access(this.pc));
        return *system.access(this.pc++);
    }

    byte nextOp(bool print = true) {
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
        ubyte op = cast(ubyte) uNextOp();

        switch (op) {
        case 0x08: // (8) PHP - implied
            debug disassemble ~= "PHP";
            this.push(&this.CCR);
            break;
        case 0x09: // (9) ORA - immediate
            debug disassemble ~= "ORA";
            this.or(Mem.IMMEDIATE);
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
        case 0x30: // (48) BMI - relative
            debug disassemble ~= "BMI";
            this.branchIf(CC.NEGATIVE, /+isSet+/ true);
            break;
        case 0x29: // (41) AND - immediate
            debug disassemble ~= "AND";
            this.and(Mem.IMMEDIATE);
            break;
        case 0x38: // (56) SEC - implied
            debug disassemble ~= "SEC";
            this.addMicroOp({ setStatus(CC.CARRY, true); });
            break;
        case 0x48: // (72) PHA - implied
            debug disassemble ~= "PHA";
            this.push(&this.A);
            break;
        case 0x49: // (73) EOR - immediate
            debug disassemble ~= "EOR";
            this.xor(Mem.IMMEDIATE);
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
            this.store(&this.A, Mem.ZEROPAGE);
            break;
        case 0x86: // (134) STX - zero page
            debug disassemble ~= "STX";
            this.store(&this.X, Mem.ZEROPAGE);
            break;
        case 0x90: // (144) BCC - relative
            debug disassemble ~= "BCC";
            this.branchIf(CC.CARRY, /+isSet+/ false);
            break;
        case 0x9A: // (154) TXS - implied
            debug disassemble ~= "TXS";
            this.addMicroOp({ this.sp = this.X; });
            break;
        case 0xA2: // (162) LDX - immediate
            debug disassemble ~= "LDX";
            this.load(&this.X, Mem.IMMEDIATE);
            break;
        case 0xA9: // (169) LDA - immediate
            debug disassemble ~= "LDA";
            this.load(&this.A, Mem.IMMEDIATE);
            break;
        case 0xAD: // (173) LDA - absolute
            debug disassemble ~= "LDA";
            this.load(&this.A, Mem.ABSOLUTE);
            break;
        case 0xB0: // (176) BCS - relative
            debug disassemble ~= "BCS";
            this.branchIf(CC.CARRY, /+isSet+/ true);
            break;
        case 0xB8: // (184) CLV - implied
            debug disassemble ~= "CLV";
            this.addMicroOp({ setStatus(CC.OVERFLOW, false); });
            break;
        case 0xC9: // (201) CMP - immediate
            debug disassemble ~= "CMP";
            this.compare(&this.A, Mem.IMMEDIATE);
            break;
        case 0xD0: // (208) BNE - relative
            debug disassemble ~= "BNE";
            this.branchIf(CC.ZERO, /+isSet+/ false);
            break;
        case 0xD8: // (216) CLD - implied
            debug disassemble ~= "CLD";
            this.addMicroOp({ setStatus(CC.DECIMAL, false); });
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

    void stackPush(byte val) {
        this.ram[this.sp--] = val;
    }

    void returnFromSubroutine() {
        this.addMicroOp({ this.nextOp(false); });
        this.addMicroOp({ this.sp++; });
        this.addMicroOp({ this.pc = (this.pc & 0xFF00) | this.ram[this.sp++]; });
        this.addMicroOp({ this.pc = (this.pc & 0x00FF) | (this.ram[this.sp] << 8);  });
        this.addMicroOp({ this.pc++; });
    }

    void call() {
        debug disassemble ~= " $" ~ format("%.2X%.2X",
                (*system.access(cast(ushort)(this.pc + 1))), (*system.access(this.pc)));
        ushort addr = 0;
        this.addMicroOp({ addr |= uNextOp(); });
        this.addMicroOp({ /* none? */ });
        this.addMicroOp({ this.ram[this.sp--] = ((this.pc & 0xFF00) >> 8); });
        this.addMicroOp({ this.ram[this.sp--] = (this.pc & 0x00FF); });
        this.addMicroOp({ addr |= (uNextOp() << 8); this.pc = addr; });
    }

    void push(byte* loc) {
        // XXX: this seems wrong
        // this.addMicroOp({ nextOp(false); }); // are these supposed to burn a byte
        this.addMicroOp({  }); // or just burn a cycle

        if (loc == &this.A) {
            this.addMicroOp({ this.stackPush(*loc); });
        }else{
            this.addMicroOp({ this.stackPush(*loc | 0x10); }); // XXX: I dont like
                    // this special case for this
        }
    }


    void pop(byte* loc) {
        // XXX: this seems wrong
        // this.addMicroOp({ nextOp(false); }); // are these supposed to burn a byte
        this.addMicroOp({  }); // or just burn a cycle
        this.addMicroOp({ this.sp++; });
        this.addMicroOp({
            *loc = this.ram[this.sp];
            if (loc == &this.A) {
                this.setZeroNegIf(*loc);
            }else{
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
            this.setZeroIf(cast(byte)(val & this.A));
        });

    }

    void jump(Mem type) {
        final switch (type) {
        case Mem.IMMEDIATE:
            debug disassemble ~= " $" ~ format("%.2X%.2X",
                    (*system.access(cast(ushort)(this.pc + 1))), (*system.access(this.pc)));
            ushort addr = 0;
            this.addMicroOp({ addr |= uNextOp(); });
            this.addMicroOp({ addr |= (uNextOp() << 8); this.pc = addr; });
            break;
        case Mem.ABSOLUTE:
            ushort addr = 0;
            debug disassemble ~= " $" ~ format("%.2X%.2X",
                    (*system.access(cast(ushort)(this.pc + 1))), (*system.access(this.pc)));
            this.addMicroOp({ addr |= uNextOp(); });
            this.addMicroOp({ addr |= (uNextOp() << 8); });
            this.addMicroOp({ this.pc = *this.system.access(addr); });
            break;
        case Mem.ZEROPAGE:
            assert(0); // unimplemented
        }
    }

    void load(byte* loc, Mem type) {
        final switch (type) {
        case Mem.IMMEDIATE:
            debug disassemble ~= " #$" ~ format("%.2X", (*system.access(this.pc)));
            this.addMicroOp({ this.setZeroNegIf(*loc = nextOp()); });
            break;
        case Mem.ABSOLUTE:
            ushort addr = 0;
            debug disassemble ~= " $" ~ format("%.2X%.2X",
                    (*system.access(cast(ushort)(this.pc + 1))), (*system.access(this.pc)));
            this.addMicroOp({ addr |= nextOp(); });
            this.addMicroOp({ addr |= (nextOp() << 8); });
            this.addMicroOp({
                this.setZeroNegIf(*loc = *this.system.access(addr));
            });
            break;
        case Mem.ZEROPAGE:
            assert(0); // unimplemented
        }
    }

    void and(Mem type) {
        final switch (type) {
        case Mem.IMMEDIATE:
            debug disassemble ~= " #$" ~ format("%.2X", (*system.access(this.pc)));
            this.addMicroOp({ this.setZeroNegIf(this.A &= nextOp()); });
            break;
        case Mem.ABSOLUTE:
            assert(0); // unimplemented
        case Mem.ZEROPAGE:
            assert(0); // unimplemented
        }
    }

    void or(Mem type) {
        final switch (type) {
        case Mem.IMMEDIATE:
            debug disassemble ~= " #$" ~ format("%.2X", (*system.access(this.pc)));
            this.addMicroOp({ this.setZeroNegIf(this.A |= nextOp()); });
            break;
        case Mem.ABSOLUTE:
            assert(0); // unimplemented
        case Mem.ZEROPAGE:
            assert(0); // unimplemented
        }
    }

    void xor(Mem type) {
        final switch (type) {
        case Mem.IMMEDIATE:
            debug disassemble ~= " #$" ~ format("%.2X", (*system.access(this.pc)));
            this.addMicroOp({ this.setZeroNegIf(this.A ^= nextOp()); });
            break;
        case Mem.ABSOLUTE:
            assert(0); // unimplemented
        case Mem.ZEROPAGE:
            assert(0); // unimplemented
        }
    }

    void compare(byte* loc, Mem type) {
        final switch (type) {
        case Mem.IMMEDIATE:
            debug disassemble ~= " #$" ~ format("%.2X", (*system.access(this.pc)));
            this.addMicroOp({
                byte b = nextOp();
                this.setZeroNegIf(cast(byte)(*loc - b));
                this.setStatus(CC.CARRY, !cast(bool)((cast(int)*loc - cast(int) b) & 0xFFFFFF00));
            });
            break;
        case Mem.ABSOLUTE:
            assert(0); // unimplemented
        case Mem.ZEROPAGE:
            assert(0); // unimplemented
        }
    }

    void store(byte* loc, Mem type) {
        final switch (type) {
        case Mem.IMMEDIATE:
            assert(0); // I don't think this is a thing
        case Mem.ABSOLUTE:
            assert(0); // unimplemented
        case Mem.ZEROPAGE:
            ushort addr = 0;
            debug disassemble ~= " $" ~ format("%.2X = %.2X",
                    (*system.access(this.pc)), *system.access((*system.access(this.pc))));
            this.addMicroOp({ addr |= nextOp(); });
            this.addMicroOp({ *this.system.access(addr) = *loc; });
        }
    }

    void branchIf(CC flag, bool ifSet) {
        byte disp;
        ushort og_pc;
        bool shouldJump;

        debug disassemble ~= " $" ~ format("%.4X", (*system.access(pc) + pc + 1));
        this.addMicroOp({
            disp = nextOp();
            og_pc = pc;
            shouldJump = this.getStatus(flag) == ifSet;
        });
        // TODO: only jump if flag
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

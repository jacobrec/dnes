module cpu.cpu;
// Imports {{{
import nes;

import std.stdio : writeln, writef;
import std.format : format;
import std.conv : text, to;
import std.container : DList;

// }}}

immutable bool OFFICAL = true;
immutable bool UNOFFICAL = false;
immutable bool LEFT = true;
immutable bool RIGHT = false;

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
        ABSOLUTE_X,
        ABSOLUTE_Y,
        ZEROPAGE,
        ZEROPAGE_X,
        ZEROPAGE_Y,
        INDIRECT,
        INDIRECT_X,
        INDIRECT_Y,
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

    void joinLastMicroOp(){
        void delegate() op2 = this.opline.back();
        this.opline.removeBack();
        void delegate() op1 = this.opline.back();
        this.opline.removeBack();
        this.opline.insertBack({ op1(); op2(); });
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

    ubyte getStatus() {
        this.CCR |= 0b00100000;
        return this.CCR;
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
    bool isRegister(ubyte* loc) {
        return loc == &A || loc == &X || loc == &Y;
    }

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
    string predisassemble;
    void readInstruction() {
        debug {
            if (!first) {
                writef(rightPad(ops, 10-cast(ubyte)predisassemble.length));
                writef(predisassemble);
                writef(rightPad(disassemble, 32));
                writef(regs);
            }
            regs = format("A:%.2X X:%.2X Y:%.2X P:%.2X SP:%.2X CYC:%3d\n", A,
                    X, Y, CCR, sp, (cycles * 3) % 341);
            first = false;
            ops = "";
            disassemble = "";
            predisassemble = "";
            writef("%.4X  ", this.pc);
        }
        ubyte op = cast(ubyte) nextOp();

        switch (op) {
        case 0x01: // (1) ORA - indirect x
            debug disassemble ~= "ORA";
            this.or(getMem(Mem.INDIRECT_X));
            break;
        case 0x03: // (3) SLO - indirect x
            debug disassemble ~= "SLO";
            this.slo(getMem(Mem.INDIRECT_X));
            break;
        case 0x04: // (4) NOP - zero page
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ZEROPAGE), UNOFFICAL);
            break;
        case 0x05: // (5) ORA - zero page
            debug disassemble ~= "ORA";
            this.or(getMem(Mem.ZEROPAGE));
            break;
        case 0x06: // (6) ASL - zero page
            debug disassemble ~= "ASL";
            this.shift(getMem(Mem.ZEROPAGE), LEFT);
            break;
        case 0x07: // (7) SLO - zero page
            debug disassemble ~= "SLO";
            this.slo(getMem(Mem.ZEROPAGE));
            break;
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
            this.shift(&this.A, LEFT);
            break;
        case 0x0C: // (12) NOP - absolute
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ABSOLUTE), UNOFFICAL); 
            break;
        case 0x0D: // (13) ORA - absolute
            debug disassemble ~= "ORA";
            this.or(getMem(Mem.ABSOLUTE));
            break;
        case 0x0E: // (14) ASL - absolute
            debug disassemble ~= "ASL";
            this.shift(getMem(Mem.ABSOLUTE), LEFT);
            break;
        case 0x0F: // (15) SLO - absolute
            debug disassemble ~= "SLO";
            this.slo(getMem(Mem.ABSOLUTE));
            break;

        case 0x10: // (16) BPL - zero page
            debug disassemble ~= "BPL";
            this.branchIf(CC.NEGATIVE, /+isSet+/ false);
            break;
        case 0x11: // (17) ORA - indirect y
            debug disassemble ~= "ORA";
            this.or(getMem(Mem.INDIRECT_Y));
            break;
        case 0x13: // (19) SLO - indirect y
            debug disassemble ~= "SLO";
            this.slo(getMem(Mem.INDIRECT_Y));
            break;
        case 0x14: // (20) NOP - zero page x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ZEROPAGE_X), UNOFFICAL);
            break;
        case 0x15: // (21) ORA - zeropage x
            debug disassemble ~= "ORA";
            this.or(getMem(Mem.ZEROPAGE_X));
            break;
        case 0x16: // (22) ASL - zeropage x
            debug disassemble ~= "ASL";
            this.shift(getMem(Mem.ZEROPAGE_X), LEFT);
            break;
        case 0x17: // (23) SLO - zeropage x
            debug disassemble ~= "SLO";
            this.slo(getMem(Mem.ZEROPAGE_X));
            break;
        case 0x18: // (24) CLC - implied
            debug disassemble ~= "CLC";
            this.addMicroOp({ setStatus(CC.CARRY, false); });
            break;
        case 0x19: // (25) ORA - absolute y
            debug disassemble ~= "ORA";
            this.or(getMem(Mem.ABSOLUTE_Y));
            break;
        case 0x1A: // (26) NOP - implied
            debug disassemble ~= "NOP"; 
            this.nop(null, UNOFFICAL);
            break;
        case 0x1B: // (27) SLO - absolute y
            debug disassemble ~= "SLO";
            this.slo(getMem(Mem.ABSOLUTE_Y));
            break;
        case 0x1C: // (28) NOP - absolute x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ABSOLUTE_X), UNOFFICAL);
            break;
        case 0x1D: // (29) ORA - absolute x
            debug disassemble ~= "ORA";
            this.or(getMem(Mem.ABSOLUTE_X));
            break;
        case 0x1E: // (30) ASL - absolute x
            debug disassemble ~= "ASL";
            this.shift(getMem(Mem.ABSOLUTE_X), LEFT);
            break;
        case 0x1F: // (31) SLO - absolute x
            debug disassemble ~= "SLO";
            this.slo(getMem(Mem.ABSOLUTE_X));
            break;

        case 0x20: // (32) JSR - implied
            debug disassemble ~= "JSR";
            this.call();
            break;
        case 0x21: // (33) AND - indirect x
            debug disassemble ~= "AND";
            this.and(getMem(Mem.INDIRECT_X));
            break;
        case 0x23: // (35) RLA - indirect x
            debug disassemble ~= "RLA";
            this.rla(getMem(Mem.INDIRECT_X));
            break;
        case 0x24: // (36) BIT - zero page
            debug disassemble ~= "BIT";
            this.testBitInMemoryWithAccumulator(getMem(Mem.ZEROPAGE));
            break;
        case 0x25: // (37) AND - zero page
            debug disassemble ~= "AND";
            this.and(getMem(Mem.ZEROPAGE));
            break;
        case 0x26: // (38) ROL - zero page
            debug disassemble ~= "ROL";
            this.rotate(getMem(Mem.ZEROPAGE), LEFT);
            break;
        case 0x27: // (39) RLA - zero page
            debug disassemble ~= "RLA";
            this.rla(getMem(Mem.ZEROPAGE));
            break;
        case 0x28: // (40) PLP - implied
            debug disassemble ~= "PLP";
            this.pop(&this.CCR);
            break;
        case 0x29: // (41) AND - immediate
            debug disassemble ~= "AND";
            this.and(getMem(Mem.IMMEDIATE));
            break;
        case 0x2A: // (42) ROL - accumulator
            debug disassemble ~= "ROL A";
            this.rotate(&this.A, LEFT);
            break;
        case 0x2C: // (44) BIT - absolute
            debug disassemble ~= "BIT";
            this.testBitInMemoryWithAccumulator(getMem(Mem.ABSOLUTE));
            break;
        case 0x2D: // (45) AND - absolute
            debug disassemble ~= "AND";
            this.and(getMem(Mem.ABSOLUTE));
            break;
        case 0x2E: // (46) ROL - absolute
            debug disassemble ~= "ROL";
            this.rotate(getMem(Mem.ABSOLUTE), LEFT);
            break;
        case 0x2F: // (45) RLA - absolute
            debug disassemble ~= "RLA";
            this.rla(getMem(Mem.ABSOLUTE));
            break;

        case 0x30: // (48) BMI - relative
            debug disassemble ~= "BMI";
            this.branchIf(CC.NEGATIVE, /+isSet+/ true);
            break;
        case 0x31: // (49) AND - indirect y
            debug disassemble ~= "AND";
            this.and(getMem(Mem.INDIRECT_Y));
            break;
        case 0x33: // (49) RLA - indirect y
            debug disassemble ~= "RLA";
            this.rla(getMem(Mem.INDIRECT_Y));
            break;
        case 0x34: // (20) NOP - zero page x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ZEROPAGE_X), UNOFFICAL);
            break;
        case 0x35: // (53) AND - zeropage x
            debug disassemble ~= "AND";
            this.and(getMem(Mem.ZEROPAGE_X));
            break;
        case 0x36: // (54) ROL - zeropage x
            debug disassemble ~= "ROL";
            this.rotate(getMem(Mem.ZEROPAGE_X), LEFT);
            break;
        case 0x37: // (54) RLA - zeropage x
            debug disassemble ~= "RLA";
            this.rla(getMem(Mem.ZEROPAGE_X));
            break;
        case 0x38: // (56) SEC - implied
            debug disassemble ~= "SEC";
            this.addMicroOp({ setStatus(CC.CARRY, true); });
            break;
        case 0x39: // (57) AND - absolute y
            debug disassemble ~= "AND";
            this.and(getMem(Mem.ABSOLUTE_Y));
            break;
        case 0x3A: // (58) NOP - implied
            debug disassemble ~= "NOP"; 
            this.nop(null, UNOFFICAL);
            break;
        case 0x3B: // (59) RLA - absolute y
            debug disassemble ~= "RLA";
            this.rla(getMem(Mem.ABSOLUTE_Y));
            break;
        case 0x3C: // (60) NOP - absolute x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ABSOLUTE_X), UNOFFICAL);
            break;
        case 0x3D: // (61) AND - absolute x
            debug disassemble ~= "AND";
            this.and(getMem(Mem.ABSOLUTE_X));
            break;
        case 0x3E: // (62) ROL - absolute x
            debug disassemble ~= "ROL";
            this.rotate(getMem(Mem.ABSOLUTE_X), LEFT);
            break;
        case 0x3F: // (63) RLA - absolute x
            debug disassemble ~= "RLA";
            this.rla(getMem(Mem.ABSOLUTE_X));
            break;

        case 0x40: // (64) RTI - implied
            debug disassemble ~= "RTI";
            this.returnFromInterrupt();
            break;
        case 0x41: // (65) EOR - indirect x
            debug disassemble ~= "EOR";
            this.xor(getMem(Mem.INDIRECT_X));
            break;
        case 0x43: // (67) SRE - indirect x
            debug disassemble ~= "SRE";
            this.sre(getMem(Mem.INDIRECT_X));
            break;
        case 0x44: // (68) NOP - zero page
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ZEROPAGE), UNOFFICAL);
            break;
        case 0x45: // (69) EOR - zero page
            debug disassemble ~= "EOR";
            this.xor(getMem(Mem.ZEROPAGE));
            break;
        case 0x46: // (70) LSR - zero page
            debug disassemble ~= "LSR";
            this.shift(getMem(Mem.ZEROPAGE), RIGHT);
            break;
        case 0x47: // (71) SRE - zero page
            debug disassemble ~= "SRE";
            this.sre(getMem(Mem.ZEROPAGE));
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
            this.shift(&this.A, RIGHT);
            break;
        case 0x4C: // (76) JMP - immediate
            debug disassemble ~= "JMP";
            this.jump(Mem.IMMEDIATE);
            break;
        case 0x4D: // (77) EOR - absolute
            debug disassemble ~= "EOR";
            this.xor(getMem(Mem.ABSOLUTE));
            break;
        case 0x4E: // (74) LSR - absolute
            debug disassemble ~= "LSR";
            this.shift(getMem(Mem.ABSOLUTE), RIGHT);
            break;
        case 0x4F: // (75) SRE - absolute
            debug disassemble ~= "SRE";
            this.sre(getMem(Mem.ABSOLUTE));
            break;

        case 0x50: // (80) BVC - relative
            debug disassemble ~= "BVC";
            this.branchIf(CC.OVERFLOW, /+isSet+/ false);
            break;
        case 0x51: // (81) EOR - indirect y
            debug disassemble ~= "EOR";
            this.xor(getMem(Mem.INDIRECT_Y));
            break;
        case 0x53: // (83) SRE - indirect y
            debug disassemble ~= "SRE";
            this.sre(getMem(Mem.INDIRECT_Y));
            break;
        case 0x54: // (84) NOP - zero page x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ZEROPAGE_X), UNOFFICAL);
            break;
        case 0x55: // (85) EOR - zeropage x
            debug disassemble ~= "EOR";
            this.xor(getMem(Mem.ZEROPAGE_X));
            break;
        case 0x56: // (86) LSR - zeropage x
            debug disassemble ~= "LSR";
            this.shift(getMem(Mem.ZEROPAGE_X), RIGHT);
            break;
        case 0x57: // (87) SRE - zeropage x
            debug disassemble ~= "SRE";
            this.sre(getMem(Mem.ZEROPAGE_X));
            break;
        case 0x59: // (89) EOR - absolute y
            debug disassemble ~= "EOR";
            this.xor(getMem(Mem.ABSOLUTE_Y));
            break;
        case 0x5A: // (90) NOP - implied
            debug disassemble ~= "NOP"; 
            this.nop(null, UNOFFICAL);
            break;
        case 0x5B: // (91) SRE - absoulte y
            debug disassemble ~= "SRE";
            this.sre(getMem(Mem.ABSOLUTE_Y));
            break;
        case 0x5C: // (92) NOP - absolute x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ABSOLUTE_X), UNOFFICAL);
            break;
        case 0x5D: // (93) EOR - absolute X
            debug disassemble ~= "EOR";
            this.xor(getMem(Mem.ABSOLUTE_X));
            break;
        case 0x5E: // (94) LSR - absolute x
            debug disassemble ~= "LSR";
            this.shift(getMem(Mem.ABSOLUTE_X), RIGHT);
            break;
        case 0x5F: // (95) SRE - absolute x
            debug disassemble ~= "SRE";
            this.sre(getMem(Mem.ABSOLUTE_X));
            break;

        case 0x60: // (96) RTS - implied
            debug disassemble ~= "RTS";
            this.returnFromSubroutine();
            break;
        case 0x61: // (97) ADC - indirect x
            debug disassemble ~= "ADC";
            this.add(&this.A, getMem(Mem.INDIRECT_X));
            break;
        case 0x64: // (100) NOP - zero page
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ZEROPAGE), UNOFFICAL);
            break;
        case 0x65: // (101) ADC - zero page
            debug disassemble ~= "ADC";
            this.add(&this.A, getMem(Mem.ZEROPAGE));
            break;
        case 0x66: // (102) ROR - zero page
            debug disassemble ~= "ROR";
            this.rotate(getMem(Mem.ZEROPAGE), RIGHT);
            break;
        case 0x68: // (104) PLA - implied
            debug disassemble ~= "PLA";
            this.pop(&this.A);
            break;
        case 0x69: // (105) ADC - immediate
            debug disassemble ~= "ADC";
            this.add(&this.A, getMem(Mem.IMMEDIATE));
            break;
        case 0x6A: // (106) ROR - accumulator
            debug disassemble ~= "ROR A";
            this.rotate(&this.A, RIGHT);
            break;
        case 0x6C: // (108) JMP - indirect
            debug disassemble ~= "JMP";
            this.jump(Mem.INDIRECT);
            break;
        case 0x6D: // (109) ADC - absolute
            debug disassemble ~= "ADC";
            this.add(&this.A, getMem(Mem.ABSOLUTE));
            break;
        case 0x6E: // (110) ROR - absolute
            debug disassemble ~= "ROR";
            this.rotate(getMem(Mem.ABSOLUTE), RIGHT);
            break;

        case 0x70: // (112) BVS - relative
            debug disassemble ~= "BVS";
            this.branchIf(CC.OVERFLOW, /+isSet+/ true);
            break;
        case 0x71: // (113) ADC - indirect y
            debug disassemble ~= "ADC";
            this.add(&this.A, getMem(Mem.INDIRECT_Y));
            break;
        case 0x74: // (116) NOP - zero page x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ZEROPAGE_X), UNOFFICAL);
            break;
        case 0x75: // (117) ADC - zeropage x
            debug disassemble ~= "ADC";
            this.add(&this.A, getMem(Mem.ZEROPAGE_X));
            break;
        case 0x76: // (118) ROR - zeropage x
            debug disassemble ~= "ROR";
            this.rotate(getMem(Mem.ZEROPAGE_X), RIGHT);
            break;
        case 0x78: // (120) SEI - implied
            debug disassemble ~= "SEI";
            this.addMicroOp({ setStatus(CC.INTERRUPT, true); });
            break;
        case 0x79: // (121) ADC - absolute y
            debug disassemble ~= "ADC";
            this.add(&this.A, getMem(Mem.ABSOLUTE_Y));
            break;
        case 0x7A: // (122) NOP - implied
            debug disassemble ~= "NOP"; 
            this.nop(null, UNOFFICAL);
            break;
        case 0x7C: // (124) NOP - absolute x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ABSOLUTE_X), UNOFFICAL);
            break;
        case 0x7D: // (125) ADC - absolute x
            debug disassemble ~= "ADC";
            this.add(&this.A, getMem(Mem.ABSOLUTE_X));
            break;
        case 0x7E: // (126) ROR - absolute x
            debug disassemble ~= "ROR";
            this.rotate(getMem(Mem.ABSOLUTE_X), RIGHT);
            break;

        case 0x80: // (128) NOP - immediate
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.IMMEDIATE), UNOFFICAL);
            break;
        case 0x81: // (129) STA - indirect x
            debug disassemble ~= "STA";
            this.store(&this.A, getMem(Mem.INDIRECT_X));
            break;
        case 0x83: // (131) SAX - indirect x
            debug disassemble ~= "SAX";
            this.sax(getMem(Mem.INDIRECT_X));
            break;
        case 0x84: // (132) STY - zero page
            debug disassemble ~= "STY";
            this.store(&this.Y, getMem(Mem.ZEROPAGE));
            break;
        case 0x85: // (133) STA - zero page
            debug disassemble ~= "STA";
            this.store(&this.A, getMem(Mem.ZEROPAGE));
            break;
        case 0x86: // (134) STX - zero page
            debug disassemble ~= "STX";
            this.store(&this.X, getMem(Mem.ZEROPAGE));
            break;
        case 0x87: // (131) SAX - zero page
            debug disassemble ~= "SAX";
            this.sax(getMem(Mem.ZEROPAGE));
            break;
        case 0x88: // (136) DEY - implied
            debug disassemble ~= "DEY";
            this.increment(&this.Y, -1);
            break;
        case 0x8A: // (138) TXA - implied
            debug disassemble ~= "TXA";
            this.transfer(&this.X, &this.A);
            break;
        case 0x8C: // (140) STY - absolute
            debug disassemble ~= "STY";
            this.store(&this.Y, getMem(Mem.ABSOLUTE));
            break;
        case 0x8D: // (142) STA - absolute
            debug disassemble ~= "STA";
            this.store(&this.A, getMem(Mem.ABSOLUTE));
            break;
        case 0x8E: // (142) STX - absolute
            debug disassemble ~= "STX";
            this.store(&this.X, getMem(Mem.ABSOLUTE));
            break;
        case 0x8F: // (143) SAX - absolute
            debug disassemble ~= "SAX";
            this.sax(getMem(Mem.ABSOLUTE));
            break;

        case 0x90: // (144) BCC - relative
            debug disassemble ~= "BCC";
            this.branchIf(CC.CARRY, /+isSet+/ false);
            break;
        case 0x91: // (145) STA - indirect y
            debug disassemble ~= "STA";
            this.store(&this.A, getMem(Mem.INDIRECT_Y));
            break;
        case 0x94: // (148) STY - zeropage x
            debug disassemble ~= "STY";
            this.store(&this.Y, getMem(Mem.ZEROPAGE_X));
            break;
        case 0x95: // (149) STA - zeropage x
            debug disassemble ~= "STA";
            this.store(&this.A, getMem(Mem.ZEROPAGE_X));
            break;
        case 0x96: // (150) STX - zeropage y
            debug disassemble ~= "STX";
            this.store(&this.X, getMem(Mem.ZEROPAGE_Y));
            break;
        case 0x97: // (151) SAX - zeropage y
            debug disassemble ~= "SAX";
            this.sax(getMem(Mem.ZEROPAGE_Y));
            break;
        case 0x98: // (152) TYA - implied
            debug disassemble ~= "TYA";
            this.transfer(&this.Y, &this.A);
            break;
        case 0x99: // (153) STA - absolute y
            debug disassemble ~= "STA";
            this.store(&this.A, getMem(Mem.ABSOLUTE_Y));
            break;
        case 0x9A: // (154) TXS - implied
            debug disassemble ~= "TXS";
            this.addMicroOp({ this.sp = this.X; });
            break;
        case 0x9D: // (157) STA - absolute x
            debug disassemble ~= "STA";
            this.store(&this.A, getMem(Mem.ABSOLUTE_X));
            break;

        case 0xA0: // (160) LDY - immediate
            debug disassemble ~= "LDY";
            this.load(&this.Y, getMem(Mem.IMMEDIATE));
            break;
        case 0xA1: // (161) LDA - indirect x
            debug disassemble ~= "LDA";
            this.load(&this.A, getMem(Mem.INDIRECT_X));
            break;
        case 0xA2: // (162) LDX - immediate
            debug disassemble ~= "LDX";
            this.load(&this.X, getMem(Mem.IMMEDIATE));
            break;
        case 0xA3: // (163) LAX - indirect x
            debug disassemble ~= "LAX";
            this.lax(getMem(Mem.INDIRECT_X));
            break;
        case 0xA4: // (164) LDY - zero page
            debug disassemble ~= "LDY";
            this.load(&this.Y, getMem(Mem.ZEROPAGE));
            break;
        case 0xA5: // (165) LDA - zero page
            debug disassemble ~= "LDA";
            this.load(&this.A, getMem(Mem.ZEROPAGE));
            break;
        case 0xA6: // (166) LDX - zero page
            debug disassemble ~= "LDX";
            this.load(&this.X, getMem(Mem.ZEROPAGE));
            break;
        case 0xA7: // (167) LAX - zeropage
            debug disassemble ~= "LAX";
            this.lax(getMem(Mem.ZEROPAGE));
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
        case 0xAC: // (w172) LDY - absolute
            debug disassemble ~= "LDY";
            this.load(&this.Y, getMem(Mem.ABSOLUTE));
            break;
        case 0xAD: // (173) LDA - absolute
            debug disassemble ~= "LDA";
            this.load(&this.A, getMem(Mem.ABSOLUTE));
            break;
        case 0xAE: // (174) LDX - absolute
            debug disassemble ~= "LDX";
            this.load(&this.X, getMem(Mem.ABSOLUTE));
            break;
        case 0xAF: // (175) LAX - absolute
            debug disassemble ~= "LAX";
            this.lax(getMem(Mem.ABSOLUTE));
            break;

        case 0xB0: // (176) BCS - relative
            debug disassemble ~= "BCS";
            this.branchIf(CC.CARRY, /+isSet+/ true);
            break;
        case 0xB1: // (177) LDA - indirect y
            debug disassemble ~= "LDA";
            this.load(&this.A, getMem(Mem.INDIRECT_Y));
            break;
        case 0xB3: // (179) LAX - indirect y
            debug disassemble ~= "LAX";
            this.lax(getMem(Mem.INDIRECT_Y));
            break;
        case 0xB4: // (180) LDY - zeropage x
            debug disassemble ~= "LDY";
            this.load(&this.Y, getMem(Mem.ZEROPAGE_X));
            break;
        case 0xB5: // (181) LDA - zeropage x
            debug disassemble ~= "LDA";
            this.load(&this.A, getMem(Mem.ZEROPAGE_X));
            break;
        case 0xB6: // (182) LDX - zeropage x
            debug disassemble ~= "LDX";
            this.load(&this.X, getMem(Mem.ZEROPAGE_Y));
            break;
        case 0xB7: // (183) LAX - zeropage y
            debug disassemble ~= "LAX";
            this.lax(getMem(Mem.ZEROPAGE_Y));
            break;
        case 0xB8: // (184) CLV - implied
            debug disassemble ~= "CLV";
            this.addMicroOp({ setStatus(CC.OVERFLOW, false); });
            break;
        case 0xB9: // (185) LDA - absolute y
            debug disassemble ~= "LDA";
            this.load(&this.A, getMem(Mem.ABSOLUTE_Y));
            break;
        case 0xBA: // (186) TSX - implied
            debug disassemble ~= "TSX";
            this.transfer(&this.sp, &this.X);
            break;
        case 0xBC: // (188) LDY - absolute x
            debug disassemble ~= "LDY";
            this.load(&this.Y, getMem(Mem.ABSOLUTE_X));
            break;
        case 0xBD: // (189) LDA - absolute x
            debug disassemble ~= "LDA";
            this.load(&this.A, getMem(Mem.ABSOLUTE_X));
            break;
        case 0xBE: // (190) LDX - absolute y
            debug disassemble ~= "LDX";
            this.load(&this.X, getMem(Mem.ABSOLUTE_Y));
            break;
        case 0xBF: // (191) LAX - absolute y
            debug disassemble ~= "LAX";
            this.lax(getMem(Mem.ABSOLUTE_Y));
            break;

        case 0xC0: // (192) CPY - immediate
            debug disassemble ~= "CPY";
            this.compare(&this.Y, getMem(Mem.IMMEDIATE));
            break;
        case 0xC1: // (193) CMP - indirect x
            debug disassemble ~= "CMP";
            this.compare(&this.A, getMem(Mem.INDIRECT_X));
            break;
        case 0xC3: // (195) DCP - indirect x
            debug disassemble ~= "DCP";
            this.dcp(getMem(Mem.INDIRECT_X));
            break;
        case 0xC4: // (192) CPY - zero page
            debug disassemble ~= "CPY";
            this.compare(&this.Y, getMem(Mem.ZEROPAGE));
            break;
        case 0xC5: // (197) CMP - zero page
            debug disassemble ~= "CMP";
            this.compare(&this.A, getMem(Mem.ZEROPAGE));
            break;
        case 0xC6: // (198) DEC - zero page
            debug disassemble ~= "DEC";
            this.increment(getMem(Mem.ZEROPAGE), -1);
            break;
        case 0xC7: // (199) DCP - zeropage
            debug disassemble ~= "DCP";
            this.dcp(getMem(Mem.ZEROPAGE));
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
        case 0xCC: // (204) CPY - absolute
            debug disassemble ~= "CPY";
            this.compare(&this.Y, getMem(Mem.ABSOLUTE));
            break;
        case 0xCD: // (205) CMP - absolute
            debug disassemble ~= "CMP";
            this.compare(&this.A, getMem(Mem.ABSOLUTE));
            break;
        case 0xCE: // (206) DEC - absolute
            debug disassemble ~= "DEC";
            this.increment(getMem(Mem.ABSOLUTE), -1);
            break;
        case 0xCF: // (207) DCP - absolute
            debug disassemble ~= "DCP";
            this.dcp(getMem(Mem.ABSOLUTE));
            break;

        case 0xD0: // (208) BNE - relative
            debug disassemble ~= "BNE";
            this.branchIf(CC.ZERO, /+isSet+/ false);
            break;
        case 0xD1: // (209) CMP - indirect y
            debug disassemble ~= "CMP";
            this.compare(&this.A, getMem(Mem.INDIRECT_Y));
            break;
        case 0xD3: // (211) DCP - indirect y
            debug disassemble ~= "DCP";
            this.dcp(getMem(Mem.INDIRECT_Y));
            break;
        case 0xD4: // (212) NOP - zero page x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ZEROPAGE_X), UNOFFICAL);
            break;
        case 0xD5: // (213) CMP - zeropage x
            debug disassemble ~= "CMP";
            this.compare(&this.A, getMem(Mem.ZEROPAGE_X));
            break;
        case 0xD6: // (214) DEC - zeropage x
            debug disassemble ~= "DEC";
            this.increment(getMem(Mem.ZEROPAGE_X), -1);
            break;
        case 0xD7: // (215) DCP - zeropage x
            debug disassemble ~= "DCP";
            this.dcp(getMem(Mem.ZEROPAGE_X));
            break;
        case 0xD8: // (216) CLD - implied
            debug disassemble ~= "CLD";
            this.addMicroOp({ setStatus(CC.DECIMAL, false); });
            break;
        case 0xD9: // (217) CMP - absolute y
            debug disassemble ~= "CMP";
            this.compare(&this.A, getMem(Mem.ABSOLUTE_Y));
            break;
        case 0xDA: // (218) NOP - implied
            debug disassemble ~= "NOP"; 
            this.nop(null, UNOFFICAL);
            break;
        case 0xDB: // (219) DCP - absolute y
            debug disassemble ~= "DCP";
            this.dcp(getMem(Mem.ABSOLUTE_Y));
            break;
        case 0xDC: // (220) NOP - absolute x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ABSOLUTE_X), UNOFFICAL);
            break;
        case 0xDD: // (221) CMP - absolute x
            debug disassemble ~= "CMP";
            this.compare(&this.A, getMem(Mem.ABSOLUTE_X));
            break;
        case 0xDE: // (222) DEC - absolute x
            debug disassemble ~= "DEC";
            this.increment(getMem(Mem.ABSOLUTE_X), -1);
            break;
        case 0xDF: // (223) DCP - absolute x
            debug disassemble ~= "DCP";
            this.dcp(getMem(Mem.ABSOLUTE_X));
            break;

        case 0xE0: // (224) CPX - immediate
            debug disassemble ~= "CPX";
            this.compare(&this.X, getMem(Mem.IMMEDIATE));
            break;
        case 0xE1: // (225) SBC - indirect x
            debug disassemble ~= "SBC";
            this.subtract(&this.A, getMem(Mem.INDIRECT_X));
            break;
        case 0xE3: // (227) ISB - indirect x
            debug disassemble ~= "ISB";
            this.isb(getMem(Mem.INDIRECT_X));
            break;
        case 0xE4: // (228) CPX - zero page
            debug disassemble ~= "CPX";
            this.compare(&this.X, getMem(Mem.ZEROPAGE));
            break;
        case 0xE5: // (229) SBC - zero page
            debug disassemble ~= "SBC";
            this.subtract(&this.A, getMem(Mem.ZEROPAGE));
            break;
        case 0xE6: // (230) INC - zero page
            debug disassemble ~= "INC";
            this.increment(getMem(Mem.ZEROPAGE), 1);
            break;
        case 0xE7: // (231) ISB - zero page
            debug disassemble ~= "ISB";
            this.isb(getMem(Mem.ZEROPAGE));
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
            this.nop(null, OFFICAL);
            break;
        case 0xEB: // (233) SBC - immediate
            debug disassemble ~= "SBC"; debug predisassemble ~= "*";
            this.subtract(&this.A, getMem(Mem.IMMEDIATE));
            break;
        case 0xEC: // (228) CPX - absolute
            debug disassemble ~= "CPX";
            this.compare(&this.X, getMem(Mem.ABSOLUTE));
            break;
        case 0xED: // (237) SBC - absolute
            debug disassemble ~= "SBC";
            this.subtract(&this.A, getMem(Mem.ABSOLUTE));
            break;
        case 0xEE: // (238) INC - absolute
            debug disassemble ~= "INC";
            this.increment(getMem(Mem.ABSOLUTE), 1);
            break;
        case 0xEF: // (239) ISB - absolute
            debug disassemble ~= "ISB";
            this.isb(getMem(Mem.ABSOLUTE));
            break;

        case 0xF0: // (240) BEQ - relative
            debug disassemble ~= "BEQ";
            this.branchIf(CC.ZERO, /+isSet+/ true);
            break;
        case 0xF1: // (241) SBC - indirect y
            debug disassemble ~= "SBC";
            this.subtract(&this.A, getMem(Mem.INDIRECT_Y));
            break;
        case 0xF3: // (243) ISB - indirect y
            debug disassemble ~= "ISB";
            this.isb(getMem(Mem.INDIRECT_Y));
            break;
        case 0xF4: // (244) NOP - zero page x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ZEROPAGE_X), UNOFFICAL);
            break;
        case 0xF5: // (245) SBC - zeropage x
            debug disassemble ~= "SBC";
            this.subtract(&this.A, getMem(Mem.ZEROPAGE_X));
            break;
        case 0xF6: // (246) INC - zeropage x
            debug disassemble ~= "INC";
            this.increment(getMem(Mem.ZEROPAGE_X), 1);
            break;
        case 0xF7: // (247) ISB - zeropage x
            debug disassemble ~= "ISB";
            this.isb(getMem(Mem.ZEROPAGE_X));
            break;
        case 0xF8: // (248) SED - relative
            debug disassemble ~= "SED";
            this.addMicroOp({ setStatus(CC.DECIMAL, true); });
            break;
        case 0xF9: // (249) SBC - absolute y
            debug disassemble ~= "SBC";
            this.subtract(&this.A, getMem(Mem.ABSOLUTE_Y));
            break;
        case 0xFA: // (250) NOP - implied
            debug disassemble ~= "NOP"; 
            this.nop(null, UNOFFICAL);
            break;
        case 0xFB: // (251) ISB - absolute y
            debug disassemble ~= "ISB";
            this.isb(getMem(Mem.ABSOLUTE_Y));
            break;
        case 0xFC: // (252) NOP - absolute x
            debug disassemble ~= "NOP"; 
            this.nop(getMem(Mem.ABSOLUTE_X), UNOFFICAL);
            break;
        case 0xFD: // (253) SBC - absolute x
            debug disassemble ~= "SBC";
            this.subtract(&this.A, getMem(Mem.ABSOLUTE_X));
            break;
        case 0xFE: // (254) INC - absolute x
            debug disassemble ~= "INC";
            this.increment(getMem(Mem.ABSOLUTE_X), 1);
            break;
        case 0xFF: // (255) ISB - absolute x
            debug disassemble ~= "ISB";
            this.isb(getMem(Mem.ABSOLUTE_X));
            break;

        default:
            writef("Unimplemented Instruction: 0x%X(%d). PC: %X\n", op, op, this.pc - 1);
            writeln(this);

            assert(0);
        }
    }
    // }}}

    // Opcode helpers {{{
    // UNOFFICAL INSTRUCTIONS
    void lax(ubyte* mem){
        debug predisassemble ~= "*";
        this.addMicroOp({ setZeroNegIf(this.A = this.X = *mem); });
    }

    void sax(ubyte* mem){
        debug predisassemble ~= "*";
        this.addMicroOp({  *mem = (this.A & this.X); });
    }

    void dcp(ubyte* mem){
        debug predisassemble ~= "*";
        this.increment(mem, -1);
        this.compare(&this.A, mem);

        // increment and compare occur at the same time, so do one more op
        // TODO: make them acctually occur at the same time, as opposed to doing an extra op after
        this.addMicroOp({ this.noMicroOp(); this.noMicroOp(); });
    }

    void isb(ubyte* mem){
        debug predisassemble ~= "*";
        this.increment(mem, 1);
        this.subtract(&this.A, mem);

        this.addMicroOp({ this.setStatus(CC.OVERFLOW, false); });
        this.joinLastMicroOp();
        this.joinLastMicroOp();
    }

    void slo(ubyte* mem){
        debug predisassemble ~= "*";
        this.shift(mem, LEFT);
        this.or(mem);

        this.joinLastMicroOp();
    }

    void rla(ubyte* mem){
        debug predisassemble ~= "*";
        this.rotate(mem, LEFT);
        this.and(mem);

        this.joinLastMicroOp();
    }

    void sre(ubyte* mem){
        debug predisassemble ~= "*";
        this.shift(mem, RIGHT);
        this.xor(mem);

        this.joinLastMicroOp();
    }

    // END UNOFFICAL INSTRUCTIONS
    void nop(ubyte* mem, bool isOffical){
        debug {
            if(!isOffical)
                predisassemble ~= "*";
        }
        this.addMicroOp({  });
    }

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

    void testBitInMemoryWithAccumulator(ubyte* mem) {
        this.addMicroOp({
            ubyte val = *mem;
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
        case Mem.INDIRECT:
            ubyte low = *system.access(this.pc);
            ubyte high = *system.access(cast(ushort)(this.pc + 1));
            ushort tot = low | (high << 8);
            ushort fin = *system.access(tot) | (
                    *system.access((0xFF00 & tot) | cast(ubyte)((tot & 0xFF) + 1)) << 8);
            debug {
                disassemble ~= format(" ($%.2X%.2X) = %.4X", high, low, fin);
            }
            this.addMicroOp({ this.nextOp(); });
            this.addMicroOp({ this.nextOp(); });
            this.addMicroOp({  });
            this.addMicroOp({ this.pc = fin; });
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

    void rotate(ubyte* mem, bool left) { // left is negative
        rotateOrShift(mem, left, /+useCarry+/ true);
    }

    void shift(ubyte* mem, bool left) { // left is negative
        rotateOrShift(mem, left, /+useCarry+/ false);
    }

    void rotateOrShift(ubyte* mem, bool left, bool useCarry) {
        if (!isRegister(mem)) {
            this.addMicroOp({  });
            this.addMicroOp({  });
        }
        this.addMicroOp({
            if (left) {
                ubyte tmp = useCarry ? getStatus() & 1 : 0;
                setStatus(CC.CARRY, cast(bool)(*mem & 0x80));
                setZeroNegIf(*mem = cast(ubyte)((*mem << 1) | tmp));
            }
            else {
                ubyte tmp = useCarry ? ((getStatus() & 1) << 7) : 0;
                setStatus(CC.CARRY, cast(bool)(*mem & 1));
                setZeroNegIf(*mem = cast(ubyte)((*mem >> 1) | tmp));
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
        if (!isRegister(loc)) {
            this.addMicroOp({  });
            this.addMicroOp({  });
        }
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
        byte disp;
        ushort og_pc;
        bool shouldJump;

        debug disassemble ~= format(" $%.4X", (cast(byte)*system.access(pc)+pc+1));
        this.addMicroOp({
            disp = cast(byte)nextOp();
            og_pc = pc;
            shouldJump = this.getStatus(flag) == ifSet;
        });
        this.addMicroOp({
            if (shouldJump) {
                pc = ((pc & 0xFF) + disp) | (pc & 0xFF00);
            }
            else {
                this.noMicroOp();
            }
        });
        this.addMicroOp({
            if ((0xFF00 & og_pc) == (0xFF00 & pc) || !shouldJump) {
                this.noMicroOp();
            }
        });
    }

    ubyte* getMem(Mem type) {
        final switch (type) {
        case Mem.IMMEDIATE:
            debug disassemble ~= " #$" ~ format("%.2X", (*system.access(this.pc)));
            this.addMicroOp({ this.R = nextOp(); this.noMicroOp(); });
            return &R;

        case Mem.ZEROPAGE:
            ushort addr = nextOp();
            this.addMicroOp({  });
            debug disassemble ~= " $" ~ format("%.2X = %.2X", addr, *system.access(addr));
            return this.system.access(addr);
        case Mem.ZEROPAGE_X:
            ubyte addr = nextOp();
            this.addMicroOp({  });
            addr += this.X;
            this.addMicroOp({  });
            debug disassemble ~= format(" $%.2X,X @ %.2X = %.2X",
                    cast(ubyte)(addr - this.X), addr, *system.access(addr));
            return this.system.access(addr);
        case Mem.ZEROPAGE_Y:
            ubyte addr = nextOp();
            this.addMicroOp({  });
            addr += this.Y;
            this.addMicroOp({  });
            debug disassemble ~= format(" $%.2X,Y @ %.2X = %.2X",
                    cast(ubyte)(addr - this.Y), addr, *system.access(addr));
            return this.system.access(addr);

        case Mem.ABSOLUTE:
            return getAbsoluteMem(null);
        case Mem.ABSOLUTE_X:
            return getAbsoluteMem(&this.X);
        case Mem.ABSOLUTE_Y:
            return getAbsoluteMem(&this.Y);

        case Mem.INDIRECT_X:
            ubyte low = nextOp();
            this.addMicroOp({  });
            ubyte preaddr = cast(ubyte)(low + this.X);
            this.addMicroOp({  });
            ushort addr = *system.access(preaddr) | (*system.access(++preaddr) << 8);
            this.addMicroOp({  });
            this.addMicroOp({  });
            debug {
                disassemble ~= format(" ($%.2X,X) @ %.2X = %.4X = %.2X", low,
                        --preaddr, addr, *system.access(addr));
            }
            return this.system.access(addr);

        case Mem.INDIRECT_Y:
            ubyte low = nextOp();
            this.addMicroOp({  });
            ushort addr = cast(ushort)((*system.access(low) | (*system.access(++low) << 8)) + this
                    .Y);
            this.addMicroOp({  });
            this.addMicroOp({  });
            if (this.Y + ((addr - this.Y) & 0xFF) > 0xFF // extra op if page cross
                 || disassemble == "STA") { // XXX: bad hack
                this.addMicroOp({  });
            }
            debug {
                disassemble ~= format(" ($%.2X),Y = %.4X @ %.4X = %.2X", --low,
                        cast(ushort)(addr - this.Y), addr, *system.access(addr));
            }
            return this.system.access(addr);

        case Mem.INDIRECT:
            assert(0); // unimplemented
        }
    }

    bool isWriteInstruct() {
        return (disassemble == "STA" || disassemble == "LSR" || disassemble == "ASL"
                || disassemble == "ROL" || disassemble == "ROR"
                || disassemble == "DEC" || disassemble == "INC");
    }

    ubyte* getAbsoluteMem(ubyte* offset_loc) {
        int offset;
        if (offset_loc == null) {
            offset = 0;
        }
        else {
            offset = *offset_loc;
        }
        ubyte low = nextOp();
        this.addMicroOp({  });
        ubyte high = nextOp();
        ushort addr = low | (high << 8);
        if (((addr + offset) & 0xFF00) != (addr & 0xFF00) || (isWriteInstruct() && offset_loc != null)) { // XXX: bad hack
            this.addMicroOp({  });
        }
        addr += offset;
        this.addMicroOp({  });
        debug {
            if (offset_loc == null) {
                disassemble ~= format(" $%.4X = %.2X", addr, *system.access(addr));
            }
            else {
                string var = offset_loc == &this.X ? "X" : "Y";
                disassemble ~= format(" $%.4X,%s @ %.4X = %.2X",
                        cast(ushort)(addr - offset), var, addr, *system.access(addr));
            }
        }
        return this.system.access(addr);

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

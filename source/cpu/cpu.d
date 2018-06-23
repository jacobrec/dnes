module cpu.cpu;
import nes;

import std.stdio : writeln, writef;
import std.format: format;
import std.conv : text, to;
import std.container : DList;

// CPU {{{
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
    enum Mem {
        IMMEDIATE,
        ABSOLUTE,
    }

    ushort pc; // The program counter
    ubyte sp; // The stack pointer

    ulong cycles; // Consumed cpu cycles

    ubyte[800] ram;

    NES system;

    DList!(void delegate()) opline;

    this(NES system) {
        this.system = system;
    }

    void addMicroOp(void delegate() op) {
        this.opline.insertBack(op);
    }

    void doMicroOp() {
        this.opline.front()();
        this.opline.removeFront();
        this.cycles++;
    }

    bool hasMicroOp() {
        return !this.opline.empty;
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
        this.pc = 0;
        this.sp = 255;

        //TODO: make this an interrupt
        this.pc = read16(system.access(0xFFFC));
        this.pc = 0xC000;
        writef("Starting at: 0x%X\n", this.pc);
    }

    void tick() {
        if (!this.hasMicroOp()) {
            this.addMicroOp({ this.readInstruction(); });
        }
        this.doMicroOp();
    }

    ubyte nextOp(){
        debug ops ~= format("%.2X ", *system.access(this.pc));
        return *system.access(this.pc++);
    }

    bool first = true;
    string regs;
    string ops;
    string disassemble;
    void readInstruction() {
        debug{
            if(!first){
                writef(rightPad(ops, 10));
                writef(rightPad(disassemble, 32));
                writef(regs);
            }
            regs = format("A:%.2X X:%.2X Y:%.2X P:%.2X SP:%.2X CYC:%3d\n", A, X, Y, CCR, sp, cycles*3);
            first = false;
            ops = "";
            disassemble = "";
            writef("%X  ", this.pc);
        }
        ubyte op = nextOp();



        switch (op) {
        case 0x4C: // (76) JMP #addr
            debug disassemble ~= "JMP";
            this.jump(Mem.IMMEDIATE);
            break;
        case 0x78: // (120) SEI
            debug disassemble ~= "SEI";
            this.addMicroOp({ setStatus(CC.INTERRUPT, true); });
            break;
        case 0x9A: // (154) TXS
            debug disassemble ~= "TXS";
            this.addMicroOp({ this.sp = this.X; });
            break;
        case 0xA2: // (162) LDX #Oper
            debug disassemble ~= "LDX";
            this.load(&this.X, Mem.IMMEDIATE);
            break;
        case 0xA9: // (169) LDA #Oper
            debug disassemble ~= "LDA";
            this.load(&this.A, Mem.IMMEDIATE);
            break;
        case 0xAD: // (173) LDA absolute
            debug disassemble ~= "LDA";
            this.load(&this.A, Mem.ABSOLUTE);
            break;
        case 0xD8: // (216) CLD
            debug disassemble ~= "CLD";
            this.addMicroOp({ setStatus(CC.DECIMAL, false); });
            break;
        default:
            writef("Unimplemented Instruction: 0x%X. PC: %X\n", op, this.pc-1);
            writeln(this);

            assert(0);
        }
    }

    // Opcode helpers {{{
    bool getStatus(CC flag) {
        return cast(bool)(this.CCR & (1 << (cast(int) flag)));
    }

    void setStatus(CC flag, bool status) {
        this.CCR ^= (-(cast(int) status) ^ this.CCR) & (1 << flag);
        this.CCR |= 0b00100000;
    }

    void jump(Mem type){
        final switch(type){
            case Mem.IMMEDIATE:
                debug disassemble ~= " #$" ~ format("%.2X%.2X", 
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
                this.addMicroOp({ this.pc |= *this.system.access(addr); });
                break;
        }
    }

    void load(ubyte* loc, Mem type){
        final switch(type){
            case Mem.IMMEDIATE:
                debug disassemble ~= " #$" ~ format("%.2X", (*system.access(this.pc)));
                this.addMicroOp({ *loc = nextOp(); });
                break;
            case Mem.ABSOLUTE:
                ushort addr = 0;
                debug disassemble ~= " $" ~ format("%.2X%.2X", 
                        (*system.access(cast(ushort)(this.pc + 1))), (*system.access(this.pc)));
                this.addMicroOp({ addr |= nextOp(); });
                this.addMicroOp({ addr |= (nextOp() << 8); });
                this.addMicroOp({ *loc |= *this.system.access(addr); });
                break;
        }
    }

    // }}}

    // Instructions {{{
    //     ADC   Add Memory to Accumulator with Carry
    //     AND   "AND" Memory with Accumulator
    //     ASL   Shift Left One Bit (Memory or Accumulator)
    //
    //     BCC   Branch on Carry Clear
    //     BCS   Branch on Carry Set
    //     BEQ   Branch on Result Zero
    //     BIT   Test Bits in Memory with Accumulator
    //     BMI   Branch on Result Minus
    //     BNE   Branch on Result not Zero
    //     BPL   Branch on Result Plus
    //     BRK   Force Break
    //     BVC   Branch on Overflow Clear
    //     BVS   Branch on Overflow Set
    //
    //     CLC   Clear Carry Flag
    //     CLD   Clear Decimal Mode
    //     CLI   Clear interrupt Disable Bit
    //     CLV   Clear Overflow Flag
    //     CMP   Compare Memory and Accumulator
    //     CPX   Compare Memory and Index X
    //     CPY   Compare Memory and Index Y
    //
    //     DEC   Decrement Memory by One
    //     DEX   Decrement Index X by One
    //     DEY   Decrement Index Y by One
    //
    //     EOR   "Exclusive-Or" Memory with Accumulator
    //
    //     INC   Increment Memory by One
    //     INX   Increment Index X by One
    //     INY   Increment Index Y by One
    //
    //     JMP   Jump to New Location
    //     JSR   Jump to New Location Saving Return Address                 
    //                                                                      
    //     LDA   Load Accumulator with Memory                               
    //     LDX   Load Index X with Memory                                   
    //     LDY   Load Index Y with Memory                                   
    //     LSR   Shift Right One Bit (Memory or Accumulator)                
    //                                                                      
    //     NOP   No Operation                                               
    //                                                                      
    //     ORA   "OR" Memory with Accumulator                               
    //                                                                      
    //     PHA   Push Accumulator on Stack                                  
    //     PHP   Push Processor Status on Stack                             
    //     PLA   Pull Accumulator from Stack                                
    //     PLP   Pull Processor Status from Stack                           
    //                                                                      
    //     ROL   Rotate One Bit Left (Memory or Accumulator)                
    //     ROR   Rotate One Bit Right (Memory or Accumulator)               
    //     RTI   Return from Interrupt                                      
    //     RTS   Return from Subroutine                                     
    //                                                                      
    //     SBC   Subtract Memory from Accumulator with Borrow               
    //     SEC   Set Carry Flag                                             
    //     SED   Set Decimal Mode                                           
    //     SEI   Set Interrupt Disable Status                               
    //     STA   Store Accumulator in Memory                                
    //     STX   Store Index X in Memory                                    
    //     STY   Store Index Y in Memory                                    
    //                                                                      
    //     TAX   Transfer Accumulator to Index X                            
    //     TAY   Transfer Accumulator to Index Y                            
    //     TSX   Transfer Stack Pointer to Index X                          
    //     TXA   Transfer Index X to Accumulator                            
    //     TXS   Transfer Index X to Stack Pointer                          
    //     TYA   Transfer Index Y to Accumulator                            

    // }}}
}
// }}}

string rightPad(string inp, int len){
    return (inp ~ "                                      ")[0..len];
}

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

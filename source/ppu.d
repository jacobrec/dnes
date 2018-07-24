module ppu;

import nes;
import cartridge.cartridge;

import std.stdio : writeln, writef;
import std.format : format;
import std.conv : text, to;
import std.bitmanip: bitfields;

struct Control{
    ubyte data;

    ubyte nametableAddr(){ return (data & 0b11) != 0; }
    bool isWideMode(){ return (data & 0x4) != 0; }
    bool isSpriteHigh(){ return (data & 0x8) != 0; }
    bool isBackgroundHigh(){ return (data & 0x10) != 0; }
    bool isSpriteTall(){ return (data & 0x20) != 0; }
    //bool unused(){ return (data & 0x40) != 0; }
    bool shouldInterrupt(){ return (data & 0x80) != 0; }
}

struct Mask{
    ubyte data;

    bool isGreyscale(){ return (data & 0x1) != 0; }
    bool isFullBackgroud(){ return (data & 0x2) != 0; }
    bool isFullSprites(){ return (data & 0x4) != 0; }
    bool isBackground(){ return (data & 0x8) != 0; }
    bool isSprites(){ return (data & 0x10) != 0; }
    bool isRed(){ return (data & 0x20) != 0; }
    bool isGreen(){ return (data & 0x40) != 0; }
    bool isBlue(){ return (data & 0x80) != 0; }
}

struct Status{
    ubyte data;

    // bool unused(){ return (data & 0x1) != 0; }
    // bool unused(){ return (data & 0x2) != 0; }
    // bool unused(){ return (data & 0x4) != 0; }
    // bool unused(){ return (data & 0x8) != 0; }
    bool isIgnoringWrites(){ return (data & 0x10) != 0; }
    bool isTooManySprites(){ return (data & 0x20) != 0; }
    bool isSprite0Hit(){ return (data & 0x40) != 0; }
    bool isVBlank(){ return (data & 0x80) != 0; }
    void setVBlank(bool on){ data ^= (-cast(int)(on) ^ data) & (0x80); }
}
struct Sprite{
    ubyte y;
    ubyte pattern;
    ubyte attr;
    ubyte x;

    ubyte colorTop() { return attr & 0b11; }
    bool  isOverBackground() { return (attr & 0b100000) != 0; }
    bool  isFlipX() { return (attr & 0b1000000) != 0; }
    bool  isFlipY() { return (attr & 0b10000000) != 0; }
}

class PPU {
    ubyte[240][256] screen; // rows by columns
    ushort scanline; // which scanline the scanline is on

    ubyte[0x800] nametables;
    ubyte[0x20] palettes; // sprite pallette is upper 0x10
    ubyte[0x100] sprite_mem;
    ubyte sprite_addr;

    ushort mem_addr;
    ubyte mem_addr_high;
    ubyte mem_addr_low;
    bool first_mem_write;

    Control control;
    Mask mask;
    Status status;

    ubyte R; // status read only
    ubyte scroll; // unimplemented

    NES system;
    this(NES system) {
        this.system = system;
        for(int i = 0; i < 256; i++){
            for(int j = 0; j < 240; j++){
                screen[i][j] = 63; // blacks out screen to start
            }
        }
    }

    // loc is the ppu address space
    ubyte* access(ushort loc) {
        loc %= 0x4000;
        if(loc < 0x2000){
            return cast(ubyte*)this.system.cartridge.mapper.accessCHR(loc);
        }else if(loc < 0x3F00){
            return this.through_mirror(loc);
        } else if(loc < 0x4000){
            return &this.palettes[loc % 0x20];
        }
        assert(0);
    }

    ubyte* through_mirror(ushort loc){
        loc -= 0x2000;
        if(this.system.cartridge.mode == MirroringMode.Horizontal){
            return &this.nametables[((loc / 2) & 0x400) + (loc % 0x400)];
        }
        else if(this.system.cartridge.mode == MirroringMode.Vertical){
            return &this.nametables[loc % 800];
        }
        else{
            return null;
        }
    }

    // loc is in the cpu address space, this
    // function is for the cpu to access the ppu
    // control and status registers.
    ubyte* accessMem(ushort loc) {
        switch (loc) {
        case 0: // 0x2000
            return &control.data;
        case 1: // 0x2001
            return &mask.data;
        case 2: // 0x2002
            R = status.data;
            status.setVBlank(false);
            return &R;
        case 3: // 0x2003
            return &sprite_addr;
        case 4: // 0x2004
            return &this.sprite_mem[sprite_addr];
        case 5: // 0x2005
            return &scroll;
        case 6: // 0x2006
            first_mem_write = !first_mem_write;
            if(!first_mem_write){
                return &mem_addr_low;
            }else{
                return &mem_addr_high;
            }
        case 7: // 0x2007
            mem_addr = (mem_addr_high << 8) | mem_addr_low;
            return access(mem_addr);
        default:
            writeln("this should be impossible");
        }
        assert(0);
    }

    void step(){ // one scanscanline
        int row = scanline-21;
    }

    void tick() {
        scanline++;

        if (scanline < 20) {
            // VINT
        }
        else if (scanline == 21) {
            // Renders dummy scanline
            step();
        }
        else if (scanline < 260) {
            // Actual render
        }
        else {
            status.setVBlank(true);
            scanline = 0;
        }
    }
}

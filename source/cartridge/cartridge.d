module cartridge.cartridge;

import std.file: exists, read;
import std.conv: text;
import std.stdio: writeln;

import cartridge.mapper0;

immutable int KB = 1024;
class Cartridge{
    const(ubyte)[][] CHRs;
    const(ubyte)[][] PRGs;
    const(ubyte)[][] RAMs;
    const(ubyte)[] trainer;
    Mapper mapper;

    void createMapper(int num){
        switch(num){
            case 0:
                this.mapper = new Mapper0(this);
                break;
            default:
                assert(0); // Unsupported mapper
        }
    }

    override const string toString(){
        return text("Cartridge(PRG:", this.PRGs.length, "|CHR:", this.CHRs.length,
                "|RAM:", this.RAMs.length, "|Trainer:", trainer.length, ")");
    }
}

abstract class Mapper{
    abstract const(ubyte*) access(ushort loc);
}

enum MirroringMode { Vertical, Horizontal, FourScreen }

struct INESformat{
    ubyte PRG_bankNum; // Number of 16KB PRG-ROM banks
    ubyte CHR_bankNum; // Number of 8KB CHR-ROM banks. Also known as VROM

    ubyte mapperNumber; // from both rom control bytes

    bool hasTrainer;    // if there is a 512 byte trainer at 0x7000-0x71FF
    bool hasBBRAM;      // If it has battey backed ram at 0x6000-0x7FFF
    MirroringMode mode; // Which mode 

    ubyte RAM_bankNum; // Number of 8KB RAM banks. Assume 1 if this is 0
}

Cartridge loadROM(string filepath){
    assert(exists(filepath));
    auto bytes = cast(const(ubyte)[]) read(filepath);
    INESformat ines = verifyAndParseINES(bytes);

    /+
        Following the header is the 512-byte trainer, if one is present, otherwise the ROM banks
        begin here, starting with PRG-ROM then CHR-ROM. The format allows for up to 256
        different memory mappers. Each mapper is assigned a specific number and the mapper
        number can be obtained by shifting bits 4-7 of control byte 2 to the left by 4 bits and then
        adding the bits 4-7 of control byte 1. 
     +/


    int index = 16;
    const(ubyte)[] getBytes(int num_bytes){
        index += num_bytes;
        return bytes[index-num_bytes..index];
    }

    Cartridge c = new Cartridge();
    if(ines.hasTrainer){
        c.trainer = getBytes(512);
    }
    for(int i = 0; i < ines.PRG_bankNum; i++){
        c.PRGs ~= getBytes(16*KB);
    }
    for(int i = 0; i < ines.CHR_bankNum; i++){
        c.CHRs ~= getBytes(8*KB);
    }
    if(ines.RAM_bankNum == 0){
        ines.RAM_bankNum++;
    }
    for(int i = 0; i < ines.RAM_bankNum; i++){
        c.RAMs ~= new ubyte[8*KB];
    }

    c.createMapper(ines.mapperNumber);

    return c;

}

INESformat verifyAndParseINES(const(ubyte)[] bytes){
    assert(bytes[0] == 'N');
    assert(bytes[1] == 'E');
    assert(bytes[2] == 'S');
    assert(bytes[3] == 0x1A);
    INESformat ines;

    ines.PRG_bankNum = bytes[4];
    ines.CHR_bankNum = bytes[5];
    ines.RAM_bankNum = bytes[8];


    ines.mapperNumber = ((0xF0 & bytes[6]) >> 4) | (bytes[7] & 0x0F);

    ines.hasTrainer = cast(bool) (bytes[6] & 0b0000_0100);
    ines.hasBBRAM = cast(bool) (bytes[6] & 0b0000_0010);

    if(bytes[6] & 0b0000_1000){
        ines.mode = MirroringMode.FourScreen;
    }else{
        if(bytes[6] & 0b0000_0001){
            ines.mode = MirroringMode.Vertical;
        }else{
            ines.mode = MirroringMode.Horizontal;
        }
    }


    assert(!(bytes[7] & 0xFF));

    for(int i = 9; i < 16; i++){
        assert(!bytes[i]);
    }

    return ines;
}

unittest{
    // Header parsing test
    INESformat ines = verifyAndParseINES(cast(const(ubyte)[]) read("roms/cartridge_test.nes"));
    assert(ines.PRG_bankNum == 16);
    assert(ines.CHR_bankNum == 0);
    assert(ines.RAM_bankNum == 0);

    assert(!ines.hasTrainer);
    assert(!ines.hasBBRAM);

    assert(ines.mode == MirroringMode.Horizontal);
    assert(ines.mapperNumber == 1);
}

unittest{
    // Cartidge sizes test
    Cartridge cart = loadROM("roms/cartridge_test.nes"); 

    assert(cart.PRGs.length == 16);
    assert(cart.CHRs.length == 0);
    assert(cart.RAMs.length == 1);
    assert(cart.trainer.length == 0);
}



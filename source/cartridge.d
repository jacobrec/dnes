module cartridge;

import std.file: exists, read;
import std.stdio: writeln;

class Cartridge{

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
    verifyAndParseINES(cast(const(ubyte)[]) read(filepath));

    Cartridge c;

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

    ubyte ctrl_1 = bytes[6];
    ubyte ctrl_2 = bytes[7];

    ines.mapperNumber = ((0xFF00 & ctrl_1) >> 4) | (ctrl_2 & 0xFF00);

    ines.hasTrainer = cast(bool) (ctrl_1 & 0b0000_0100);
    ines.hasBBRAM = cast(bool) (ctrl_1 & 0b0000_0010);

    if(ctrl_1 & 0b0000_1000){
        ines.mode = MirroringMode.FourScreen;
    }else{
        if(ctrl_1 & 0b0000_0001){
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
    INESformat ines = verifyAndParseINES(cast(const(ubyte)[]) read("roms/cartridge_test.nes"));
    assert(ines.PRG_bankNum == 16);
    assert(ines.CHR_bankNum == 0);
    assert(ines.RAM_bankNum == 0);

    assert(!ines.hasTrainer);
    assert(!ines.hasBBRAM);

    assert(ines.mode == MirroringMode.Horizontal);
    assert(ines.mapperNumber == 0);
}



module cartridge.mapper0;

import cartridge.cartridge;
import std.stdio:writeln;

class Mapper0: Mapper{

    Cartridge cart;

    this(Cartridge cart){
        this.cart = cart;
    }

    override const(ubyte*) access(ushort loc){
        ubyte* pointer;
        // Not 100% sure on this lower bound
        // TODO: SRAM is somewhere
        assert(loc >= 0x6000 && loc <= 0xFFFF);
        if(loc < 0x8000){
            return &cart.RAMs[0][loc % 0x800];
        }else{
            if(cart.PRGs.length < 2){
                return &cart.PRGs[0][loc % 0x4000];
            }else{
                if(loc > 0xC000){
                    return &cart.PRGs[1][loc % 0x4000];
                }else{
                    return &cart.PRGs[0][loc % 0x4000];
                }
            }
        }
    }

    override const(ubyte*) accessCHR(ushort loc){
        return &cart.PRGs[0][loc % 0x2000];
    }
}

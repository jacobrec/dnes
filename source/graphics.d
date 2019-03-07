abstract class Renderer{
    uint[64] pallet =
    [ 0x7C7C7C, 0x0000FC, 0x0000BC, 0x4428BC, 0x940084, 0xA80020, 0xA81000, 0x881400,
      0x503000, 0x007800, 0x006800, 0x005800, 0x004058, 0x000000, 0x000000, 0x000000,
      0xBCBCBC, 0x0078F8, 0x0058F8, 0x6844FC, 0xD800CC, 0xE40058, 0xF83800, 0xE45C10,
      0xAC7C00, 0x00B800, 0x00A800, 0x00A844, 0x008888, 0x000000, 0x000000, 0x000000,
      0xF8F8F8, 0x3CBCFC, 0x6888FC, 0x9878F8, 0xF878F8, 0xF85898, 0xF87858, 0xFCA044,
      0xF8B800, 0xB8F818, 0x58D854, 0x58F898, 0x00E8D8, 0x787878, 0x000000, 0x000000,
      0xFCFCFC, 0xA4E4FC, 0xB8B8F8, 0xD8B8F8, 0xF8B8F8, 0xF8A4C0, 0xF0D0B0, 0xFCE0A8,
      0xF8D878, 0xD8F878, 0xB8F8B8, 0xB8F8D8, 0x00FCFC, 0xF8D8F8, 0x000000, 0x000000];
    void render(const ref ubyte[240][256] screen);
}


class TerminalRenderer: Renderer{
    import std.stdio;
    import std.conv;

    override void render(const ref ubyte[240][256] screen){
        write("\033[1;1H");
        for(int row = 0; row < 239; row += 2){
            for(int col = 0; col < 256; col++){
                printPixelPair(screen[col][row], screen[col][row+1]);
            }
            write("\033[E");
        }
        write("\033[0m");
        for(int col = 0; col < 256; col++)
            write("+");

    }
    void printPixelPair(ubyte top, ubyte bottom){
        pure string hexToString(uint hex){
            ubyte r = (hex >> 16) & 0xFF;
            ubyte g = (hex >> 8) & 0xFF;
            ubyte b = (hex) & 0xFF;
            return text(r, ";", g, ";", b);
        }
        write("\033[38;2;", hexToString(pallet[top]), ";48;2;", hexToString(pallet[bottom]), "m");
        writef("%s", '▀');
    }
}

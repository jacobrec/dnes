DNES_OUTPUT=dtest_output.log
DNES_OUTPUT_HEAD=dnes.log
EXTERNAL_OUTPUT=nestest.log
EXTERNAL_INPUT=roms/nestest.log

dub build
./dnes > $DNES_OUTPUT 2> /dev/null

LINE=$(wc -l $DNES_OUTPUT | ag '\d+' -o)
head $EXTERNAL_INPUT -n $LINE > $EXTERNAL_OUTPUT 2> /dev/null
head $DNES_OUTPUT -n $LINE > $DNES_OUTPUT_HEAD 2> /dev/null


# cmp tmp2.log tmp3.log -l -b 2> /dev/null
diff --context=1 --color=always -d $EXTERNAL_OUTPUT $DNES_OUTPUT_HEAD  2> /dev/null

rm $DNES_OUTPUT
rm $DNES_OUTPUT_HEAD
rm $EXTERNAL_OUTPUT
rm dnes -f


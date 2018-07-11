DNES_OUTPUT=dtest_output.log
DNES_OUTPUT_HEAD=dnes.log
EXTERNAL_OUTPUT=nestest.log
EXTERNAL_INPUT=roms/nestest.log

dub build > /dev/null
./dnes > $DNES_OUTPUT 2> /dev/null

LINE=$(wc -l $DNES_OUTPUT | ag '\d+' -o)
head $EXTERNAL_INPUT -n $LINE > $EXTERNAL_OUTPUT 2> /dev/null
head $DNES_OUTPUT -n $LINE > $DNES_OUTPUT_HEAD 2> /dev/null


# cmp $EXTERNAL_OUTPUT $DNES_OUTPUT_HEAD -l -b 2> /dev/null
OUTPUT=$(colordiff --context=1  -d $EXTERNAL_OUTPUT $DNES_OUTPUT_HEAD  2> /dev/null)
#git diff -U1 --word-diff --no-index -- $EXTERNAL_OUTPUT $DNES_OUTPUT_HEAD  #| ag -v ^@@

printf "$OUTPUT"
echo ""

rm $DNES_OUTPUT
rm $DNES_OUTPUT_HEAD
rm $EXTERNAL_OUTPUT
rm dnes -f

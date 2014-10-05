#!/bin/sh

NSIS="$BASE/NSIS/makensis"
ZIP=_make.zip
URL1=http://sourceforge.net/projects/gnuwin32/files/make/3.81/make-3.81-bin.zip/download
URL2=http://sourceforge.net/projects/gnuwin32/files/make/3.81/make-3.81-dep.zip/download

./configure -prefix ./ -with-doc no -no-native-compiler
make 
if [ ! -e bin/make.exe ]; then
  wget -O $ZIP $URL1 && 7z x $ZIP "bin/*"
  wget -O $ZIP $URL2 && 7z x $ZIP "bin/*"
  rm -rf $ZIP
fi
VERSION=`grep ^VERSION= config/Makefile | cut -d = -f 2`
cd dev/nsis
"$NSIS" -DVERSION=$VERSION -DGTK_RUNTIME="`cygpath -w $BASE`" coq.nsi
ls *exe
cd ../..

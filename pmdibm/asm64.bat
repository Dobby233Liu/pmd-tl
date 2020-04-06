@echo off
setlocal
set _oldcd="%cd%"
cd/d %~dp0
@echo on
..\..\..\msdos ..\..\..\optasm\inst\optasm pmdl;
..\..\..\msdos ..\..\..\optasm\inst\optasm pmdibm;
..\..\..\msdos ..\..\..\optasm\inst\optasm mc;
..\..\..\msdos ..\..\..\optasm\inst\optasm mch;
..\..\..\msdos ..\..\..\optasm\inst\optasm efc;
..\..\..\msdos ..\..\..\optasm\inst\optasm pmp;
..\..\..\msdos ..\..\..\optasm\inst\olink pmdl,pmdl.com;
..\..\..\msdos ..\..\..\optasm\inst\olink pmdibm,pmdibm.com;
..\..\..\msdos ..\..\..\optasm\inst\olink mc;
..\..\..\msdos ..\..\..\optasm\inst\olink mch;
..\..\..\msdos ..\..\..\optasm\inst\olink efc;
..\..\..\msdos ..\..\..\optasm\inst\olink pmp,pmp.com;
@echo off
cd/d %_oldcd%
endlocal
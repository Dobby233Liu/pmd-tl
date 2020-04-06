@echo off
setlocal
set _oldcd="%cd%"
cd/d %~dp0
@echo on
..\..\..\msdos ..\..\..\optasm\inst\optasm mc;
..\..\..\msdos ..\..\..\optasm\inst\optasm mch;
..\..\..\msdos ..\..\..\optasm\inst\optasm efc;
..\..\..\msdos ..\..\..\optasm\inst\olink mc;
..\..\..\msdos ..\..\..\optasm\inst\olink mch;
..\..\..\msdos ..\..\..\optasm\inst\olink efc;
@echo off
cd/d %_oldcd%
endlocal